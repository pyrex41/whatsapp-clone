defmodule GlobalbridgeBackendWeb.AITranslation50LanguagesTest do
  @moduledoc """
  Comprehensive test of 50 different languages to evaluate detection accuracy
  across common and obscure languages.

  This test helps identify which languages work well with each strategy and
  which ones might need special handling or prompt improvements.
  """

  use GlobalbridgeBackendWeb.ConnCase, async: false

  import Phoenix.ConnTest

  alias GlobalbridgeBackend.Cache.ParticipantCache

  @moduletag :integration
  @moduletag :comprehensive
  @moduletag timeout: 600_000

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
      id: "test-user-50lang-#{:rand.uniform(100000)}",
      email: "50lang-test@example.com"
    }

    conn = assign(conn, :current_user, user)

    %{conn: conn, user: user}
  end

  @doc """
  Test cases covering 50 diverse languages from different language families:
  - Indo-European (Romance, Germanic, Slavic, Indo-Aryan)
  - Sino-Tibetan
  - Afro-Asiatic
  - Altaic
  - Austronesian
  - Niger-Congo
  - Japonic
  - Koreanic
  - Uralic
  - And more...
  """
  def get_50_language_test_cases do
    [
      # Common European Languages
      %{text: "Hello, how are you?", expected_code: "en", name: "English"},
      %{text: "Hola, ¿cómo estás?", expected_code: "es", name: "Spanish"},
      %{text: "Bonjour, comment allez-vous?", expected_code: "fr", name: "French"},
      %{text: "Guten Tag, wie geht es Ihnen?", expected_code: "de", name: "German"},
      %{text: "Ciao, come stai?", expected_code: "it", name: "Italian"},
      %{text: "Olá, como você está?", expected_code: "pt", name: "Portuguese"},

      # Slavic Languages
      %{text: "Привет, как дела?", expected_code: "ru", name: "Russian"},
      %{text: "Cześć, jak się masz?", expected_code: "pl", name: "Polish"},
      %{text: "Dobrý den, jak se máte?", expected_code: "cs", name: "Czech"},
      %{text: "Здравствуйте, як справи?", expected_code: "uk", name: "Ukrainian"},
      %{text: "Здраво, како си?", expected_code: "sr", name: "Serbian"},
      %{text: "Добар дан, како сте?", expected_code: "bg", name: "Bulgarian"},

      # Nordic Languages
      %{text: "Hej, hur mår du?", expected_code: "sv", name: "Swedish"},
      %{text: "Hei, hvordan har du det?", expected_code: "no", name: "Norwegian"},
      %{text: "Hej, hvordan har du det?", expected_code: "da", name: "Danish"},
      %{text: "Hei, mitä kuuluu?", expected_code: "fi", name: "Finnish"},
      %{text: "Halló, hvernig hefurðu það?", expected_code: "is", name: "Icelandic"},

      # Asian Languages
      %{text: "你好，你好吗？", expected_code: "zh", name: "Chinese (Simplified)"},
      %{text: "你好，你好嗎？", expected_code: "zh", name: "Chinese (Traditional)"},
      %{text: "こんにちは、お元気ですか？", expected_code: "ja", name: "Japanese"},
      %{text: "안녕하세요, 어떻게 지내세요?", expected_code: "ko", name: "Korean"},
      %{text: "สวัสดี คุณเป็นอย่างไรบ้าง", expected_code: "th", name: "Thai"},
      %{text: "Xin chào, bạn khỏe không?", expected_code: "vi", name: "Vietnamese"},
      %{text: "नमस्ते, आप कैसे हैं?", expected_code: "hi", name: "Hindi"},
      %{text: "হ্যালো, আপনি কেমন আছেন?", expected_code: "bn", name: "Bengali"},

      # Middle Eastern Languages
      %{text: "مرحبا، كيف حالك؟", expected_code: "ar", name: "Arabic"},
      %{text: "שלום, מה שלומך?", expected_code: "he", name: "Hebrew"},
      %{text: "سلام، حال شما چطور است?", expected_code: "fa", name: "Persian (Farsi)"},
      %{text: "Merhaba, nasılsın?", expected_code: "tr", name: "Turkish"},

      # Southeast Asian Languages
      %{text: "Halo, apa kabar?", expected_code: "id", name: "Indonesian"},
      %{text: "Kumusta ka?", expected_code: "tl", name: "Tagalog (Filipino)"},
      %{text: "ສະບາຍດີ, ເປັນແນວໃດ?", expected_code: "lo", name: "Lao"},
      %{text: "ជំរាបសួរ តើអ្នកសុខសប្បាយទេ?", expected_code: "km", name: "Khmer (Cambodian)"},
      %{text: "မင်္ဂလာပါ၊ ဘယ်လိုနေလဲ?", expected_code: "my", name: "Burmese"},

      # South Asian Languages
      %{text: "ਸਤ ਸ੍ਰੀ ਅਕਾਲ, ਤੁਸੀਂ ਕਿਵੇਂ ਹੋ?", expected_code: "pa", name: "Punjabi"},
      %{text: "નમસ્તે, તમે કેમ છો?", expected_code: "gu", name: "Gujarati"},
      %{text: "வணக்கம், எப்படி இருக்கிறீர்கள்?", expected_code: "ta", name: "Tamil"},
      %{text: "నమస్కారం, మీరు ఎలా ఉన్నారు?", expected_code: "te", name: "Telugu"},

      # African Languages
      %{text: "Sawubona, unjani?", expected_code: "zu", name: "Zulu"},
      %{text: "Habari, unajisikiaje?", expected_code: "sw", name: "Swahili"},
      %{text: "Sannu, yaya kake?", expected_code: "ha", name: "Hausa"},
      %{text: "Molo, unjani?", expected_code: "xh", name: "Xhosa"},

      # Other European Languages
      %{text: "Γεια σου, πώς είσαι;", expected_code: "el", name: "Greek"},
      %{text: "Bună ziua, cum ești?", expected_code: "ro", name: "Romanian"},
      %{text: "Helló, hogy vagy?", expected_code: "hu", name: "Hungarian"},
      %{text: "Hallo, hoe gaat het?", expected_code: "nl", name: "Dutch"},

      # Celtic Languages
      %{text: "Dia duit, conas atá tú?", expected_code: "ga", name: "Irish (Gaelic)"},
      %{text: "Shwmae, sut wyt ti?", expected_code: "cy", name: "Welsh"},

      # Baltic Languages
      %{text: "Sveiki, kā jums klājas?", expected_code: "lv", name: "Latvian"},
      %{text: "Labas, kaip laikaisi?", expected_code: "lt", name: "Lithuanian"},

      # Additional Languages
      %{text: "Tere, kuidas sul läheb?", expected_code: "et", name: "Estonian"},
      %{text: "Здраво, како сте?", expected_code: "mk", name: "Macedonian"}
    ]
  end

  describe "Comprehensive 50 Language Detection Test" do
    @tag :fifty_languages
    test "compares detection accuracy across 50 languages for both strategies", %{conn: conn} do
      test_cases = get_50_language_test_cases()

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(100))
      IO.puts("COMPREHENSIVE 50-LANGUAGE DETECTION ACCURACY TEST")
      IO.puts("=" |> String.duplicate(100))
      IO.puts("Testing #{length(test_cases)} languages with both Combined and Dedicated strategies")
      IO.puts("=" |> String.duplicate(100))
      IO.puts("")

      results =
        Enum.with_index(test_cases, 1)
        |> Enum.map(fn {test_case, index} ->
          IO.puts("[#{index}/#{length(test_cases)}] Testing: #{test_case.name}")

          # Test combined strategy
          combined_result = test_language_detection(conn, test_case, "combined")

          # Small delay to avoid rate limiting
          :timer.sleep(1000)

          # Test dedicated strategy
          dedicated_result = test_language_detection(conn, test_case, "dedicated")

          # Longer delay between languages
          :timer.sleep(1500)

          combined_correct =
            combined_result.detected_code == test_case.expected_code ||
              combined_result.detected_language == test_case.name

          dedicated_correct =
            dedicated_result.detected_code == test_case.expected_code ||
              dedicated_result.detected_language == test_case.name

          IO.puts(
            "  Combined: #{combined_result.detected_language} (#{combined_result.detected_code}) #{if combined_correct, do: "✓", else: "✗ (expected #{test_case.expected_code})"}"
          )

          IO.puts(
            "  Dedicated: #{dedicated_result.detected_language} (#{dedicated_result.detected_code}) #{if dedicated_correct, do: "✓", else: "✗ (expected #{test_case.expected_code})"}"
          )

          IO.puts("")

          %{
            language: test_case.name,
            expected_code: test_case.expected_code,
            combined: combined_result,
            combined_correct: combined_correct,
            dedicated: dedicated_result,
            dedicated_correct: dedicated_correct
          }
        end)

      # Print summary statistics
      print_language_test_summary(results)

      # Calculate overall accuracy
      combined_accuracy = Enum.count(results, & &1.combined_correct) / length(results) * 100
      dedicated_accuracy = Enum.count(results, & &1.dedicated_correct) / length(results) * 100

      IO.puts("\n")
      IO.puts("=" |> String.duplicate(100))
      IO.puts("FINAL ACCURACY RESULTS")
      IO.puts("=" |> String.duplicate(100))
      IO.puts("Combined Strategy:  #{Float.round(combined_accuracy, 1)}% (#{Enum.count(results, & &1.combined_correct)}/#{length(results)} correct)")
      IO.puts("Dedicated Strategy: #{Float.round(dedicated_accuracy, 1)}% (#{Enum.count(results, & &1.dedicated_correct)}/#{length(results)} correct)")
      IO.puts("=" |> String.duplicate(100))
      IO.puts("")

      # Both strategies should have reasonable accuracy (at least 60% for such diverse languages)
      assert combined_accuracy >= 60.0,
             "Combined strategy accuracy too low: #{combined_accuracy}%"

      assert dedicated_accuracy >= 60.0,
             "Dedicated strategy accuracy too low: #{dedicated_accuracy}%"
    end
  end

  # Helper functions

  defp test_language_detection(conn, test_case, strategy) do
    conn =
      post(conn, "/api/v1/ai/translate", %{
        "text" => test_case.text,
        "detection_strategy" => strategy
      })

    case json_response(conn, 200) do
      %{"success" => true} = response ->
        %{
          detected_language: response["source_language"],
          detected_code: response["source_language_code"],
          translation: response["translation"],
          confidence: response["confidence"],
          success: true
        }

      _error ->
        %{
          detected_language: "error",
          detected_code: "error",
          translation: nil,
          confidence: 0.0,
          success: false
        }
    end
  rescue
    _ ->
      %{
        detected_language: "error",
        detected_code: "error",
        translation: nil,
        confidence: 0.0,
        success: false
      }
  end

  defp print_language_test_summary(results) do
    IO.puts("\n")
    IO.puts("=" |> String.duplicate(100))
    IO.puts("DETAILED RESULTS BY LANGUAGE FAMILY")
    IO.puts("=" |> String.duplicate(100))

    # Group by language family (simplified grouping)
    language_families = %{
      "European Romance" => [
        "Spanish",
        "French",
        "Italian",
        "Portuguese",
        "Romanian"
      ],
      "European Germanic" => [
        "English",
        "German",
        "Dutch",
        "Swedish",
        "Norwegian",
        "Danish",
        "Icelandic"
      ],
      "European Slavic" => [
        "Russian",
        "Polish",
        "Czech",
        "Ukrainian",
        "Serbian",
        "Bulgarian",
        "Macedonian"
      ],
      "Asian (East)" => ["Chinese (Simplified)", "Chinese (Traditional)", "Japanese", "Korean"],
      "Asian (South)" => ["Hindi", "Bengali", "Punjabi", "Gujarati", "Tamil", "Telugu"],
      "Asian (Southeast)" => [
        "Thai",
        "Vietnamese",
        "Indonesian",
        "Tagalog (Filipino)",
        "Lao",
        "Khmer (Cambodian)",
        "Burmese"
      ],
      "Middle Eastern" => ["Arabic", "Hebrew", "Persian (Farsi)", "Turkish"],
      "African" => ["Zulu", "Swahili", "Hausa", "Xhosa"],
      "Other" => [
        "Greek",
        "Hungarian",
        "Finnish",
        "Estonian",
        "Irish (Gaelic)",
        "Welsh",
        "Latvian",
        "Lithuanian"
      ]
    }

    Enum.each(language_families, fn {family, languages} ->
      family_results = Enum.filter(results, fn r -> r.language in languages end)

      if length(family_results) > 0 do
        combined_correct = Enum.count(family_results, & &1.combined_correct)
        dedicated_correct = Enum.count(family_results, & &1.dedicated_correct)
        total = length(family_results)

        combined_pct = Float.round(combined_correct / total * 100, 1)
        dedicated_pct = Float.round(dedicated_correct / total * 100, 1)

        IO.puts("\n#{family} (#{total} languages)")
        IO.puts("  Combined:  #{combined_pct}% (#{combined_correct}/#{total})")
        IO.puts("  Dedicated: #{dedicated_pct}% (#{dedicated_correct}/#{total})")

        # Show failures
        failures =
          Enum.filter(family_results, fn r ->
            !r.combined_correct or !r.dedicated_correct
          end)

        if length(failures) > 0 do
          IO.puts("  Failures:")

          Enum.each(failures, fn f ->
            if !f.combined_correct do
              IO.puts(
                "    - #{f.language}: Combined detected as #{f.combined.detected_language}"
              )
            end

            if !f.dedicated_correct do
              IO.puts(
                "    - #{f.language}: Dedicated detected as #{f.dedicated.detected_language}"
              )
            end
          end)
        end
      end
    end)

    IO.puts("")
  end
end
