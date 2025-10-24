defmodule GlobalbridgeBackend.AI.Cache.SearchCache do
  @moduledoc """
  Cache for semantic search results to improve performance and reduce API costs.

  Caches search results based on query, thread, and search parameters.
  Uses Cachex for in-memory caching with configurable TTL.
  """

  # Cache search results for 1 hour (search results can be slightly stale)
  @search_ttl :timer.hours(1)

  # Cache vector search results for 30 minutes
  @vector_ttl :timer.minutes(30)

  @doc """
  Gets cached search results for a query.
  """
  def get_search_results(thread_id, query, opts \\ []) do
    key = search_key(thread_id, query, opts)

    case Cachex.get(:ai_cache, key) do
      {:ok, nil} -> nil
      {:ok, cached} -> Jason.decode!(cached, keys: :atoms)
    end
  end

  @doc """
  Stores search results in cache.
  """
  def put_search_results(thread_id, query, results, opts \\ []) do
    key = search_key(thread_id, query, opts)
    json = Jason.encode!(results)

    Cachex.put(:ai_cache, key, json, ttl: @search_ttl)
  end

  @doc """
  Gets cached vector search results for an embedding.
  """
  def get_vector_results(thread_id, embedding, limit) do
    key = vector_key(thread_id, embedding, limit)

    case Cachex.get(:ai_cache, key) do
      {:ok, nil} -> nil
      {:ok, cached} -> Jason.decode!(cached, keys: :atoms)
    end
  end

  @doc """
  Stores vector search results in cache.
  """
  def put_vector_results(thread_id, embedding, results, limit) do
    key = vector_key(thread_id, embedding, limit)
    json = Jason.encode!(results)

    Cachex.put(:ai_cache, key, json, ttl: @vector_ttl)
  end

  @doc """
  Invalidates all search cache entries for a thread.
  Useful when new messages are added to a thread.
  """
  def invalidate_thread_cache(thread_id) do
    # Find all keys for this thread and delete them
    # This is a simple implementation - in production you might want a more sophisticated approach
    case Cachex.stream(:ai_cache) do
      {:ok, stream} ->
        stream
        |> Stream.filter(fn entry ->
          case entry do
            {:entry, key, _value, _ttl} ->
              String.starts_with?(key, "search:#{thread_id}:") or
                String.starts_with?(key, "vector:#{thread_id}:")

            _ ->
              false
          end
        end)
        |> Enum.each(fn {:entry, key, _value, _ttl} ->
          Cachex.del(:ai_cache, key)
        end)

      _ ->
        :ok
    end
  end

  @doc """
  Gets search cache statistics.
  """
  def stats do
    Cachex.stats(:ai_cache)
  end

  @doc """
  Clears all search-related cache entries.
  """
  def clear do
    # Clear search and vector cache entries
    case Cachex.stream(:ai_cache) do
      {:ok, stream} ->
        stream
        |> Stream.filter(fn entry ->
          case entry do
            {:entry, key, _value, _ttl} ->
              String.starts_with?(key, "search:") or String.starts_with?(key, "vector:")

            _ ->
              false
          end
        end)
        |> Enum.each(fn {:entry, key, _value, _ttl} ->
          Cachex.del(:ai_cache, key)
        end)

      _ ->
        :ok
    end
  end

  # Private functions

  defp search_key(thread_id, query, opts) do
    # Normalize query for consistent caching
    normalized_query = normalize_query(query)
    limit = Keyword.get(opts, :limit, 10)
    recency_bias = Keyword.get(opts, :recency_bias, false)
    recency_weight = Keyword.get(opts, :recency_weight, 0.3)

    # Create a hash of the normalized query and parameters
    params_string = "#{limit}:#{recency_bias}:#{recency_weight}"
    hash = :crypto.hash(:sha256, normalized_query <> params_string) |> Base.encode16(case: :lower)

    "search:#{thread_id}:#{hash}"
  end

  defp vector_key(thread_id, embedding, limit) do
    # Create a hash of the embedding (first 100 elements for performance)
    embedding_sample = Enum.take(embedding, 100)
    hash = :crypto.hash(:sha256, Jason.encode!(embedding_sample)) |> Base.encode16(case: :lower)

    "vector:#{thread_id}:#{hash}:#{limit}"
  end

  defp normalize_query(query) do
    query
    |> String.downcase()
    |> String.trim()
    # Normalize whitespace
    |> String.replace(~r/\s+/, " ")
  end
end
