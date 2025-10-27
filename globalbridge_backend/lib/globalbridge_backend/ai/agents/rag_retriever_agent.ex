defmodule GlobalbridgeBackend.AI.Agents.RAGRetrieverAgent do
  @moduledoc """
  Agent for retrieving relevant messages using RAG (Retrieval-Augmented Generation) techniques.

  This agent performs semantic search on message embeddings stored in the vec0 virtual table
  to find the most relevant messages for summarization or other AI tasks. It uses cosine
  similarity to rank messages and can apply recency bias for more relevant results.
  """

  alias Agens.Agent
  alias GlobalbridgeBackend.AI.SemanticSearch

  require Logger

  @doc """
  Returns the configuration for the RAGRetrieverAgent.

  Uses OpenAI serving with a specialized prompt for RAG retrieval tasks.
  The agent is designed to retrieve contextually relevant messages for summarization.
  """
  @spec config() :: %Agent.Config{}
  def config do
    %Agent.Config{
      name: :rag_retriever_agent,
      serving: :openai_serving,
      prompt: %Agent.Prompt{
        identity:
          "You are an expert at retrieving relevant information from conversation threads.",
        context: """
        Your task is to analyze a conversation thread and retrieve the most relevant messages
        for creating a comprehensive summary. Focus on:

        1. Key decisions and agreements
        2. Important facts and information shared
        3. Action items and commitments
        4. Questions and their resolutions
        5. Changes in direction or plans
        6. Critical problems and solutions

        Generate a search query that will find these important elements, then use the
        semantic search system to retrieve relevant messages.
        """,
        constraints: """
        - Generate a concise but comprehensive search query
        - Focus on substantive content over casual conversation
        - Consider both explicit statements and implicit context
        - Prioritize recent messages but don't ignore important historical context
        - Output format: First line is the search query, followed by retrieval instructions
        """
      }
    }
  end

  @doc """
  Performs RAG retrieval for a given thread and summarization objective.

  This function can be called directly to retrieve messages without going through
  the full Agens job workflow. Useful for testing or direct integration.

  ## Parameters
  - `thread_id`: The thread to search in
  - `objective`: Description of what information is needed (e.g., "summarize key decisions")
  - `opts`: Options for search configuration

  ## Options
  - `limit`: Maximum number of messages to retrieve (default: 20)
  - `recency_bias`: Whether to apply recency bias (default: true)
  - `recency_weight`: Weight for recency bias (default: 0.3)
  - `max_context_length`: Maximum context length for LLM (default: 8000)

  ## Returns
  - `{:ok, %{results: results, context: context}}` on success
  - `{:error, reason}` on failure
  """
  @spec retrieve(String.t(), String.t(), keyword()) ::
          {:ok, %{results: list(), context: String.t()}} | {:error, String.t()}
  def retrieve(thread_id, objective, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    use_recency = Keyword.get(opts, :recency_bias, true)
    recency_weight = Keyword.get(opts, :recency_weight, 0.3)
    max_context_length = Keyword.get(opts, :max_context_length, 8000)

    Logger.info(
      "RAGRetrieverAgent: Retrieving messages for thread #{thread_id} with objective: #{objective}"
    )

    # Generate a search query based on the objective
    case generate_search_query(objective) do
      {:ok, search_query} ->
        Logger.debug("Generated search query: #{search_query}")

        # Perform semantic search with the generated query
        search_opts = [
          limit: limit,
          recency_bias: use_recency,
          recency_weight: recency_weight,
          max_context_length: max_context_length
        ]

        case SemanticSearch.search_with_context(thread_id, search_query, search_opts) do
          {:ok, %{results: results, context: context}} when results != [] ->
            Logger.info("Retrieved #{length(results)} messages for summarization")
            {:ok, %{results: results, context: context}}

          {:ok, %{results: [], context: _}} ->
            # No embeddings found - fall back to recent messages
            Logger.warning("No embeddings found for thread #{thread_id}, falling back to recent messages")
            fallback_to_recent_messages(thread_id, limit, max_context_length)

          {:error, reason} ->
            Logger.error("Semantic search failed: #{inspect(reason)}, falling back to recent messages")
            fallback_to_recent_messages(thread_id, limit, max_context_length)
        end

      {:error, reason} ->
        Logger.error("Failed to generate search query: #{inspect(reason)}")
        {:error, "Failed to generate search query: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates an optimized search query from a summarization objective.

  This function creates a search query that will effectively retrieve the most
  relevant messages for the given summarization objective.
  """
  @spec generate_search_query(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def generate_search_query(objective) do
    # For now, use a simple transformation. In a more advanced implementation,
    # this could use an LLM to generate better search queries.
    # But for efficiency and cost optimization, we'll use rule-based query generation.

    cond do
      # Decision-focused summaries
      String.contains?(objective, "decision") ->
        {:ok, "decisions agreements choices conclusions"}

      # Action item summaries
      String.contains?(objective, "action") or String.contains?(objective, "todo") ->
        {:ok, "action items tasks responsibilities commitments"}

      # Problem/solution summaries
      String.contains?(objective, "problem") or String.contains?(objective, "solution") ->
        {:ok, "problems issues solutions fixes resolutions"}

      # General conversation summaries
      String.contains?(objective, "summary") or String.contains?(objective, "overview") ->
        {:ok, "key points important information main topics"}

      # Meeting summaries
      String.contains?(objective, "meeting") ->
        {:ok, "meeting discussion agenda outcomes next steps"}

      # Default: use the objective as-is, cleaned up
      true ->
        # Remove common summarization words and create a focused query
        cleaned =
          objective
          |> String.downcase()
          |> String.replace(
            ~r/\b(summarize|summarization|summary|overview|key|important|main)\b/,
            ""
          )
          |> String.replace(~r/\s+/, " ")
          |> String.trim()

        if String.length(cleaned) > 0 do
          {:ok, cleaned}
        else
          {:ok, "key information important details"}
        end
    end
  end

  @doc """
  Processes the agent's output to extract retrieval results.

  This helper function can be used to parse the agent's response when called
  through the Agens framework.
  """
  @spec parse_retrieval_output(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_retrieval_output(output) do
    # Extract the search query from the first line
    lines = String.split(output, "\n", trim: true)

    case lines do
      [query | _rest] ->
        # Clean up the query (remove any prefixes like "Search query:")
        clean_query =
          query
          |> String.replace(~r/^(search query|query):\s*/i, "")
          |> String.trim()

        if String.length(clean_query) > 0 do
          {:ok, clean_query}
        else
          {:error, "No valid search query found in output"}
        end

      [] ->
        {:error, "Empty output from retriever agent"}
    end
  end

  # Private helper: fallback to recent messages when embeddings are unavailable
  defp fallback_to_recent_messages(thread_id, limit, max_context_length) do
    alias GlobalbridgeBackend.Repo
    alias GlobalbridgeBackend.Schemas.Message
    alias GlobalbridgeBackend.AI.RAGRetriever
    import Ecto.Query

    Logger.info("Fetching #{limit} most recent messages from thread #{thread_id} as fallback")

    # Query most recent messages directly from database
    messages =
      from(m in Message,
        where: m.thread_id == ^thread_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        select: %{
          id: m.id,
          content: m.content,
          sender_id: m.sender_id,
          created_at: m.inserted_at
        }
      )
      |> Repo.all()
      |> Enum.reverse()  # Reverse to chronological order for better context

    if Enum.empty?(messages) do
      Logger.warning("No messages found in thread #{thread_id}")
      {:error, "No messages found in thread"}
    else
      # Build context from the messages
      context = RAGRetriever.build_context(messages,
        max_length: max_context_length,
        include_metadata: true
      )

      Logger.info("Built fallback context with #{length(messages)} messages")
      {:ok, %{results: messages, context: context}}
    end
  end
end
