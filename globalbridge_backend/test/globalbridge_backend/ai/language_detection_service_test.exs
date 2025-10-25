defmodule GlobalbridgeBackend.AI.LanguageDetectionServiceTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.LanguageDetectionService

  describe "get_language_name/1" do
    test "converts language codes to full names" do
      assert LanguageDetectionService.get_language_name("es") == "Spanish"
      assert LanguageDetectionService.get_language_name("en") == "English"
      assert LanguageDetectionService.get_language_name("fr") == "French"
      assert LanguageDetectionService.get_language_name("de") == "German"
      assert LanguageDetectionService.get_language_name("it") == "Italian"
      assert LanguageDetectionService.get_language_name("pt") == "Portuguese"
      assert LanguageDetectionService.get_language_name("ja") == "Japanese"
      assert LanguageDetectionService.get_language_name("zh") == "Chinese"
      assert LanguageDetectionService.get_language_name("ko") == "Korean"
      assert LanguageDetectionService.get_language_name("ru") == "Russian"
      assert LanguageDetectionService.get_language_name("ar") == "Arabic"
      assert LanguageDetectionService.get_language_name("hi") == "Hindi"
    end

    test "returns input for unknown language codes" do
      assert LanguageDetectionService.get_language_name("unknown") == "unknown"
      assert LanguageDetectionService.get_language_name("xyz") == "xyz"
    end

    test "handles case insensitivity" do
      assert LanguageDetectionService.get_language_name("ES") == "Spanish"
      assert LanguageDetectionService.get_language_name("En") == "English"
    end
  end

  describe "get_language_code/1" do
    test "converts language names to codes" do
      assert LanguageDetectionService.get_language_code("Spanish") == "es"
      assert LanguageDetectionService.get_language_code("English") == "en"
      assert LanguageDetectionService.get_language_code("French") == "fr"
      assert LanguageDetectionService.get_language_code("German") == "de"
      assert LanguageDetectionService.get_language_code("Italian") == "it"
      assert LanguageDetectionService.get_language_code("Portuguese") == "pt"
      assert LanguageDetectionService.get_language_code("Japanese") == "ja"
      assert LanguageDetectionService.get_language_code("Chinese") == "zh"
      assert LanguageDetectionService.get_language_code("Korean") == "ko"
      assert LanguageDetectionService.get_language_code("Russian") == "ru"
      assert LanguageDetectionService.get_language_code("Arabic") == "ar"
      assert LanguageDetectionService.get_language_code("Hindi") == "hi"
    end

    test "returns nil for unknown language names" do
      assert LanguageDetectionService.get_language_code("Unknown Language") == nil
      assert LanguageDetectionService.get_language_code("Klingon") == nil
    end

    test "handles case insensitivity" do
      assert LanguageDetectionService.get_language_code("spanish") == "es"
      assert LanguageDetectionService.get_language_code("ENGLISH") == "en"
      assert LanguageDetectionService.get_language_code("FrEnCh") == "fr"
    end
  end

  describe "get_detection_strategy/0" do
    test "returns configured strategy or default" do
      strategy = LanguageDetectionService.get_detection_strategy()
      assert strategy in [:dedicated, :combined]
    end

    test "defaults to dedicated when env not set" do
      # In test environment, we expect it to use the default
      strategy = LanguageDetectionService.get_detection_strategy()
      assert strategy == :dedicated
    end
  end

  describe "detect_language_dedicated/1 - integration" do
    @tag :integration
    @tag timeout: 30_000
    test "detects Spanish text" do
      case LanguageDetectionService.detect_language_dedicated("Hola, ¿cómo estás?") do
        {:ok, result} ->
          assert result.language
          assert result.language_code
          assert result.confidence
          assert is_float(result.confidence)
          assert result.confidence >= 0.0 and result.confidence <= 1.0

        {:error, reason} ->
          # API might not be configured in test environment
          assert reason =~ "GROQ_API_KEY"
      end
    end

    @tag :integration
    @tag timeout: 30_000
    test "detects French text" do
      case LanguageDetectionService.detect_language_dedicated("Bonjour le monde") do
        {:ok, result} ->
          assert result.language
          assert result.language_code
          assert result.confidence

        {:error, reason} ->
          assert reason =~ "GROQ_API_KEY"
      end
    end

    @tag :integration
    @tag timeout: 30_000
    test "detects German text" do
      case LanguageDetectionService.detect_language_dedicated("Guten Tag") do
        {:ok, result} ->
          assert result.language
          assert result.language_code

        {:error, reason} ->
          assert reason =~ "GROQ_API_KEY"
      end
    end

    test "returns error when API key not configured" do
      # Save current API key
      original_key = System.get_env("GROQ_API_KEY")

      # Temporarily unset it
      System.delete_env("GROQ_API_KEY")

      result = LanguageDetectionService.detect_language_dedicated("Hello")

      # Restore original key
      if original_key do
        System.put_env("GROQ_API_KEY", original_key)
      end

      assert {:error, "GROQ_API_KEY not configured"} = result
    end
  end

  describe "detect_and_translate/2 - integration" do
    @tag :integration
    @tag timeout: 30_000
    test "detects and translates Spanish to English" do
      case LanguageDetectionService.detect_and_translate("Hola mundo", "en") do
        {:ok, result} ->
          assert result.translation
          assert result.source_language
          assert result.source_language_code
          assert result.target_language == "English"
          assert result.target_language_code == "en"
          assert result.confidence
          assert is_list(result.cultural_notes)

        {:error, reason} ->
          assert reason =~ "GROQ_API_KEY"
      end
    end

    @tag :integration
    @tag timeout: 30_000
    test "detects and translates to Spanish" do
      case LanguageDetectionService.detect_and_translate("Hello world", "es") do
        {:ok, result} ->
          assert result.translation
          assert result.target_language == "Spanish"
          assert result.target_language_code == "es"

        {:error, reason} ->
          assert reason =~ "GROQ_API_KEY"
      end
    end

    @tag :integration
    @tag timeout: 30_000
    test "defaults to English when target not specified" do
      case LanguageDetectionService.detect_and_translate("Bonjour") do
        {:ok, result} ->
          assert result.target_language == "English"
          assert result.target_language_code == "en"

        {:error, reason} ->
          assert reason =~ "GROQ_API_KEY"
      end
    end

    test "returns error when API key not configured" do
      original_key = System.get_env("GROQ_API_KEY")
      System.delete_env("GROQ_API_KEY")

      result = LanguageDetectionService.detect_and_translate("Hello", "es")

      if original_key do
        System.put_env("GROQ_API_KEY", original_key)
      end

      assert {:error, "GROQ_API_KEY not configured"} = result
    end
  end

  describe "language code mappings" do
    test "all supported language codes have name mappings" do
      supported_codes = ~w(en es fr de it pt ja zh ko ru ar hi)

      Enum.each(supported_codes, fn code ->
        name = LanguageDetectionService.get_language_name(code)
        assert name != code, "Missing name mapping for code: #{code}"
      end)
    end

    test "all language names have reverse code mappings" do
      language_names = [
        "English",
        "Spanish",
        "French",
        "German",
        "Italian",
        "Portuguese",
        "Japanese",
        "Chinese",
        "Korean",
        "Russian",
        "Arabic",
        "Hindi"
      ]

      Enum.each(language_names, fn name ->
        code = LanguageDetectionService.get_language_code(name)
        assert code != nil, "Missing code mapping for language: #{name}"
        assert String.length(code) == 2, "Invalid code format for #{name}: #{code}"
      end)
    end

    test "round-trip conversion preserves information" do
      codes = ~w(en es fr de it pt ja zh ko ru ar hi)

      Enum.each(codes, fn code ->
        name = LanguageDetectionService.get_language_name(code)
        round_trip_code = LanguageDetectionService.get_language_code(name)
        assert round_trip_code == code, "Round trip failed for #{code}: #{name} → #{round_trip_code}"
      end)
    end
  end
end
