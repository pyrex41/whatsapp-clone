defmodule GlobalbridgeBackend.AI.EmbeddingCache do
  @moduledoc """
  ETS-based cache for query embeddings to enable eager generation.

  This cache allows us to:
  1. Generate query embeddings when thread opens (background)
  2. Use cached embeddings when user taps composer (instant!)
  3. Invalidate when new messages arrive

  ## Performance Impact
  - Without cache: 5-7s embedding generation on composer tap
  - With cache: <1ms lookup, suggestions appear in ~1s
  """

  use GenServer
  require Logger

  @table_name :embedding_cache
  @default_ttl 600_000  # 10 minutes in milliseconds

  ## Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Gets a cached embedding for a thread's conversation context.

  Returns {:ok, embedding} if found and not expired, :miss otherwise.
  """
  def get(thread_id) when is_binary(thread_id) do
    case :ets.lookup(@table_name, thread_id) do
      [{^thread_id, embedding, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          Logger.debug("[EMBEDDING_CACHE] HIT for thread #{thread_id}")
          {:ok, embedding}
        else
          Logger.debug("[EMBEDDING_CACHE] EXPIRED for thread #{thread_id}")
          :ets.delete(@table_name, thread_id)
          :miss
        end

      [] ->
        Logger.debug("[EMBEDDING_CACHE] MISS for thread #{thread_id}")
        :miss
    end
  end

  @doc """
  Stores an embedding in the cache with optional TTL.

  ## Options
  - ttl: Time-to-live in milliseconds (default: 10 minutes)
  """
  def put(thread_id, embedding, opts \\ []) when is_binary(thread_id) and is_list(embedding) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expires_at = System.monotonic_time(:millisecond) + ttl

    :ets.insert(@table_name, {thread_id, embedding, expires_at})
    Logger.debug("[EMBEDDING_CACHE] STORED for thread #{thread_id}, expires in #{ttl}ms")
    :ok
  end

  @doc """
  Invalidates (deletes) a cached embedding for a thread.

  Call this when a new message is sent to the thread.
  """
  def invalidate(thread_id) when is_binary(thread_id) do
    :ets.delete(@table_name, thread_id)
    Logger.debug("[EMBEDDING_CACHE] INVALIDATED for thread #{thread_id}")
    :ok
  end

  @doc """
  Clears all expired entries from the cache.

  Called periodically by the GenServer.
  """
  def cleanup_expired do
    now = System.monotonic_time(:millisecond)

    expired = :ets.select(@table_name, [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [:"$1"]}
    ])

    Enum.each(expired, fn thread_id ->
      :ets.delete(@table_name, thread_id)
    end)

    if length(expired) > 0 do
      Logger.debug("[EMBEDDING_CACHE] Cleaned up #{length(expired)} expired entries")
    end

    :ok
  end

  @doc """
  Gets cache statistics.
  """
  def stats do
    size = :ets.info(@table_name, :size)
    memory = :ets.info(@table_name, :memory)

    %{
      entries: size,
      memory_words: memory,
      memory_kb: div(memory * :erlang.system_info(:wordsize), 1024)
    }
  end

  ## GenServer Callbacks

  @impl true
  def init(:ok) do
    # Create ETS table
    :ets.new(@table_name, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    Logger.info("[EMBEDDING_CACHE] Started with table #{@table_name}")

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    # Run cleanup every 5 minutes
    Process.send_after(self(), :cleanup, 5 * 60 * 1000)
  end
end
