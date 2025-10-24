defmodule GlobalbridgeBackend.AI.BudgetMonitor do
  @moduledoc """
  Monitors AI API budgets and alerts when thresholds are exceeded.

  This module provides budget monitoring capabilities with configurable
  thresholds, alerting mechanisms, and budget enforcement.
  """

  use GenServer
  require Logger

  alias GlobalbridgeBackend.AI.CostTracker

  # Default budget configurations
  @default_budgets %{
    monthly: %{
      # $50 per month
      limit: 50.0,
      # 80% of budget
      warning_threshold: 0.8,
      # 95% of budget
      critical_threshold: 0.95
    },
    daily: %{
      # $5 per day
      limit: 5.0,
      # 70% of budget
      warning_threshold: 0.7,
      # 90% of budget
      critical_threshold: 0.9
    },
    hourly: %{
      # $1 per hour
      limit: 1.0,
      # 50% of budget
      warning_threshold: 0.5,
      # 80% of budget
      critical_threshold: 0.8
    }
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Load budget configuration from environment or use defaults
    budgets = Keyword.get(opts, :budgets, load_budget_config())

    # Schedule periodic budget checks
    schedule_budget_check()

    {:ok, %{budgets: budgets, alerts_sent: MapSet.new()}}
  end

  @doc """
  Checks if a cost would exceed the current budget.

  ## Parameters
  - `cost_usd`: The cost in USD to check
  - `period`: :hourly, :daily, or :monthly

  ## Returns
  - `:ok` if within budget
  - `{:warning, remaining}` if approaching limit
  - `{:exceeded, over_by}` if over budget
  """
  @spec check_budget(float(), atom()) :: :ok | {:warning, float()} | {:exceeded, float()}
  def check_budget(cost_usd, period \\ :monthly) do
    GenServer.call(__MODULE__, {:check_budget, cost_usd, period})
  end

  @doc """
  Gets current budget status for all periods.

  ## Returns
  - Map with budget status for each period
  """
  @spec get_budget_status() :: map()
  def get_budget_status do
    GenServer.call(__MODULE__, :get_budget_status)
  end

  @doc """
  Updates budget configuration.

  ## Parameters
  - `period`: :hourly, :daily, or :monthly
  - `config`: Budget configuration map with :limit, :warning_threshold, :critical_threshold
  """
  @spec update_budget(atom(), map()) :: :ok
  def update_budget(period, config) do
    GenServer.call(__MODULE__, {:update_budget, period, config})
  end

  @doc """
  Resets budget tracking (useful for new billing periods).
  """
  @spec reset_budget(atom()) :: :ok
  def reset_budget(period) do
    GenServer.call(__MODULE__, {:reset_budget, period})
  end

  @impl true
  def handle_call({:check_budget, cost_usd, period}, _from, state) do
    budgets = state.budgets
    budget_config = Map.get(budgets, period, Map.get(@default_budgets, period))

    # Get current spending for the period
    {:ok, current_spending} = get_current_spending(period)

    total_cost = current_spending + cost_usd
    limit = budget_config.limit

    cond do
      total_cost > limit ->
        over_by = total_cost - limit
        {:reply, {:exceeded, over_by}, state}

      total_cost >= limit * budget_config.critical_threshold ->
        remaining = limit - total_cost
        {:reply, {:critical, remaining}, state}

      total_cost >= limit * budget_config.warning_threshold ->
        remaining = limit - total_cost
        {:reply, {:warning, remaining}, state}

      true ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:get_budget_status, _from, state) do
    budgets = state.budgets

    status =
      Enum.map([:hourly, :daily, :monthly], fn period ->
        budget_config = Map.get(budgets, period, Map.get(@default_budgets, period))
        {:ok, current_spending} = get_current_spending(period)

        percentage_used =
          if budget_config.limit > 0 do
            current_spending / budget_config.limit * 100
          else
            0.0
          end

        {period,
         %{
           limit: budget_config.limit,
           current_spending: current_spending,
           remaining: budget_config.limit - current_spending,
           percentage_used: Float.round(percentage_used, 2),
           warning_threshold: budget_config.warning_threshold * 100,
           critical_threshold: budget_config.critical_threshold * 100,
           status: get_budget_status_indicator(current_spending, budget_config)
         }}
      end)
      |> Map.new()

    {:reply, status, state}
  end

  @impl true
  def handle_call({:update_budget, period, config}, _from, state) do
    updated_budgets = Map.put(state.budgets, period, config)
    {:reply, :ok, %{state | budgets: updated_budgets}}
  end

  @impl true
  def handle_call({:reset_budget, period}, _from, state) do
    # In a real implementation, this would reset counters in the database
    Logger.info("Reset budget tracking for period: #{period}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:check_budgets, state) do
    # Periodic budget check
    updated_state = check_all_budgets(state)

    # Schedule next check
    schedule_budget_check()

    {:noreply, updated_state}
  end

  # Private functions

  defp get_current_spending(:hourly) do
    CostTracker.get_cost_stats(:hour)
    |> case do
      {:ok, stats} -> {:ok, stats.total_cost}
      _ -> {:ok, 0.0}
    end
  end

  defp get_current_spending(:daily) do
    CostTracker.get_cost_stats(:day)
    |> case do
      {:ok, stats} -> {:ok, stats.total_cost}
      _ -> {:ok, 0.0}
    end
  end

  defp get_current_spending(:monthly) do
    CostTracker.get_monthly_total()
  end

  defp get_budget_status_indicator(current_spending, budget_config) do
    percentage = current_spending / budget_config.limit

    cond do
      percentage >= budget_config.critical_threshold -> :critical
      percentage >= budget_config.warning_threshold -> :warning
      percentage >= 1.0 -> :exceeded
      true -> :ok
    end
  end

  defp check_all_budgets(state) do
    budgets = state.budgets
    alerts_sent = state.alerts_sent

    updated_alerts_sent =
      Enum.reduce([:hourly, :daily, :monthly], alerts_sent, fn period, acc ->
        budget_config = Map.get(budgets, period, Map.get(@default_budgets, period))
        {:ok, current_spending} = get_current_spending(period)

        status = get_budget_status_indicator(current_spending, budget_config)
        alert_key = {period, status}

        # Send alert if we haven't already sent one for this status
        if MapSet.member?(acc, alert_key) do
          acc
        else
          send_budget_alert(period, status, current_spending, budget_config)
          MapSet.put(acc, alert_key)
        end
      end)

    # Reset alerts for statuses that are no longer active
    final_alerts_sent = reset_old_alerts(updated_alerts_sent)

    %{state | alerts_sent: final_alerts_sent}
  end

  defp send_budget_alert(period, status, current_spending, budget_config) do
    message =
      case status do
        :warning ->
          "Budget warning: #{period} spending at #{Float.round(current_spending / budget_config.limit * 100, 1)}% of limit ($#{Float.round(current_spending, 2)})"

        :critical ->
          "Budget critical: #{period} spending at #{Float.round(current_spending / budget_config.limit * 100, 1)}% of limit ($#{Float.round(current_spending, 2)})"

        :exceeded ->
          "Budget exceeded: #{period} spending is $#{Float.round(current_spending - budget_config.limit, 2)} over the $#{budget_config.limit} limit"

        _ ->
          nil
      end

    if message do
      Logger.warning("BUDGET ALERT: #{message}")

      # In a real implementation, this would send notifications via email, Slack, etc.
      # send_notification(:budget_alert, message)
    end
  end

  defp reset_old_alerts(current_alerts) do
    # In a real implementation, this would track which alerts are still active
    # and remove old ones from the alerts_sent set
    current_alerts
  end

  defp schedule_budget_check do
    # Check budgets every 5 minutes
    Process.send_after(self(), :check_budgets, 5 * 60 * 1000)
  end

  defp load_budget_config do
    # Load budget configuration from environment variables or config
    # For now, return defaults
    @default_budgets
  end
end
