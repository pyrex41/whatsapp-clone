defmodule GlobalbridgeBackend.AI.Cache do
  @moduledoc """
  ETS-based caching for AI operations (translations, embeddings, etc.).

  ## Features

  - Fast in-memory storage with ETS
  - TTL-based expiration
  - Pattern-based deletion
  - Automatic cleanup of expired entries

  ## Usage

      # Start the cache (usually in application.ex)
      {:ok, _pid} = Cache.start_link()

      # Store with TTL
      Cache.put("translation:en:es:hello", "¡Hola!", ttl: 3600)

      # Retrieve
      {:ok, "¡Hola!"} = Cache.get("translation:en:es:hello")

      # Delete pattern
      Cache.delete_pattern("translation:en:es:")
  """

  use GenServer
  require Logger

  @table_name :ai_cache
  @cleanup_interval 60_000  # Clean expired entries every 60 seconds

  ## Client API

  @doc """
  Starts the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a value from the cache.

  Returns {:ok, value} if found and not expired, {:error, :not_found} otherwise.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if expires_at == :infinity or System.system_time(:second) < expires_at do
          {:ok, value}
        else
          # Expired - delete it
          :ets.delete(@table_name, key)
          {:error, :not_found}
        end
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Puts a value into the cache.

  ## Options

  - :ttl - Time to live in seconds (default: 3600)
  - If ttl is :infinity, the entry never expires

  ## Examples

      Cache.put("key", "value", ttl: 3600)
      Cache.put("key", "value", ttl: :infinity)
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, 3600)

    expires_at = case ttl do
      :infinity -> :infinity
      seconds when is_integer(seconds) -> System.system_time(:second) + seconds
    end

    :ets.insert(@table_name, {key, value, expires_at})
    :ok
  end

  @doc """
  Deletes all entries matching a pattern.

  Pattern uses simple prefix matching:
  - "translation:en:es:" matches all English to Spanish translations

  ## Examples

      Cache.delete_pattern("translation:en:es:")
      Cache.delete_pattern("embedding:")
  """
  def delete_pattern(pattern) do
    # For pattern matching, we'll iterate through all keys
    # This is acceptable since ETS is very fast and cache size is limited
    prefix = String.trim_trailing(pattern, "*")

    deleted = :ets.foldl(fn {key, _value, _expires_at}, acc ->
      if String.starts_with?(key, prefix) do
        :ets.delete(@table_name, key)
        acc + 1
      else
        acc
      end
    end, 0, @table_name)

    Logger.debug("Deleted #{deleted} cache entries matching pattern: #{pattern}")
    {:ok, deleted}
  end

  @doc """
  Deletes a specific key from the cache.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Clears all entries from the cache.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Gets cache statistics.
  """
  def stats do
    total_entries = :ets.info(@table_name, :size)
    memory_bytes = :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)

    %{
      total_entries: total_entries,
      memory_bytes: memory_bytes,
      memory_mb: Float.round(memory_bytes / 1_024_000, 2)
    }
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    Logger.info("AI Cache started with ETS table: #{@table_name}")
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_entries do
    now = System.system_time(:second)

    # Iterate and delete expired entries
    deleted = :ets.foldl(fn {key, _value, expires_at}, acc ->
      if expires_at != :infinity and expires_at < now do
        :ets.delete(@table_name, key)
        acc + 1
      else
        acc
      end
    end, 0, @table_name)

    if deleted > 0 do
      Logger.debug("Cleaned up #{deleted} expired cache entries")
    end
  end
end
