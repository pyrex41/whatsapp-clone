defmodule GlobalbridgeBackend.AI.CostTrackerTest do
  use ExUnit.Case, async: false

  alias GlobalbridgeBackend.AI.CostTracker

  setup do
    # CostTracker is already started by the Application supervisor
    # Just clear any existing data from previous tests
    CostTracker.clear_all_costs()

    on_exit(fn ->
      # Clean up after each test
      CostTracker.clear_all_costs()
    end)

    :ok
  end

  describe "ETS table initialization" do
    test "creates ETS table on init" do
      assert :ets.info(:cost_tracking) != :undefined
      info = :ets.info(:cost_tracking)
      assert info[:type] == :ordered_set
      assert info[:named_table] == true
      assert info[:read_concurrency] == true
      assert info[:write_concurrency] == true
    end
  end

  describe "log_cost/5" do
    test "logs embedding cost successfully and persists to ETS" do
      result =
        CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{thread_id: "123"})

      assert result == :ok

      # Verify data is in ETS
      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.record_count >= 1
      assert stats.total_input_tokens >= 100
    end

    test "logs LLM cost successfully and persists to ETS" do
      result =
        CostTracker.log_cost(:llm, "gpt-4o", 150, 50, %{user_id: "456", operation: "summarize"})

      assert result == :ok

      # Verify data is in ETS
      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.record_count >= 1
      assert stats.total_input_tokens >= 150
      assert stats.total_output_tokens >= 50
    end

    test "handles unknown service type with zero cost" do
      result = CostTracker.log_cost(:unknown, "model", 10, 0, %{})

      assert result == :ok

      # Verify it's logged even with zero cost
      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.record_count >= 1
    end

    test "handles concurrent cost logging" do
      # Simulate concurrent logging from multiple processes
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            CostTracker.log_cost(:embedding, "text-embedding-3-small", i, 0, %{index: i})
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, &(&1 == :ok))

      # Verify all records are in ETS
      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.record_count == 100
    end
  end

  describe "get_cost_stats/2" do
    setup do
      # Insert test data with known values
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 1000, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 2000, 1000, %{})
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 500, 0, %{})

      :ok
    end

    test "returns cost statistics for current hour" do
      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      assert is_map(stats)
      assert stats.period == :hour
      assert is_number(stats.total_cost)
      assert stats.total_cost > 0
      assert stats.total_input_tokens == 3500
      assert stats.total_output_tokens == 1000
      assert stats.record_count == 3
      assert is_map(stats.service_breakdown)
      assert is_map(stats.model_breakdown)
    end

    test "returns cost statistics for current day" do
      {:ok, stats} = CostTracker.get_cost_stats(:day)

      assert stats.period == :day
      assert stats.total_input_tokens == 3500
      assert stats.record_count == 3
    end

    test "filters by service type" do
      {:ok, embedding_stats} = CostTracker.get_cost_stats(:hour, :embedding)
      {:ok, llm_stats} = CostTracker.get_cost_stats(:hour, :llm)

      # Embedding: 1000 + 500 = 1500 tokens
      assert embedding_stats.total_input_tokens == 1500
      assert embedding_stats.total_output_tokens == 0
      assert embedding_stats.record_count == 2

      # LLM: 2000 input, 1000 output
      assert llm_stats.total_input_tokens == 2000
      assert llm_stats.total_output_tokens == 1000
      assert llm_stats.record_count == 1
    end

    test "service breakdown is correct" do
      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      assert Map.has_key?(stats.service_breakdown, :embedding)
      assert Map.has_key?(stats.service_breakdown, :llm)

      embedding_breakdown = stats.service_breakdown[:embedding]
      assert embedding_breakdown.count == 2
      assert embedding_breakdown.total_input_tokens == 1500

      llm_breakdown = stats.service_breakdown[:llm]
      assert llm_breakdown.count == 1
      assert llm_breakdown.total_input_tokens == 2000
    end

    test "model breakdown is correct" do
      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      assert Map.has_key?(stats.model_breakdown, "text-embedding-3-small")
      assert Map.has_key?(stats.model_breakdown, "gpt-4o")

      embedding_breakdown = stats.model_breakdown["text-embedding-3-small"]
      assert embedding_breakdown.count == 2

      llm_breakdown = stats.model_breakdown["gpt-4o"]
      assert llm_breakdown.count == 1
    end

    test "returns empty stats when no costs logged" do
      CostTracker.clear_all_costs()

      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      assert stats.total_cost == 0.0
      assert stats.total_input_tokens == 0
      assert stats.total_output_tokens == 0
      assert stats.record_count == 0
      assert stats.service_breakdown == %{}
      assert stats.model_breakdown == %{}
    end
  end

  describe "get_monthly_total/0" do
    test "returns monthly total cost" do
      # Log some costs
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 1000, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 2000, 1000, %{})

      {:ok, total} = CostTracker.get_monthly_total()

      assert is_float(total)
      assert total > 0
    end

    test "returns zero when no costs logged" do
      CostTracker.clear_all_costs()

      {:ok, total} = CostTracker.get_monthly_total()

      assert total == 0.0
    end
  end

  describe "get_costs_by_period/3" do
    test "retrieves costs within a specific time range" do
      # Log costs
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      # Query for last hour
      now = DateTime.utc_now()
      one_hour_ago = DateTime.add(now, -3600, :second)

      start_time_us = DateTime.to_unix(one_hour_ago, :microsecond)
      end_time_us = DateTime.to_unix(now, :microsecond)

      results = CostTracker.get_costs_by_period(start_time_us, end_time_us)

      assert length(results) == 2
      assert Enum.all?(results, &is_map/1)
      assert Enum.all?(results, &Map.has_key?(&1, :service))
      assert Enum.all?(results, &Map.has_key?(&1, :cost_usd))
    end

    test "filters by service in time range" do
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      now = DateTime.utc_now()
      one_hour_ago = DateTime.add(now, -3600, :second)

      start_time_us = DateTime.to_unix(one_hour_ago, :microsecond)
      end_time_us = DateTime.to_unix(now, :microsecond)

      embedding_results = CostTracker.get_costs_by_period(start_time_us, end_time_us, :embedding)
      llm_results = CostTracker.get_costs_by_period(start_time_us, end_time_us, :llm)

      assert length(embedding_results) == 1
      assert length(llm_results) == 1
      assert hd(embedding_results).service == :embedding
      assert hd(llm_results).service == :llm
    end

    test "returns empty list for time range with no costs" do
      # Query for a past time range
      now = DateTime.utc_now()
      two_days_ago = DateTime.add(now, -172_800, :second)
      one_day_ago = DateTime.add(now, -86400, :second)

      start_time_us = DateTime.to_unix(two_days_ago, :microsecond)
      end_time_us = DateTime.to_unix(one_day_ago, :microsecond)

      results = CostTracker.get_costs_by_period(start_time_us, end_time_us)

      assert results == []
    end
  end

  describe "get_daily_aggregation/2" do
    test "aggregates costs by day" do
      # Log costs
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      today = Date.utc_today()
      daily_stats = CostTracker.get_daily_aggregation(today, today)

      assert is_map(daily_stats)
      today_str = Date.to_string(today)
      assert Map.has_key?(daily_stats, today_str)

      today_stats = daily_stats[today_str]
      assert today_stats.total_cost > 0
      assert today_stats.total_input_tokens == 300
      assert today_stats.total_output_tokens == 100
      assert today_stats.record_count == 2
    end

    test "returns empty map for date range with no costs" do
      yesterday = Date.add(Date.utc_today(), -1)
      two_days_ago = Date.add(Date.utc_today(), -2)

      daily_stats = CostTracker.get_daily_aggregation(two_days_ago, yesterday)

      assert daily_stats == %{}
    end

    test "includes service and model breakdowns in daily stats" do
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      today = Date.utc_today()
      daily_stats = CostTracker.get_daily_aggregation(today, today)

      today_str = Date.to_string(today)
      today_stats = daily_stats[today_str]

      assert is_map(today_stats.service_breakdown)
      assert is_map(today_stats.model_breakdown)
      assert Map.has_key?(today_stats.service_breakdown, :embedding)
      assert Map.has_key?(today_stats.service_breakdown, :llm)
    end
  end

  describe "get_weekly_aggregation/2" do
    test "aggregates costs by week" do
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      today = Date.utc_today()
      weekly_stats = CostTracker.get_weekly_aggregation(today, today)

      assert is_map(weekly_stats)
      assert map_size(weekly_stats) >= 1

      # Check that we have valid weekly stats
      {_week_key, week_data} = Enum.at(weekly_stats, 0)
      assert week_data.total_cost > 0
      assert week_data.total_input_tokens == 300
      assert week_data.record_count == 2
    end
  end

  describe "get_monthly_aggregation/2" do
    test "aggregates costs by month" do
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      today = Date.utc_today()
      monthly_stats = CostTracker.get_monthly_aggregation(today, today)

      assert is_map(monthly_stats)
      assert map_size(monthly_stats) >= 1

      # Get current month key (YYYY-MM format)
      current_month =
        "#{today.year}-#{String.pad_leading(to_string(today.month), 2, "0")}"

      assert Map.has_key?(monthly_stats, current_month)

      month_data = monthly_stats[current_month]
      assert month_data.total_cost > 0
      assert month_data.total_input_tokens == 300
      assert month_data.record_count == 2
      assert is_map(month_data.service_breakdown)
      assert is_map(month_data.model_breakdown)
    end
  end

  describe "clear_all_costs/0" do
    test "clears all cost records from ETS" do
      # Log some costs
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 200, 100, %{})

      # Verify costs exist
      {:ok, stats_before} = CostTracker.get_cost_stats(:hour)
      assert stats_before.record_count == 2

      # Clear all costs
      assert :ok = CostTracker.clear_all_costs()

      # Verify costs are cleared
      {:ok, stats_after} = CostTracker.get_cost_stats(:hour)
      assert stats_after.record_count == 0
      assert stats_after.total_cost == 0.0
    end
  end

  describe "cost calculation accuracy" do
    test "calculates embedding costs correctly" do
      # text-embedding-3-small: $0.020 per 1K tokens = 0.00002 per token
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 1000, 0, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      expected_cost = 0.020
      assert_in_delta stats.total_cost, expected_cost, 0.001
    end

    test "calculates LLM costs correctly for GPT-4o" do
      # GPT-4o: $0.005 per 1K input tokens, $0.015 per 1K output tokens
      # = 0.000005 per input token, 0.000015 per output token
      CostTracker.log_cost(:llm, "gpt-4o", 1000, 500, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      # 1000 * 0.000005 + 500 * 0.000015 = 0.005 + 0.0075 = 0.0125
      expected_cost = 0.0125
      assert_in_delta stats.total_cost, expected_cost, 0.001
    end

    test "handles multiple models correctly" do
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 1000, 0, %{})
      CostTracker.log_cost(:embedding, "text-embedding-3-large", 1000, 0, %{})
      CostTracker.log_cost(:llm, "gpt-4o", 1000, 500, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)

      # text-embedding-3-small: 0.020
      # text-embedding-3-large: 0.130
      # gpt-4o: 0.0125
      # Total: 0.1625
      expected_total = 0.1625
      assert_in_delta stats.total_cost, expected_total, 0.001
    end
  end

  describe "performance benchmarks" do
    @tag :performance
    test "query performance with 10k+ records is < 10ms" do
      # Insert 10,000 cost records
      for i <- 1..10_000 do
        CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{index: i})
      end

      # Benchmark query performance
      {time_us, {:ok, stats}} =
        :timer.tc(fn ->
          CostTracker.get_cost_stats(:day)
        end)

      time_ms = time_us / 1000

      # Performance requirement: < 10ms
      assert time_ms < 10.0, "Query took #{time_ms}ms, expected < 10ms"
      assert stats.record_count == 10_000
    end

    @tag :performance
    test "concurrent read/write performance" do
      # Simulate concurrent operations
      write_tasks =
        for i <- 1..1000 do
          Task.async(fn ->
            CostTracker.log_cost(:embedding, "text-embedding-3-small", i, 0, %{index: i})
          end)
        end

      read_tasks =
        for _ <- 1..100 do
          Task.async(fn ->
            CostTracker.get_cost_stats(:hour)
          end)
        end

      # Wait for all tasks
      write_results = Task.await_many(write_tasks, 10_000)
      read_results = Task.await_many(read_tasks, 10_000)

      # All writes should succeed
      assert Enum.all?(write_results, &(&1 == :ok))

      # All reads should succeed
      assert Enum.all?(read_results, fn
               {:ok, _stats} -> true
               _ -> false
             end)
    end

    @tag :performance
    test "aggregation performance with large dataset" do
      # Insert 5000 records across different days
      for i <- 1..5000 do
        CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{index: i})
      end

      # Benchmark daily aggregation
      {time_us, daily_stats} =
        :timer.tc(fn ->
          today = Date.utc_today()
          CostTracker.get_daily_aggregation(today, today)
        end)

      time_ms = time_us / 1000

      # Should be fast even with 5k records
      assert time_ms < 50.0, "Daily aggregation took #{time_ms}ms, expected < 50ms"
      assert is_map(daily_stats)
    end
  end

  describe "edge cases and error handling" do
    test "handles zero tokens" do
      assert :ok = CostTracker.log_cost(:embedding, "text-embedding-3-small", 0, 0, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.total_cost == 0.0
      assert stats.record_count == 1
    end

    test "handles large token counts" do
      # 1 million tokens
      assert :ok = CostTracker.log_cost(:embedding, "text-embedding-3-small", 1_000_000, 0, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.total_cost > 0
      assert stats.total_input_tokens == 1_000_000
    end

    test "handles empty metadata" do
      assert :ok = CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.record_count == 1
    end

    test "handles complex metadata" do
      metadata = %{
        user_id: "12345",
        thread_id: "thread-abc",
        operation: "summarize",
        nested: %{
          key: "value",
          list: [1, 2, 3]
        }
      }

      assert :ok = CostTracker.log_cost(:llm, "gpt-4o", 100, 50, metadata)

      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      assert stats.record_count == 1
    end

    test "handles unknown models with fallback costs" do
      # Unknown embedding model should use fallback cost
      CostTracker.log_cost(:embedding, "unknown-embedding-model", 1000, 0, %{})

      {:ok, stats} = CostTracker.get_cost_stats(:hour)
      # Should have some cost (fallback: 0.0001 per token)
      assert stats.total_cost > 0
    end
  end
end
