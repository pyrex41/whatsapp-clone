defmodule GlobalbridgeBackend.AI.RAGRetriever do
  @moduledoc """
  RAG (Retrieval-Augmented Generation) Retriever for semantic search.

  This module provides semantic search capabilities with:
  - Vector similarity search using cosine similarity
  - Recency bias to boost recent messages
  - Context building for LLM input
  - Per-thread message retrieval
  """

  alias GlobalbridgeBackend.AI.VectorStore
  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.AI.Cache
  alias GlobalbridgeBackend.Repos.ThreadRepo

  require Logger

  @doc """
  Performs semantic search for messages in a thread using a pre-computed embedding.

  Returns a list of message results with embeddings, content, and metadata.
  """
  def search_by_embedding(thread_id, embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    # Check vector search cache first
    cached_vector_results = Cache.get_vector_result(thread_id, embedding, limit)

    vector_results =
      if cached_vector_results do
        Logger.debug("Using cached vector search results for thread #{thread_id}")
        cached_vector_results
      else
        # Perform vector search with the provided embedding
        case VectorStore.search(thread_id, embedding, limit: limit) do
          {:ok, results} ->
            # Cache the vector results
            Cache.put_vector_result(thread_id, embedding, results, limit)
            results

          {:error, error} ->
            Logger.error("Vector search failed: #{inspect(error)}")
            {:error, error}
        end
      end

    # If we got an error from cache or search, return it
    if match?({:error, _}, vector_results) do
      vector_results
    else
      # Enrich results with message content and metadata
      enrich_search_results(thread_id, vector_results)
    end
  end

  @doc """
  Performs semantic search for messages in a thread.

  Generates an embedding for the text query and searches for similar messages.
  Returns a list of message results with embeddings, content, and metadata.
  """
  def search(thread_id, query_text, opts \\ []) do
    _limit = Keyword.get(opts, :limit, 10)

    # Generate embedding for the query
    case EmbeddingService.generate(query_text) do
      {:ok, query_embedding} ->
        search_by_embedding(thread_id, query_embedding, opts)

      {:error, error} ->
        Logger.error("Failed to generate query embedding: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Performs semantic search with recency bias applied.

  Recent messages are boosted in the results based on their age.
  """
  def search_with_recency_bias(thread_id, embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    recency_weight = Keyword.get(opts, :recency_weight, 0.3)

    # Get more results for filtering
    case search_by_embedding(thread_id, embedding, limit: limit * 2) do
      {:ok, results} ->
        # Apply recency bias and re-rank
        biased_results = apply_recency_bias(results, recency_weight)

        # Return top results after bias
        {:ok, Enum.take(biased_results, limit)}

      error ->
        error
    end
  end

  @doc """
  Builds context string from search results for LLM input.

  Formats results chronologically with metadata.
  """
  def build_context(results, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, 4000)
    include_metadata = Keyword.get(opts, :include_metadata, true)

    # Sort results chronologically (most recent first)
    sorted_results = Enum.sort_by(results, & &1.inserted_at, {:desc, DateTime})

    # Build context string
    context_parts =
      Enum.map(sorted_results, fn result ->
        format_message_context(result, include_metadata)
      end)

    # Join and truncate if needed
    full_context = Enum.join(context_parts, "\n\n")

    if String.length(full_context) > max_length do
      truncated = String.slice(full_context, 0, max_length - 3) <> "..."
      truncated
    else
      full_context
    end
  end

  # Private functions

  defp enrich_search_results(thread_id, vector_results) do
    repo = ThreadRepo.get_repo(thread_id)

    # Extract message IDs from vector results
    message_ids = Enum.map(vector_results, & &1.message_id)

    if Enum.empty?(message_ids) do
      {:ok, []}
    else
      # Query messages table for full content and metadata
      placeholders = Enum.map(message_ids, fn _ -> "?" end) |> Enum.join(",")

      sql = """
      SELECT
        id,
        content,
        content_type,
        sender_id,
        inserted_at,
        updated_at,
        reply_to_id,
        is_deleted
      FROM messages
      WHERE id IN (#{placeholders})
        AND is_deleted = 0
      ORDER BY inserted_at DESC
      """

      case Ecto.Adapters.SQL.query(repo, sql, message_ids) do
        {:ok, %{rows: rows}} ->
          # Create a map of message_id to message data for quick lookup
          message_map =
            Map.new(rows, fn [
                               id,
                               content,
                               content_type,
                               sender_id,
                               inserted_at,
                               updated_at,
                               reply_to_id,
                               is_deleted
                             ] ->
              {id,
               %{
                 id: id,
                 content: content,
                 content_type: content_type,
                 sender_id: sender_id,
                 inserted_at: parse_timestamp(inserted_at),
                 updated_at: parse_timestamp(updated_at),
                 reply_to_id: reply_to_id,
                 is_deleted: is_deleted
               }}
            end)

          # Combine vector results with message data
          enriched_results =
            Enum.map(vector_results, fn vector_result ->
              case Map.get(message_map, vector_result.message_id) do
                nil ->
                  # Message not found or deleted
                  nil

                message_data ->
                  Map.merge(vector_result, message_data)
              end
            end)
            |> Enum.reject(&is_nil/1)

          {:ok, enriched_results}

        {:error, error} ->
          Logger.error("Failed to fetch message data: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  defp apply_recency_bias(results, weight) do
    now = DateTime.utc_now()

    Enum.map(results, fn result ->
      # Calculate hours since message was inserted
      hours_old = DateTime.diff(now, result.inserted_at, :hour)

      # Apply exponential decay: newer messages get higher boost
      # recency_score = 1 / (1 + hours_old * decay_factor)
      # Adjust this to control recency bias strength
      decay_factor = 0.1
      recency_score = :math.exp(-decay_factor * hours_old)

      # Combine original distance with recency bias
      adjusted_distance = result.distance * (1 - weight) + (1 - recency_score) * weight

      Map.put(result, :adjusted_distance, adjusted_distance)
    end)
    |> Enum.sort_by(& &1.adjusted_distance)
  end

  defp format_message_context(result, include_metadata) do
    timestamp = format_timestamp(result.inserted_at)

    if include_metadata do
      """
      [#{timestamp}] User #{result.sender_id}:
      #{result.content}
      (Similarity: #{Float.round(1 - result.distance, 3)})
      """
    else
      """
      User #{result.sender_id}: #{result.content}
      """
    end
  end

  defp parse_timestamp(timestamp_str) when is_binary(timestamp_str) do
    case DateTime.from_iso8601(timestamp_str) do
      {:ok, datetime, _offset} -> datetime
      # Fallback for invalid timestamps
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end
end
