defmodule GlobalbridgeBackendWeb.HealthController do
  use GlobalbridgeBackendWeb, :controller

  require Logger

  @doc """
  Health check endpoint that returns the overall system health status.

  This endpoint performs various health checks including:
  - Database connectivity
  - Bridge registry status
  - AI service availability
  - System metrics

  Returns a JSON response with health status and details.
  """
  def index(conn, _params) do
    health_checks = [
      {:database, check_database()},
      {:bridges, check_bridges()},
      {:ai_services, check_ai_services()},
      {:system, check_system()}
    ]

    # Determine overall health status
    overall_status =
      if Enum.all?(health_checks, fn {_name, result} -> result.status == :healthy end) do
        :healthy
      else
        :degraded
      end

    # Log unhealthy components
    unhealthy_checks =
      Enum.filter(health_checks, fn {_name, result} -> result.status != :healthy end)

    if unhealthy_checks != [] do
      Logger.warning("Health check found unhealthy components: #{inspect(unhealthy_checks)}")
    end

    # Prepare response
    response = %{
      status: overall_status,
      timestamp: DateTime.utc_now(),
      version: Application.spec(:globalbridge_backend, :vsn) || "unknown",
      environment: Application.get_env(:globalbridge_backend, :env) || "unknown",
      checks:
        Enum.into(health_checks, %{}, fn {name, result} ->
          {name, Map.take(result, [:status, :details, :response_time_ms])}
        end)
    }

    status_code = if overall_status == :healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(response)
  end

  # Private health check functions

  defp check_database do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Simple database connectivity check
      case GlobalbridgeBackend.Repo.query("SELECT 1") do
        {:ok, _result} ->
          response_time = System.monotonic_time(:millisecond) - start_time

          %{
            status: :healthy,
            details: "Database connection successful",
            response_time_ms: response_time
          }

        {:error, error} ->
          response_time = System.monotonic_time(:millisecond) - start_time

          %{
            status: :unhealthy,
            details: "Database query failed: #{inspect(error)}",
            response_time_ms: response_time
          }
      end
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time

        %{
          status: :unhealthy,
          details: "Database check failed: #{inspect(error)}",
          response_time_ms: response_time
        }
    end
  end

  defp check_bridges do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Check if bridge registry is running
      case Process.whereis(GlobalbridgeBackend.Bridges.Registry) do
        nil ->
          response_time = System.monotonic_time(:millisecond) - start_time

          %{
            status: :unhealthy,
            details: "Bridge registry not running",
            response_time_ms: response_time
          }

        _pid ->
          # Check if bridge supervisor is running
          case Process.whereis(GlobalbridgeBackend.Bridges.Supervisor) do
            nil ->
              response_time = System.monotonic_time(:millisecond) - start_time

              %{
                status: :unhealthy,
                details: "Bridge supervisor not running",
                response_time_ms: response_time
              }

            _supervisor_pid ->
              response_time = System.monotonic_time(:millisecond) - start_time

              %{
                status: :healthy,
                details: "Bridge registry and supervisor running",
                response_time_ms: response_time
              }
          end
      end
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time

        %{
          status: :unhealthy,
          details: "Bridge check failed: #{inspect(error)}",
          response_time_ms: response_time
        }
    end
  end

  defp check_ai_services do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Check if AI cache is available
      case Cachex.exists?(:ai_cache) do
        {:ok, true} ->
          response_time = System.monotonic_time(:millisecond) - start_time
          %{status: :healthy, details: "AI cache available", response_time_ms: response_time}

        _ ->
          response_time = System.monotonic_time(:millisecond) - start_time
          %{status: :degraded, details: "AI cache not available", response_time_ms: response_time}
      end
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time

        %{
          status: :unhealthy,
          details: "AI services check failed: #{inspect(error)}",
          response_time_ms: response_time
        }
    end
  end

  defp check_system do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Basic system checks
      memory_info = :erlang.memory()
      process_count = :erlang.system_info(:process_count)

      # Check if memory usage is reasonable (< 80% of available)
      total_memory = memory_info[:total]
      used_memory = memory_info[:processes] + memory_info[:system]

      memory_usage_percent =
        if total_memory > 0 do
          used_memory / total_memory * 100
        else
          0
        end

      status =
        if memory_usage_percent < 80 and process_count < 10000 do
          :healthy
        else
          :degraded
        end

      response_time = System.monotonic_time(:millisecond) - start_time

      details =
        "Memory usage: #{Float.round(memory_usage_percent, 1)}%, Processes: #{process_count}"

      %{status: status, details: details, response_time_ms: response_time}
    rescue
      error ->
        response_time = System.monotonic_time(:millisecond) - start_time

        %{
          status: :unhealthy,
          details: "System check failed: #{inspect(error)}",
          response_time_ms: response_time
        }
    end
  end
end
