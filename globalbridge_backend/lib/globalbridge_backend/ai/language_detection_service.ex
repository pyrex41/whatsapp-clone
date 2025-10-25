defmodule GlobalbridgeBackend.AI.LanguageDetectionService do
  @moduledoc """
  Service for detecting the source language of text using LLM-based detection.

  Provides two detection strategies:
  1. Dedicated detection (separate LLM call specialized in language detection)
  2. Combined detection (detection happens during translation in single call)

  Configuration:
  - LANGUAGE_DETECTION_STRATEGY: "dedicated" | "combined" (default: "combined")
  - TRANSLATION_MODEL: Model to use (e.g., "llama-3.3-70b-versatile" or "grok-4-fast-non-reasoning")
  - GROQ_API_KEY: API key for Groq (required for llama models)
  - XAI_API_KEY: API key for XAI (required for grok models)

  Provider is automatically determined based on model name:
  - Models starting with "grok-" use XAI API
  - Models containing "llama" or "mixtral" use Groq API
  """

  require Logger

  @language_code_to_name %{
    "en" => "English",
    "es" => "Spanish",
    "fr" => "French",
    "de" => "German",
    "it" => "Italian",
    "pt" => "Portuguese",
    "ja" => "Japanese",
    "zh" => "Chinese",
    "ko" => "Korean",
    "ru" => "Russian",
    "ar" => "Arabic",
    "hi" => "Hindi"
  }

  @language_name_to_code %{
    "english" => "en",
    "spanish" => "es",
    "french" => "fr",
    "german" => "de",
    "italian" => "it",
    "portuguese" => "pt",
    "japanese" => "ja",
    "chinese" => "zh",
    "korean" => "ko",
    "russian" => "ru",
    "arabic" => "ar",
    "hindi" => "hi"
  }

  @doc """
  Gets the full language name from a language code.

  ## Examples
      iex> get_language_name("es")
      "Spanish"

      iex> get_language_name("unknown")
      "unknown"
  """
  def get_language_name(code) when is_binary(code) do
    Map.get(@language_code_to_name, String.downcase(code), code)
  end

  @doc """
  Gets the language code from a full language name.

  ## Examples
      iex> get_language_code("Spanish")
      "es"

      iex> get_language_code("Unknown Language")
      nil
  """
  def get_language_code(name) when is_binary(name) do
    Map.get(@language_name_to_code, String.downcase(name))
  end

  @doc """
  Detects the language of the given text using a dedicated LLM call.

  This strategy makes a separate, specialized API call focused only on
  language detection. It's more accurate but requires an additional API call.

  ## Parameters
    - text: The text to analyze

  ## Returns
    - {:ok, %{language: "Spanish", language_code: "es", confidence: 0.98}}
    - {:error, reason}

  ## Examples
      iex> detect_language_dedicated("Hola mundo")
      {:ok, %{language: "Spanish", language_code: "es", confidence: 0.98}}
  """
  def detect_language_dedicated(text) when is_binary(text) do
    model = System.get_env("TRANSLATION_MODEL") || "llama-3.3-70b-versatile"
    provider = determine_provider(model)

    Logger.info("LanguageDetectionService: Detecting language using dedicated strategy with #{provider} (#{model})")

    prompt = """
    Detect the primary language of the following text.
    Provide a confidence score (0.0 to 1.0) indicating how certain you are.

    Text: #{text}

    Respond in JSON format:
    {
      "language": "full language name (e.g., Spanish, French, English)",
      "confidence": 0.98
    }

    Only return the JSON, nothing else.
    """

    call_api_for_detection(provider, model, prompt)
  end

  defp determine_provider(model) do
    cond do
      String.starts_with?(model, "grok-") -> :xai
      String.contains?(model, "llama") or String.contains?(model, "mixtral") -> :groq
      true -> :groq  # Default to Groq
    end
  end

  defp call_api_for_detection(provider, model, prompt) do
    {api_key, api_key_name, url} =
      case provider do
        :xai ->
          {System.get_env("XAI_API_KEY"), "XAI_API_KEY", "https://api.x.ai/v1/chat/completions"}
        :groq ->
          {System.get_env("GROQ_API_KEY"), "GROQ_API_KEY", "https://api.groq.com/openai/v1/chat/completions"}
      end

    if is_nil(api_key) do
      {:error, "#{api_key_name} not configured"}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        model: model,
        messages: [
          %{
            role: "system",
            content: "You are a language detection expert. Always respond with valid JSON."
          },
          %{role: "user", content: prompt}
        ],
        temperature: 0.1,
        response_format: %{type: "json_object"}
      })

      case HTTPoison.post(url, body, headers, recv_timeout: 15_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          parse_detection_response(response_body)

        {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
          Logger.error("#{provider} API error during language detection: #{status_code} - #{error_body}")
          {:error, "Language detection API error: #{status_code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTP error calling #{provider} for language detection: #{inspect(reason)}")
          {:error, "Language detection service unavailable"}
      end
    end
  end

  @doc """
  Parses the language detection response from the LLM.

  Extracts language name, converts to code, and includes confidence.
  """
  defp parse_detection_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        case Jason.decode(content) do
          {:ok, %{"language" => language, "confidence" => confidence}} ->
            language_code = get_language_code(language) || "unknown"

            result = %{
              language: language,
              language_code: language_code,
              confidence: confidence
            }

            Logger.info(
              "LanguageDetectionService: Detected language: #{language} (#{language_code}), confidence: #{confidence}"
            )

            {:ok, result}

          {:ok, invalid_json} ->
            Logger.error("Invalid JSON structure from language detection: #{inspect(invalid_json)}")
            {:error, "Invalid language detection response format"}

          {:error, decode_error} ->
            Logger.error("Failed to decode language detection JSON: #{inspect(decode_error)}")
            {:error, "Failed to parse language detection result"}
        end

      {:error, decode_error} ->
        Logger.error("Failed to decode Groq API response: #{inspect(decode_error)}")
        {:error, "Failed to parse API response"}

      _ ->
        {:error, "Invalid API response format"}
    end
  end

  @doc """
  Detects the language and translates in a single LLM call.

  This strategy is more efficient (1 API call instead of 2) but may be
  slightly less accurate for language detection.

  ## Parameters
    - text: The text to translate
    - target_language_code: Optional target language code (if nil, defaults to English)

  ## Returns
    - {:ok, %{
        translation: "translated text",
        confidence: 0.95,
        cultural_notes: [],
        source_language: "Spanish",
        source_language_code: "es",
        target_language: "English",
        target_language_code: "en"
      }}
    - {:error, reason}

  ## Examples
      iex> detect_and_translate("Hola mundo", "en")
      {:ok, %{
        translation: "Hello world",
        source_language: "Spanish",
        source_language_code: "es",
        target_language: "English",
        target_language_code: "en",
        confidence: 0.98,
        cultural_notes: []
      }}
  """
  def detect_and_translate(text, target_language_code \\ "en") do
    model = System.get_env("TRANSLATION_MODEL") || "llama-3.3-70b-versatile"
    provider = determine_provider(model)
    target_language_name = get_language_name(target_language_code || "en")

    Logger.info(
      "LanguageDetectionService: Detecting and translating to #{target_language_name} using combined strategy with #{provider} (#{model})"
    )

    prompt = """
    Detect the source language of the following text, then translate it to #{target_language_name}.
    Provide a confidence score (0.0 to 1.0) for the translation quality.
    If there are any idioms or cultural phrases, note them.

    Text: #{text}

    Respond in JSON format:
    {
      "source_language": "detected language name (e.g., Spanish, French)",
      "target_language": "#{target_language_name}",
      "translation": "the translated text",
      "confidence": 0.95,
      "cultural_notes": []
    }

    The cultural_notes should be an array of objects with this structure:
    {
      "source_phrase": "the idiom or cultural phrase",
      "explanation": "what it means",
      "target_equivalent": "best translation in target language",
      "cultural_context": "cultural background information"
    }

    Only return the JSON, nothing else.
    """

    call_api_for_translation(provider, model, prompt, target_language_code)
  end

  defp call_api_for_translation(provider, model, prompt, target_language_code) do
    {api_key, api_key_name, url} =
      case provider do
        :xai ->
          {System.get_env("XAI_API_KEY"), "XAI_API_KEY", "https://api.x.ai/v1/chat/completions"}
        :groq ->
          {System.get_env("GROQ_API_KEY"), "GROQ_API_KEY", "https://api.groq.com/openai/v1/chat/completions"}
      end

    if is_nil(api_key) do
      {:error, "#{api_key_name} not configured"}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        model: model,
        messages: [
          %{
            role: "system",
            content: "You are a professional translator. Always respond with valid JSON."
          },
          %{role: "user", content: prompt}
        ],
        temperature: 0.3,
        response_format: %{type: "json_object"}
      })

      case HTTPoison.post(url, body, headers, recv_timeout: 30_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          parse_combined_response(response_body, target_language_code)

        {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
          Logger.error("#{provider} API error during detect-and-translate: #{status_code} - #{error_body}")
          {:error, "Translation API error: #{status_code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTP error calling #{provider} for detect-and-translate: #{inspect(reason)}")
          {:error, "Translation service unavailable"}
      end
    end
  end

  @doc """
  Parses the combined detection and translation response from the LLM.
  """
  defp parse_combined_response(response_body, target_language_code) do
    case Jason.decode(response_body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        case Jason.decode(content) do
          {:ok, result} ->
            source_language = result["source_language"]
            source_language_code = get_language_code(source_language) || "unknown"
            target_language = result["target_language"]

            response = %{
              translation: result["translation"],
              confidence: result["confidence"] || 0.9,
              cultural_notes: result["cultural_notes"] || [],
              source_language: source_language,
              source_language_code: source_language_code,
              target_language: target_language,
              target_language_code: target_language_code
            }

            Logger.info(
              "LanguageDetectionService: Detected #{source_language} (#{source_language_code}), translated to #{target_language}"
            )

            {:ok, response}

          {:error, _} ->
            {:error, "Failed to parse translation result"}
        end

      _ ->
        {:error, "Invalid API response format"}
    end
  end

  @doc """
  Gets the configured language detection strategy.

  Returns either "dedicated" or "combined" based on the
  LANGUAGE_DETECTION_STRATEGY environment variable.

  Defaults to "dedicated" for higher accuracy.
  """
  def get_detection_strategy do
    case System.get_env("LANGUAGE_DETECTION_STRATEGY") do
      "combined" -> :combined
      "dedicated" -> :dedicated
      _ -> :dedicated
    end
  end
end
