defmodule GlobalbridgeBackend.AI.CostTracker do
  @moduledoc """
  Tracks API costs for AI services.

  This module provides functionality to log costs for various AI API calls,
  calculate usage statistics, and provide cost reporting capabilities.
  """

  use GenServer
  require Logger

  alias GlobalbridgeBackend.AI.Telemetry

  # Note: AICost schema would need to be created for full functionality
  # For now, we'll use in-memory tracking with ETS or similar

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
    {:ok, %{}}
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
  - `{:ok, stats}` with cost statistics
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
    # For now, return mock statistics since we don't have database persistence
    now = DateTime.utc_now()
    start_time = calculate_start_time(now, period)

    # Mock data - in production this would query the database
    mock_results = [
      %{
        service: :embedding,
        model: "text-embedding-3-small",
        cost_usd: 0.001,
        input_tokens: 100,
        output_tokens: 0
      },
      %{service: :llm, model: "gpt-4o", cost_usd: 0.01, input_tokens: 200, output_tokens: 100}
    ]

    # Filter by service if specified
    results =
      if service, do: Enum.filter(mock_results, &(&1.service == service)), else: mock_results

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
  def handle_call({:get_cost_stats, period, service}, _from, state) do
    # For now, return mock statistics since we don't have database persistence
    now = DateTime.utc_now()
    start_time = calculate_start_time(now, period)

    # Mock data - in production this would query the database
    mock_results = [
      %{
        service: :embedding,
        model: "text-embedding-3-small",
        cost_usd: 0.001,
        input_tokens: 100,
        output_tokens: 0
      },
      %{service: :llm, model: "gpt-4o", cost_usd: 0.01, input_tokens: 200, output_tokens: 100}
    ]

    # Filter by service if specified
    results =
      if service, do: Enum.filter(mock_results, &(&1.service == service)), else: mock_results

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
    # Mock monthly total - in production this would query the database
    {:reply, {:ok, 12.34}, state}
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
    # For now, we'll just log to console since we don't have the AICost schema
    # In a real implementation, this would insert into the database
    Logger.debug("Cost record: #{inspect(cost_data)}")
    {:ok, cost_data}
  end
end
