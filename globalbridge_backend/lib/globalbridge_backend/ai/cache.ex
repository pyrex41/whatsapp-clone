defmodule GlobalbridgeBackend.AI.Cache do
  @moduledoc """
  Unified in-memory caching for AI and sharded repos.

  - General KV cache (ETS) with TTL
  - Repository cache (separate ETS table) with 24h TTL
  - Lightweight helpers for embeddings/search/vector results
  """

  use GenServer
  require Logger

  # ETS table names
  @kv_table :ai_cache
  @repo_table :thread_repo_cache

  # TTLs (in milliseconds where called out, seconds for ETS timestamps below)
  @cleanup_interval 60_000
  @repos_ttl :timer.hours(24)    # 24h
  @embeddings_ttl :timer.hours(1)
  @search_results_ttl :timer.minutes(15)

  ## Client API

  @doc """
  Starts the cache GenServer and ensures ETS tables exist.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Idempotent init for tests or manual setup (not the GenServer callback).
  Ensures ETS tables exist when supervisor hasn't started yet.
  """
  def init() do
    ensure_tables()
    :ok
  end

  # --- General KV helpers (backed by @kv_table) ---

  @doc """
  Gets a value from the KV cache. Returns {:ok, value} | {:error, :not_found}.
  """
  def get(key) do
    ensure_tables()
    case :ets.lookup(@kv_table, key) do
      [{^key, value, :infinity}] -> {:ok, value}
      [{^key, value, expires_at}] ->
        if System.system_time(:second) < expires_at do
          {:ok, value}
        else
          :ets.delete(@kv_table, key)
          {:error, :not_found}
        end
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Puts a value into the KV cache. Options: :ttl (seconds or :infinity).
  """
  def put(key, value, opts \\ []) do
    ensure_tables()
    ttl = Keyword.get(opts, :ttl, 3600)
    expires_at = case ttl do
      :infinity -> :infinity
      seconds when is_integer(seconds) -> System.system_time(:second) + seconds
    end
    :ets.insert(@kv_table, {key, value, expires_at})
    :ok
  end

  @doc """
  Deletes all KV entries whose key starts with the given prefix pattern.
  """
  def delete_pattern(pattern) do
    ensure_tables()
    prefix = String.trim_trailing(pattern, "*")
    deleted = :ets.foldl(fn {key, _value, _exp}, acc ->
      if is_binary(key) and String.starts_with?(key, prefix) do
        :ets.delete(@kv_table, key)
        acc + 1
      else
        acc
      end
    end, 0, @kv_table)
    Logger.debug("Deleted #{deleted} KV entries matching: #{pattern}")
    {:ok, deleted}
  end

  @doc """
  Deletes a specific KV key.
  """
  def delete(key) do
    ensure_tables()
    :ets.delete(@kv_table, key)
    :ok
  end

  @doc """
  Clears all KV entries.
  """
  def clear do
    ensure_tables()
    :ets.delete_all_objects(@kv_table)
    :ok
  end

  # --- Repository cache (backed by @repo_table) ---

  @doc """
  Returns cached repo module for shard_id or nil if not found/expired.
  """
  def get_repo(shard_id) do
    ensure_tables()
    case :ets.lookup(@repo_table, shard_id) do
      [{^shard_id, repo_module, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          repo_module
        else
          :ets.delete(@repo_table, shard_id)
          nil
        end
      [] -> nil
    end
  end

  @doc """
  Caches a repo module for a shard with 24h TTL.
  """
  def put_repo(shard_id, repo_module) do
    ensure_tables()
    :ets.insert(@repo_table, {shard_id, repo_module, System.monotonic_time(:millisecond) + @repos_ttl})
    :ok
  end

  @doc """
  Removes a repo entry from the cache.
  """
  def uncache_repo(shard_id) do
    ensure_tables()
    :ets.delete(@repo_table, shard_id)
    :ok
  end

  @doc """
  Returns true if a shard's repo is cached and not expired.
  """
  def repo_cached?(shard_id) do
    get_repo(shard_id) != nil
  end

  @doc """
  Deletes all expired repo entries.
  """
  def cleanup_expired_repos do
    ensure_tables()
    now = System.monotonic_time(:millisecond)
    :ets.foldl(fn {shard_id, _repo, expires_at}, acc ->
      if expires_at <= now do
        :ets.delete(@repo_table, shard_id)
        acc + 1
      else
        acc
      end
    end, 0, @repo_table)
    :ok
  end

  @doc """
  Clears all repository cache entries.
  """
  def clear_repos do
    ensure_tables()
    :ets.delete_all_objects(@repo_table)
    :ok
  end

  # --- Higher-level helpers (lightweight wrappers) ---

  def get_embedding(text, model) do
    key = "embedding:#{model}:" <> :crypto.hash(:sha256, String.downcase(String.trim(text))) |> Base.encode16(case: :lower)
    case get(key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  def put_embedding(text, embedding, model) do
    key = "embedding:#{model}:" <> :crypto.hash(:sha256, String.downcase(String.trim(text))) |> Base.encode16(case: :lower)
    put(key, embedding, ttl: div(@embeddings_ttl, 1000))
  end

  def get_search_result(thread_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    key = "search:#{thread_id}:" <> hash_downcased(query) <> if(limit, do: ":l=#{limit}", else: "")
    case get(key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  def put_search_result(thread_id, query, results, opts \\ []) do
    limit = Keyword.get(opts, :limit)
    key = "search:#{thread_id}:" <> hash_downcased(query) <> if(limit, do: ":l=#{limit}", else: "")
    put(key, results, ttl: div(@search_results_ttl, 1000))
  end

  def get_vector_result(thread_id, embedding, limit) do
    key = "vector:#{thread_id}:" <> hash_term({embedding, limit})
    case get(key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  def put_vector_result(thread_id, embedding, results, limit) do
    key = "vector:#{thread_id}:" <> hash_term({embedding, limit})
    put(key, results, ttl: div(@search_results_ttl, 1000))
  end

  def invalidate_thread_search(thread_id) do
    delete_pattern("search:#{thread_id}:")
    delete_pattern("vector:#{thread_id}:")
    :ok
  end

  def clear_embeddings, do: delete_pattern("embedding:")
  def clear_search_results do
    delete_pattern("search:")
    delete_pattern("vector:")
    :ok
  end

  @doc """
  Clears all cache types (KV + repos).
  """
  def clear_all do
    clear()
    clear_repos()
    :ok
  end

  @doc """
  Returns cache statistics including KV and repo tables and TTL settings.
  """
  def stats do
    ensure_tables()
    kv_size = :ets.info(@kv_table, :size)
    kv_mem = :ets.info(@kv_table, :memory) * :erlang.system_info(:wordsize)
    repo_size = :ets.info(@repo_table, :size)
    %{
      total_entries: kv_size,
      memory_bytes: kv_mem,
      memory_mb: Float.round(kv_mem / 1_024_000, 2),
      ets_repos: repo_size,
      ttls: %{
        embeddings: @embeddings_ttl,
        search_results: @search_results_ttl,
        repos: @repos_ttl
      }
    }
  end

  ## GenServer callbacks
  @impl true
  def init(_opts) do
    ensure_tables()
    schedule_cleanup()
    Logger.info("AI Cache started (kv=#{inspect(@kv_table)}, repos=#{inspect(@repo_table)})")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_kv()
    cleanup_expired_repos()
    schedule_cleanup()
    {:noreply, state}
  end

  # --- Private helpers ---

  defp ensure_tables do
    if :ets.info(@kv_table) == :undefined do
      :ets.new(@kv_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    end

    if :ets.info(@repo_table) == :undefined do
      :ets.new(@repo_table, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval)

  defp cleanup_expired_kv do
    now = System.system_time(:second)
    :ets.foldl(fn {key, _value, expires_at}, acc ->
      if expires_at != :infinity and expires_at < now do
        :ets.delete(@kv_table, key)
        acc + 1
      else
        acc
      end
    end, 0, @kv_table)
    :ok
  end

  defp hash_downcased(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp hash_term(term) do
    :erlang.phash2(term) |> Integer.to_string()
  end
end
