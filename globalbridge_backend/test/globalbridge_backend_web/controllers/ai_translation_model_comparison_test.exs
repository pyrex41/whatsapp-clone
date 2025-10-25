defmodule GlobalbridgeBackendWeb.AITranslationModelComparisonTest do
  @moduledoc """
  Comprehensive model comparison test for translation and language detection.

  Tests multiple models from different providers:
  - XAI/Grok: grok-code-fast-1, grok-4-fast-nonreasoning, grok-4-fast-reasoning
  - Groq: llama-3.1-8b-instant, llama-3.3-70b-versatile, meta-llama/llama-guard-4-12b,
          meta-llama/llama-4-scout-17b-16e-instruct, meta-llama/llama-prompt-guard-2-22m

  Evaluates:
  - Detection accuracy across 15 representative languages
  - Translation quality
  - Speed/latency
  - Error rates
  """

  use GlobalbridgeBackendWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias GlobalbridgeBackend.Cache.ParticipantCache

  @moduletag :integration
  @moduletag :model_comparison
  @moduletag timeout: 900_000  # 15 minutes

  setup %{conn: conn} do
    # Start ParticipantCache if not already running
    case Process.whereis(ParticipantCache) do
      nil ->
        {:ok, _pid} = start_supervised(ParticipantCache)

      _pid ->
        :ok
    end

    ParticipantCache.clear()

    user = %{
      id: "test-user-models-#{:rand.uniform(100000)}",
      email: "models-test@example.com"
    }

    conn = assign(conn, :current_user, user)

    %{conn: conn, user: user}
  end

  @doc """
  Models to test - organized by provider
  """
  def get_test_models do
    %{
      xai: [
        "grok-code-fast-1",
        "grok-4-fast-non-reasoning",
        "grok-4-fast-reasoning"
      ],
      groq: [
        "llama-3.1-8b-instant",
        "llama-3.3-70b-versatile",
        "meta-llama/llama-4-scout-17b-16e-instruct"
      ]
    }
  end

  @doc """
  Representative language test cases covering different language families.
  Using 10 diverse languages for faster iteration across many models.
  """
  def get_representative_languages do
    [
      # Common European
      %{text: "Hello, how are you?", expected_code: "en", name: "English", family: "Germanic"},
      %{text: "Hola, ¿cómo estás?", expected_code: "es", name: "Spanish", family: "Romance"},
      %{text: "Bonjour, comment allez-vous?", expected_code: "fr", name: "French", family: "Romance"},

      # Slavic
      %{text: "Привет, как дела?", expected_code: "ru", name: "Russian", family: "Slavic"},

      # Asian
      %{text: "你好，你好吗？", expected_code: "zh", name: "Chinese", family: "Sino-Tibetan"},
      %{text: "こんにちは、お元気ですか？", expected_code: "ja", name: "Japanese", family: "Japonic"},
      %{text: "नमस्ते, आप कैसे हैं?", expected_code: "hi", name: "Hindi", family: "Indo-Aryan"},

      # Middle Eastern
      %{text: "مرحبا، كيف حالك؟", expected_code: "ar", name: "Arabic", family: "Afro-Asiatic"},

      # Other
      %{text: "Merhaba, nasılsın?", expected_code: "tr", name: "Turkish", family: "Turkic"},
      %{text: "Halo, apa kabar?", expected_code: "id", name: "Indonesian", family: "Austronesian"}
    ]
  end

  describe "Multi-Model Translation Comparison" do
    @tag :model_benchmark
    test "compares all models across representative languages", %{conn: conn} do
      models = get_test_models()
      languages = get_representative_languages()

      all_models = models.xai ++ models.groq

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(120))
      IO.puts("MULTI-MODEL TRANSLATION & DETECTION COMPARISON")
      IO.puts("=" |> String.duplicate(120))
      IO.puts("Models to test: #{length(all_models)}")
      IO.puts("Languages to test: #{length(languages)}")
      IO.puts("Total tests: #{length(all_models) * length(languages)} (combined strategy)")
      IO.puts("=" |> String.duplicate(120))
      IO.puts("")

      # Test each model
      model_results =
        Enum.map(all_models, fn model ->
          provider = determine_provider(model)

          IO.puts("\n")
          IO.puts("-" |> String.duplicate(120))
          IO.puts("Testing Model: #{model} (Provider: #{provider})")
          IO.puts("-" |> String.duplicate(120))

          # Test all languages with this model
          language_results =
            Enum.with_index(languages, 1)
            |> Enum.map(fn {lang, idx} ->
              IO.puts("  [#{idx}/#{length(languages)}] #{lang.name}...")

              result = test_model_with_language(conn, model, lang)

              status = if result.success and result.correct, do: "✓", else: "✗"
              detected = if result.success, do: result.detected_language, else: "ERROR"
              latency = if result.success, do: "#{result.latency}ms", else: "N/A"

              IO.puts("      Result: #{status} Detected: #{detected} | Latency: #{latency}")

              # Rate limiting delay
              :timer.sleep(800)

              result
            end)

          # Calculate model statistics
          successful = Enum.count(language_results, & &1.success)
          correct = Enum.count(language_results, &(&1.success and &1.correct))
          total = length(language_results)

          avg_latency =
            language_results
            |> Enum.filter(& &1.success)
            |> Enum.map(& &1.latency)
            |> case do
              [] -> 0
              latencies -> Enum.sum(latencies) / length(latencies)
            end

          accuracy = if successful > 0, do: correct / successful * 100, else: 0.0
          success_rate = successful / total * 100

          IO.puts("\n  Model Summary:")
          IO.puts("    Success Rate: #{Float.round(success_rate, 1)}% (#{successful}/#{total})")
          IO.puts("    Accuracy: #{Float.round(accuracy, 1)}% (#{correct}/#{successful} of successful)")
          IO.puts("    Avg Latency: #{Float.round(avg_latency, 0)}ms")
          IO.puts("    Errors: #{total - successful}")

          %{
            model: model,
            provider: provider,
            total_tests: total,
            successful: successful,
            correct: correct,
            success_rate: success_rate,
            accuracy: accuracy,
            avg_latency: avg_latency,
            errors: total - successful,
            language_results: language_results
          }
        end)

      # Print comprehensive summary
      print_model_comparison_summary(model_results)

      # Find best model
      best_model = Enum.max_by(model_results, fn m ->
        # Weighted score: 50% accuracy, 30% success rate, 20% speed
        (m.accuracy * 0.5) + (m.success_rate * 0.3) - (m.avg_latency / 100 * 0.2)
      end)

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(120))
      IO.puts("🏆 RECOMMENDED MODEL: #{best_model.model}")
      IO.puts("   Provider: #{best_model.provider}")
      IO.puts("   Accuracy: #{Float.round(best_model.accuracy, 1)}%")
      IO.puts("   Success Rate: #{Float.round(best_model.success_rate, 1)}%")
      IO.puts("   Avg Latency: #{Float.round(best_model.avg_latency, 0)}ms")
      IO.puts("=" |> String.duplicate(120))
      IO.puts("")
    end
  end

  # Helper functions

  defp determine_provider(model) do
    cond do
      String.starts_with?(model, "grok-") -> :xai
      String.contains?(model, "llama") or String.contains?(model, "mixtral") -> :groq
      true -> :unknown
    end
  end

  defp test_model_with_language(conn, model, language) do
    start_time = System.monotonic_time(:millisecond)

    # Set the model in environment for this test
    original_model = System.get_env("TRANSLATION_MODEL")
    System.put_env("TRANSLATION_MODEL", model)

    try do
      conn = post(conn, "/api/v1/ai/translate", %{
        "text" => language.text,
        "detection_strategy" => "combined"
      })

      elapsed = System.monotonic_time(:millisecond) - start_time

      case json_response(conn, 200) do
        %{"success" => true} = response ->
          detected_code = response["source_language_code"]
          detected_lang = response["source_language"]

          # Check if detection is correct (either code or name matches)
          correct =
            detected_code == language.expected_code or
            String.downcase(detected_lang || "") == String.downcase(language.name)

          %{
            success: true,
            correct: correct,
            detected_language: detected_lang,
            detected_code: detected_code,
            translation: response["translation"],
            latency: elapsed,
            error: nil
          }

        _error ->
          %{
            success: false,
            correct: false,
            detected_language: nil,
            detected_code: nil,
            translation: nil,
            latency: elapsed,
            error: "API returned error response"
          }
      end
    rescue
      e ->
        elapsed = System.monotonic_time(:millisecond) - start_time
        %{
          success: false,
          correct: false,
          detected_language: nil,
          detected_code: nil,
          translation: nil,
          latency: elapsed,
          error: Exception.message(e)
        }
    after
      # Restore original model
      if original_model do
        System.put_env("TRANSLATION_MODEL", original_model)
      else
        System.delete_env("TRANSLATION_MODEL")
      end
    end
  end

  defp print_model_comparison_summary(model_results) do
    IO.puts("\n")
    IO.puts("=" |> String.duplicate(120))
    IO.puts("COMPREHENSIVE MODEL COMPARISON SUMMARY")
    IO.puts("=" |> String.duplicate(120))

    # Sort by accuracy descending
    sorted_results = Enum.sort_by(model_results, & &1.accuracy, :desc)

    IO.puts("\n#{String.pad_trailing("Model", 45)} | #{String.pad_trailing("Provider", 8)} | #{String.pad_trailing("Success", 10)} | #{String.pad_trailing("Accuracy", 10)} | #{String.pad_trailing("Latency", 10)} | Errors")
    IO.puts("-" |> String.duplicate(120))

    Enum.each(sorted_results, fn result ->
      model_name = String.pad_trailing(result.model, 45)
      provider = String.pad_trailing(to_string(result.provider), 8)
      success = String.pad_trailing("#{Float.round(result.success_rate, 1)}%", 10)
      accuracy = String.pad_trailing("#{Float.round(result.accuracy, 1)}%", 10)
      latency = String.pad_trailing("#{Float.round(result.avg_latency, 0)}ms", 10)
      errors = result.errors

      IO.puts("#{model_name} | #{provider} | #{success} | #{accuracy} | #{latency} | #{errors}")
    end)

    IO.puts("")

    # Group by provider
    IO.puts("\nPERFORMANCE BY PROVIDER:")
    IO.puts("-" |> String.duplicate(120))

    model_results
    |> Enum.group_by(& &1.provider)
    |> Enum.each(fn {provider, models} ->
      avg_accuracy = Enum.sum(Enum.map(models, & &1.accuracy)) / length(models)
      avg_success = Enum.sum(Enum.map(models, & &1.success_rate)) / length(models)
      avg_latency = Enum.sum(Enum.map(models, & &1.avg_latency)) / length(models)

      IO.puts("\n#{provider |> to_string() |> String.upcase()}:")
      IO.puts("  Models tested: #{length(models)}")
      IO.puts("  Avg Accuracy: #{Float.round(avg_accuracy, 1)}%")
      IO.puts("  Avg Success Rate: #{Float.round(avg_success, 1)}%")
      IO.puts("  Avg Latency: #{Float.round(avg_latency, 0)}ms")
    end)

    IO.puts("")
  end
end
