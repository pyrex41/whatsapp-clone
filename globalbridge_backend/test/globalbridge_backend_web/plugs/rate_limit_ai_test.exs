defmodule GlobalbridgeBackendWeb.Plugs.RateLimitAITest do
  use GlobalbridgeBackendWeb.ConnCase, async: false

  alias GlobalbridgeBackend.Contexts.Auth
  alias GlobalbridgeBackendWeb.Plugs.RateLimitAI

  setup do
    # Create a test user
    user_attrs = %{
      "username" => "test_rate_limit_#{:rand.uniform(1_000_000)}",
      "phone_number" => "+1#{:rand.uniform(1_000_000_000)}",
      "password" => "SecurePassword123!",
      "display_name" => "Test User"
    }

    {:ok, user, _tokens} = Auth.signup(user_attrs)

    # Clear any existing rate limits for this user
    cleanup_rate_limits(user.id)

    {:ok, user: user}
  end

  describe "rate limiting per endpoint" do
    test "allows requests under limit", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      # Simulate 5 requests to translate endpoint (limit: 60)
      for _ <- 1..5 do
        conn =
          conn
          |> put_req_header("content-type", "application/json")
          |> Map.put(:path_info, ["api", "v1", "ai", "translate"])
          |> RateLimitAI.call([])

        assert conn.status != 429
        assert conn.halted == false
      end
    end

    test "enforces rate limit at limit boundary", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      # Set a low limit for testing
      endpoint = "translate"
      limit = 3

      # Override config for testing
      Application.put_env(:globalbridge_backend, :ai_rate_limits, %{translate: limit})

      # Make requests up to the limit
      for i <- 1..limit do
        conn =
          conn
          |> put_req_header("content-type", "application/json")
          |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
          |> RateLimitAI.call([])

        # Should succeed
        assert conn.status != 429, "Request #{i} should succeed"
        assert conn.halted == false
      end

      # Next request should be rate limited
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
        |> RateLimitAI.call([])

      assert conn.status == 429
      assert conn.halted == true
    end

    test "returns 429 with proper headers when limit exceeded", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      endpoint = "summarize_thread"
      limit = 2

      Application.put_env(:globalbridge_backend, :ai_rate_limits, %{summarize_thread: limit})

      # Exceed the limit
      for _ <- 1..limit do
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
        |> RateLimitAI.call([])
      end

      # This request should be denied
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
        |> RateLimitAI.call([])

      assert conn.status == 429
      assert conn.halted == true

      # Check Retry-After header is present
      retry_after = get_resp_header(conn, "retry-after")
      assert length(retry_after) > 0
      assert String.to_integer(List.first(retry_after)) > 0

      # Check rate limit headers
      assert get_resp_header(conn, "x-ratelimit-limit") == [to_string(limit)]
      assert get_resp_header(conn, "x-ratelimit-remaining") == ["0"]
      assert length(get_resp_header(conn, "x-ratelimit-reset")) > 0

      # Check response body
      response = json_response(conn, 429)
      assert response["error"] == "Rate limit exceeded"
      assert response["retry_after_seconds"]
      assert response["limit"] == limit
    end

    test "rate limits are per-user", %{conn: conn, user: user} do
      # Create second user
      user2_attrs = %{
        "username" => "test_rate_limit_2_#{:rand.uniform(1_000_000)}",
        "phone_number" => "+1#{:rand.uniform(1_000_000_000)}",
        "password" => "SecurePassword123!",
        "display_name" => "Test User 2"
      }

      {:ok, user2, _tokens} = Auth.signup(user2_attrs)
      cleanup_rate_limits(user2.id)

      endpoint = "extract_tasks"
      limit = 2

      Application.put_env(:globalbridge_backend, :ai_rate_limits, %{extract_tasks: limit})

      # User 1 exhausts their limit
      conn1 = assign(conn, :current_user, user)

      for _ <- 1..limit do
        conn1
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
        |> RateLimitAI.call([])
      end

      # User 1's next request should be denied
      conn1_denied =
        conn1
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
        |> RateLimitAI.call([])

      assert conn1_denied.status == 429

      # User 2 should still be able to make requests
      conn2 = assign(conn, :current_user, user2)

      conn2_allowed =
        conn2
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
        |> RateLimitAI.call([])

      assert conn2_allowed.status != 429
      assert conn2_allowed.halted == false
    end

    test "rate limits are per-endpoint", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      limit = 2
      Application.put_env(:globalbridge_backend, :ai_rate_limits, %{
        translate: limit,
        analyze_tone: limit
      })

      # Exhaust limit for translate endpoint
      for _ <- 1..limit do
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", "translate"])
        |> RateLimitAI.call([])
      end

      # Next translate request should be denied
      conn_translate =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", "translate"])
        |> RateLimitAI.call([])

      assert conn_translate.status == 429

      # But analyze_tone should still work
      conn_analyze =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", "analyze_tone"])
        |> RateLimitAI.call([])

      assert conn_analyze.status != 429
      assert conn_analyze.halted == false
    end

    test "requires authentication", %{conn: conn} do
      # Don't assign current_user
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", "translate"])
        |> RateLimitAI.call([])

      assert conn.status == 401
      assert conn.halted == true

      response = json_response(conn, 401)
      assert response["error"] == "Authentication required"
    end

    test "respects environment variable configuration", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      # Set environment variable
      System.put_env("AI_RATE_LIMIT_TRANSLATE", "5")

      on_exit(fn ->
        System.delete_env("AI_RATE_LIMIT_TRANSLATE")
      end)

      # Make 5 requests (should succeed)
      for _ <- 1..5 do
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", "translate"])
        |> RateLimitAI.call([])
      end

      # 6th request should be denied
      conn_denied =
        conn
        |> put_req_header("content-type", "application/json")
        |> Map.put(:path_info, ["api", "v1", "ai", "translate"])
        |> RateLimitAI.call([])

      assert conn_denied.status == 429
    end
  end

  describe "telemetry events" do
    test "emits telemetry event when rate limit exceeded", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      endpoint = "translate"
      limit = 1

      Application.put_env(:globalbridge_backend, :ai_rate_limits, %{translate: limit})

      # Attach telemetry handler
      test_pid = self()

      :telemetry.attach(
        "test-rate-limit-handler",
        [:globalbridge_backend, :ai, :rate_limit, :exceeded],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-rate-limit-handler")
      end)

      # Exhaust limit
      conn
      |> put_req_header("content-type", "application/json")
      |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
      |> RateLimitAI.call([])

      # Trigger rate limit
      conn
      |> put_req_header("content-type", "application/json")
      |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
      |> RateLimitAI.call([])

      # Check telemetry event was received
      assert_receive {:telemetry_event, %{count: 1}, metadata}, 1000
      assert metadata.user_id == user.id
      assert metadata.endpoint == endpoint
      assert metadata.timestamp
    end
  end

  describe "concurrent requests" do
    test "handles concurrent requests correctly", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      limit = 10
      concurrent_requests = 20

      Application.put_env(:globalbridge_backend, :ai_rate_limits, %{translate: limit})

      # Spawn concurrent requests
      tasks =
        for _ <- 1..concurrent_requests do
          Task.async(fn ->
            conn
            |> put_req_header("content-type", "application/json")
            |> Map.put(:path_info, ["api", "v1", "ai", "translate"])
            |> RateLimitAI.call([])
            |> Map.get(:status)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Count successful and rate-limited responses
      successful = Enum.count(results, &(&1 != 429))
      rate_limited = Enum.count(results, &(&1 == 429))

      # Should have exactly `limit` successful requests
      assert successful == limit
      # Remaining should be rate limited
      assert rate_limited == concurrent_requests - limit
    end
  end

  describe "different endpoint limits" do
    test "enforces correct limits for each endpoint", %{conn: conn, user: user} do
      conn = assign(conn, :current_user, user)

      endpoints_and_limits = [
        {"translate", 60},
        {"analyze_tone", 30},
        {"summarize_thread", 10},
        {"search_semantic", 30},
        {"extract_tasks", 10}
      ]

      for {endpoint, expected_limit} <- endpoints_and_limits do
        # Reset rate limits
        cleanup_rate_limits(user.id)

        # Make requests up to the limit
        for _ <- 1..expected_limit do
          conn
          |> put_req_header("content-type", "application/json")
          |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
          |> RateLimitAI.call([])
        end

        # Next request should be denied
        conn_result =
          conn
          |> put_req_header("content-type", "application/json")
          |> Map.put(:path_info, ["api", "v1", "ai", endpoint])
          |> RateLimitAI.call([])

        assert conn_result.status == 429,
               "Expected #{endpoint} to be rate limited after #{expected_limit} requests"

        response = json_response(conn_result, 429)
        assert response["limit"] == expected_limit
      end
    end
  end

  # Helper function to cleanup rate limits
  defp cleanup_rate_limits(user_id) do
    endpoints = ["translate", "analyze_tone", "summarize_thread", "search_semantic", "extract_tasks"]

    for endpoint <- endpoints do
      rate_key = "ai:#{endpoint}:user:#{user_id}"
      Hammer.delete_buckets(rate_key)
    end
  end
end
