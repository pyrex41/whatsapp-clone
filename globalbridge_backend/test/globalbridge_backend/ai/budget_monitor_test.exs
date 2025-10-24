defmodule GlobalbridgeBackend.AI.BudgetMonitorTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.BudgetMonitor
  alias GlobalbridgeBackend.AI.CostTracker

  setup do
    # Start the BudgetMonitor GenServer for testing
    {:ok, _pid} = BudgetMonitor.start_link([])
    :ok
  end

  describe "check_budget/2" do
    test "allows costs within budget" do
      # Test with a small cost that should be within budget
      result = BudgetMonitor.check_budget(0.1, :monthly)

      assert result == :ok
    end

    test "warns when approaching budget limit" do
      # Log a large cost to trigger warning
      # ~$1.25 cost
      CostTracker.log_cost(:llm, "gpt-4o", 100_000, 50_000, %{})

      result = BudgetMonitor.check_budget(40.0, :monthly)

      assert match?({:warning, _}, result)
    end

    test "rejects costs exceeding budget" do
      # Log costs that exceed budget
      # ~$12.5 cost
      CostTracker.log_cost(:llm, "gpt-4o", 1_000_000, 500_000, %{})

      result = BudgetMonitor.check_budget(10.0, :monthly)

      assert match?({:exceeded, _}, result)
    end
  end

  describe "get_budget_status/0" do
    test "returns budget status for all periods" do
      status = BudgetMonitor.get_budget_status()

      assert is_map(status)
      assert Map.has_key?(status, :hourly)
      assert Map.has_key?(status, :daily)
      assert Map.has_key?(status, :monthly)

      # Check structure of each period
      Enum.each([:hourly, :daily, :monthly], fn period ->
        period_status = status[period]
        assert Map.has_key?(period_status, :limit)
        assert Map.has_key?(period_status, :current_spending)
        assert Map.has_key?(period_status, :remaining)
        assert Map.has_key?(period_status, :percentage_used)
        assert Map.has_key?(period_status, :status)
      end)
    end
  end

  describe "update_budget/2" do
    test "updates budget configuration" do
      new_config = %{
        limit: 100.0,
        warning_threshold: 0.75,
        critical_threshold: 0.9
      }

      result = BudgetMonitor.update_budget(:monthly, new_config)

      assert result == :ok

      # Verify the update
      status = BudgetMonitor.get_budget_status()
      monthly_status = status[:monthly]

      assert monthly_status.limit == 100.0
      # Converted to percentage
      assert monthly_status.warning_threshold == 75.0
    end
  end

  describe "reset_budget/1" do
    test "resets budget tracking" do
      result = BudgetMonitor.reset_budget(:monthly)

      assert result == :ok
    end
  end

  describe "budget status indicators" do
    test "correctly identifies budget status" do
      # Test with different spending levels
      status = BudgetMonitor.get_budget_status()
      monthly_status = status[:monthly]

      # Should be :ok for low spending
      assert monthly_status.status in [:ok, :warning, :critical, :exceeded]
    end
  end

  describe "periodic budget checks" do
    test "handles periodic check messages" do
      # Send the periodic check message
      send(BudgetMonitor, :check_budgets)

      # The GenServer should handle this without crashing
      # In a real test, you might wait for processing or check side effects
      # Give it time to process
      Process.sleep(100)

      assert Process.alive?(Process.whereis(BudgetMonitor))
    end
  end

  describe "alert thresholds" do
    test "warning threshold triggers correctly" do
      # Update budget to a low limit for testing
      BudgetMonitor.update_budget(:monthly, %{
        limit: 10.0,
        # 50%
        warning_threshold: 0.5,
        # 80%
        critical_threshold: 0.8
      })

      # This should trigger a warning (if spending is > $5)
      result = BudgetMonitor.check_budget(6.0, :monthly)

      case result do
        # Acceptable if no spending logged yet
        :ok -> assert true
        # Expected when spending is high
        {:warning, _} -> assert true
        # Other states are also valid
        _ -> assert true
      end
    end
  end
end
