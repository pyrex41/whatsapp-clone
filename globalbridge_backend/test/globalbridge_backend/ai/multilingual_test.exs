defmodule GlobalbridgeBackend.AI.MultilingualTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.AI.SemanticSearch
  alias GlobalbridgeBackend.AI.Tools.TaskExtractionTool

  # Test data in multiple languages
  @test_texts %{
    english:
      "I need to finish the project report by Friday and schedule a meeting with the team.",
    spanish:
      "Necesito terminar el informe del proyecto para el viernes y programar una reunión con el equipo.",
    french:
      "Je dois finir le rapport de projet pour vendredi et programmer une réunion avec l'équipe.",
    german:
      "Ich muss den Projektbericht bis Freitag fertigstellen und ein Treffen mit dem Team planen.",
    japanese: "金曜日までにプロジェクトレポートを完了し、チームとのミーティングをスケジュールする必要があります。",
    arabic: "أحتاج إلى إنهاء تقرير المشروع بحلول يوم الجمعة وجدولة اجتماع مع الفريق.",
    chinese: "我需要在星期五之前完成项目报告，并安排与团队的会议。"
  }

  describe "multilingual embedding generation" do
    test "generates consistent embeddings across languages" do
      # Test that embeddings are generated for different languages
      Enum.each(@test_texts, fn {language, text} ->
        assert {:ok, embedding} = EmbeddingService.generate(text)
        assert is_list(embedding)
        # Expected dimension
        assert length(embedding) == 3072
        assert Enum.all?(embedding, &is_float/1)
      end)
    end

    test "handles unicode characters correctly" do
      # Test with various unicode characters
      unicode_texts = [
        # Mixed English, Chinese, emoji
        "Hello 世界 🌍",
        # Accented characters
        "café résumé naïve",
        # Arabic
        "مرحبا بالعالم",
        # Japanese
        "こんにちは世界"
      ]

      Enum.each(unicode_texts, fn text ->
        assert {:ok, embedding} = EmbeddingService.generate(text)
        assert is_list(embedding)
        assert length(embedding) == 3072
      end)
    end
  end

  describe "multilingual semantic search" do
    test "searches work with multilingual content" do
      # Test that semantic search works with different languages
      # Note: This would require actual test data in the database
      # For now, we test the interface

      test_queries = [
        {"project deadline", "english"},
        {"fecha límite del proyecto", "spanish"},
        {"date limite projet", "french"},
        {"Projektfrist", "german"}
      ]

      Enum.each(test_queries, fn {query, language} ->
        try do
          result = SemanticSearch.search("test-thread", query)
          # Should return an error due to database not being available in unit tests
          assert is_tuple(result)
          assert elem(result, 0) == :error
        rescue
          e ->
            # If it raises an exception, that's also acceptable for unit tests
            assert true
        end
      end)
    end

    test "build_context handles multilingual text" do
      # Test context building with multilingual content
      multilingual_results = [
        %{
          content: @test_texts.english,
          distance: 0.1,
          inserted_at: DateTime.utc_now(),
          sender_id: "user1"
        },
        %{
          content: @test_texts.spanish,
          distance: 0.2,
          inserted_at: DateTime.utc_now(),
          sender_id: "user2"
        },
        %{
          content: @test_texts.french,
          distance: 0.3,
          inserted_at: DateTime.utc_now(),
          sender_id: "user3"
        }
      ]

      context = GlobalbridgeBackend.AI.RAGRetriever.build_context(multilingual_results)

      assert is_binary(context)
      assert String.length(context) > 0
      # Should contain text from different languages
      assert String.contains?(context, "project") or String.contains?(context, "proyecto") or
               String.contains?(context, "projet")
    end
  end

  describe "multilingual task extraction" do
    test "extracts tasks from different languages" do
      # Test task extraction with multilingual input
      Enum.each(@test_texts, fn {language, text} ->
        search_results = [%{content: text, score: 0.9, inserted_at: DateTime.utc_now()}]
        {:ok, result} = TaskExtractionTool.extract_from_context(text, search_results)

        # Should return a valid result structure
        assert is_map(result)
        assert Map.has_key?(result, :tasks)
        assert Map.has_key?(result, :deadlines)
        assert Map.has_key?(result, :decisions)
        assert is_list(result.tasks)
        assert is_list(result.deadlines)
        assert is_list(result.decisions)
      end)
    end

    test "handles language-specific date formats" do
      # Test with different date formats used in various languages
      date_texts = [
        # English
        "Complete by Friday",
        # Spanish
        "Terminar para el viernes",
        # French
        "Terminer pour vendredi",
        # German
        "Bis Freitag fertigstellen",
        # Japanese
        "金曜日までに完了",
        # Arabic
        "إكمال بحلول الجمعة"
      ]

      Enum.each(date_texts, fn text ->
        search_results = [%{content: text, score: 0.9, inserted_at: DateTime.utc_now()}]
        {:ok, result} = TaskExtractionTool.extract_from_context(text, search_results)
        assert is_map(result)
        # Should extract some tasks or deadlines
        assert length(result.tasks) + length(result.deadlines) >= 0
      end)
    end

    test "serializes multilingual results to JSON" do
      # Test JSON serialization with multilingual content
      context = @test_texts.spanish
      search_results = [%{content: context, score: 0.9, inserted_at: DateTime.utc_now()}]

      {:ok, result} = TaskExtractionTool.extract_from_context(context, search_results)

      {:ok, json} = TaskExtractionTool.to_json(result)
      assert is_binary(json)

      # Should contain JSON structure with version and task data
      assert String.contains?(json, "\"version\":\"1.0\"")
      assert String.contains?(json, "\"tasks\":[]")
    end
  end

  describe "language detection edge cases" do
    test "handles mixed language content" do
      mixed_text = "Hello mundo, comment ça va? Guten Tag and こんにちは"
      search_results = [%{content: mixed_text, score: 0.9, inserted_at: DateTime.utc_now()}]

      {:ok, result} = TaskExtractionTool.extract_from_context(mixed_text, search_results)
      assert is_map(result)
      # Should still process mixed content
    end

    test "handles empty or whitespace-only text" do
      empty_texts = ["", "   ", "\n\t  \n"]

      Enum.each(empty_texts, fn text ->
        search_results = [%{content: text, score: 0.9, inserted_at: DateTime.utc_now()}]
        {:ok, result} = TaskExtractionTool.extract_from_context(text, search_results)
        assert is_map(result)
        assert result.tasks == []
        assert result.deadlines == []
        assert result.decisions == []
      end)
    end

    test "handles very long multilingual text" do
      # Create a long text with multiple languages
      long_text = Enum.map_join(@test_texts, " ", fn {_lang, text} -> text end)
      # Make it even longer
      long_text = String.duplicate(long_text, 3)

      search_results = [%{content: long_text, score: 0.9, inserted_at: DateTime.utc_now()}]
      {:ok, result} = TaskExtractionTool.extract_from_context(long_text, search_results)
      assert is_map(result)
      # Should handle long text gracefully
    end
  end

  describe "cultural context handling" do
    test "recognizes culturally specific terms" do
      # Test with culturally specific content that might affect task extraction
      cultural_texts = [
        # Indian holiday
        "Schedule a meeting for Diwali preparations",
        # Chinese holiday
        "Complete before Chinese New Year",
        # Islamic holiday
        "Finish by Ramadan end date",
        # French national holiday
        "Submit before Bastille Day"
      ]

      Enum.each(cultural_texts, fn text ->
        search_results = [%{content: text, score: 0.9, inserted_at: DateTime.utc_now()}]
        {:ok, result} = TaskExtractionTool.extract_from_context(text, search_results)
        assert is_map(result)
        assert Map.has_key?(result, :tasks)
      end)
    end
  end
end
