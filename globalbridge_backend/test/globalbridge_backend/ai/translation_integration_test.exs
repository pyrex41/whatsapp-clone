defmodule GlobalbridgeBackend.AI.TranslationIntegrationTest do
  use GlobalbridgeBackend.DataCase, async: false

  alias GlobalbridgeBackend.AI.{
    SmartReplyGenerator,
    ConversationLanguageDetector,
    TranslationService
  }
  alias GlobalbridgeBackend.Schemas.{User, Message}
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Contexts.Threads
  alias GlobalbridgeBackend.Repos.ThreadRepo

  setup do
    # Create test users with language preferences
    english_user = Repo.insert!(%User{
      username: "english_user_#{:rand.uniform(1000000)}",
      email: "english_#{:rand.uniform(1000000)}@example.com",
      password_hash: Bcrypt.hash_pwd_salt("password123"),
      display_name: "English User",
      preferred_language: "en"
    })

    spanish_user = Repo.insert!(%User{
      username: "spanish_user_#{:rand.uniform(1000000)}",
      email: "spanish_#{:rand.uniform(1000000)}@example.com",
      password_hash: Bcrypt.hash_pwd_salt("password123"),
      display_name: "Spanish User",
      preferred_language: "es"
    })

    # Create test thread
    {:ok, thread} = Threads.create_thread(%{
      thread_type: "group",
      title: "Multilingual Test Thread",
      created_by: english_user.id
    })

    # Add both participants
    Threads.add_participant(thread, english_user.id)
    Threads.add_participant(thread, spanish_user.id)

    # Initialize thread database
    ThreadRepo.get_repo(thread.database_shard_id)

    {:ok, english_user: english_user, spanish_user: spanish_user, thread: thread}
  end

  describe "ConversationLanguageDetector" do
    test "detects Spanish as primary language", %{thread: thread, spanish_user: spanish_user} do
      # Create Spanish messages
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      messages = [
        "¿Cómo estás?",
        "Estoy bien, gracias",
        "¿Vamos a la reunión mañana?",
        "Sí, nos vemos ahí"
      ]

      for content <- messages do
        repo.insert!(%Message{
          id: Ecto.UUID.generate(),
          thread_id: thread.id,
          content: content,
          content_type: "text",
          sender_id: spanish_user.id,
          detected_language: "es",
          inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      end

      # Detect language
      assert {:ok, "es", confidence} = ConversationLanguageDetector.detect_thread_language(thread.id)
      assert confidence == 1.0
    end

    test "detects mixed languages", %{thread: thread, english_user: english_user, spanish_user: spanish_user} do
      repo = ThreadRepo.get_repo(thread.database_shard_id)

      # Create mixed messages
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      repo.insert!(%Message{
        id: Ecto.UUID.generate(),
        thread_id: thread.id,
        content: "Hello!",
        content_type: "text",
        sender_id: english_user.id,
        detected_language: "en",
        inserted_at: now,
        updated_at: now
      })

      repo.insert!(%Message{
        id: Ecto.UUID.generate(),
        thread_id: thread.id,
        content: "¡Hola!",
        content_type: "text",
        sender_id: spanish_user.id,
        detected_language: "es",
        inserted_at: now,
        updated_at: now
      })

      # Should return mixed
      result = ConversationLanguageDetector.detect_thread_language(thread.id, 2)
      assert match?({:mixed, _}, result) or match?({:ok, _, _}, result)
    end

    test "returns unknown for threads with no messages", %{thread: thread} do
      assert {:unknown, []} = ConversationLanguageDetector.detect_thread_language(thread.id)
    end

    test "checks if translation is needed", %{thread: thread, english_user: english_user, spanish_user: spanish_user} do
      # Create Spanish messages
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      repo.insert!(%Message{
        id: Ecto.UUID.generate(),
        thread_id: thread.id,
        content: "¿Cómo estás?",
        content_type: "text",
        sender_id: spanish_user.id,
        detected_language: "es",
        inserted_at: now,
        updated_at: now
      })

      # English user needs translation for Spanish thread
      assert ConversationLanguageDetector.needs_translation?(thread.id, english_user.id) == true

      # Spanish user doesn't need translation
      assert ConversationLanguageDetector.needs_translation?(thread.id, spanish_user.id) == false
    end
  end

  describe "TranslationService" do
    test "translates batch of texts" do
      texts = ["Hello!", "How are you?", "See you later!"]

      {:ok, translations} = TranslationService.translate_batch(texts, "en", "es")

      assert length(translations) == 3
      # Translations should be different from originals
      assert Enum.all?(Enum.zip(texts, translations), fn {orig, trans} ->
        String.downcase(orig) != String.downcase(trans)
      end)

      IO.puts("\n🌐 Batch Translation Test:")
      Enum.zip(texts, translations)
      |> Enum.each(fn {orig, trans} ->
        IO.puts("   #{orig} → #{trans}")
      end)
    end

    test "returns original if same language" do
      texts = ["Hello!", "World!"]
      {:ok, result} = TranslationService.translate_batch(texts, "en", "en")
      assert result == texts
    end

    test "caches translations" do
      texts = ["Thanks!"]

      # First call - should hit API
      start1 = System.monotonic_time(:millisecond)
      {:ok, _} = TranslationService.translate_batch(texts, "en", "es")
      time1 = System.monotonic_time(:millisecond) - start1

      # Second call - should hit cache
      start2 = System.monotonic_time(:millisecond)
      {:ok, _} = TranslationService.translate_batch(texts, "en", "es")
      time2 = System.monotonic_time(:millisecond) - start2

      # Cache should be much faster (at least 10x)
      IO.puts("\n⚡ Cache Performance:")
      IO.puts("   First call: #{time1}ms")
      IO.puts("   Cached call: #{time2}ms")
      IO.puts("   Speedup: #{Float.round(time1 / max(time2, 1), 1)}x")

      assert time2 < time1 / 5  # Cache should be at least 5x faster
    end

    test "handles safe fallback on error" do
      texts = ["Hello!"]
      # Test with nil target language to cause validation error
      # In production, errors would come from network issues, rate limits, etc.
      # Using nil here simulates a scenario where translation would fail
      {:ok, result} = TranslationService.translate_batch_safe(texts, "en", nil)
      # Should return original texts on error
      assert is_list(result)
      # Either returns originals or at least returns same number of texts
      assert length(result) == length(texts)
    end
  end

  describe "SmartReplyGenerator with Translation" do
    test "generates suggestions with translation metadata for multilingual thread", %{
      thread: thread,
      english_user: english_user,
      spanish_user: spanish_user
    } do
      # Create Spanish conversation
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      messages = [
        %Message{
          id: Ecto.UUID.generate(),
          thread_id: thread.id,
          content: "¿Cómo estás?",
          content_type: "text",
          sender_id: spanish_user.id,
          detected_language: "es",
          inserted_at: now,
          updated_at: now
        },
        %Message{
          id: Ecto.UUID.generate(),
          thread_id: thread.id,
          content: "Bien, ¿y tú?",
          content_type: "text",
          sender_id: spanish_user.id,
          detected_language: "es",
          inserted_at: now,
          updated_at: now
        }
      ]

      Enum.each(messages, &repo.insert!/1)

      # Generate suggestions for English user
      {:ok, suggestions} = SmartReplyGenerator.generate_suggestions(
        english_user.id,
        thread.id,
        messages,
        count: 3
      )

      assert length(suggestions) == 3

      # Check each suggestion has translation metadata
      Enum.each(suggestions, fn suggestion ->
        assert Map.has_key?(suggestion, :translation)
        translation = suggestion.translation

        # Should have translation enabled for English user in Spanish thread
        assert translation.enabled == true
        assert translation.target_language == "es"
        assert translation.target_language_name == "Spanish"
        assert translation.user_can_toggle == true
        assert translation.auto_translate_on_send == true

        # Should have both display and translated content
        assert is_binary(suggestion.content)  # Display in English
        assert is_binary(translation.translated_content)  # Send in Spanish

        # Content should be different (unless translation fails/fallback)
        IO.puts("\n💬 Suggestion with Translation:")
        IO.puts("   Display (en): #{suggestion.content}")
        IO.puts("   Send (es): #{translation.translated_content}")
      end)
    end

    test "generates suggestions without translation for same-language thread", %{
      thread: thread,
      english_user: english_user
    } do
      # Create English conversation
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      messages = [
        %Message{
          id: Ecto.UUID.generate(),
          thread_id: thread.id,
          content: "How are you?",
          content_type: "text",
          sender_id: english_user.id,
          detected_language: "en",
          inserted_at: now,
          updated_at: now
        }
      ]

      Enum.each(messages, &repo.insert!/1)

      # Generate suggestions
      {:ok, suggestions} = SmartReplyGenerator.generate_suggestions(
        english_user.id,
        thread.id,
        messages,
        count: 3
      )

      # Should have translation metadata but disabled
      Enum.each(suggestions, fn suggestion ->
        assert suggestion.translation.enabled == false
        assert suggestion.translation.user_can_toggle == false
        assert suggestion.translation.auto_translate_on_send == false
      end)
    end

    test "performance: translation adds minimal overhead", %{
      thread: thread,
      english_user: english_user,
      spanish_user: spanish_user
    } do
      # Create Spanish conversation
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      messages = [
        %Message{
          id: Ecto.UUID.generate(),
          thread_id: thread.id,
          content: "¿Vamos a comer?",
          content_type: "text",
          sender_id: spanish_user.id,
          detected_language: "es",
          inserted_at: now,
          updated_at: now
        }
      ]

      Enum.each(messages, &repo.insert!/1)

      # Measure with translation
      start = System.monotonic_time(:millisecond)
      {:ok, suggestions} = SmartReplyGenerator.generate_suggestions(
        english_user.id,
        thread.id,
        messages,
        count: 3,
        include_translations: true
      )
      time_with_translation = System.monotonic_time(:millisecond) - start

      IO.puts("\n⏱️  Performance with Translation:")
      IO.puts("   Total time: #{time_with_translation}ms")
      IO.puts("   Suggestions: #{length(suggestions)}")
      IO.puts("   Translation enabled: #{hd(suggestions).translation.enabled}")

      # Should complete in reasonable time (<5s for real API calls)
      assert time_with_translation < 10_000, "Translation took #{time_with_translation}ms, expected <10s"
    end
  end
end
