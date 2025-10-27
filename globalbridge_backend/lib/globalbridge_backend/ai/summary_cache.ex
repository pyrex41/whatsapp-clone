defmodule GlobalbridgeBackend.AI.SummaryCache do
  @moduledoc """
  Caches conversation summaries to avoid redundant LLM calls.

  Features:
  - Caches summaries with message count tracking
  - Supports incremental updates for small message deltas
  - Auto-expires old summaries
  - Thread-safe ETS-based storage
  """

  use GenServer
  require Logger

  @table_name :summary_cache
  @max_age_seconds 3600 * 24  # 24 hours
  @incremental_threshold 20    # Messages delta for incremental update

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Gets a cached summary for a thread.

  Returns:
  - `{:ok, summary, message_count}` if cached and fresh
  - `:miss` if not cached or expired
  """
  def get(thread_id) do
    case :ets.lookup(@table_name, thread_id) do
      [{^thread_id, summary, message_count, cached_at}] ->
        age = System.system_time(:second) - cached_at

        if age < @max_age_seconds do
          {:ok, summary, message_count}
        else
          Logger.debug("Summary cache expired for thread #{thread_id}")
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc """
  Puts a summary in the cache.
  """
  def put(thread_id, summary, message_count) do
    cached_at = System.system_time(:second)
    :ets.insert(@table_name, {thread_id, summary, message_count, cached_at})
    Logger.debug("Cached summary for thread #{thread_id} (#{message_count} messages)")
    :ok
  end

  @doc """
  Checks if incremental update is recommended.

  Returns `{:incremental, old_summary, new_message_count}` if the delta is small enough,
  otherwise returns `:full_regenerate`.
  """
  def should_update_incrementally?(thread_id, current_message_count) do
    case get(thread_id) do
      {:ok, old_summary, old_message_count} ->
        delta = current_message_count - old_message_count

        cond do
          delta <= 0 ->
            # No new messages, use cached
            {:use_cached, old_summary}

          delta <= @incremental_threshold ->
            # Small delta, do incremental update
            {:incremental, old_summary, old_message_count, delta}

          true ->
            # Large delta, full regenerate
            :full_regenerate
        end

      :miss ->
        :full_regenerate
    end
  end

  @doc """
  Clears the cache entry for a thread.
  """
  def delete(thread_id) do
    :ets.delete(@table_name, thread_id)
    :ok
  end

  @doc """
  Clears all cached summaries.
  """
  def clear_all do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  # Server Callbacks

  @impl true
  def init(_) do
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    Logger.info("Summary cache initialized")
    {:ok, %{}}
  end
end
