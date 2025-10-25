defmodule GlobalbridgeBackend.AI.Cache do
  @moduledoc """
  Unified caching layer for AI services using Cachex + ETS.

  This module provides a consolidated caching interface for:
  - Embeddings (1 hour TTL)
  - Search results (15 minutes TTL)
  - Thread repositories (24 hours TTL)

  ## Architecture

  - **Cachex**: Application-level caching for embeddings and search results
  - **ETS**: Process-level caching for thread repositories

  ## Cache Keys

  - Embeddings: `embedding:{model}:{text_hash}`
  - Search results: `search:{thread_id}:{query_hash}:{params}`
  - Vector results: `vector:{thread_id}:{embedding_hash}:{limit}`
  - Repositories: `repo:{shard_id}` (stored in ETS)
  """

  require Logger

  # TTL configurations
  @embeddings_ttl :timer.hours(1)
  @search_results_ttl :timer.minutes(15)
  @repos_ttl :timer.hours(24)

  # Cache names
  @cachex_name :ai_cache
  @ets_table :thread_repo_cache

  ## Initialization

  @doc """
  Initializes the ETS table for repository caching.
  Called automatically on application start.
  """
  def init do
    # Create ETS table if it doesn't exist
    if :ets.info(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])
    end

    :ok
  end

  ## Embedding Cache Operations

  @doc """
  Gets a cached embedding for text.

  Returns the embedding vector if found, nil otherwise.
  """
  def get_embedding(text, model \\ "text-embedding-3-large") do
    key = embedding_key(text, model)

    case Cachex.get(@cachex_name, key) do
      {:ok, nil} ->
        nil

      {:ok, cached} ->
        Jason.decode!(cached)

      {:error, reason} ->
        Logger.warning("Failed to get embedding from cache: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Stores an embedding in cache with 1 hour TTL.
  """
  def put_embedding(text, embedding, model \\ "text-embedding-3-large") do
    key = embedding_key(text, model)
    json = Jason.encode!(embedding)

    case Cachex.put(@cachex_name, key, json, ttl: @embeddings_ttl) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to cache embedding: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Checks if an embedding exists in cache.
  """
  def embedding_exists?(text, model \\ "text-embedding-3-large") do
    key = embedding_key(text, model)

    case Cachex.exists?(@cachex_name, key) do
      {:ok, exists} -> exists
      _ -> false
    end
  end

  ## Search Results Cache Operations

  @doc """
  Gets cached search results for a query.

  Returns the search results if found, nil otherwise.
  """
  def get_search_result(thread_id, query, opts \\ []) do
    key = search_key(thread_id, query, opts)

    case Cachex.get(@cachex_name, key) do
      {:ok, nil} ->
        nil

      {:ok, cached} ->
        Jason.decode!(cached, keys: :atoms)

      {:error, reason} ->
        Logger.warning("Failed to get search results from cache: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Stores search results in cache with 15 minute TTL.
  """
  def put_search_result(thread_id, query, results, opts \\ []) do
    key = search_key(thread_id, query, opts)
    json = Jason.encode!(results)

    case Cachex.put(@cachex_name, key, json, ttl: @search_results_ttl) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to cache search results: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets cached vector search results for an embedding.
  """
  def get_vector_result(thread_id, embedding, limit) do
    key = vector_key(thread_id, embedding, limit)

    case Cachex.get(@cachex_name, key) do
      {:ok, nil} ->
        nil

      {:ok, cached} ->
        Jason.decode!(cached, keys: :atoms)

      {:error, reason} ->
        Logger.warning("Failed to get vector results from cache: #{inspect(reason)}")
        nil
    end
  end

  @doc """
  Stores vector search results in cache with 15 minute TTL.
  """
  def put_vector_result(thread_id, embedding, results, limit) do
    key = vector_key(thread_id, embedding, limit)
    json = Jason.encode!(results)

    case Cachex.put(@cachex_name, key, json, ttl: @search_results_ttl) do
      {:ok, true} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to cache vector results: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Invalidates all search cache entries for a thread.
  Useful when new messages are added to a thread.
  """
  def invalidate_thread_search(thread_id) do
    # Get all keys
    case Cachex.keys(@cachex_name) do
      {:ok, keys} ->
        keys
        |> Enum.filter(fn key ->
          String.starts_with?(key, "search:#{thread_id}:") or
            String.starts_with?(key, "vector:#{thread_id}:")
        end)
        |> Enum.each(fn key ->
          Cachex.del(@cachex_name, key)
        end)

        :ok

      _ ->
        :ok
    end
  end

  ## Repository Cache Operations (ETS)

  @doc """
  Gets a cached repository module for a shard.

  Returns the repo module if found, nil otherwise.
  """
  def get_repo(shard_id) do
    case :ets.lookup(@ets_table, shard_id) do
      [{^shard_id, repo_module, _timestamp}] ->
        repo_module

      [] ->
        nil
    end
  end

  @doc """
  Stores a repository module in ETS cache with 24 hour TTL.

  Note: ETS doesn't natively support TTL, so we store a timestamp
  and check it during retrieval. The cleanup happens periodically.
  """
  def put_repo(shard_id, repo_module) do
    timestamp = System.monotonic_time(:second)
    :ets.insert(@ets_table, {shard_id, repo_module, timestamp})
    :ok
  end

  @doc """
  Removes a repository from cache.
  """
  def uncache_repo(shard_id) do
    :ets.delete(@ets_table, shard_id)
    :ok
  end

  @doc """
  Checks if a repository is cached (and not expired).
  """
  def repo_cached?(shard_id) do
    case :ets.lookup(@ets_table, shard_id) do
      [{^shard_id, _repo_module, timestamp}] ->
        # Check if entry is still within TTL
        current_time = System.monotonic_time(:second)
        age_seconds = current_time - timestamp
        ttl_seconds = div(@repos_ttl, 1000)

        age_seconds < ttl_seconds

      [] ->
        false
    end
  end

  @doc """
  Cleans up expired repository cache entries.

  Should be called periodically to prevent memory leaks.
  """
  def cleanup_expired_repos do
    current_time = System.monotonic_time(:second)
    ttl_seconds = div(@repos_ttl, 1000)

    :ets.select_delete(@ets_table, [
      {
        {:_, :_, :"$1"},
        [{:<, {:-, current_time, :"$1"}, ttl_seconds}],
        [true]
      }
    ])

    :ok
  end

  ## Cache Statistics & Management

  @doc """
  Gets comprehensive cache statistics.
  """
  def stats do
    cachex_stats = Cachex.stats(@cachex_name)
    ets_size = :ets.info(@ets_table, :size)

    %{
      cachex: cachex_stats,
      ets_repos: ets_size,
      ttls: %{
        embeddings: @embeddings_ttl,
        search_results: @search_results_ttl,
        repos: @repos_ttl
      }
    }
  end

  @doc """
  Clears all embedding cache entries.
  """
  def clear_embeddings do
    case Cachex.keys(@cachex_name) do
      {:ok, keys} ->
        keys
        |> Enum.filter(&String.starts_with?(&1, "embedding:"))
        |> Enum.each(&Cachex.del(@cachex_name, &1))

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Clears all search-related cache entries.
  """
  def clear_search_results do
    case Cachex.keys(@cachex_name) do
      {:ok, keys} ->
        keys
        |> Enum.filter(fn key ->
          String.starts_with?(key, "search:") or String.starts_with?(key, "vector:")
        end)
        |> Enum.each(&Cachex.del(@cachex_name, &1))

        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Clears all repository cache entries.
  """
  def clear_repos do
    if :ets.info(@ets_table) != :undefined do
      :ets.delete_all_objects(@ets_table)
    end

    :ok
  end

  @doc """
  Clears all caches (Cachex + ETS).
  """
  def clear_all do
    Cachex.clear(@cachex_name)
    clear_repos()
    :ok
  end

  ## Private Functions

  defp embedding_key(text, model) do
    # Create a hash of the text for cache key
    hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
    "embedding:#{model}:#{hash}"
  end

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
