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
      {:ok, %{results: _results, context: context}} ->
        # Step 2: Generate summary from context
        case SummarizerAgent.summarize(context, thread_id, opts) do
          {:ok, summary} ->
            Logger.info("SummarizationJob: Direct summarization completed successfully")

            {:ok,
             %{
               thread_id: thread_id,
               objective: objective,
               summary: summary,
               # Approximate count
               retrieved_messages: length(context)
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
