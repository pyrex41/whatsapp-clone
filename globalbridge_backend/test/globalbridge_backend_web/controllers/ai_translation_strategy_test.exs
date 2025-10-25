defmodule GlobalbridgeBackendWeb.AITranslationStrategyTest do
  @moduledoc """
  Comprehensive tests comparing the two language detection strategies:
  - "combined": Single LLM call for detection + translation
  - "dedicated": Separate detection call, then translation

  These tests measure performance, accuracy, and behavior differences.
  """

  use GlobalbridgeBackendWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias GlobalbridgeBackend.Cache.ParticipantCache

  @moduletag :integration
  @moduletag timeout: 120_000

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
      id: "test-user-strategy-#{:rand.uniform(100000)}",
      email: "strategy-test@example.com"
    }

    # Mock the current_user assignment
    conn = assign(conn, :current_user, user)

    %{conn: conn, user: user}
  end

  describe "Strategy Performance Comparison" do
    @tag :performance
    test "compares latency between combined and dedicated strategies", %{conn: conn} do
      test_texts = [
        {"Hola mundo", "Spanish"},
        {"Bonjour le monde", "French"},
        {"Hallo Welt", "German"},
        {"こんにちは世界", "Japanese"}
      ]

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("STRATEGY PERFORMANCE COMPARISON")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("")

      results =
        Enum.map(test_texts, fn {text, expected_lang} ->
          IO.puts("Testing text: \"#{text}\" (Expected: #{expected_lang})")
          IO.puts("-" |> String.duplicate(80))

          # Test combined strategy
          combined_result = measure_strategy(conn, text, "combined")

          # Wait a bit to avoid rate limiting
          :timer.sleep(1000)

          # Test dedicated strategy
          dedicated_result = measure_strategy(conn, text, "dedicated")

          IO.puts("")

          %{
            text: text,
            expected_language: expected_lang,
            combined: combined_result,
            dedicated: dedicated_result
          }
        end)

      # Print summary
      IO.puts("=" |> String.duplicate(80))
      IO.puts("SUMMARY")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("")

      print_summary_table(results)

      IO.puts("")
      IO.puts("=" |> String.duplicate(80))

      # Assertions
      Enum.each(results, fn result ->
        assert result.combined.success, "Combined strategy failed for #{result.text}"
        assert result.dedicated.success, "Dedicated strategy failed for #{result.text}"
      end)
    end

    @tag :accuracy
    test "compares detection accuracy for various languages", %{conn: conn} do
      test_cases = [
        %{text: "Hola, ¿cómo estás?", expected_code: "es", name: "Spanish"},
        %{text: "Bonjour, comment allez-vous?", expected_code: "fr", name: "French"},
        %{text: "Guten Tag, wie geht es Ihnen?", expected_code: "de", name: "German"},
        %{text: "Ciao, come stai?", expected_code: "it", name: "Italian"},
        %{text: "Olá, como você está?", expected_code: "pt", name: "Portuguese"},
        %{text: "こんにちは、お元気ですか？", expected_code: "ja", name: "Japanese"},
        %{text: "你好，你好吗？", expected_code: "zh", name: "Chinese"},
        %{text: "안녕하세요, 어떻게 지내세요?", expected_code: "ko", name: "Korean"},
        %{text: "Привет, как дела?", expected_code: "ru", name: "Russian"},
        %{text: "مرحبا، كيف حالك؟", expected_code: "ar", name: "Arabic"},
        %{text: "नमस्ते, आप कैसे हैं?", expected_code: "hi", name: "Hindi"}
      ]

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("LANGUAGE DETECTION ACCURACY TEST")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("")

      results =
        Enum.map(test_cases, fn test_case ->
          IO.puts("Testing: #{test_case.name} (#{test_case.expected_code})")

          # Test combined
          combined_conn =
            post(conn, "/api/v1/ai/translate", %{
              "text" => test_case.text,
              "detection_strategy" => "combined"
            })

          combined_response = json_response(combined_conn, 200)
          combined_detected = combined_response["source_language_code"]
          combined_correct = combined_detected == test_case.expected_code

          IO.puts(
            "  Combined: #{combined_detected} #{if combined_correct, do: "✓", else: "✗"}"
          )

          # Wait to avoid rate limiting
          :timer.sleep(1000)

          # Test dedicated
          dedicated_conn =
            post(conn, "/api/v1/ai/translate", %{
              "text" => test_case.text,
              "detection_strategy" => "dedicated"
            })

          dedicated_response = json_response(dedicated_conn, 200)
          dedicated_detected = dedicated_response["source_language_code"]
          dedicated_correct = dedicated_detected == test_case.expected_code

          IO.puts(
            "  Dedicated: #{dedicated_detected} #{if dedicated_correct, do: "✓", else: "✗"}"
          )

          IO.puts("")

          %{
            language: test_case.name,
            expected: test_case.expected_code,
            combined_detected: combined_detected,
            combined_correct: combined_correct,
            dedicated_detected: dedicated_detected,
            dedicated_correct: dedicated_correct
          }
        end)

      # Calculate accuracy
      combined_accuracy =
        Enum.count(results, & &1.combined_correct) / length(results) * 100

      dedicated_accuracy =
        Enum.count(results, & &1.dedicated_correct) / length(results) * 100

      IO.puts("=" |> String.duplicate(80))
      IO.puts("ACCURACY RESULTS")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("Combined Strategy:  #{Float.round(combined_accuracy, 1)}% correct")
      IO.puts("Dedicated Strategy: #{Float.round(dedicated_accuracy, 1)}% correct")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("")

      # Both strategies should have reasonable accuracy (at least 70%)
      assert combined_accuracy >= 70.0,
             "Combined strategy accuracy too low: #{combined_accuracy}%"

      assert dedicated_accuracy >= 70.0,
             "Dedicated strategy accuracy too low: #{dedicated_accuracy}%"
    end

    @tag :cost
    test "estimates cost difference between strategies", %{conn: conn} do
      text = "Hola, ¿cómo estás hoy? Espero que todo esté bien."

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("COST ANALYSIS")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("")

      # Approximate token counts (rough estimation)
      # Combined: 1 call with ~150 tokens total
      # Dedicated: 2 calls with ~100 tokens first, ~150 tokens second = ~250 total

      combined_conn =
        post(conn, "/api/v1/ai/translate", %{
          "text" => text,
          "detection_strategy" => "combined"
        })

      combined_response = json_response(combined_conn, 200)
      assert combined_response["success"]

      :timer.sleep(1000)

      dedicated_conn =
        post(conn, "/api/v1/ai/translate", %{
          "text" => text,
          "detection_strategy" => "dedicated"
        })

      dedicated_response = json_response(dedicated_conn, 200)
      assert dedicated_response["success"]

      # Rough cost estimates (llama-3.3-70b-versatile pricing)
      # Input: $0.05/1M tokens, Output: $0.20/1M tokens
      combined_estimated_tokens = 150
      dedicated_estimated_tokens = 250

      combined_cost = combined_estimated_tokens * 0.20 / 1_000_000
      dedicated_cost = dedicated_estimated_tokens * 0.20 / 1_000_000

      IO.puts("Text: \"#{text}\"")
      IO.puts("")
      IO.puts("Combined Strategy:")
      IO.puts("  Estimated tokens: ~#{combined_estimated_tokens}")
      IO.puts("  Estimated cost: $#{Float.round(combined_cost * 1_000_000, 6)}/1M tokens")
      IO.puts("  API calls: 1")
      IO.puts("")
      IO.puts("Dedicated Strategy:")
      IO.puts("  Estimated tokens: ~#{dedicated_estimated_tokens}")
      IO.puts("  Estimated cost: $#{Float.round(dedicated_cost * 1_000_000, 6)}/1M tokens")
      IO.puts("  API calls: 2")
      IO.puts("")
      IO.puts(
        "Cost difference: ~#{Float.round((dedicated_cost - combined_cost) / combined_cost * 100, 1)}% more expensive for dedicated"
      )
      IO.puts("=" |> String.duplicate(80))
      IO.puts("")
    end

    @tag :edge_cases
    test "handles edge cases consistently across strategies", %{conn: conn} do
      edge_cases = [
        %{name: "Very short text", text: "Hola", expected_success: true},
        %{
          name: "Mixed language",
          text: "Hello world, hola mundo",
          expected_success: true
        },
        %{
          name: "Text with emojis",
          text: "Hola 👋 ¿cómo estás? 😊",
          expected_success: true
        },
        %{
          name: "Text with numbers",
          text: "Tengo 25 años y vivo en Madrid",
          expected_success: true
        }
      ]

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("EDGE CASE HANDLING")
      IO.puts("=" |> String.duplicate(80))
      IO.puts("")

      Enum.each(edge_cases, fn test_case ->
        IO.puts("Testing: #{test_case.name}")
        IO.puts("  Text: \"#{test_case.text}\"")

        # Test combined
        combined_conn =
          post(conn, "/api/v1/ai/translate", %{
            "text" => test_case.text,
            "detection_strategy" => "combined"
          })

        combined_response = json_response(combined_conn, 200)
        combined_success = combined_response["success"] == true

        IO.puts("  Combined: #{if combined_success, do: "✓", else: "✗"}")

        :timer.sleep(1000)

        # Test dedicated
        dedicated_conn =
          post(conn, "/api/v1/ai/translate", %{
            "text" => test_case.text,
            "detection_strategy" => "dedicated"
          })

        dedicated_response = json_response(dedicated_conn, 200)
        dedicated_success = dedicated_response["success"] == true

        IO.puts("  Dedicated: #{if dedicated_success, do: "✓", else: "✗"}")
        IO.puts("")

        if test_case.expected_success do
          assert combined_success, "Combined strategy failed for #{test_case.name}"
          assert dedicated_success, "Dedicated strategy failed for #{test_case.name}"
        end
      end)

      IO.puts("=" |> String.duplicate(80))
      IO.puts("")
    end
  end

  # Helper functions

  defp measure_strategy(conn, text, strategy) do
    start_time = System.monotonic_time(:millisecond)

    conn =
      post(conn, "/api/v1/ai/translate", %{
        "text" => text,
        "detection_strategy" => strategy
      })

    elapsed_time = System.monotonic_time(:millisecond) - start_time

    response = json_response(conn, 200)

    IO.puts(
      "  #{String.capitalize(strategy)} (#{elapsed_time}ms): #{response["source_language"]} → #{response["translation"]}"
    )

    %{
      strategy: strategy,
      elapsed_ms: elapsed_time,
      success: response["success"] == true,
      detected_language: response["source_language"],
      detected_code: response["source_language_code"],
      translation: response["translation"],
      confidence: response["confidence"]
    }
  end

  defp print_summary_table(results) do
    IO.puts(
      String.pad_trailing("Text", 25) <>
        " | " <>
        String.pad_trailing("Strategy", 10) <>
        " | " <>
        String.pad_trailing("Detected", 10) <>
        " | " <>
        String.pad_trailing("Latency", 10) <>
        " | " <> "Confidence"
    )

    IO.puts("-" |> String.duplicate(80))

    Enum.each(results, fn result ->
      text_preview =
        if String.length(result.text) > 22 do
          String.slice(result.text, 0, 19) <> "..."
        else
          result.text
        end

      IO.puts(
        String.pad_trailing(text_preview, 25) <>
          " | " <>
          String.pad_trailing("Combined", 10) <>
          " | " <>
          String.pad_trailing(result.combined.detected_language || "N/A", 10) <>
          " | " <>
          String.pad_trailing("#{result.combined.elapsed_ms}ms", 10) <>
          " | " <> "#{Float.round(result.combined.confidence || 0.0, 2)}"
      )

      IO.puts(
        String.pad_trailing("", 25) <>
          " | " <>
          String.pad_trailing("Dedicated", 10) <>
          " | " <>
          String.pad_trailing(result.dedicated.detected_language || "N/A", 10) <>
          " | " <>
          String.pad_trailing("#{result.dedicated.elapsed_ms}ms", 10) <>
          " | " <> "#{Float.round(result.dedicated.confidence || 0.0, 2)}"
      )

      IO.puts("")
    end)
  end
end
