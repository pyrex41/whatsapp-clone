defmodule GlobalbridgeBackendWeb.AISmartReplyTest do
  use GlobalbridgeBackendWeb.ConnCase, async: false

  alias GlobalbridgeBackend.{Repo, Chat}
  alias GlobalbridgeBackend.Schemas.{User, Thread, Message, UserStyleProfile, SuggestionFeedback}
  alias GlobalbridgeBackend.AI.{SmartReplyGenerator, ConversationMonitor}

  setup do
    # Create test user
    user = Repo.insert!(%User{
      username: "testuser_#{:rand.uniform(1000000)}",
      email: "test_#{:rand.uniform(1000000)}@example.com",
      password_hash: Bcrypt.hash_pwd_salt("password123"),
      display_name: "Test User"
    })

    # Create test thread
    thread = Repo.insert!(%Thread{
      title: "Test Thread",
      thread_type: "group",
      database_shard_id: Ecto.UUID.generate()
    })

    # Add user as participant
    Repo.insert!(%GlobalbridgeBackend.Schemas.ThreadParticipant{
      thread_id: thread.id,
      user_id: user.id,
      role: "member"
    })

    # Create authenticated connection (same approach as ai_controller_security_test.exs)
    conn = build_conn()
      |> assign(:current_user, user)
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user, thread: thread}
  end

  describe "POST /api/v1/ai/suggest_replies" do
    test "returns suggestions for thread with messages", %{conn: conn, thread: thread, user: user} do
      # Create some messages in the thread
      create_test_messages(thread.id, user.id, [
        "Hey, how are you doing?",
        "I'm working on the new AI features",
        "They're pretty cool, check it out!",
        "What do you think about adding smart replies?"
      ])

      # Measure request time
      start_time = System.monotonic_time(:millisecond)

      response = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id,
          "count" => 3,
          "style_match" => true
        })
        |> json_response(200)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      # Assertions
      assert response["success"] == true
      assert is_list(response["suggestions"])
      assert length(response["suggestions"]) <= 3
      assert response["thread_id"] == thread.id

      # Check suggestion structure
      suggestion = List.first(response["suggestions"])
      assert suggestion["type"] == "smart_reply"
      assert is_binary(suggestion["content"])
      assert is_float(suggestion["confidence"])
      assert is_integer(suggestion["position"])
      assert is_map(suggestion["context"])

      # Performance assertion
      assert elapsed_ms < 15_000, "Request took #{elapsed_ms}ms, expected <15s"

      IO.puts("\n✅ suggest_replies endpoint test passed")
      IO.puts("   - Returned #{length(response["suggestions"])} suggestions")
      IO.puts("   - Response time: #{elapsed_ms}ms")
      IO.puts("   - First suggestion: \"#{suggestion["content"]}\"")
      IO.puts("   - Confidence: #{suggestion["confidence"]}")
    end

    test "respects count parameter", %{conn: conn, thread: thread, user: user} do
      create_test_messages(thread.id, user.id, ["Hello", "How are you?"])

      response = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id,
          "count" => 5
        })
        |> json_response(200)

      assert length(response["suggestions"]) <= 5
    end

    test "returns error for empty thread", %{conn: conn, thread: thread} do
      response = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id
        })
        |> json_response(422)

      assert response["error"] =~ "No messages in thread"
    end

    test "returns error for invalid thread_id", %{conn: conn} do
      response = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => Ecto.UUID.generate()
        })
        |> json_response(403)

      assert response["error"] =~ "Access denied"
    end

    test "validates count parameter", %{conn: conn, thread: thread, user: user} do
      create_test_messages(thread.id, user.id, ["Test"])

      # Too high
      response = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id,
          "count" => 15
        })
        |> json_response(400)

      assert response["error"] =~ "count must be"

      # Too low
      response = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id,
          "count" => 0
        })
        |> json_response(400)

      assert response["error"] =~ "count must be"
    end

    test "measures performance with style matching enabled vs disabled", %{conn: conn, thread: thread, user: user} do
      # Create user style profile
      Repo.insert!(%UserStyleProfile{
        user_id: user.id,
        formality_level: 0.3,
        emoji_frequency: 1.5,
        messages_analyzed: 50,
        confidence_score: 0.8
      })

      create_test_messages(thread.id, user.id, [
        "hey what's up?",
        "working on some cool stuff",
        "wanna check it out?"
      ])

      # With style matching
      start_time = System.monotonic_time(:millisecond)
      response_with_style = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id,
          "style_match" => true
        })
        |> json_response(200)
      time_with_style = System.monotonic_time(:millisecond) - start_time

      # Without style matching
      start_time = System.monotonic_time(:millisecond)
      response_without_style = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id,
          "style_match" => false
        })
        |> json_response(200)
      time_without_style = System.monotonic_time(:millisecond) - start_time

      IO.puts("\n📊 Performance comparison:")
      IO.puts("   - With style matching: #{time_with_style}ms")
      IO.puts("   - Without style matching: #{time_without_style}ms")
      IO.puts("   - Suggestions with style: #{inspect(response_with_style["suggestions"])}")
      IO.puts("   - Suggestions without style: #{inspect(response_without_style["suggestions"])}")

      assert response_with_style["success"]
      assert response_without_style["success"]
    end
  end

  describe "POST /api/v1/ai/record_feedback" do
    test "successfully records accepted suggestion", %{conn: conn, thread: thread, user: user} do
      create_test_messages(thread.id, user.id, ["Test message"])

      suggestion = %{
        "type" => "smart_reply",
        "content" => "Sounds good!",
        "confidence" => 0.85,
        "position" => 1,
        "context" => %{"matched_style" => true}
      }

      start_time = System.monotonic_time(:millisecond)

      response = conn
        |> post("/api/v1/ai/record_feedback", %{
          "thread_id" => thread.id,
          "suggestion" => suggestion,
          "accepted" => true,
          "time_to_response_ms" => 2500
        })
        |> json_response(200)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      assert response["success"] == true
      assert response["message"] == "Feedback recorded successfully"

      # Verify feedback was stored
      feedback = Repo.get_by(SuggestionFeedback, user_id: user.id)
      assert feedback != nil
      assert feedback.accepted == true
      assert feedback.suggestion_type == "smart_reply"
      assert feedback.suggestion_content == "Sounds good!"
      assert feedback.time_to_response_ms == 2500

      IO.puts("\n✅ record_feedback endpoint test passed")
      IO.puts("   - Response time: #{elapsed_ms}ms")
      IO.puts("   - Feedback stored: accepted=#{feedback.accepted}")
      IO.puts("   - Time to response: #{feedback.time_to_response_ms}ms")

      # Performance assertion - with real OpenAI embeddings, expect 3-5s
      assert elapsed_ms < 10_000, "Feedback recording took #{elapsed_ms}ms, expected <10s (real embeddings)"
    end

    test "records rejected suggestion with reason", %{conn: conn, thread: thread, user: user} do
      create_test_messages(thread.id, user.id, ["Test"])

      suggestion = %{
        "type" => "smart_reply",
        "content" => "Okay",
        "confidence" => 0.5,
        "position" => 3
      }

      response = conn
        |> post("/api/v1/ai/record_feedback", %{
          "thread_id" => thread.id,
          "suggestion" => suggestion,
          "accepted" => false,
          "rejection_reason" => "Not my style"
        })
        |> json_response(200)

      assert response["success"] == true

      feedback = Repo.get_by(SuggestionFeedback, user_id: user.id)
      assert feedback.accepted == false
      assert feedback.rejection_reason == "Not my style"
    end

    test "records modified content when user edited suggestion", %{conn: conn, thread: thread, user: user} do
      create_test_messages(thread.id, user.id, ["Test"])

      suggestion = %{
        "type" => "smart_reply",
        "content" => "Thanks",
        "confidence" => 0.9,
        "position" => 1
      }

      response = conn
        |> post("/api/v1/ai/record_feedback", %{
          "thread_id" => thread.id,
          "suggestion" => suggestion,
          "accepted" => true,
          "modified_content" => "Thanks a lot!"
        })
        |> json_response(200)

      assert response["success"] == true

      feedback = Repo.get_by(SuggestionFeedback, user_id: user.id)
      assert feedback.user_modified_content == "Thanks a lot!"
    end

    test "validates suggestion structure", %{conn: conn, thread: thread} do
      # Missing required fields
      response = conn
        |> post("/api/v1/ai/record_feedback", %{
          "thread_id" => thread.id,
          "suggestion" => %{"content" => "Test"},
          "accepted" => true
        })
        |> json_response(400)

      assert response["error"] =~ "missing required fields"
    end

    test "requires accepted field", %{conn: conn, thread: thread} do
      suggestion = %{
        "type" => "smart_reply",
        "content" => "Test",
        "confidence" => 0.8,
        "position" => 1
      }

      response = conn
        |> post("/api/v1/ai/record_feedback", %{
          "thread_id" => thread.id,
          "suggestion" => suggestion
        })
        |> json_response(400)

      assert response["error"] =~ "accepted"
    end
  end

  describe "GET /api/v1/ai/conversation_insights" do
    test "returns user insights without thread filter", %{conn: conn, user: user, thread: thread} do
      # Create user style profile
      Repo.insert!(%UserStyleProfile{
        user_id: user.id,
        formality_level: 0.45,
        vocabulary_complexity: 0.6,
        emoji_frequency: 1.2,
        messages_analyzed: 120,
        confidence_score: 0.87,
        last_updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      # Create some feedback with thread_id
      create_test_feedback_with_thread(user.id, thread.id, [
        %{type: "smart_reply", accepted: true},
        %{type: "smart_reply", accepted: true},
        %{type: "smart_reply", accepted: false},
        %{type: "confusion_clarification", accepted: true}
      ])

      start_time = System.monotonic_time(:millisecond)

      response = conn
        |> get("/api/v1/ai/conversation_insights")
        |> json_response(200)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      assert response["success"] == true
      assert is_list(response["acceptance_stats"])
      assert is_map(response["user_style_profile"])

      # Check profile data
      profile = response["user_style_profile"]
      assert profile["formality_level"] == 0.45
      assert profile["emoji_frequency"] == 1.2
      assert profile["messages_analyzed"] == 120
      assert profile["confidence_score"] == 0.87

      # Check acceptance stats exist (at least one type)
      stats = response["acceptance_stats"]
      assert length(stats) > 0

      # Verify stats have the right structure
      first_stat = List.first(stats)
      assert Map.has_key?(first_stat, "type") || Map.has_key?(first_stat, "suggestion_type")
      assert Map.has_key?(first_stat, "total")
      assert Map.has_key?(first_stat, "accepted")

      IO.puts("\n✅ conversation_insights endpoint test passed")
      IO.puts("   - Response time: #{elapsed_ms}ms")
      IO.puts("   - Profile confidence: #{profile["confidence_score"]}")
      IO.puts("   - Messages analyzed: #{profile["messages_analyzed"]}")
      IO.puts("   - Acceptance stats: #{length(stats)} types")

      # Performance assertion
      assert elapsed_ms < 1000, "Insights query took #{elapsed_ms}ms, expected <1s"
    end

    test "returns insights with thread filter", %{conn: conn, user: user, thread: thread} do
      # Create messages in thread
      create_test_messages(thread.id, user.id, ["Message 1", "Message 2"])

      # Start monitoring
      ConversationMonitor.monitor_thread(thread.id)

      response = conn
        |> get("/api/v1/ai/conversation_insights?thread_id=#{thread.id}")
        |> json_response(200)

      assert response["success"] == true
      assert is_map(response["thread_state"])
    end

    test "returns null for missing profile", %{conn: conn} do
      response = conn
        |> get("/api/v1/ai/conversation_insights")
        |> json_response(200)

      assert response["success"] == true
      assert response["user_style_profile"] == nil
      assert response["acceptance_stats"] == []
    end

    test "measures query performance with large dataset", %{conn: conn, user: user} do
      # Create profile
      Repo.insert!(%UserStyleProfile{
        user_id: user.id,
        messages_analyzed: 1000,
        confidence_score: 0.95
      })

      # Create 100 feedback entries
      Enum.each(1..100, fn i ->
        Repo.insert!(%SuggestionFeedback{
          user_id: user.id,
          suggestion_type: Enum.random(["smart_reply", "confusion_clarification", "complexity_simplification"]),
          suggestion_content: "Test #{i}",
          accepted: rem(i, 2) == 0,
          confidence_score: 0.8
        })
      end)

      start_time = System.monotonic_time(:millisecond)

      response = conn
        |> get("/api/v1/ai/conversation_insights")
        |> json_response(200)

      elapsed_ms = System.monotonic_time(:millisecond) - start_time

      assert response["success"] == true

      IO.puts("\n📊 Large dataset performance:")
      IO.puts("   - 100 feedback entries")
      IO.puts("   - Query time: #{elapsed_ms}ms")
      IO.puts("   - Acceptance stats: #{length(response["acceptance_stats"])} types")

      assert elapsed_ms < 2000, "Large query took #{elapsed_ms}ms, expected <2s"
    end
  end

  describe "Integration: Full suggestion workflow" do
    test "complete flow: messages → suggestions → feedback → insights", %{conn: conn, user: user, thread: thread} do
      IO.puts("\n🔄 Testing full AI workflow...")

      # Step 1: Create conversation history
      IO.puts("\n1️⃣ Creating conversation history...")
      messages = create_test_messages(thread.id, user.id, [
        "hey what's up?",
        "not much, just coding",
        "cool, what are you working on?",
        "some AI features, pretty interesting",
        "sounds good! 😊"
      ])

      # Step 2: Learn user style (happens automatically in real system)
      IO.puts("\n2️⃣ Learning user style from messages...")
      start_learn = System.monotonic_time(:millisecond)

      Enum.each(messages, fn msg ->
        SmartReplyGenerator.learn_user_style(user.id, msg, thread.id)
      end)

      learn_time = System.monotonic_time(:millisecond) - start_learn
      IO.puts("   ✓ Style learning completed in #{learn_time}ms")

      # Step 3: Get suggestions
      IO.puts("\n3️⃣ Requesting smart reply suggestions...")
      start_suggest = System.monotonic_time(:millisecond)

      suggest_response = conn
        |> post("/api/v1/ai/suggest_replies", %{
          "thread_id" => thread.id,
          "count" => 3,
          "style_match" => true
        })
        |> json_response(200)

      suggest_time = System.monotonic_time(:millisecond) - start_suggest
      IO.puts("   ✓ Suggestions generated in #{suggest_time}ms")
      IO.puts("   ✓ Got #{length(suggest_response["suggestions"])} suggestions")

      assert suggest_response["success"] == true
      suggestions = suggest_response["suggestions"]
      assert length(suggestions) > 0

      # Step 4: Record feedback
      IO.puts("\n4️⃣ Recording user feedback...")
      start_feedback = System.monotonic_time(:millisecond)

      feedback_response = conn
        |> post("/api/v1/ai/record_feedback", %{
          "thread_id" => thread.id,
          "suggestion" => List.first(suggestions),
          "accepted" => true,
          "time_to_response_ms" => 1500
        })
        |> json_response(200)

      feedback_time = System.monotonic_time(:millisecond) - start_feedback
      IO.puts("   ✓ Feedback recorded in #{feedback_time}ms")

      assert feedback_response["success"] == true

      # Step 5: Get insights
      IO.puts("\n5️⃣ Retrieving conversation insights...")
      start_insights = System.monotonic_time(:millisecond)

      insights_response = conn
        |> get("/api/v1/ai/conversation_insights")
        |> json_response(200)

      insights_time = System.monotonic_time(:millisecond) - start_insights
      IO.puts("   ✓ Insights retrieved in #{insights_time}ms")

      assert insights_response["success"] == true
      assert insights_response["user_style_profile"] != nil
      assert length(insights_response["acceptance_stats"]) > 0

      # Summary
      total_time = learn_time + suggest_time + feedback_time + insights_time
      IO.puts("\n📊 Workflow Summary:")
      IO.puts("   - Style learning: #{learn_time}ms")
      IO.puts("   - Suggestion generation: #{suggest_time}ms")
      IO.puts("   - Feedback recording: #{feedback_time}ms")
      IO.puts("   - Insights query: #{insights_time}ms")
      IO.puts("   - Total workflow time: #{total_time}ms")

      profile = insights_response["user_style_profile"]
      IO.puts("\n   User Profile:")
      IO.puts("   - Messages analyzed: #{profile["messages_analyzed"]}")
      IO.puts("   - Confidence score: #{profile["confidence_score"]}")
      IO.puts("   - Formality level: #{profile["formality_level"]}")

      stats = List.first(insights_response["acceptance_stats"])
      if stats do
        IO.puts("\n   Acceptance Stats:")
        IO.puts("   - Type: #{stats["suggestion_type"]}")
        IO.puts("   - Acceptance rate: #{stats["acceptance_rate"]}")
      end

      # Performance assertions
      assert learn_time < 10_000, "Learning took too long"
      assert suggest_time < 15_000, "Suggestions took too long"
      assert feedback_time < 1_000, "Feedback took too long"
      assert insights_time < 1_000, "Insights took too long"
    end
  end

  # Helper functions

  defp create_test_messages(thread_id, user_id, contents) do
    repo = GlobalbridgeBackend.Repos.ThreadRepo.get_repo(thread_id)

    Enum.map(contents, fn content ->
      message = %Message{
        id: Ecto.UUID.generate(),
        thread_id: thread_id,
        sender_id: user_id,
        content: content,
        content_type: "text"
      }

      case repo.insert(message) do
        {:ok, msg} -> msg
        {:error, _} -> message
      end
    end)
  end

  defp create_test_feedback(user_id, feedback_list) do
    Enum.each(feedback_list, fn attrs ->
      Repo.insert!(%SuggestionFeedback{
        user_id: user_id,
        suggestion_type: attrs.type,
        suggestion_content: "Test suggestion",
        accepted: attrs.accepted,
        confidence_score: 0.8
      })
    end)
  end

  defp create_test_feedback_with_thread(user_id, thread_id, feedback_list) do
    Enum.each(feedback_list, fn attrs ->
      Repo.insert!(%SuggestionFeedback{
        user_id: user_id,
        thread_id: thread_id,
        suggestion_type: attrs.type,
        suggestion_content: "Test suggestion",
        accepted: attrs.accepted,
        confidence_score: 0.8
      })
    end)
  end
end
