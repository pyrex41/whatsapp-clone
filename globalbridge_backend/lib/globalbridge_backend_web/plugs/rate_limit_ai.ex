defmodule GlobalbridgeBackendWeb.Plugs.RateLimitAI do
  @moduledoc """
  Per-user rate limiting plug for AI endpoints to prevent cost explosion and DoS attacks.

  Each endpoint has different limits based on cost:
  - translate: 60/min (low cost, high volume)
  - analyze_tone: 30/min (medium cost, medium volume)
  - summarize_thread: 10/min (high cost, low volume)
  - search_semantic: 30/min (medium cost, medium volume)
  - extract_tasks: 10/min (high cost, low volume)

  Configuration is via environment variables:
  - AI_RATE_LIMIT_TRANSLATE (default: 60)
  - AI_RATE_LIMIT_ANALYZE_TONE (default: 30)
  - AI_RATE_LIMIT_SUMMARIZE_THREAD (default: 10)
  - AI_RATE_LIMIT_SEARCH_SEMANTIC (default: 30)
  - AI_RATE_LIMIT_EXTRACT_TASKS (default: 10)
  """

  import Plug.Conn
  require Logger

  @default_limits %{
    "translate" => 60,
    "analyze_tone" => 30,
    "summarize_thread" => 10,
    "search_semantic" => 30,
    "extract_tasks" => 10,
    "vec_health" => 60
  }

  @time_window_ms 60_000

  def init(opts), do: opts

  def call(conn, _opts) do
    # Get current user from conn.assigns (set by auth pipeline)
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Authentication required"})
        |> halt()

      user ->
        rate_limit_user(conn, user)
    end
  end

  defp rate_limit_user(conn, user) do
    endpoint = get_endpoint_name(conn)
    limit = get_rate_limit(endpoint)
    user_id = user.id

    # Create per-user per-endpoint rate limit key
    rate_key = "ai:#{endpoint}:user:#{user_id}"

    case Hammer.check_rate(rate_key, @time_window_ms, limit) do
      {:allow, count} ->
        # Add rate limit headers for transparency
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(limit - count))
        |> put_resp_header("x-ratelimit-reset", to_string(get_reset_time()))

      {:deny, retry_after_ms} ->
        # Calculate retry-after in seconds
        retry_after_seconds = div(retry_after_ms, 1000)

        # Log rate limit hit for monitoring
        log_rate_limit_hit(user_id, endpoint, limit)

        # Emit telemetry event for alerting
        emit_rate_limit_telemetry(user_id, endpoint)

        conn
        |> put_status(429)
        |> put_resp_header("retry-after", to_string(retry_after_seconds))
        |> put_resp_header("x-ratelimit-limit", to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("x-ratelimit-reset", to_string(get_reset_time()))
        |> Phoenix.Controller.json(%{
          error: "Rate limit exceeded",
          message: "Too many requests to #{endpoint} endpoint",
          retry_after_seconds: retry_after_seconds,
          limit: limit,
          window: "60 seconds"
        })
        |> halt()
    end
  end

  defp get_endpoint_name(conn) do
    # Extract endpoint name from path
    # e.g., /api/v1/ai/translate -> "translate"
    case conn.path_info do
      [_, _, "ai", endpoint | _] -> endpoint
      [_, "ai", endpoint | _] -> endpoint
      _ -> "unknown"
    end
  end

  defp get_rate_limit(endpoint) do
    # Try to get from config first, then environment, then defaults
    config_limit = Application.get_env(:globalbridge_backend, :ai_rate_limits, %{})[endpoint]
    env_limit = get_env_limit(endpoint)
    default_limit = @default_limits[endpoint]

    config_limit || env_limit || default_limit || 10
  end

  defp get_env_limit(endpoint) do
    env_var = "AI_RATE_LIMIT_#{String.upcase(endpoint)}"

    case System.get_env(env_var) do
      nil -> nil
      value -> String.to_integer(value)
    end
  rescue
    ArgumentError -> nil
  end

  defp get_reset_time do
    # Return Unix timestamp for when the current window resets
    System.system_time(:second) + 60
  end

  defp log_rate_limit_hit(user_id, endpoint, limit) do
    Logger.warning(
      "AI rate limit exceeded",
      user_id: user_id,
      endpoint: endpoint,
      limit: limit,
      window: "60s"
    )
  end

  defp emit_rate_limit_telemetry(user_id, endpoint) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :rate_limit, :exceeded],
      %{count: 1},
      %{
        user_id: user_id,
        endpoint: endpoint,
        timestamp: System.system_time(:millisecond)
      }
    )
  end
end
