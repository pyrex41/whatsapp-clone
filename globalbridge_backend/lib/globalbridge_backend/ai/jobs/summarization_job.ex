defmodule GlobalbridgeBackend.AI.Jobs.SummarizationJob do
  @moduledoc """
  Agens Job for orchestrating thread summarization using RAG and AI agents.

  This job coordinates the retrieval of relevant messages using RAG techniques
  and generates structured summaries using AI agents. The process involves:

  1. RAGRetrieverAgent: Retrieves relevant messages based on summarization objectives
  2. SummarizerAgent: Generates structured summaries with decisions, action items, etc.

  Optimized for cost using Claude Haiku and designed for thread-specific summarization.
  """

  alias GlobalbridgeBackend.AI.Agents.RAGRetrieverAgent
  alias GlobalbridgeBackend.AI.Agents.SummarizerAgent

  require Logger

  @doc """
  Creates and runs a summarization for a specific thread.

  This is the main entry point for thread summarization. It handles the complete
  workflow from retrieval to final summary generation using direct agent calls.

  ## Parameters
  - `thread_id`: The thread to summarize
  - `objective`: Optional summarization objective (default: "comprehensive summary")
  - `opts`: Configuration options

  ## Options
  - `max_messages`: Maximum messages to retrieve (default: 20)
  - `recency_bias`: Whether to apply recency bias (default: true)
  - `recency_weight`: Weight for recency bias (default: 0.3)
  - `max_context_length`: Maximum context length (default: 8000)

  ## Returns
  - `{:ok, result}` with the structured summary
  - `{:error, reason}` on failure
  """
  @spec summarize_thread(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def summarize_thread(thread_id, objective \\ "comprehensive summary", opts \\ []) do
    Logger.info("SummarizationJob: Starting summarization for thread #{thread_id}")

    # Use the direct summarization approach
    case summarize_direct(thread_id, objective, opts) do
      {:ok, result} ->
        Logger.info("SummarizationJob: Completed summarization for thread #{thread_id}")
        {:ok, result}

      {:error, reason} ->
        Logger.error(
          "SummarizationJob: Failed to summarize thread #{thread_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Incremental summarization: updates an existing summary with new messages.

  This is more efficient than full regeneration when only a few messages have been added.
  It takes the previous summary and the new messages, and generates an updated summary.

  ## Parameters
  - `thread_id`: The thread to summarize
  - `old_summary`: The previous summary data (map with summary, decisions, etc.)
  - `old_message_count`: How many messages were included in the old summary
  - `opts`: Configuration options

  ## Returns
  - `{:ok, result}` with the updated structured summary
  - `{:error, reason}` on failure
  """
  @spec summarize_thread_incremental(String.t(), map(), integer(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def summarize_thread_incremental(thread_id, old_summary, old_message_count, opts \\ []) do
    Logger.info("SummarizationJob: Incremental summarization for thread #{thread_id} from message #{old_message_count}")

    # Fetch only new messages
    new_message_opts = Keyword.merge(opts, [
      offset: old_message_count,
      max_messages: 20  # Limit to recent messages
    ])

    case RAGRetrieverAgent.retrieve(thread_id, "new messages", new_message_opts) do
      {:ok, %{results: results, context: new_context}} when length(results) > 0 ->
        # Construct incremental update prompt
        incremental_context = """
        PREVIOUS SUMMARY:
        Summary: #{old_summary.summary}
        Decisions: #{Enum.join(old_summary.decisions || [], ", ")}
        Action Items: #{Enum.join(old_summary.action_items || [], ", ")}
        Key Points: #{Enum.join(old_summary.key_points || [], ", ")}

        NEW MESSAGES:
        #{new_context}

        Please UPDATE the previous summary with the new information from the new messages.
        Merge any new decisions, action items, and key points with the existing ones.
        """

        case SummarizerAgent.summarize(incremental_context, thread_id, opts) do
          {:ok, summary} ->
            Logger.info("SummarizationJob: Incremental summarization completed")
            {:ok, %{
              thread_id: thread_id,
              objective: "incremental update",
              summary: summary,
              retrieved_messages: length(results)
            }}

          {:error, reason} ->
            Logger.error("SummarizationJob: Incremental SummarizerAgent failed: #{inspect(reason)}")
            {:error, "Incremental summary generation failed: #{inspect(reason)}"}
        end

      {:ok, %{results: []}} ->
        # No new messages, return old summary
        Logger.info("SummarizationJob: No new messages for incremental update")
        {:ok, %{
          thread_id: thread_id,
          objective: "no update",
          summary: old_summary,
          retrieved_messages: 0
        }}

      {:error, reason} ->
        Logger.error("SummarizationJob: Failed to retrieve new messages: #{inspect(reason)}")
        {:error, "Failed to retrieve new messages: #{inspect(reason)}"}
    end
  end

  @doc """
  Convenience function for direct summarization without job orchestration.

  This bypasses the full Agens job framework and directly calls the agents.
  Useful for simple summarization or testing.
  """
  @spec summarize_direct(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def summarize_direct(thread_id, objective \\ "comprehensive summary", opts \\ []) do
    Logger.info("SummarizationJob: Direct summarization for thread #{thread_id}")

    # Step 1: Retrieve relevant messages
    case RAGRetrieverAgent.retrieve(thread_id, objective, opts) do
      {:ok, %{results: results, context: context}} ->
        # Step 2: Generate summary from context
        case SummarizerAgent.summarize(context, thread_id, opts) do
          {:ok, summary} ->
            Logger.info("SummarizationJob: Direct summarization completed successfully")

            {:ok,
             %{
               thread_id: thread_id,
               objective: objective,
               summary: summary,
               # Count of retrieved messages
               retrieved_messages: length(results)
             }}

          {:error, reason} ->
            Logger.error("SummarizationJob: SummarizerAgent failed: #{inspect(reason)}")
            {:error, "Summary generation failed: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("SummarizationJob: RAGRetrieverAgent failed: #{inspect(reason)}")
        {:error, "Message retrieval failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Validates summarization configuration.

  Useful for testing and validation before running summarization.
  """
  @spec validate_config(map()) :: {:ok, map()} | {:error, String.t()}
  def validate_config(config) do
    required_keys = [:thread_id, :objective]

    missing_keys =
      Enum.filter(required_keys, fn key ->
        not Map.has_key?(config, key) or is_nil(Map.get(config, key))
      end)

    if Enum.empty?(missing_keys) do
      {:ok, config}
    else
      {:error, "Missing required configuration keys: #{Enum.join(missing_keys, ", ")}"}
    end
  end
end
