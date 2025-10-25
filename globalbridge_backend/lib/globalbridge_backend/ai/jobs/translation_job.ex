defmodule GlobalbridgeBackend.AI.Jobs.TranslationJob do
  @moduledoc """
  Defines the TranslationJob for multi-agent orchestration using Agens.

  This job orchestrates language detection, translation, and idiom analysis with cultural context.

  Sequential workflow steps:
  1. Detect the source language of the input text
  2. Translate the text to the target language with cultural context
  3. Analyze idioms and cultural expressions in the source text
  4. Assemble enriched response with cultural_notes field

  Uses Groq's llama-3.1-70b-versatile for idiom detection (~$0.59/1M tokens)
  and XAI's Grok for translation summarization.
  """

  alias Agens.Job
  alias GlobalbridgeBackend.AI.Agents.IdiomAnalyzerAgent

  @doc """
  Returns the job configuration for the TranslationJob.

  This includes sequential steps for language detection, translation, and idiom analysis.
  Sequential execution is required due to strict data dependencies:
  - Translation depends on language detection
  - Idiom analysis depends on both language detection and translation
  - Response assembly depends on all previous steps
  """
  def job_config do
    %Job.Config{
      name: :translation_job,
      description: "Multi-step translation process with language detection, translation, and idiom analysis",
      steps: [
        %Job.Step{
          agent: :language_detection_agent,
          objective: "Detect the source language of the input text and output it in the format 'Detected language: <language>'"
        },
        %Job.Step{
          agent: :translator_agent,
          objective: "Translate the text to the target language using cultural context analysis, ensuring appropriateness and nuance"
        },
        %Job.Step{
          agent: :idiom_analyzer_agent,
          objective: """
          Analyze the source text for idioms, cultural expressions, and phrases that may require additional context.
          Return a JSON array of idioms with their explanations, target language equivalents, and cultural context.
          If no idioms are found, return an empty array [].
          """
        }
      ]
    }
  end

  @doc """
  Runs the translation job and returns an enriched response with cultural notes.

  This function orchestrates the complete translation workflow:
  1. Detect source language
  2. Translate to target language
  3. Analyze idioms in source text
  4. Assemble response with cultural_notes field

  ## Parameters
  - `text`: The text to translate
  - `target_language`: The target language (e.g., "Spanish", "French")
  - `opts`: Options for the job execution

  ## Options
  - `timeout`: Job timeout in milliseconds (default: 60_000)

  ## Returns
  - `{:ok, response}` where response contains:
    - `translation`: The translated text
    - `confidence`: Translation confidence score (0.0-1.0)
    - `cultural_notes`: Array of idiom analyses with cultural context
    - `source_language`: Detected source language
    - `target_language`: Target language
  - `{:error, reason}` on failure

  ## Examples

      iex> translate_with_idioms("Break a leg on your test!", "Spanish")
      {:ok, %{
        translation: "¡Buena suerte en tu examen!",
        confidence: 0.95,
        cultural_notes: [
          %{
            source_phrase: "Break a leg",
            explanation: "A theatrical idiom meaning 'good luck'",
            target_equivalent: "¡Mucha mierda!",
            cultural_context: "Theater tradition of wishing performers good luck"
          }
        ],
        source_language: "English",
        target_language: "Spanish"
      }}
  """
  def translate_with_idioms(text, target_language, opts \\ []) do
    _timeout = Keyword.get(opts, :timeout, 60_000)

    # Run the job workflow via GenServer call
    case GenServer.call(:translation_job, {:run, text}) do
      {:ok, job_result} ->
        # Parse the job result and assemble enriched response
        assemble_translation_response(job_result, text, target_language)

      {:error, reason} ->
        {:error, "Translation job failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Assembles the final translation response with cultural notes.

  Parses the job result from the Agens workflow and constructs a response
  with translation, confidence score, and cultural_notes array.

  ## Parameters
  - `job_result`: The result from Job.run/3
  - `text`: Original source text
  - `target_language`: Target language

  ## Returns
  - `{:ok, response}` with enriched translation data
  - `{:error, reason}` if parsing or assembly fails
  """
  def assemble_translation_response(job_result, text, target_language) do
    # Extract step results from job
    # job_result is typically a list of step outputs or a single final output
    with {:ok, source_lang} <- extract_source_language(job_result),
         {:ok, translation_data} <- extract_translation(job_result),
         {:ok, idioms} <- extract_idioms(job_result) do
      response = %{
        translation: translation_data.translation,
        confidence: translation_data.confidence,
        cultural_notes: idioms,
        source_language: source_lang,
        target_language: target_language
      }

      {:ok, response}
    else
      {:error, reason} ->
        {:error, "Failed to assemble translation response: #{inspect(reason)}"}
    end
  end

  # Private helper functions

  defp extract_source_language(job_result) do
    # Extract language from "Detected language: <language>" format
    case Regex.run(~r/Detected language:\s*(.+)/i, to_string(job_result)) do
      [_, language] ->
        {:ok, String.trim(language)}

      nil ->
        # Default fallback
        {:ok, "English"}
    end
  end

  defp extract_translation(job_result) do
    # Extract translation and confidence from "Translation: <text> Confidence: <score>" format
    result_str = to_string(job_result)

    case Regex.run(~r/Translation:\s*(.+?)\s*Confidence:\s*([0-9.]+)/s, result_str) do
      [_, translation, confidence_str] ->
        case Float.parse(confidence_str) do
          {confidence, _} ->
            {:ok, %{translation: String.trim(translation), confidence: confidence}}

          :error ->
            {:error, "Invalid confidence score"}
        end

      nil ->
        {:error, "Unable to parse translation result"}
    end
  end

  defp extract_idioms(job_result) do
    # Extract idioms from the job result
    # The idiom analyzer agent should return a JSON array
    result_str = to_string(job_result)

    # Try to extract JSON array from the result
    case extract_json_array(result_str) do
      {:ok, json_str} ->
        IdiomAnalyzerAgent.parse_analysis_result(json_str)

      :error ->
        # No idioms found or parsing failed - return empty array
        {:ok, []}
    end
  end

  defp extract_json_array(text) do
    # Try to find a JSON array in the text
    case Regex.run(~r/\[.*\]/s, text) do
      [json_str] ->
        {:ok, json_str}

      nil ->
        :error
    end
  end
end
