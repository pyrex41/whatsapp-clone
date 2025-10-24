defmodule GlobalbridgeBackend.AI.CostTrackerTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.CostTracker

  setup do
    # Start the CostTracker GenServer for testing
    {:ok, _pid} = CostTracker.start_link([])
    :ok
  end

  describe "log_cost/5" do
    test "logs embedding cost successfully" do
      result =
        CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{thread_id: "123"})

      assert result == :ok
    end

    test "logs LLM cost successfully" do
      result =
        CostTracker.log_cost(:llm, "gpt-4o", 150, 50, %{user_id: "456", operation: "summarize"})

      assert result == :ok
    end

    test "handles unknown service type" do
      result = CostTracker.log_cost(:unknown, "model", 10, 0, %{})

      # Should still succeed with 0 cost
      assert result == :ok
    end
  end

  describe "get_cost_stats/2" do
    test "returns cost statistics for current hour" do
      # Log some test costs
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      assert is_map(stats)
      assert stats.period == :hour
      assert is_number(stats.total_cost)
      assert stats.total_cost >= 0
      assert is_list(stats.service_breakdown)
      assert is_list(stats.model_breakdown)
    end

    test "filters by service type" do
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      {:ok, embedding_stats} = CostTracker.get_cost_stats(:hour, :embedding)
      {:ok, llm_stats} = CostTracker.get_cost_stats(:hour, :llm)

      assert embedding_stats.total_cost >= 0
      assert llm_stats.total_cost >= 0
    end
  end

  describe "get_monthly_total/0" do
    test "returns monthly total cost" do
      result = CostTracker.get_monthly_total()

      assert match?({:ok, total} when is_number(total), result)
    end
  end

  describe "cost calculation" do
    test "calculates embedding costs correctly" do
      # Test the internal cost calculation logic
      # This would require testing the private calculate_cost function
      # For now, we test through the public interface
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 1000, 0, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      # text-embedding-3-small costs $0.020 per 1K tokens
      expected_cost = 0.020
      assert_in_delta stats.total_cost, expected_cost, 0.001
    end

    test "calculates LLM costs correctly" do
      CostTracker.log_cost(:llm, "gpt-4o", 1000, 500, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      # GPT-4o costs $0.005 per input token + $0.015 per output token
      expected_cost = 1000 * 0.005 + 500 * 0.015
      assert_in_delta stats.total_cost, expected_cost, 0.001
    end
  end

  describe "telemetry integration" do
    test "sends telemetry events when logging costs" do
      # This test would verify that telemetry events are sent
      # In a real test, you would use Telemetry.Test to capture events
      result = CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{test: true})

      assert result == :ok
      # Telemetry events would be verified here
    end
  end
end
