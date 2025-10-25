defmodule GlobalbridgeBackend.AI.Agents.IdiomAnalyzerAgent do
  @moduledoc """
  Agent for detecting and analyzing idioms, cultural phrases, and expressions in translations.

  This agent analyzes translated text to identify idioms, culturally-specific phrases, and expressions
  that may require additional context for accurate understanding. It provides target language equivalents
  and cultural explanations to enrich the translation experience.

  Uses Groq's llama-3.1-70b-versatile model for fast, cost-effective idiom detection (~$0.59/1M tokens).
  Optimized for high-quality cultural analysis with structured JSON output.
  """

  alias Agens.Agent

  require Logger

  @type idiom :: %{
          source_phrase: String.t(),
          explanation: String.t(),
          target_equivalent: String.t(),
          cultural_context: String.t()
        }

  @type analysis_result :: [idiom()]

  @doc """
  Returns the configuration for the IdiomAnalyzerAgent.

  Uses Groq's llama-3.1-70b-versatile via OpenAIServing for cost-effective idiom detection.
  The model is selected by setting the model name to "groq-llama-3.1-70b-versatile" which
  routes through OpenAIServing to the Groq API.

  ## Configuration Details
  - Model: Groq llama-3.1-70b-versatile (~$0.59/1M tokens)
  - Serving: OpenAI serving (routes to Groq based on model name)
  - Output: Structured JSON array of idioms
  - Temperature: Low (0.1) for consistent detection
  """
  @spec config() :: %Agent.Config{}
  def config do
    %Agent.Config{
      name: :idiom_analyzer_agent,
      serving: :openai_serving,
      prompt: %Agent.Prompt{
        identity: "You are an expert in cross-cultural communication and idiomatic expressions.",
        context: """
        Your task is to analyze translated text and identify idioms, culturally-specific phrases,
        colloquialisms, and expressions that may not have direct equivalents or may require
        cultural context for accurate understanding.

        Focus on:
        1. Idiomatic expressions and their cultural meanings
        2. Proverbs, sayings, and culturally-specific phrases
        3. Colloquialisms and informal language with cultural nuance
        4. Expressions that may confuse non-native speakers
        5. Target language equivalents that convey the same meaning
        6. Cultural context that helps understand the phrase's significance
        """,
        constraints: """
        Output MUST be a valid JSON array with this exact structure:
        [
          {
            "source_phrase": "The original idiomatic phrase from the source text",
            "explanation": "Clear explanation of what the phrase means",
            "target_equivalent": "The equivalent phrase or expression in the target language",
            "cultural_context": "Cultural background and significance of the phrase"
          }
        ]

        Rules:
        - Return an empty array [] if no idioms or cultural phrases are detected
        - source_phrase: Extract the exact phrase from the source text
        - explanation: 1-2 sentences explaining the literal and figurative meaning
        - target_equivalent: The most appropriate equivalent in the target language
        - cultural_context: Brief cultural context (1-2 sentences) about origin or usage
        - Only include phrases with genuine cultural or idiomatic significance
        - Avoid including simple translations or common words
        - Output ONLY the JSON array, no additional text or code blocks
        - Ensure all JSON is properly formatted and escaped
        """
      }
    }
  end

  @doc """
  Analyzes text for idioms and cultural expressions.

  This function detects idioms in the source text and provides cultural context
  and target language equivalents. It can be called directly without going through
  the full Agens job workflow.

  ## Parameters
  - `text`: The source text to analyze for idioms
  - `source_language`: The source language (e.g., "English")
  - `target_language`: The target language (e.g., "Spanish")
  - `opts`: Options for analysis

  ## Options
  - `model`: AI model to use (default: "groq-llama-3.1-70b-versatile")
  - `temperature`: Creativity level 0.0-1.0 (default: 0.1 for consistency)
  - `timeout`: Request timeout in ms (default: 60_000)

  ## Returns
  - `{:ok, [idiom()]}` on success (empty array if no idioms found)
  - `{:error, reason}` on failure

  ## Examples

      iex> analyze("Break a leg on your performance!", "English", "Spanish")
      {:ok, [
        %{
          source_phrase: "Break a leg",
          explanation: "A theatrical idiom meaning 'good luck'...",
          target_equivalent: "¡Mucha mierda!",
          cultural_context: "Theater tradition of wishing performers good luck..."
        }
      ]}

      iex> analyze("The cat is on the mat.", "English", "Spanish")
      {:ok, []}
  """
  @spec analyze(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, analysis_result()} | {:error, String.t()}
  def analyze(text, source_language, target_language, opts \\ []) do
    # Use Groq Llama 70B for idiom analysis (fast and cost-effective)
    model = Keyword.get(opts, :model, "groq-llama-3.1-70b-versatile")
    temperature = Keyword.get(opts, :temperature, 0.1)
    timeout = Keyword.get(opts, :timeout, 60_000)

    Logger.info(
      "IdiomAnalyzerAgent: Analyzing idioms (#{source_language} -> #{target_language}) using model: #{model}"
    )

    if String.trim(text) == "" do
      Logger.info("Empty text provided to idiom analyzer, returning empty array")
      {:ok, []}
    else
      # Construct the full prompt with language context
      full_prompt = """
      Analyze the following text for idioms, cultural phrases, and expressions.

      Source Language: #{source_language}
      Target Language: #{target_language}
      Text: #{text}

      #{config().prompt.context}

      #{config().prompt.constraints}
      """

      # Call the OpenAI serving (will route to Groq based on model name)
      case GenServer.call(
             :openai_serving,
             {:run,
              %Agens.Message{
                input: text,
                prompt: full_prompt
              }},
             timeout
           ) do
        {:ok, result} when is_binary(result) ->
          parse_analysis_result(result)

        {:error, reason} ->
          Logger.error("IdiomAnalyzerAgent: API call failed: #{inspect(reason)}")
          {:error, "Idiom analysis failed: #{inspect(reason)}"}

        unexpected ->
          Logger.error("IdiomAnalyzerAgent: Unexpected response: #{inspect(unexpected)}")
          {:error, "Unexpected response from idiom analysis service"}
      end
    end
  end

  @doc """
  Parses the raw idiom analyzer output into a structured result.

  This helper function extracts the JSON array from the agent's string output,
  handling various output formats including code blocks and plain JSON.

  ## Examples

      iex> parse_analysis_result("[]")
      {:ok, []}

      iex> parse_analysis_result(~s([{"source_phrase": "test", "explanation": "...", "target_equivalent": "...", "cultural_context": "..."}]))
      {:ok, [%{source_phrase: "test", ...}]}
  """
  @spec parse_analysis_result(String.t()) :: {:ok, analysis_result()} | {:error, String.t()}
  def parse_analysis_result(output) do
    # Extract JSON from the output (may be wrapped in code blocks or contain extra text)
    json_content = extract_json_from_output(output)

    case Jason.decode(json_content) do
      {:ok, idioms} when is_list(idioms) ->
        # Validate and normalize each idiom entry
        case parse_idioms(idioms) do
          {:ok, parsed_idioms} ->
            {:ok, parsed_idioms}

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, invalid_json} ->
        Logger.error("IdiomAnalyzerAgent: Expected JSON array, got: #{inspect(invalid_json)}")
        {:error, "Invalid idiom analysis format: expected JSON array"}

      {:error, decode_error} ->
        Logger.error("IdiomAnalyzerAgent: JSON decode error: #{inspect(decode_error)}")
        Logger.error("IdiomAnalyzerAgent: Raw output: #{output}")
        {:error, "Failed to parse idiom analysis JSON: #{inspect(decode_error)}"}
    end
  end

  @doc """
  Validates an idiom analysis result structure.

  Useful for testing and validation of idiom analysis outputs.
  """
  @spec valid_analysis?(analysis_result()) :: boolean()
  def valid_analysis?(idioms) when is_list(idioms) do
    Enum.all?(idioms, &valid_idiom?/1)
  end

  def valid_analysis?(_), do: false

  @doc """
  Validates a single idiom entry.
  """
  @spec valid_idiom?(idiom()) :: boolean()
  def valid_idiom?(%{
        source_phrase: source_phrase,
        explanation: explanation,
        target_equivalent: target_equivalent,
        cultural_context: cultural_context
      })
      when is_binary(source_phrase) and is_binary(explanation) and
             is_binary(target_equivalent) and is_binary(cultural_context) do
    # Ensure none of the strings are empty
    String.trim(source_phrase) != "" and
      String.trim(explanation) != "" and
      String.trim(target_equivalent) != "" and
      String.trim(cultural_context) != ""
  end

  def valid_idiom?(_), do: false

  # Private functions

  defp parse_idioms(idioms) do
    parsed =
      Enum.map(idioms, fn idiom ->
        case idiom do
          %{
            "source_phrase" => source_phrase,
            "explanation" => explanation,
            "target_equivalent" => target_equivalent,
            "cultural_context" => cultural_context
          }
          when is_binary(source_phrase) and is_binary(explanation) and
                 is_binary(target_equivalent) and is_binary(cultural_context) ->
            %{
              source_phrase: String.trim(source_phrase),
              explanation: String.trim(explanation),
              target_equivalent: String.trim(target_equivalent),
              cultural_context: String.trim(cultural_context)
            }

          _ ->
            nil
        end
      end)

    if Enum.any?(parsed, &is_nil/1) do
      {:error, "Invalid idiom structure: missing required fields"}
    else
      {:ok, parsed}
    end
  end

  defp extract_json_from_output(output) do
    # Try to extract JSON from code blocks first
    case Regex.run(~r/```(?:json)?\s*\n(.*?)```/s, output) do
      [_, json_content] ->
        String.trim(json_content)

      nil ->
        # Try to find JSON array directly
        case Regex.run(~r/\[.*\]/s, output) do
          [json_content] ->
            String.trim(json_content)

          nil ->
            # Return the whole output as fallback
            output
        end
    end
  end
end
