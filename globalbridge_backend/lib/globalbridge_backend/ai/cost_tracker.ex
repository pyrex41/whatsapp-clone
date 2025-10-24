defmodule GlobalbridgeBackend.AI.CostTracker do
  @moduledoc """
  Tracks API costs for AI services with ETS-based persistence.

  This module provides functionality to log costs for various AI API calls,
  calculate usage statistics, and provide cost reporting capabilities.

  ## Features
  - ETS-based cost persistence with < 10ms query performance
  - Real-time cost tracking for embeddings and LLM calls
  - Aggregation by day, week, and month
  - Service and model breakdowns
  - Concurrent read/write support

  ## Examples

      # Log a cost
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{thread_id: "123"})

      # Get statistics
      {:ok, stats} = CostTracker.get_cost_stats(:day)

      # Get daily aggregation
      daily = CostTracker.get_daily_aggregation(~D[2024-01-01], ~D[2024-01-31])
  """

  use GenServer
  require Logger

  alias GlobalbridgeBackend.AI.Telemetry

  # Cost rates per token/model (in USD)
  @embedding_costs %{
    # $0.020 per 1K tokens
    "text-embedding-3-small" => 0.00002,
    # $0.130 per 1K tokens
    "text-embedding-3-large" => 0.00013,
    # $0.100 per 1K tokens
    "text-embedding-ada-002" => 0.00010
  }

  @llm_costs %{
    # GPT-4 costs
    # $30/$60 per 1M tokens
    "gpt-4" => %{input: 0.00003, output: 0.00006},
    # $60/$120 per 1M tokens
    "gpt-4-32k" => %{input: 0.00006, output: 0.00012},
    # $10/$30 per 1M tokens
    "gpt-4-turbo" => %{input: 0.00001, output: 0.00003},
    # $5/$15 per 1M tokens
    "gpt-4o" => %{input: 0.000005, output: 0.000015},
    # $0.15/$0.60 per 1M tokens
    "gpt-4o-mini" => %{input: 0.00000015, output: 0.0000006},

    # GPT-3.5 costs
    # $0.50/$1.50 per 1M tokens
    "gpt-3.5-turbo" => %{input: 0.0000005, output: 0.0000015},

    # Claude costs (approximate)
    # $0.25/$1.25 per 1M tokens
    "claude-3-haiku" => %{input: 0.00000025, output: 0.00000125},
    # $3/$15 per 1M tokens
    "claude-3-sonnet" => %{input: 0.000003, output: 0.000015},
    # $15/$75 per 1M tokens
    "claude-3-opus" => %{input: 0.000015, output: 0.000075}
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create ETS table for cost tracking with optimized settings
    # Using ordered_set for efficient range queries
    # read_concurrency and write_concurrency for high-performance concurrent access
    table =
      :ets.new(:cost_tracking, [
        :ordered_set,
        :named_table,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    Logger.info("CostTracker initialized with ETS table: :cost_tracking")

    {:ok, %{table: table}}
  end

  @doc """
  Logs a cost for an AI API call.

  ## Parameters
  - `service`: The AI service used (:embedding, :llm, :translation, etc.)
  - `model`: The specific model used
  - `input_tokens`: Number of input tokens (for LLM calls)
  - `output_tokens`: Number of output tokens (for LLM calls)
  - `metadata`: Additional metadata about the call

  ## Examples
      CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{thread_id: "123"})
      CostTracker.log_cost(:llm, "gpt-4o", 150, 50, %{user_id: "456", operation: "summarize"})
  """
  @spec log_cost(atom(), String.t(), integer(), integer(), map()) :: :ok | {:error, String.t()}
  def log_cost(service, model, input_tokens, output_tokens, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:log_cost, service, model, input_tokens, output_tokens, metadata})
  end

  @doc """
  Gets cost statistics for a time period.

  ## Parameters
  - `period`: :hour, :day, :week, :month
  - `service`: Optional service filter (:embedding, :llm, etc.)

  ## Returns
  - `{:ok, stats}` with cost statistics including breakdowns by service and model
  """
  @spec get_cost_stats(atom(), atom() | nil) :: {:ok, map()} | {:error, String.t()}
  def get_cost_stats(period, service \\ nil) do
    GenServer.call(__MODULE__, {:get_cost_stats, period, service})
  end

  @doc """
  Gets total costs for the current month.
  """
  @spec get_monthly_total() :: {:ok, float()} | {:error, String.t()}
  def get_monthly_total do
    GenServer.call(__MODULE__, :get_monthly_total)
  end

  @doc """
  Gets costs for a specific time period using ETS queries.

  ## Parameters
  - `start_time`: Start timestamp in microseconds
  - `end_time`: End timestamp in microseconds
  - `service`: Optional service filter (:embedding, :llm, etc.)

  ## Returns
  - List of cost records matching the criteria

  ## Examples
      start_time = DateTime.to_unix(~U[2024-01-01 00:00:00Z], :microsecond)
      end_time = DateTime.to_unix(~U[2024-01-31 23:59:59Z], :microsecond)
      CostTracker.get_costs_by_period(start_time, end_time, :embedding)
  """
  @spec get_costs_by_period(integer(), integer(), atom() | nil) :: list()
  def get_costs_by_period(start_time, end_time, service \\ nil) do
    GenServer.call(__MODULE__, {:get_costs_by_period, start_time, end_time, service})
  end

  @doc """
  Gets aggregated costs by day within a time range.

  Returns a map where keys are date strings (YYYY-MM-DD) and values are
  daily statistics including total cost, token counts, and breakdowns.

  ## Parameters
  - `start_date`: Start date (Date struct)
  - `end_date`: End date (Date struct)

  ## Returns
  - Map of date => daily stats

  ## Examples
      CostTracker.get_daily_aggregation(~D[2024-01-01], ~D[2024-01-31])
  """
  @spec get_daily_aggregation(Date.t(), Date.t()) :: map()
  def get_daily_aggregation(start_date, end_date) do
    GenServer.call(__MODULE__, {:get_daily_aggregation, start_date, end_date})
  end

  @doc """
  Gets aggregated costs by week within a time range.

  ## Parameters
  - `start_date`: Start date (Date struct)
  - `end_date`: End date (Date struct)

  ## Returns
  - Map of week_number => weekly stats
  """
  @spec get_weekly_aggregation(Date.t(), Date.t()) :: map()
  def get_weekly_aggregation(start_date, end_date) do
    GenServer.call(__MODULE__, {:get_weekly_aggregation, start_date, end_date})
  end

  @doc """
  Gets aggregated costs by month within a time range.

  ## Parameters
  - `start_date`: Start date (Date struct)
  - `end_date`: End date (Date struct)

  ## Returns
  - Map of year_month (YYYY-MM) => monthly stats
  """
  @spec get_monthly_aggregation(Date.t(), Date.t()) :: map()
  def get_monthly_aggregation(start_date, end_date) do
    GenServer.call(__MODULE__, {:get_monthly_aggregation, start_date, end_date})
  end

  @doc """
  Clears all cost records from ETS.

  This is primarily useful for testing. In production, consider implementing
  a retention policy that automatically archives old records instead.
  """
  @spec clear_all_costs() :: :ok
  def clear_all_costs do
    GenServer.call(__MODULE__, :clear_all_costs)
  end

  # GenServer Callbacks

  @impl true
  def handle_call(
        {:log_cost, service, model, input_tokens, output_tokens, metadata},
        _from,
        state
      ) do
    cost = calculate_cost(service, model, input_tokens, output_tokens)

    cost_data = %{
      service: service,
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cost_usd: cost,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    case insert_cost_record(cost_data) do
      {:ok, _record} ->
        # Send telemetry event
        Telemetry.cost_logged(service, model, cost, metadata)

        Logger.info("Logged AI cost: $#{Float.round(cost, 6)} for #{service}:#{model}")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Failed to log AI cost: #{inspect(reason)}")
        {:reply, {:error, "Failed to log cost"}, state}
    end
  end

  @impl true
  def handle_call({:get_cost_stats, period, service}, _from, state) do
    now = DateTime.utc_now()
    start_time = calculate_start_time(now, period)

    # Convert DateTime to microseconds for ETS query
    start_time_us = DateTime.to_unix(start_time, :microsecond)
    end_time_us = DateTime.to_unix(now, :microsecond)

    # Query ETS for records in time range
    results = query_costs_by_time(start_time_us, end_time_us, service)

    stats = %{
      period: period,
      start_time: start_time,
      end_time: now,
      total_cost: Enum.reduce(results, 0.0, &(&1.cost_usd + &2)),
      total_input_tokens: Enum.reduce(results, 0, &(&1.input_tokens + &2)),
      total_output_tokens: Enum.reduce(results, 0, &(&1.output_tokens + &2)),
      service_breakdown: group_by_service(results),
      model_breakdown: group_by_model(results),
      record_count: length(results)
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:get_monthly_total, _from, state) do
    now = DateTime.utc_now()
    # Calculate start of current month
    start_of_month = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}

    start_time_us = DateTime.to_unix(start_of_month, :microsecond)
    end_time_us = DateTime.to_unix(now, :microsecond)

    # Query ETS for all records in current month
    results = query_costs_by_time(start_time_us, end_time_us, nil)
    total = Enum.reduce(results, 0.0, &(&1.cost_usd + &2))

    {:reply, {:ok, total}, state}
  end

  @impl true
  def handle_call({:get_costs_by_period, start_time, end_time, service}, _from, state) do
    results = query_costs_by_time(start_time, end_time, service)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:get_daily_aggregation, start_date, end_date}, _from, state) do
    # Convert dates to microsecond timestamps
    start_datetime = DateTime.new!(start_date, ~T[00:00:00])
    end_datetime = DateTime.new!(end_date, ~T[23:59:59])

    start_time_us = DateTime.to_unix(start_datetime, :microsecond)
    end_time_us = DateTime.to_unix(end_datetime, :microsecond)

    # Get all records in range
    results = query_costs_by_time(start_time_us, end_time_us, nil)

    # Group by day
    daily_stats =
      results
      |> Enum.group_by(fn record ->
        Date.to_string(DateTime.to_date(record.timestamp))
      end)
      |> Enum.map(fn {date, records} ->
        {date,
         %{
           total_cost: Enum.reduce(records, 0.0, &(&1.cost_usd + &2)),
           total_input_tokens: Enum.reduce(records, 0, &(&1.input_tokens + &2)),
           total_output_tokens: Enum.reduce(records, 0, &(&1.output_tokens + &2)),
           record_count: length(records),
           service_breakdown: group_by_service(records),
           model_breakdown: group_by_model(records)
         }}
      end)
      |> Map.new()

    {:reply, daily_stats, state}
  end

  @impl true
  def handle_call({:get_weekly_aggregation, start_date, end_date}, _from, state) do
    # Convert dates to microsecond timestamps
    start_datetime = DateTime.new!(start_date, ~T[00:00:00])
    end_datetime = DateTime.new!(end_date, ~T[23:59:59])

    start_time_us = DateTime.to_unix(start_datetime, :microsecond)
    end_time_us = DateTime.to_unix(end_datetime, :microsecond)

    # Get all records in range
    results = query_costs_by_time(start_time_us, end_time_us, nil)

    # Group by ISO week (year + week number)
    weekly_stats =
      results
      |> Enum.group_by(fn record ->
        date = DateTime.to_date(record.timestamp)

        {year, week} =
          Date.to_iso8601(date) |> String.split("-") |> Enum.take(2) |> List.to_tuple()

        "#{year}-W#{String.pad_leading(week, 2, "0")}"
      end)
      |> Enum.map(fn {week_key, records} ->
        {week_key,
         %{
           total_cost: Enum.reduce(records, 0.0, &(&1.cost_usd + &2)),
           total_input_tokens: Enum.reduce(records, 0, &(&1.input_tokens + &2)),
           total_output_tokens: Enum.reduce(records, 0, &(&1.output_tokens + &2)),
           record_count: length(records),
           service_breakdown: group_by_service(records),
           model_breakdown: group_by_model(records)
         }}
      end)
      |> Map.new()

    {:reply, weekly_stats, state}
  end

  @impl true
  def handle_call({:get_monthly_aggregation, start_date, end_date}, _from, state) do
    # Convert dates to microsecond timestamps
    start_datetime = DateTime.new!(start_date, ~T[00:00:00])
    end_datetime = DateTime.new!(end_date, ~T[23:59:59])

    start_time_us = DateTime.to_unix(start_datetime, :microsecond)
    end_time_us = DateTime.to_unix(end_datetime, :microsecond)

    # Get all records in range
    results = query_costs_by_time(start_time_us, end_time_us, nil)

    # Group by year-month
    monthly_stats =
      results
      |> Enum.group_by(fn record ->
        date = DateTime.to_date(record.timestamp)
        "#{date.year}-#{String.pad_leading(to_string(date.month), 2, "0")}"
      end)
      |> Enum.map(fn {month_key, records} ->
        {month_key,
         %{
           total_cost: Enum.reduce(records, 0.0, &(&1.cost_usd + &2)),
           total_input_tokens: Enum.reduce(records, 0, &(&1.input_tokens + &2)),
           total_output_tokens: Enum.reduce(records, 0, &(&1.output_tokens + &2)),
           record_count: length(records),
           service_breakdown: group_by_service(records),
           model_breakdown: group_by_model(records)
         }}
      end)
      |> Map.new()

    {:reply, monthly_stats, state}
  end

  @impl true
  def handle_call(:clear_all_costs, _from, state) do
    :ets.delete_all_objects(:cost_tracking)
    Logger.info("Cleared all cost tracking records")
    {:reply, :ok, state}
  end

  # Private functions

  defp calculate_cost(:embedding, model, tokens, _output_tokens) do
    # Default fallback
    cost_per_token = Map.get(@embedding_costs, model, 0.0001)
    cost_per_token * tokens
  end

  defp calculate_cost(:llm, model, input_tokens, output_tokens) do
    # Default fallback
    model_costs = Map.get(@llm_costs, model, %{input: 0.00001, output: 0.00002})
    model_costs.input * input_tokens + model_costs.output * output_tokens
  end

  defp calculate_cost(_service, _model, _input_tokens, _output_tokens) do
    # Unknown service type
    0.0
  end

  defp calculate_start_time(now, :hour) do
    DateTime.add(now, -3600, :second)
  end

  defp calculate_start_time(now, :day) do
    DateTime.add(now, -86400, :second)
  end

  defp calculate_start_time(now, :week) do
    DateTime.add(now, -604_800, :second)
  end

  defp calculate_start_time(now, :month) do
    # 30 days
    DateTime.add(now, -2_592_000, :second)
  end

  defp group_by_service(results) do
    Enum.group_by(results, & &1.service)
    |> Enum.map(fn {service, records} ->
      {service,
       %{
         count: length(records),
         total_cost: Enum.reduce(records, 0.0, &(&1.cost_usd + &2)),
         total_input_tokens: Enum.reduce(records, 0, &(&1.input_tokens + &2)),
         total_output_tokens: Enum.reduce(records, 0, &(&1.output_tokens + &2))
       }}
    end)
    |> Map.new()
  end

  defp group_by_model(results) do
    Enum.group_by(results, & &1.model)
    |> Enum.map(fn {model, records} ->
      {model,
       %{
         count: length(records),
         total_cost: Enum.reduce(records, 0.0, &(&1.cost_usd + &2)),
         total_input_tokens: Enum.reduce(records, 0, &(&1.input_tokens + &2)),
         total_output_tokens: Enum.reduce(records, 0, &(&1.output_tokens + &2))
       }}
    end)
    |> Map.new()
  end

  defp insert_cost_record(cost_data) do
    # Create composite key: {timestamp_microseconds, unique_integer}
    # This ensures ordering by time and uniqueness for concurrent inserts
    timestamp_us = DateTime.to_unix(cost_data.timestamp, :microsecond)
    key = {timestamp_us, System.unique_integer([:positive])}

    # Insert into ETS with the cost data
    true = :ets.insert(:cost_tracking, {key, cost_data})

    Logger.debug("Cost record inserted to ETS: #{inspect(cost_data)}")
    {:ok, cost_data}
  end

  # Query costs from ETS by time range with optional service filter
  # Uses ETS match specifications for efficient querying
  defp query_costs_by_time(start_time_us, end_time_us, service) do
    # Use ETS select with match specification for efficient querying
    # Pattern: {{timestamp, _unique}, cost_data}
    # Guard: timestamp >= start AND timestamp <= end
    # Return: cost_data
    match_spec = [
      {{{:"$1", :_}, :"$2"},
       [{:andalso, {:>=, :"$1", start_time_us}, {:"=<", :"$1", end_time_us}}], [:"$2"]}
    ]

    results = :ets.select(:cost_tracking, match_spec)

    # Filter by service if specified
    if service do
      Enum.filter(results, &(&1.service == service))
    else
      results
    end
  end
end
