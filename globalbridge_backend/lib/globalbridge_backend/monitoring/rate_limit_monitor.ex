defmodule GlobalbridgeBackend.Monitoring.RateLimitMonitor do
  @moduledoc """
  Monitors AI rate limit events and provides alerting capabilities.

  This module attaches to telemetry events and can trigger alerts based on:
  - High frequency of rate limit hits for a user
  - Specific endpoints being heavily rate limited
  - System-wide rate limit patterns

  Configure alerting thresholds via environment:
  - RATE_LIMIT_ALERT_THRESHOLD (default: 10 hits per user per hour)
  - RATE_LIMIT_ALERT_WINDOW_MS (default: 3600000 = 1 hour)
  """

  use GenServer
  require Logger

  @default_alert_threshold 10
  @default_window_ms 3_600_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current rate limit statistics.
  Returns a map of user_id => endpoint => hit_count
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Reset statistics for a specific user and endpoint.
  """
  def reset_stats(user_id, endpoint) do
    GenServer.cast(__MODULE__, {:reset_stats, user_id, endpoint})
  end

  @doc """
  Get users who have exceeded alert thresholds.
  """
  def get_alerts do
    GenServer.call(__MODULE__, :get_alerts)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Attach to telemetry events
    :telemetry.attach(
      "rate-limit-monitor",
      [:globalbridge_backend, :ai, :rate_limit, :exceeded],
      &__MODULE__.handle_event/4,
      %{}
    )

    # Initialize state with ETS table for efficient lookups
    table = :ets.new(:rate_limit_stats, [:set, :public, :named_table])

    state = %{
      stats_table: table,
      alert_threshold: get_alert_threshold(),
      window_ms: get_window_ms()
    }

    Logger.info("Rate limit monitor started with threshold: #{state.alert_threshold} hits per #{div(state.window_ms, 1000)}s")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = build_stats_map(state.stats_table)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_alerts, _from, state) do
    alerts = find_alerts(state.stats_table, state.alert_threshold, state.window_ms)
    {:reply, alerts, state}
  end

  @impl true
  def handle_cast({:reset_stats, user_id, endpoint}, state) do
    key = {user_id, endpoint}
    :ets.delete(state.stats_table, key)
    {:noreply, state}
  end

  # Telemetry Event Handler

  def handle_event(
        [:globalbridge_backend, :ai, :rate_limit, :exceeded],
        _measurements,
        %{user_id: user_id, endpoint: endpoint, timestamp: timestamp},
        _config
      ) do
    # Record the event
    record_event(user_id, endpoint, timestamp)

    # Check if we should trigger an alert
    check_and_alert(user_id, endpoint)
  end

  # Private Functions

  defp record_event(user_id, endpoint, timestamp) do
    key = {user_id, endpoint}

    case :ets.lookup(:rate_limit_stats, key) do
      [] ->
        :ets.insert(:rate_limit_stats, {key, [{timestamp, 1}]})

      [{^key, events}] ->
        # Clean old events outside the window
        window_ms = get_window_ms()
        cutoff = timestamp - window_ms
        recent_events = Enum.filter(events, fn {ts, _} -> ts > cutoff end)

        # Add new event
        updated_events = [{timestamp, 1} | recent_events]
        :ets.insert(:rate_limit_stats, {key, updated_events})
    end
  end

  defp check_and_alert(user_id, endpoint) do
    key = {user_id, endpoint}
    threshold = get_alert_threshold()
    window_ms = get_window_ms()

    case :ets.lookup(:rate_limit_stats, key) do
      [{^key, events}] ->
        now = System.system_time(:millisecond)
        cutoff = now - window_ms
        recent_count = events |> Enum.filter(fn {ts, _} -> ts > cutoff end) |> length()

        if recent_count >= threshold do
          trigger_alert(user_id, endpoint, recent_count, threshold)
        end

      _ ->
        :ok
    end
  end

  defp trigger_alert(user_id, endpoint, count, threshold) do
    Logger.warning("""
    🚨 AI Rate Limit Alert!
    User: #{user_id}
    Endpoint: #{endpoint}
    Hits: #{count} (threshold: #{threshold})
    Window: #{div(get_window_ms(), 1000)}s
    """)

    # Emit additional telemetry for external monitoring systems
    :telemetry.execute(
      [:globalbridge_backend, :ai, :rate_limit, :alert],
      %{count: count},
      %{
        user_id: user_id,
        endpoint: endpoint,
        threshold: threshold,
        severity: calculate_severity(count, threshold)
      }
    )
  end

  defp calculate_severity(count, threshold) do
    ratio = count / threshold

    cond do
      ratio >= 3 -> :critical
      ratio >= 2 -> :high
      ratio >= 1.5 -> :medium
      true -> :low
    end
  end

  defp build_stats_map(table) do
    :ets.tab2list(table)
    |> Enum.reduce(%{}, fn {{user_id, endpoint}, events}, acc ->
      now = System.system_time(:millisecond)
      cutoff = now - get_window_ms()
      recent_count = events |> Enum.filter(fn {ts, _} -> ts > cutoff end) |> length()

      user_stats = Map.get(acc, user_id, %{})
      updated_user_stats = Map.put(user_stats, endpoint, recent_count)
      Map.put(acc, user_id, updated_user_stats)
    end)
  end

  defp find_alerts(table, threshold, window_ms) do
    now = System.system_time(:millisecond)
    cutoff = now - window_ms

    :ets.tab2list(table)
    |> Enum.filter(fn {{_user_id, _endpoint}, events} ->
      recent_count = events |> Enum.filter(fn {ts, _} -> ts > cutoff end) |> length()
      recent_count >= threshold
    end)
    |> Enum.map(fn {{user_id, endpoint}, events} ->
      recent_count = events |> Enum.filter(fn {ts, _} -> ts > cutoff end) |> length()

      %{
        user_id: user_id,
        endpoint: endpoint,
        count: recent_count,
        threshold: threshold,
        severity: calculate_severity(recent_count, threshold)
      }
    end)
  end

  defp get_alert_threshold do
    case System.get_env("RATE_LIMIT_ALERT_THRESHOLD") do
      nil -> @default_alert_threshold
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> @default_alert_threshold
  end

  defp get_window_ms do
    case System.get_env("RATE_LIMIT_ALERT_WINDOW_MS") do
      nil -> @default_window_ms
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> @default_window_ms
  end
end
