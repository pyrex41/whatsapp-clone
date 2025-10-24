defmodule GlobalbridgeBackend.AI.Agents.TranslatorAgent do
  @moduledoc """
  Agent for translating text using OpenAI with cultural context integration.

  This module provides the configuration for an Agens agent that performs translations
  while incorporating cultural nuances via the CulturalContextTool. It outputs translated
  text with an AI-estimated confidence score (0.0 to 1.0) based on factors like text complexity,
  cultural context availability, and potential translation challenges (e.g., idioms).

  The agent is designed for use within the Agens job step framework (e.g., TranslationJob)
  but includes helper functions for direct parsing and translation if needed outside the job.
  """

  alias Agens.Agent

  @type translation_result :: %{
    translation: String.t(),
    confidence: float()
  }

  @doc """
  Returns the configuration for the TranslatorAgent.

  This config integrates OpenAI serving, the CulturalContextTool for cultural awareness,
  and a prompt that instructs the model to provide translations with confidence scores.
  The prompt handles edge cases like empty text or identical source/target languages.
  """
  @spec config() :: %Agent.Config{}
  def config do
    %Agent.Config{
      name: :translator_agent,
      serving: :openai_serving,
      tool: GlobalbridgeBackend.AI.Tools.CulturalContextTool,
      prompt: %Agent.Prompt{
        identity: "You are an expert translator specializing in culturally appropriate translations.",
        context:
          "Translate the given text from the detected source language to the target language, using any provided cultural context to ensure appropriateness and nuance. Provide a confidence score reflecting translation quality.",
        constraints: """
        - Always consider cultural nuances, idioms, regional variations, and contextual appropriateness from the cultural analysis.
        - Output in this exact format:
          Translation: <translated text>
          Confidence: <score between 0.0 and 1.0>
        - Base confidence on: text complexity, availability of cultural context, presence of idioms or challenging phrases, and overall translation fidelity.
        - Edge cases:
          - If source and target languages are the same, return the original text with confidence 1.0.
          - If input text is empty or whitespace-only, return empty text with confidence 1.0.
          - If translation is uncertain (e.g., due to unknown idioms), lower the confidence accordingly (e.g., 0.5 or below).
        """
      }
    }
  end

  @doc """
  Parses the raw output from the TranslatorAgent into a structured result.

  This helper extracts the translation and confidence score from the agent's string output,
  enabling easier consumption in the application (e.g., by TranslationJob or other callers).
  Returns an error if the output format is invalid.

  ## Examples

      iex> parse_result("Translation: Hello world\\nConfidence: 0.95")
      {:ok, %{translation: "Hello world", confidence: 0.95}}

      iex> parse_result("Invalid output")
      {:error, "Unable to parse translation result"}
  """
  @spec parse_result(String.t()) :: {:ok, translation_result} | {:error, String.t()}
  def parse_result(output) do
    case Regex.run(~r/Translation:\s*(.+?)\s*Confidence:\s*([0-9.]+)/s, output) do
      [_, translation, confidence_str] ->
        case Float.parse(confidence_str) do
          {confidence, ""} when confidence >= 0.0 and confidence <= 1.0 ->
            {:ok, %{translation: String.trim(translation), confidence: confidence}}
          _ ->
            {:error, "Invalid confidence score: must be a float between 0.0 and 1.0"}
        end
      _ ->
        {:error, "Unable to parse translation result: expected 'Translation: <text> Confidence: <score>' format"}
    end
  end

  @doc """
  Performs a translation directly using the TranslatorAgent's logic.

  This function constructs a prompt, simulates the agent's workflow (including cultural context),
  and calls the OpenAI serving. It's useful for testing or direct use outside the job framework.
  Note: This bypasses the full Agens job orchestration but uses the same serving and tool logic.

  ## Parameters
  - `text`: The input text to translate.
  - `source_lang`: The source language (e.g., "English").
  - `target_lang`: The target language (e.g., "Spanish").

  ## Examples

      iex> translate("Hello", "English", "Spanish")
      {:ok, %{translation: "Hola", confidence: 0.98}}

      iex> translate("", "English", "Spanish")
      {:ok, %{translation: "", confidence: 1.0}}
  """
  @spec translate(String.t(), String.t(), String.t()) :: {:ok, translation_result} | {:error, String.t()}
  def translate(text, source_lang, target_lang) do
    # Handle edge cases directly for efficiency
    cond do
      String.trim(text) == "" ->
        {:ok, %{translation: "", confidence: 1.0}}
      source_lang == target_lang ->
        {:ok, %{translation: text, confidence: 1.0}}
      true ->
        # Simulate cultural context pre-processing
        cultural_input = GlobalbridgeBackend.AI.Tools.CulturalContextTool.pre(text)
        # Construct the full prompt (mirroring the agent's prompt)
        full_prompt = """
        #{cultural_input}

        Translate from #{source_lang} to #{target_lang}: #{text}

        #{config().prompt.context}

        #{config().prompt.constraints}
        """
        # Call the serving (assumes :openai_serving is running; in prod, handle via supervision)
        case GenServer.call(:openai_serving, {:run, %Agens.Message{input: text, prompt: full_prompt}}) do
          result when is_binary(result) ->
            parse_result(result)
          {:error, reason} ->
            {:error, "Translation failed: #{inspect(reason)}"}
        end
    end
  end
end
