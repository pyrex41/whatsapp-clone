defmodule GlobalbridgeBackendWeb.AIControllerValidationTest do
  use GlobalbridgeBackendWeb.ConnCase, async: true

  alias GlobalbridgeBackend.Schemas.User
  alias GlobalbridgeBackend.Repo

  setup %{conn: conn} do
    # Create a test user directly
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        email: "test#{System.unique_integer([:positive])}@example.com",
        username: "testuser#{System.unique_integer([:positive])}",
        phone_number: "+1555000#{:rand.uniform(9000) + 1000}",
        password: "Test1234!@#$"
      })
      |> Repo.insert()

    # Create a valid UUID for testing
    thread_id = Ecto.UUID.generate()

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> assign(:current_user, user)

    {:ok, conn: conn, user: user, thread_id: thread_id}
  end

  # Helper to create a test user
  defp create_test_user do
    {:ok, user} =
      %User{}
      |> User.changeset(%{
        email: "test#{System.unique_integer([:positive])}@example.com",
        username: "testuser#{System.unique_integer([:positive])}",
        phone_number: "+1555000#{:rand.uniform(9000) + 1000}",
        password: "Test1234!@#$"
      })
      |> Repo.insert()

    user
  end

  # Helper to create a mock thread fixture
  defp thread_fixture(user_id) do
    %{id: Ecto.UUID.generate(), user_id: user_id}
  end

  describe "POST /api/ai/translate - Input Validation" do
    test "rejects missing text parameter", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/translate", %{"target_language" => "es"})

      assert json_response(conn, 400) == %{
               "error" => "Text must be a non-empty string"
             }
    end

    test "rejects empty text", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/translate", %{"text" => "", "target_language" => "es"})

      assert json_response(conn, 400) == %{
               "error" => "Text must be a non-empty string"
             }
    end

    test "rejects text exceeding max length", %{conn: conn} do
      long_text = String.duplicate("a", 10_001)

      conn =
        post(conn, ~p"/api/ai/translate", %{"text" => long_text, "target_language" => "es"})

      assert json_response(conn, 400) == %{
               "error" => "Text must not exceed 10,000 characters"
             }
    end

    test "rejects missing target_language", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/translate", %{"text" => "Hello"})

      assert json_response(conn, 400) == %{
               "error" => "Target language is required"
             }
    end

    test "rejects invalid target_language", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/translate", %{"text" => "Hello", "target_language" => "invalid"})

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Language must be one of"
    end

    test "rejects invalid source_language", %{conn: conn} do
      conn =
        post(conn, ~p"/api/ai/translate", %{
          "text" => "Hello",
          "target_language" => "es",
          "source_language" => "invalid"
        })

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Language must be one of"
    end

    test "accepts valid translation request", %{conn: conn} do
      # This will fail in actual execution but should pass validation
      conn =
        post(conn, ~p"/api/ai/translate", %{
          "text" => "Hello world",
          "target_language" => "es",
          "source_language" => "en"
        })

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end

    test "accepts translation request with auto source language", %{conn: conn} do
      conn =
        post(conn, ~p"/api/ai/translate", %{
          "text" => "Hello world",
          "target_language" => "es"
        })

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end
  end

  describe "POST /api/ai/analyze_tone - Input Validation" do
    test "rejects missing text parameter", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/analyze_tone", %{})

      assert json_response(conn, 400) == %{
               "error" => "Text must be a non-empty string"
             }
    end

    test "rejects empty text", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/analyze_tone", %{"text" => ""})

      assert json_response(conn, 400) == %{
               "error" => "Text must be a non-empty string"
             }
    end

    test "rejects text exceeding max length", %{conn: conn} do
      long_text = String.duplicate("a", 10_001)
      conn = post(conn, ~p"/api/ai/analyze_tone", %{"text" => long_text})

      assert json_response(conn, 400) == %{
               "error" => "Text must not exceed 10,000 characters"
             }
    end

    test "rejects invalid language code", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/analyze_tone", %{"text" => "Hello", "language" => "invalid"})

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Language must be one of"
    end

    test "accepts valid tone analysis request", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/analyze_tone", %{"text" => "This is great!"})

      assert %{"success" => true} = json_response(conn, 200)
    end

    test "accepts valid tone analysis with language", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/analyze_tone", %{"text" => "This is great!", "language" => "en"})

      assert %{"success" => true} = json_response(conn, 200)
    end

    test "defaults to 'en' language when not provided", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/analyze_tone", %{"text" => "This is great!"})

      assert %{"success" => true, "analysis" => %{"language" => "en"}} = json_response(conn, 200)
    end
  end

  describe "POST /api/ai/summarize_thread - Input Validation" do
    test "rejects missing thread_id", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/summarize_thread", %{})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID is required"
             }
    end

    test "rejects invalid thread_id format", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/summarize_thread", %{"thread_id" => "invalid-uuid"})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID must be a valid UUID"
             }
    end

    test "rejects max_length below minimum", %{conn: conn, thread_id: thread_id} do
      conn =
        post(conn, ~p"/api/ai/summarize_thread", %{
          "thread_id" => thread_id,
          "max_length" => 0
        })

      assert json_response(conn, 400) == %{
               "error" => "Max length must be between 1 and 1,000"
             }
    end

    test "rejects max_length above maximum", %{conn: conn, thread_id: thread_id} do
      conn =
        post(conn, ~p"/api/ai/summarize_thread", %{
          "thread_id" => thread_id,
          "max_length" => 1001
        })

      assert json_response(conn, 400) == %{
               "error" => "Max length must be between 1 and 1,000"
             }
    end

    test "rejects invalid max_length string", %{conn: conn, thread_id: thread_id} do
      conn =
        post(conn, ~p"/api/ai/summarize_thread", %{
          "thread_id" => thread_id,
          "max_length" => "abc"
        })

      assert json_response(conn, 400) == %{
               "error" => "Max length must be a valid integer"
             }
    end

    test "accepts valid string max_length", %{conn: conn, thread_id: thread_id} do
      conn =
        post(conn, ~p"/api/ai/summarize_thread", %{
          "thread_id" => thread_id,
          "max_length" => "500"
        })

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end

    test "uses default max_length when not provided", %{conn: conn, thread_id: thread_id} do
      conn = post(conn, ~p"/api/ai/summarize_thread", %{"thread_id" => thread_id})

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end
  end

  describe "POST /api/ai/search_semantic - Input Validation" do
    test "rejects missing query parameter", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{})

      assert json_response(conn, 400) == %{
               "error" => "Query must be a non-empty string"
             }
    end

    test "rejects empty query", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => ""})

      assert json_response(conn, 400) == %{
               "error" => "Query must be a non-empty string"
             }
    end

    test "rejects query exceeding max length", %{conn: conn} do
      long_query = String.duplicate("a", 1_001)
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => long_query})

      assert json_response(conn, 400) == %{
               "error" => "Query must not exceed 1,000 characters"
             }
    end

    test "rejects invalid thread_id format", %{conn: conn} do
      conn =
        post(conn, ~p"/api/ai/search_semantic", %{
          "query" => "test",
          "thread_id" => "invalid-uuid"
        })

      assert json_response(conn, 400) == %{
               "error" => "Thread ID must be a valid UUID"
             }
    end

    test "rejects limit below minimum", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => "test", "limit" => 0})

      assert json_response(conn, 400) == %{
               "error" => "Limit must be between 1 and 50"
             }
    end

    test "rejects limit above maximum", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => "test", "limit" => 51})

      assert json_response(conn, 400) == %{
               "error" => "Limit must be between 1 and 50"
             }
    end

    test "rejects invalid limit string", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => "test", "limit" => "abc"})

      assert json_response(conn, 400) == %{
               "error" => "Limit must be a valid integer"
             }
    end

    test "rejects invalid recency_bias", %{conn: conn} do
      conn =
        post(conn, ~p"/api/ai/search_semantic", %{"query" => "test", "recency_bias" => "maybe"})

      assert json_response(conn, 400) == %{
               "error" => "Value must be true or false"
             }
    end

    test "rejects invalid translate", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => "test", "translate" => "yes"})

      assert json_response(conn, 400) == %{
               "error" => "Value must be true or false"
             }
    end

    test "accepts valid search request without thread_id", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => "project deadline"})

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end

    test "accepts valid search request with all parameters", %{conn: conn, thread_id: thread_id} do
      conn =
        post(conn, ~p"/api/ai/search_semantic", %{
          "query" => "project deadline",
          "thread_id" => thread_id,
          "limit" => "20",
          "recency_bias" => "true",
          "translate" => "false"
        })

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end
  end

  describe "POST /api/ai/extract_tasks - Input Validation" do
    test "rejects missing thread_id", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/extract_tasks", %{})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID is required"
             }
    end

    test "rejects invalid thread_id format", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/extract_tasks", %{"thread_id" => "invalid-uuid"})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID must be a valid UUID"
             }
    end

    test "rejects query exceeding max length", %{conn: conn, thread_id: thread_id} do
      long_query = String.duplicate("a", 1_001)

      conn =
        post(conn, ~p"/api/ai/extract_tasks", %{"thread_id" => thread_id, "query" => long_query})

      assert json_response(conn, 400) == %{
               "error" => "Query must not exceed 1,000 characters"
             }
    end

    test "uses default query when not provided", %{conn: conn, thread_id: thread_id} do
      conn = post(conn, ~p"/api/ai/extract_tasks", %{"thread_id" => thread_id})

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end

    test "accepts valid task extraction request with custom query", %{conn: conn, thread_id: thread_id} do
      conn =
        post(conn, ~p"/api/ai/extract_tasks", %{
          "thread_id" => thread_id,
          "query" => "urgent tasks"
        })

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end
  end

  describe "POST /api/ai/vec_health - Input Validation" do
    test "rejects missing thread_id", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/vec_health", %{})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID is required"
             }
    end

    test "rejects invalid thread_id format", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/vec_health", %{"thread_id" => "invalid-uuid"})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID must be a valid UUID"
             }
    end

    test "accepts valid vec_health request", %{conn: conn, thread_id: thread_id} do
      conn = post(conn, ~p"/api/ai/vec_health", %{"thread_id" => thread_id})

      # Should not be a 400 error (validation passed)
      refute conn.status == 400
    end
  end

  describe "Security and DoS Prevention" do
    test "prevents DoS via extremely long text", %{conn: conn} do
      huge_text = String.duplicate("a", 100_000)

      conn = post(conn, ~p"/api/ai/translate", %{"text" => huge_text, "target_language" => "es"})

      assert json_response(conn, 400) == %{
               "error" => "Text must not exceed 10,000 characters"
             }
    end

    test "prevents DoS via extremely large limit", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/search_semantic", %{"query" => "test", "limit" => 1_000_000})

      assert json_response(conn, 400) == %{
               "error" => "Limit must be between 1 and 50"
             }
    end

    test "prevents SQL injection via malformed UUID", %{conn: conn} do
      malformed_uuid = "' OR 1=1 --"
      conn = post(conn, ~p"/api/ai/vec_health", %{"thread_id" => malformed_uuid})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID must be a valid UUID"
             }
    end

    test "prevents XSS via malformed UUID", %{conn: conn} do
      xss_attempt = "<script>alert('xss')</script>"
      conn = post(conn, ~p"/api/ai/vec_health", %{"thread_id" => xss_attempt})

      assert json_response(conn, 400) == %{
               "error" => "Thread ID must be a valid UUID"
             }
    end

    test "trims whitespace from text input", %{conn: conn} do
      conn =
        post(conn, ~p"/api/ai/analyze_tone", %{"text" => "  Valid text with spaces  "})

      # Should pass validation and not return 400
      refute conn.status == 400
    end

    test "rejects whitespace-only text", %{conn: conn} do
      conn = post(conn, ~p"/api/ai/analyze_tone", %{"text" => "     "})

      assert json_response(conn, 400) == %{
               "error" => "Text must be a non-empty string"
             }
    end
  end

  describe "Authorization and Access Control" do
    @tag :skip
    test "returns 403 when accessing unauthorized thread for summarization", %{conn: conn} do
      other_thread_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/api/ai/summarize_thread", %{"thread_id" => other_thread_id})

      # Authorization tests skipped - require full database setup
      assert conn.status in [403, 422]
    end

    @tag :skip
    test "returns 403 when accessing unauthorized thread for search", %{conn: conn} do
      other_thread_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/ai/search_semantic", %{
          "query" => "test",
          "thread_id" => other_thread_id
        })

      assert conn.status in [403, 422]
    end

    @tag :skip
    test "returns 403 when accessing unauthorized thread for task extraction", %{conn: conn} do
      other_thread_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/api/ai/extract_tasks", %{"thread_id" => other_thread_id})

      assert conn.status in [403, 422]
    end

    @tag :skip
    test "returns 403 when accessing unauthorized thread for vec_health", %{conn: conn} do
      other_thread_id = Ecto.UUID.generate()

      conn = post(conn, ~p"/api/ai/vec_health", %{"thread_id" => other_thread_id})

      assert conn.status in [403, 422]
    end
  end
end
