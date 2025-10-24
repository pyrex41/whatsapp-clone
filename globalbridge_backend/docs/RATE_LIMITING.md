# AI Endpoint Rate Limiting

## Overview

Per-user rate limiting has been implemented to prevent cost explosion and DoS attacks on AI endpoints. Each endpoint has different limits based on cost and resource consumption.

## Rate Limits

Default limits per user per minute:

| Endpoint | Limit/min | Cost Level | Reason |
|----------|-----------|------------|--------|
| `/translate` | 60 | Low | High volume, low cost |
| `/analyze_tone` | 30 | Medium | Medium volume, medium cost |
| `/summarize_thread` | 10 | High | Low volume, high cost (RAG + LLM) |
| `/search_semantic` | 30 | Medium | Medium volume, vector search |
| `/extract_tasks` | 10 | High | Low volume, high cost (RAG + LLM) |
| `/vec_health` | 60 | Low | Diagnostic endpoint |

## Configuration

### Environment Variables

Override default limits using environment variables:

```bash
# Rate limits (requests per minute per user)
export AI_RATE_LIMIT_TRANSLATE=60
export AI_RATE_LIMIT_ANALYZE_TONE=30
export AI_RATE_LIMIT_SUMMARIZE_THREAD=10
export AI_RATE_LIMIT_SEARCH_SEMANTIC=30
export AI_RATE_LIMIT_EXTRACT_TASKS=10
export AI_RATE_LIMIT_VEC_HEALTH=60

# Monitoring alert thresholds
export RATE_LIMIT_ALERT_THRESHOLD=10        # Number of rate limit hits before alerting
export RATE_LIMIT_ALERT_WINDOW_MS=3600000   # Window in ms (default: 1 hour)
```

### Application Config

Limits can also be configured in `config/config.exs`:

```elixir
config :globalbridge_backend, :ai_rate_limits,
  translate: 60,
  analyze_tone: 30,
  summarize_thread: 10,
  search_semantic: 30,
  extract_tasks: 10,
  vec_health: 60
```

Priority order: Environment Variable > Application Config > Hardcoded Defaults

## Response Headers

All AI endpoint responses include rate limit headers:

```
X-RateLimit-Limit: 60          # Total limit for the window
X-RateLimit-Remaining: 45      # Requests remaining
X-RateLimit-Reset: 1234567890  # Unix timestamp when limit resets
```

## Rate Limit Exceeded Response

When rate limited, the API returns HTTP 429 with:

```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests to translate endpoint",
  "retry_after_seconds": 42,
  "limit": 60,
  "window": "60 seconds"
}
```

Headers:
```
HTTP/1.1 429 Too Many Requests
Retry-After: 42
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1234567890
```

## Monitoring & Alerting

### Telemetry Events

Rate limiting emits two telemetry events:

#### 1. Rate Limit Exceeded
```elixir
[:globalbridge_backend, :ai, :rate_limit, :exceeded]
```
Metadata:
- `user_id` - UUID of the user
- `endpoint` - Name of the endpoint
- `timestamp` - Event timestamp

#### 2. Rate Limit Alert
```elixir
[:globalbridge_backend, :ai, :rate_limit, :alert]
```
Triggered when a user exceeds `RATE_LIMIT_ALERT_THRESHOLD` hits within the alert window.

Metadata:
- `user_id` - UUID of the user
- `endpoint` - Name of the endpoint
- `threshold` - Alert threshold
- `severity` - `:low`, `:medium`, `:high`, or `:critical`

### Rate Limit Monitor

The `RateLimitMonitor` GenServer tracks rate limit events and provides:

```elixir
# Get current statistics
GlobalbridgeBackend.Monitoring.RateLimitMonitor.get_stats()
# Returns: %{user_id => %{endpoint => count}}

# Get users who exceeded alert thresholds
GlobalbridgeBackend.Monitoring.RateLimitMonitor.get_alerts()
# Returns: [%{user_id:, endpoint:, count:, threshold:, severity:}]

# Reset stats for a user/endpoint
GlobalbridgeBackend.Monitoring.RateLimitMonitor.reset_stats(user_id, endpoint)
```

### Log Output

Rate limit events are logged:

```
[warning] AI rate limit exceeded user_id=abc-123 endpoint=translate limit=60 window=60s
```

Alert threshold exceeded:
```
[warning] 🚨 AI Rate Limit Alert!
User: abc-123
Endpoint: translate
Hits: 15 (threshold: 10)
Window: 3600s
```

### Severity Levels

Alerts are categorized by severity based on how far over threshold:

- **Low**: 1-1.5x threshold
- **Medium**: 1.5-2x threshold
- **High**: 2-3x threshold
- **Critical**: 3x+ threshold

## Integration with Monitoring Systems

### Prometheus/Grafana

Telemetry events can be exported to Prometheus using `telemetry_metrics_prometheus`:

```elixir
# In your application
{TelemetryMetricsPrometheus,
  metrics: [
    counter("globalbridge_backend.ai.rate_limit.exceeded.count",
      tags: [:user_id, :endpoint]
    ),
    last_value("globalbridge_backend.ai.rate_limit.exceeded.timestamp",
      tags: [:user_id, :endpoint]
    )
  ]
}
```

### Custom Alerting

Attach to telemetry events in your application:

```elixir
:telemetry.attach(
  "my-alert-handler",
  [:globalbridge_backend, :ai, :rate_limit, :alert],
  fn _event, _measurements, metadata, _config ->
    if metadata.severity in [:high, :critical] do
      # Send to Slack, PagerDuty, etc.
      send_alert(metadata)
    end
  end,
  nil
)
```

## Testing

Comprehensive tests are available in `test/globalbridge_backend_web/plugs/rate_limit_ai_test.exs`.

Run tests:
```bash
mix test test/globalbridge_backend_web/plugs/rate_limit_ai_test.exs
```

Test coverage includes:
- Under limit: requests succeed
- At limit boundary: correct enforcement
- Over limit: returns 429 with headers
- Per-user isolation
- Per-endpoint isolation
- Concurrent request handling
- Environment variable configuration
- Telemetry event emission

## Architecture

### Rate Limiting Flow

```
Request → Auth Pipeline → AI Rate Limit Plug → Controller
                              ↓
                         Hammer.check_rate()
                              ↓
                     Allow/Deny Decision
                              ↓
                    (if denied) Return 429
                              ↓
                    Emit Telemetry Event
                              ↓
                    Rate Limit Monitor
                              ↓
                    Check Alert Threshold
                              ↓
                    (if exceeded) Alert
```

### Key Components

1. **RateLimitAI Plug** (`lib/globalbridge_backend_web/plugs/rate_limit_ai.ex`)
   - Per-user per-endpoint rate limiting
   - Uses Hammer library
   - Emits telemetry events
   - Returns 429 with proper headers

2. **RateLimitMonitor** (`lib/globalbridge_backend/monitoring/rate_limit_monitor.ex`)
   - Tracks rate limit events
   - Provides statistics and alerts
   - Uses ETS for efficient storage
   - Configurable alert thresholds

3. **Telemetry Integration** (`lib/globalbridge_backend_web/telemetry.ex`)
   - Exposes metrics for monitoring
   - Counter for rate limit hits
   - Last value for timestamps

### Rate Limit Keys

Format: `ai:{endpoint}:user:{user_id}`

Examples:
- `ai:translate:user:abc-123-def-456`
- `ai:summarize_thread:user:abc-123-def-456`

This ensures:
- Per-user isolation
- Per-endpoint isolation
- Efficient lookups in Hammer

## Performance Considerations

- **Hammer Backend**: Uses ETS (in-memory) for fast lookups
- **Concurrent Requests**: Hammer handles concurrency correctly
- **Memory Usage**: Minimal - only stores buckets per user/endpoint
- **Cleanup**: Hammer automatically cleans up expired buckets

## Security Considerations

- **DoS Prevention**: Rate limits prevent API abuse
- **Cost Control**: Prevents runaway AI costs
- **Authentication Required**: Rate limiting only applies to authenticated users
- **Per-User Fairness**: Users cannot affect each other's limits

## Future Enhancements

- [ ] Tier-based rate limits (free vs paid users)
- [ ] Dynamic rate limiting based on system load
- [ ] Rate limit bypass for admin users
- [ ] Historical rate limit analytics
- [ ] Integration with feature flags
- [ ] Temporary rate limit increases for specific users
- [ ] Rate limit webhooks for external systems

## Troubleshooting

### Rate limits too restrictive

Increase limits via environment variables or config:
```bash
export AI_RATE_LIMIT_TRANSLATE=120
```

### Rate limits not working

1. Check Hammer is configured: `config :hammer, backend: {...}`
2. Verify plug is in router pipeline
3. Check authentication is working (assigns current_user)
4. Review logs for errors

### False positive alerts

Increase alert threshold:
```bash
export RATE_LIMIT_ALERT_THRESHOLD=20
export RATE_LIMIT_ALERT_WINDOW_MS=7200000  # 2 hours
```

### Testing rate limits locally

Use a low limit for testing:
```elixir
# In config/dev.exs
config :globalbridge_backend, :ai_rate_limits,
  translate: 5  # Very low limit for testing
```

## References

- [Hammer Documentation](https://hexdocs.pm/hammer/)
- [Phoenix Plugs](https://hexdocs.pm/phoenix/plug.html)
- [Telemetry](https://hexdocs.pm/telemetry/)
