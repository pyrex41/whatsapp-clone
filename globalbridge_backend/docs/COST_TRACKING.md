# Cost Tracking Documentation

## Overview

The Cost Tracking system provides ETS-based persistence for monitoring and analyzing AI API costs in production. It tracks costs for embedding models, LLM calls, and other AI services with < 25ms query performance.

## Features

- **ETS-Based Persistence**: In-memory storage with ordered sets for efficient range queries
- **Real-Time Tracking**: Log costs immediately as API calls are made
- **Aggregation Support**: Query costs by hour, day, week, or month
- **Service Filtering**: Filter costs by service type (embedding, llm, etc.)
- **Concurrent Access**: Optimized for high-concurrency scenarios with read/write concurrency
- **Performance**: < 25ms for stats queries on 10k+ records
- **Breakdowns**: Automatic grouping by service and model

## Architecture

### Data Storage

The cost tracker uses ETS (Erlang Term Storage) with the following configuration:

```elixir
:ets.new(:cost_tracking, [
  :ordered_set,          # Maintains ordered insertion for efficient range queries
  :named_table,          # Named table for direct access
  :public,               # Allows read from any process
  read_concurrency: true,  # Optimizes concurrent reads
  write_concurrency: true  # Optimizes concurrent writes
])
```

### Data Structure

Each cost record is stored with a composite key:

```elixir
# Key: {timestamp_microseconds, unique_integer}
# Value: cost_data map
{
  {1634567890123456, 789},  # Composite key for uniqueness and ordering
  %{
    service: :embedding,
    model: "text-embedding-3-small",
    input_tokens: 100,
    output_tokens: 0,
    cost_usd: 0.002,
    metadata: %{thread_id: "123"},
    timestamp: ~U[2024-10-24 12:34:50.123456Z]
  }
}
```

## API Reference

### Logging Costs

```elixir
# Log an embedding cost
CostTracker.log_cost(:embedding, "text-embedding-3-small", 100, 0, %{thread_id: "123"})

# Log an LLM cost
CostTracker.log_cost(:llm, "gpt-4o", 150, 50, %{
  user_id: "456",
  operation: "summarize"
})
```

### Querying Statistics

```elixir
# Get stats for the current hour
{:ok, stats} = CostTracker.get_cost_stats(:hour)

# Get stats for the current day, filtered by service
{:ok, embedding_stats} = CostTracker.get_cost_stats(:day, :embedding)

# Stats structure:
%{
  period: :hour,
  start_time: ~U[2024-10-24 08:00:00Z],
  end_time: ~U[2024-10-24 09:00:00Z],
  total_cost: 12.34,
  total_input_tokens: 50000,
  total_output_tokens: 25000,
  record_count: 150,
  service_breakdown: %{
    embedding: %{
      count: 100,
      total_cost: 2.50,
      total_input_tokens: 25000,
      total_output_tokens: 0
    },
    llm: %{
      count: 50,
      total_cost: 9.84,
      total_input_tokens: 25000,
      total_output_tokens: 25000
    }
  },
  model_breakdown: %{
    "text-embedding-3-small" => %{count: 100, total_cost: 2.50, ...},
    "gpt-4o" => %{count: 50, total_cost: 9.84, ...}
  }
}
```

### Time Period Queries

```elixir
# Get costs by specific time range (microsecond timestamps)
start_time = DateTime.to_unix(~U[2024-01-01 00:00:00Z], :microsecond)
end_time = DateTime.to_unix(~U[2024-01-31 23:59:59Z], :microsecond)
records = CostTracker.get_costs_by_period(start_time, end_time, :embedding)
```

### Aggregations

```elixir
# Daily aggregation
daily_stats = CostTracker.get_daily_aggregation(~D[2024-01-01], ~D[2024-01-31])
# Returns: %{
#   "2024-01-01" => %{total_cost: 5.67, total_input_tokens: 10000, ...},
#   "2024-01-02" => %{total_cost: 6.78, total_input_tokens: 12000, ...},
#   ...
# }

# Weekly aggregation
weekly_stats = CostTracker.get_weekly_aggregation(~D[2024-01-01], ~D[2024-12-31])
# Returns: %{
#   "2024-W01" => %{total_cost: 45.67, ...},
#   "2024-W02" => %{total_cost: 52.34, ...},
#   ...
# }

# Monthly aggregation
monthly_stats = CostTracker.get_monthly_aggregation(~D[2024-01-01], ~D[2024-12-31])
# Returns: %{
#   "2024-01" => %{total_cost: 234.56, ...},
#   "2024-02" => %{total_cost: 267.89, ...},
#   ...
# }
```

### Monthly Total

```elixir
# Get total costs for current month
{:ok, total} = CostTracker.get_monthly_total()
```

### Clear Costs (Testing)

```elixir
# Clear all cost records (use only in testing)
:ok = CostTracker.clear_all_costs()
```

## Cost Rates

### Embedding Models

| Model | Cost per 1K tokens |
|-------|-------------------|
| text-embedding-3-small | $0.020 |
| text-embedding-3-large | $0.130 |
| text-embedding-ada-002 | $0.100 |

### LLM Models

| Model | Input per 1M tokens | Output per 1M tokens |
|-------|-------------------|---------------------|
| gpt-4 | $30.00 | $60.00 |
| gpt-4-32k | $60.00 | $120.00 |
| gpt-4-turbo | $10.00 | $30.00 |
| gpt-4o | $5.00 | $15.00 |
| gpt-4o-mini | $0.15 | $0.60 |
| gpt-3.5-turbo | $0.50 | $1.50 |
| claude-3-haiku | $0.25 | $1.25 |
| claude-3-sonnet | $3.00 | $15.00 |
| claude-3-opus | $15.00 | $75.00 |

## Performance Characteristics

### Query Performance

Based on performance testing:

- **10k records**: ~23ms for `get_cost_stats`
- **5k records**: ~31ms for daily aggregation
- **1k concurrent writes + 100 reads**: All succeed without errors

### Optimization Features

1. **Ordered Set**: ETS ordered_set provides O(log n) lookups and efficient range queries
2. **Read Concurrency**: Multiple processes can read simultaneously without locks
3. **Write Concurrency**: Optimized for concurrent insertions
4. **Composite Keys**: `{timestamp, unique_integer}` ensures uniqueness and ordering
5. **Match Specifications**: Efficient ETS queries with minimal data copying

### Memory Considerations

Each cost record uses approximately 200-300 bytes of memory. For 10,000 records:
- Memory usage: ~2-3 MB
- Query time: ~23ms

For production systems with millions of records, consider implementing:
- Periodic archival to database
- Retention policies (e.g., keep last 30 days in ETS)
- Background aggregation jobs

## Integration Examples

### In Controllers

```elixir
defmodule MyApp.AIController do
  alias GlobalbridgeBackend.AI.CostTracker

  def generate_embedding(conn, %{"text" => text}) do
    # Call OpenAI API
    {:ok, response} = OpenAI.embeddings(text, model: "text-embedding-3-small")

    # Log cost
    token_count = count_tokens(text)
    CostTracker.log_cost(:embedding, "text-embedding-3-small", token_count, 0, %{
      user_id: conn.assigns.current_user.id,
      endpoint: "generate_embedding"
    })

    json(conn, %{embedding: response.embedding})
  end
end
```

### In Background Jobs

```elixir
defmodule MyApp.EmbeddingJob do
  use Oban.Worker
  alias GlobalbridgeBackend.AI.CostTracker

  @impl Oban.Worker
  def perform(%{args: %{"message_id" => message_id}}) do
    message = Messages.get_message!(message_id)

    # Generate embedding
    {:ok, response} = OpenAI.embeddings(message.content,
      model: "text-embedding-3-small"
    )

    # Log cost
    CostTracker.log_cost(:embedding, "text-embedding-3-small",
      response.usage.total_tokens, 0, %{
        message_id: message_id,
        job: "EmbeddingJob"
      }
    )

    :ok
  end
end
```

### Monitoring Dashboard

```elixir
defmodule MyAppWeb.CostDashboardLive do
  use Phoenix.LiveView
  alias GlobalbridgeBackend.AI.CostTracker

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(5000, self(), :update_stats)
    end

    {:ok, assign(socket, :stats, load_stats())}
  end

  def handle_info(:update_stats, socket) do
    {:noreply, assign(socket, :stats, load_stats())}
  end

  defp load_stats do
    {:ok, today} = CostTracker.get_cost_stats(:day)
    {:ok, week} = CostTracker.get_cost_stats(:week)
    {:ok, month_total} = CostTracker.get_monthly_total()

    %{
      today: today,
      week: week,
      month_total: month_total
    }
  end
end
```

## Testing

The cost tracker includes comprehensive tests covering:

- ETS table initialization
- Cost logging with persistence
- Query operations with filtering
- Aggregations (daily, weekly, monthly)
- Concurrent operations
- Performance benchmarks
- Edge cases and error handling

Run tests:

```bash
# All tests except performance
mix test test/globalbridge_backend/ai/cost_tracker_test.exs --exclude performance

# Performance tests only
mix test test/globalbridge_backend/ai/cost_tracker_test.exs --only performance

# All tests
mix test test/globalbridge_backend/ai/cost_tracker_test.exs
```

## Production Considerations

### 1. Data Retention

Implement a retention policy to prevent unbounded memory growth:

```elixir
# Example: Archive old records to database
defmodule MyApp.CostArchiver do
  use GenServer

  def init(_) do
    # Archive every hour
    :timer.send_interval(:timer.hours(1), :archive)
    {:ok, %{}}
  end

  def handle_info(:archive, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)
    cutoff_us = DateTime.to_unix(cutoff, :microsecond)

    # Archive to database, then clear from ETS
    archive_and_clear(cutoff_us)

    {:noreply, state}
  end
end
```

### 2. Monitoring

Set up alerts for cost thresholds:

```elixir
# Check hourly costs
{:ok, stats} = CostTracker.get_cost_stats(:hour)

if stats.total_cost > 100.0 do
  Logger.warning("High hourly cost: $#{stats.total_cost}")
  # Send alert
end
```

### 3. Budget Limits

Integrate with BudgetMonitor for automatic enforcement:

```elixir
# BudgetMonitor already uses CostTracker for cost data
# See lib/globalbridge_backend/ai/budget_monitor.ex
```

## Troubleshooting

### ETS Table Not Found

If you see `:undefined` when checking `:ets.info(:cost_tracking)`:

1. Ensure CostTracker is started in Application supervisor
2. Check logs for startup errors
3. Verify GenServer is running: `Process.whereis(GlobalbridgeBackend.AI.CostTracker)`

### Memory Usage Growing

If memory usage is too high:

1. Implement retention policy (see above)
2. Archive old records to database
3. Clear ETS periodically (with backup)

### Performance Degradation

If queries become slow:

1. Check ETS table size: `:ets.info(:cost_tracking)[:size]`
2. Implement archival for old data
3. Consider sharding by time period
4. Use more specific time ranges in queries

## Related Documentation

- [Budget Monitoring](./BUDGET_MONITORING.md)
- [AI Backend Architecture](./AI_BACKEND.md)
- [SQLite Vector Setup](./SQLITE_VEC_SETUP.md)
