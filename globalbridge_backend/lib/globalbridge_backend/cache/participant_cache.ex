defmodule GlobalbridgeBackend.Cache.ParticipantCache do
  @moduledoc """
  ETS-based cache for thread participant lookups to avoid repeated database queries.
  """

  use GenServer
  require Logger

  @table_name :participant_cache
  # Cache for 5 minutes
  @cache_ttl :timer.minutes(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Check if a user is a participant in a thread (with caching).
  """
  def is_participant?(thread_id, user_id) do
    case lookup(thread_id, user_id) do
      {:ok, is_participant} ->
        is_participant

      :not_found ->
        # Cache miss - check database and cache result
        is_participant = GlobalbridgeBackend.Chat.is_thread_participant?(thread_id, user_id)
        put(thread_id, user_id, is_participant)
        is_participant
    end
  end

  @doc """
  Invalidate cache for a specific thread when participants change.
  """
  def invalidate_thread(thread_id) do
    GenServer.call(__MODULE__, {:invalidate_thread, thread_id})
  end

  @doc """
  Clear entire cache (useful for testing or maintenance).
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Private API

  defp lookup(thread_id, user_id) do
    case :ets.lookup(@table_name, {thread_id, user_id}) do
      [{_key, value, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, value}
        else
          # Expired - remove and return not_found
          :ets.delete(@table_name, {thread_id, user_id})
          :not_found
        end

      [] ->
        :not_found
    end
  end

  defp put(thread_id, user_id, value) do
    expires_at = DateTime.add(DateTime.utc_now(), @cache_ttl, :millisecond)
    :ets.insert(@table_name, {{thread_id, user_id}, value, expires_at})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [:named_table, :public, :set])

    # Schedule cleanup of expired entries every minute
    Process.send_after(self(), :cleanup_expired, :timer.minutes(1))

    {:ok, %{}}
  end

  @impl true
  def handle_call({:invalidate_thread, thread_id}, _from, state) do
    # Remove all entries for this thread
    match_spec = [{{{thread_id, :"$1"}, :_, :_}, [], [true]}]
    :ets.select_delete(@table_name, match_spec)

    Logger.debug("Invalidated participant cache for thread: #{thread_id}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    Logger.info("Cleared entire participant cache")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = DateTime.utc_now()

    # Remove expired entries
    match_spec = [{{:_, :_, :"$1"}, [], [{:>, {:const, now}, :"$1"}]}]
    deleted_count = :ets.select_delete(@table_name, match_spec)

    if deleted_count > 0 do
      Logger.debug("Cleaned up #{deleted_count} expired participant cache entries")
    end

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired, :timer.minutes(1))

    {:noreply, state}
  end
end
