defmodule GlobalbridgeBackend.AI.Agents.SummarizerAgent do
  @moduledoc """
  Agent for generating structured summaries from conversation context.

  This agent processes retrieved message context and generates comprehensive,
  structured summaries including key decisions, action items, and important
  information. Uses Claude Haiku for cost-effective summarization.
  """

  alias Agens.Agent

  require Logger

  @type summary_result :: %{
          summary: String.t(),
          decisions: [String.t()],
          action_items: [String.t()],
          key_points: [String.t()],
          participants: [String.t()],
          confidence_score: float()
        }

  @doc """
  Returns the configuration for the SummarizerAgent.

  Uses OpenAI serving with Claude Haiku model for cost optimization.
  Includes detailed prompt engineering for structured JSON output.
  """
  @spec config() :: %Agent.Config{}
  def config do
    %Agent.Config{
      name: :summarizer_agent,
      serving: :openai_serving,
      prompt: %Agent.Prompt{
        identity: "You are an expert conversation analyst and summarizer.",
        context: """
        Your task is to analyze conversation threads and generate structured summaries
        that capture the essential information, decisions, and action items. You excel
        at identifying key insights from complex discussions and presenting them in
        clear, actionable formats.

        Focus on:
        1. Main topics and themes discussed
        2. Decisions made or agreements reached
        3. Action items and responsibilities assigned
        4. Important facts, data, or information shared
        5. Questions raised and resolutions provided
        6. Changes in plans, directions, or understanding
        7. Key participants and their contributions
        """,
        constraints: """
        Output MUST be valid JSON with this exact structure:
        {
          "summary": "Brief overview paragraph (2-3 sentences)",
          "decisions": ["List of key decisions made"],
          "action_items": ["List of action items with assignees if mentioned"],
          "key_points": ["List of important facts or information"],
          "participants": ["List of main participants mentioned"],
          "confidence_score": 0.95
        }

        Rules:
        - summary: 2-3 sentences maximum, capturing the essence
        - decisions: Only include explicit decisions or agreements
        - action_items: Include who is responsible when mentioned
        - key_points: Important information, not casual conversation
        - participants: People actively involved in the discussion
        - confidence_score: 0.0-1.0 based on clarity and completeness of information

        If information is unclear or missing, use empty arrays and lower confidence.
        Never include meta-commentary about the summary itself.
        """
      }
    }
  end

  @doc """
  Generates a structured summary from conversation context.

  This function can be called directly to summarize conversation context
  without going through the full Agens job workflow.

  ## Parameters
  - `context`: The conversation context string from RAG retrieval
  - `thread_id`: Optional thread identifier for context
  - `opts`: Options for summarization

  ## Options
  - `model`: AI model to use (default: configured model, optimized for cost)
  - `temperature`: Creativity level 0.0-1.0 (default: 0.1 for consistency)

  ## Returns
  - `{:ok, summary_result}` on success
  - `{:error, reason}` on failure
  """
  @spec summarize(String.t(), String.t() | nil, keyword()) ::
          {:ok, summary_result} | {:error, String.t()}
  def summarize(context, thread_id \\ nil, opts \\ []) do
    model = Keyword.get(opts, :model, System.get_env("OPENAI_MODEL") || "claude-3-haiku-20240307")
    temperature = Keyword.get(opts, :temperature, 0.1)

    Logger.info("SummarizerAgent: Generating summary for thread #{thread_id || "unknown"}")

    if String.trim(context) == "" do
      Logger.warning("Empty context provided to summarizer")
      {:error, "Cannot summarize empty context"}
    else
      # Construct the full prompt with context
      full_prompt = """
      Please analyze this conversation and provide a structured summary:

      #{context}

      #{config().prompt.context}

      #{config().prompt.constraints}
      """

      # Call the OpenAI serving directly
      case GenServer.call(
             :openai_serving,
             {:run,
              %Agens.Message{
                input: context,
                prompt: full_prompt
              }}
           ) do
        {:ok, result} when is_binary(result) ->
          parse_summary_result(result)

        {:error, reason} ->
          Logger.error("SummarizerAgent: OpenAI API call failed: #{inspect(reason)}")
          {:error, "Summary generation failed: #{inspect(reason)}"}

        unexpected ->
          Logger.error("SummarizerAgent: Unexpected response: #{inspect(unexpected)}")
          {:error, "Unexpected response from summarization service"}
      end
    end
  end

  @doc """
  Parses the raw summarizer output into a structured result.

  This helper function extracts the JSON summary from the agent's string output,
  enabling easier consumption in the application.

  ## Examples

      iex> parse_summary_result("```json\\n{\\"summary\\": \\"Brief overview\\", \\"decisions\\": []}\\n```")
      {:ok, %{summary: "Brief overview", decisions: []}}
  """
  @spec parse_summary_result(String.t()) :: {:ok, summary_result} | {:error, String.t()}
  def parse_summary_result(output) do
    # Extract JSON from the output (may be wrapped in code blocks)
    json_content = extract_json_from_output(output)

    case Jason.decode(json_content) do
      {:ok,
       %{
         "summary" => summary,
         "decisions" => decisions,
         "action_items" => action_items,
         "key_points" => key_points,
         "participants" => participants,
         "confidence_score" => confidence_score
       }}
      when is_binary(summary) and is_list(decisions) and is_list(action_items) and
             is_list(key_points) and is_list(participants) and is_number(confidence_score) ->
        # Validate and normalize the data
        result = %{
          summary: String.trim(summary),
          decisions: Enum.map(decisions, &String.trim/1),
          action_items: Enum.map(action_items, &String.trim/1),
          key_points: Enum.map(key_points, &String.trim/1),
          participants: Enum.map(participants, &String.trim/1),
          confidence_score: max(0.0, min(1.0, confidence_score))
        }

        {:ok, result}

      {:ok, invalid_json} ->
        Logger.error("SummarizerAgent: Invalid JSON structure: #{inspect(invalid_json)}")
        {:error, "Invalid summary format: missing required fields"}

      {:error, decode_error} ->
        Logger.error("SummarizerAgent: JSON decode error: #{inspect(decode_error)}")
        Logger.error("SummarizerAgent: Raw output: #{output}")
        {:error, "Failed to parse summary JSON: #{inspect(decode_error)}"}
    end
  end

  @doc """
  Validates a summary result structure.

  Useful for testing and validation of summary outputs.
  """
  @spec valid_summary?(summary_result) :: boolean()
  def valid_summary?(%{
        summary: summary,
        decisions: decisions,
        action_items: action_items,
        key_points: key_points,
        participants: participants,
        confidence_score: confidence_score
      })
      when is_binary(summary) and is_list(decisions) and is_list(action_items) and
             is_list(key_points) and is_list(participants) and is_number(confidence_score) and
             confidence_score >= 0.0 and confidence_score <= 1.0 do
    true
  end

  def valid_summary?(_), do: false

  # Private functions

  defp extract_json_from_output(output) do
    # Try to extract JSON from code blocks first
    case Regex.run(~r/```(?:json)?\s*\n(.*?)```/s, output) do
      [_, json_content] ->
        String.trim(json_content)

      nil ->
        # Try to find JSON object directly
        case Regex.run(~r/\{.*\}/s, output) do
          [json_content] ->
            String.trim(json_content)

          nil ->
            # Return the whole output as fallback
            output
        end
    end
  end
end
