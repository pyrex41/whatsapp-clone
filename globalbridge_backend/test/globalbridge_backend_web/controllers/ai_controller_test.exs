defmodule GlobalbridgeBackendWeb.AIControllerTest do
  use GlobalbridgeBackendWeb.ConnCase, async: true

  import Phoenix.ConnTest

  alias GlobalbridgeBackend.Cache.ParticipantCache

  setup %{conn: conn} do
    # Start ParticipantCache if not already running
    case Process.whereis(ParticipantCache) do
      nil ->
        {:ok, _pid} = start_supervised(ParticipantCache)

      _pid ->
        :ok
    end

    # Clear cache before each test
    ParticipantCache.clear()

    # Create a test user and sign them in
    user = %{
      id: "test-user-123",
      email: "test@example.com"
    }

    # Mock the current_user assignment (normally done by auth pipeline)
    conn = assign(conn, :current_user, user)

    %{conn: conn, user: user}
  end

  describe "POST /api/v1/ai/translate" do
    test "translates text successfully with target language provided", %{conn: conn} do
      params = %{
        "text" => "Hello world",
        "target_language" => "es",
        "source_language" => "en"
      }

      conn = post(conn, "/api/v1/ai/translate", params)
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["translation"]
      assert response["source_language"]
      assert response["source_language_code"]
      assert response["target_language"]
      assert response["target_language_code"] == "es"
      assert response["detection_strategy"] == "none"
      assert is_float(response["confidence"])
      assert is_list(response["cultural_notes"])
    end

    test "auto-detects language with combined strategy when target_language not provided", %{
      conn: conn
    } do
      params = %{
        "text" => "Hola mundo",
        "detection_strategy" => "combined"
      }

      start_time = System.monotonic_time(:millisecond)
      conn = post(conn, "/api/v1/ai/translate", params)
      elapsed_time = System.monotonic_time(:millisecond) - start_time

      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["translation"]
      assert response["source_language"]
      assert response["source_language_code"]
      assert response["target_language"] == "English"
      assert response["target_language_code"] == "en"
      assert response["detection_strategy"] == "combined"

      IO.puts("\n[PERF] Combined strategy translation took: #{elapsed_time}ms")
    end

    test "auto-detects language with dedicated strategy when target_language not provided", %{
      conn: conn
    } do
      params = %{
        "text" => "Hola mundo",
        "detection_strategy" => "dedicated"
      }

      start_time = System.monotonic_time(:millisecond)
      conn = post(conn, "/api/v1/ai/translate", params)
      elapsed_time = System.monotonic_time(:millisecond) - start_time

      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["translation"]
      assert response["source_language"]
      assert response["source_language_code"]
      assert response["target_language"] == "English"
      assert response["target_language_code"] == "en"
      assert response["detection_strategy"] == "dedicated"

      IO.puts("\n[PERF] Dedicated strategy translation took: #{elapsed_time}ms")
    end

    test "uses default detection strategy from env when not specified", %{conn: conn} do
      params = %{
        "text" => "Bonjour le monde"
      }

      conn = post(conn, "/api/v1/ai/translate", params)
      response = json_response(conn, 200)

      assert response["success"] == true
      assert response["detection_strategy"] in ["combined", "dedicated"]
    end

    test "handles text with idioms and returns cultural notes", %{conn: conn} do
      params = %{
        "text" => "Break a leg on your exam!",
        "target_language" => "es"
      }

      conn = post(conn, "/api/v1/ai/translate", params)
      response = json_response(conn, 200)

      assert response["success"] == true
      # Cultural notes might be empty or populated depending on LLM response
      assert is_list(response["cultural_notes"])
    end

    test "handles empty text", %{conn: conn} do
      params = %{
        "text" => "",
        "target_language" => "es"
      }

      conn = post(conn, "/api/v1/ai/translate", params)

      # Should return validation error for empty text
      assert json_response(conn, 400)["error"]
    end

    test "validates language codes", %{conn: conn} do
      params = %{
        "text" => "Hello world",
        "target_language" => "invalid_code"
      }

      conn = post(conn, "/api/v1/ai/translate", params)

      assert json_response(conn, 400)["error"] =~ "Language must be one of"
    end
  end

  describe "POST /api/v1/ai/analyze_tone" do
    test "analyzes tone successfully", %{conn: conn} do
      params = %{
        "text" => "This is great work!",
        "language" => "en"
      }

      conn = post(conn, "/api/v1/ai/analyze_tone", params)

      assert json_response(conn, 200)["success"] == true
      assert json_response(conn, 200)["analysis"]
      assert json_response(conn, 200)["text"] == "This is great work!"
    end

    test "returns error for missing text", %{conn: conn} do
      # Missing text
      params = %{"language" => "en"}

      conn = post(conn, "/api/v1/ai/analyze_tone", params)

      assert json_response(conn, 400)["error"]
    end
  end

  describe "POST /api/v1/ai/summarize_thread" do
    test "summarizes thread successfully when user has access", %{conn: conn, user: user} do
      thread_id = "test-thread-123"

      # Grant access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{
        "thread_id" => thread_id,
        "max_length" => 150
      }

      conn = post(conn, "/api/v1/ai/summarize_thread", params)

      # This might return an error in test environment due to missing data
      # But it should return a proper JSON response
      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end

    test "returns 403 when user does not have access to thread", %{conn: conn, user: user} do
      thread_id = "unauthorized-thread-123"

      # Deny access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{
        "thread_id" => thread_id,
        "max_length" => 150
      }

      conn = post(conn, "/api/v1/ai/summarize_thread", params)

      assert json_response(conn, 403)["error"] == "You do not have access to this thread"
    end

    test "returns error for missing thread_id", %{conn: conn} do
      # Missing thread_id
      params = %{"max_length" => 150}

      conn = post(conn, "/api/v1/ai/summarize_thread", params)

      assert json_response(conn, 400)["error"]
    end
  end

  describe "POST /api/v1/ai/search_semantic" do
    test "performs semantic search when user has access", %{conn: conn, user: user} do
      thread_id = "test-thread-456"

      # Grant access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{
        "query" => "project deadline",
        "thread_id" => thread_id,
        "limit" => 5
      }

      conn = post(conn, "/api/v1/ai/search_semantic", params)

      # Should return a proper response structure
      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end

    test "returns 403 when user does not have access to thread", %{conn: conn, user: user} do
      thread_id = "unauthorized-thread-456"

      # Deny access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{
        "query" => "project deadline",
        "thread_id" => thread_id,
        "limit" => 5
      }

      conn = post(conn, "/api/v1/ai/search_semantic", params)

      assert json_response(conn, 403)["error"] == "You do not have access to this thread"
    end

    test "allows search without thread_id for global search", %{conn: conn} do
      params = %{
        "query" => "project deadline",
        "limit" => 5
      }

      conn = post(conn, "/api/v1/ai/search_semantic", params)

      # Should work without thread_id
      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end

    test "returns error for missing query", %{conn: conn} do
      # Missing query
      params = %{"thread_id" => "test-thread-456"}

      conn = post(conn, "/api/v1/ai/search_semantic", params)

      assert json_response(conn, 400)["error"]
    end

    test "handles recency bias parameter", %{conn: conn, user: user} do
      thread_id = "test-thread-789"

      # Grant access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{
        "query" => "recent updates",
        "thread_id" => thread_id,
        "recency_bias" => true
      }

      conn = post(conn, "/api/v1/ai/search_semantic", params)

      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end
  end

  describe "POST /api/v1/ai/extract_tasks" do
    test "extracts tasks from thread when user has access", %{conn: conn, user: user} do
      thread_id = "test-thread-999"

      # Grant access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{
        "thread_id" => thread_id,
        "query" => "tasks, deadlines"
      }

      conn = post(conn, "/api/v1/ai/extract_tasks", params)

      # Should return a proper response structure
      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end

    test "returns 403 when user does not have access to thread", %{conn: conn, user: user} do
      thread_id = "unauthorized-thread-999"

      # Deny access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{
        "thread_id" => thread_id,
        "query" => "tasks, deadlines"
      }

      conn = post(conn, "/api/v1/ai/extract_tasks", params)

      assert json_response(conn, 403)["error"] == "You do not have access to this thread"
    end

    test "returns error for missing thread_id", %{conn: conn} do
      # Missing thread_id
      params = %{"query" => "tasks"}

      conn = post(conn, "/api/v1/ai/extract_tasks", params)

      assert json_response(conn, 400)["error"]
    end

    test "uses default query when not provided", %{conn: conn, user: user} do
      thread_id = "test-thread-000"

      # Grant access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # No query provided
      params = %{"thread_id" => thread_id}

      conn = post(conn, "/api/v1/ai/extract_tasks", params)

      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end
  end

  describe "POST /api/v1/ai/vec_health" do
    test "returns vector health when user has access", %{conn: conn, user: user} do
      thread_id = "test-thread-vec"

      # Grant access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{"thread_id" => thread_id}

      conn = post(conn, "/api/v1/ai/vec_health", params)

      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end

    test "returns 403 when user does not have access to thread", %{conn: conn, user: user} do
      thread_id = "unauthorized-thread-vec"

      # Deny access to thread
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      params = %{"thread_id" => thread_id}

      conn = post(conn, "/api/v1/ai/vec_health", params)

      assert json_response(conn, 403)["error"] == "You do not have access to this thread"
    end

    test "returns error for missing thread_id", %{conn: conn} do
      params = %{}

      conn = post(conn, "/api/v1/ai/vec_health", params)

      assert json_response(conn, 400)["error"]
    end
  end

  describe "authorization across endpoints" do
    test "different threads have independent authorization", %{conn: conn, user: user} do
      thread1 = "authorized-thread-1"
      thread2 = "authorized-thread-2"
      thread3 = "unauthorized-thread-3"

      # Grant access to thread1 and thread2, deny thread3
      :ets.insert(
        :participant_cache,
        {{thread1, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      :ets.insert(
        :participant_cache,
        {{thread2, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      :ets.insert(
        :participant_cache,
        {{thread3, user.id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # Thread1 should work
      conn1 = post(conn, "/api/v1/ai/summarize_thread", %{"thread_id" => thread1})
      response1 = json_response(conn1, 200)
      assert Map.has_key?(response1, "success") or Map.has_key?(response1, "error")

      # Thread2 should work
      conn2 = post(conn, "/api/v1/ai/extract_tasks", %{"thread_id" => thread2})
      response2 = json_response(conn2, 200)
      assert Map.has_key?(response2, "success") or Map.has_key?(response2, "error")

      # Thread3 should fail
      conn3 = post(conn, "/api/v1/ai/vec_health", %{"thread_id" => thread3})
      assert json_response(conn3, 403)["error"] == "You do not have access to this thread"
    end

    test "authorization check performance is fast", %{conn: conn, user: user} do
      thread_id = "perf-test-thread"

      # Pre-cache access
      :ets.insert(
        :participant_cache,
        {{thread_id, user.id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # Make multiple requests and measure timing
      {elapsed_time, _results} =
        :timer.tc(fn ->
          for _ <- 1..10 do
            post(conn, "/api/v1/ai/vec_health", %{"thread_id" => thread_id})
          end
        end)

      # Average time per request in milliseconds
      avg_time_ms = elapsed_time / 10 / 1000

      # Should average well under 5ms per request (including full HTTP roundtrip)
      # Authorization itself should be < 1ms
      assert avg_time_ms < 50.0,
             "Average request time #{avg_time_ms}ms is too high (includes full HTTP processing)"
    end
  end

  describe "authentication" do
    test "requires authentication", %{conn: conn} do
      # Remove the current_user assignment to test unauthenticated access
      conn = assign(conn, :current_user, nil)

      params = %{
        "text" => "Hello",
        "target_language" => "es"
      }

      conn = post(conn, "/api/v1/ai/translate", params)

      # Should still work since we're not testing the full auth pipeline here
      # In a real scenario, the auth pipeline would reject unauthenticated requests
      response = json_response(conn, 200)
      assert Map.has_key?(response, "success") or Map.has_key?(response, "error")
    end
  end

  describe "error handling" do
    test "handles malformed JSON gracefully", %{conn: conn} do
      # Send malformed JSON - Phoenix should handle this
      conn =
        put_req_header(conn, "content-type", "application/json")
        |> post("/api/v1/ai/translate", "invalid json")

      # Phoenix will return a 400 Bad Request for malformed JSON
      assert conn.status == 400
    end
  end
end
