defmodule GlobalbridgeBackend.Bridges.Telemetry do
  @moduledoc """
  Telemetry and metrics for bridge operations.

  This module provides telemetry events and Prometheus metrics for monitoring
  bridge performance, message throughput, connection health, and operational metrics.
  """

  require Logger

  @doc """
  Attaches telemetry handlers for bridge metrics.

  Call this function during application startup to set up telemetry collection.
  """
  def setup do
    # Attach handlers for bridge events
    events = [
      [:globalbridge_backend, :bridge, :message, :received],
      [:globalbridge_backend, :bridge, :message, :sent],
      [:globalbridge_backend, :bridge, :message, :error],
      [:globalbridge_backend, :bridge, :connection, :established],
      [:globalbridge_backend, :bridge, :connection, :lost],
      [:globalbridge_backend, :bridge, :connection, :error],
      [:globalbridge_backend, :bridge, :webhook, :received],
      [:globalbridge_backend, :bridge, :webhook, :error],
      [:globalbridge_backend, :bridge, :health_check, :passed],
      [:globalbridge_backend, :bridge, :health_check, :failed],
      [:globalbridge_backend, :bridge, :rate_limit, :exceeded]
    ]

    :telemetry.attach_many(
      "bridge-metrics-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("Bridge telemetry handlers attached")
  end

  @doc """
  Records a message received from an external bridge.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `message_type`: Type of message (:text, :image, :file, etc.)
  - `size_bytes`: Size of the message in bytes
  - `metadata`: Additional metadata
  """
  def message_received(bridge_id, bridge_type, message_type, size_bytes, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :message, :received],
      %{size_bytes: size_bytes},
      %{bridge_id: bridge_id, bridge_type: bridge_type, message_type: message_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a message sent to an external bridge.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `message_type`: Type of message (:text, :image, :file, etc.)
  - `size_bytes`: Size of the message in bytes
  - `duration_ms`: Time taken to send the message
  - `metadata`: Additional metadata
  """
  def message_sent(bridge_id, bridge_type, message_type, size_bytes, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :message, :sent],
      %{size_bytes: size_bytes, duration_ms: duration_ms},
      %{bridge_id: bridge_id, bridge_type: bridge_type, message_type: message_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a message processing error.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `error_type`: Type of error (:format_error, :routing_error, :api_error, etc.)
  - `metadata`: Additional metadata
  """
  def message_error(bridge_id, bridge_type, error_type, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :message, :error],
      %{},
      %{bridge_id: bridge_id, bridge_type: bridge_type, error_type: error_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a bridge connection being established.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `connection_type`: Type of connection (:polling, :webhook, :websocket)
  - `metadata`: Additional metadata
  """
  def connection_established(bridge_id, bridge_type, connection_type, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :connection, :established],
      %{},
      %{bridge_id: bridge_id, bridge_type: bridge_type, connection_type: connection_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a bridge connection being lost.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `reason`: Reason for disconnection (:manual, :error, :timeout, etc.)
  - `uptime_seconds`: How long the connection was active
  - `metadata`: Additional metadata
  """
  def connection_lost(bridge_id, bridge_type, reason, uptime_seconds, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :connection, :lost],
      %{uptime_seconds: uptime_seconds},
      %{bridge_id: bridge_id, bridge_type: bridge_type, reason: reason} |> Map.merge(metadata)
    )
  end

  @doc """
  Records a bridge connection error.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `error_type`: Type of connection error (:auth_failed, :network_error, :rate_limited, etc.)
  - `retry_count`: Number of retry attempts
  - `metadata`: Additional metadata
  """
  def connection_error(bridge_id, bridge_type, error_type, retry_count, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :connection, :error],
      %{retry_count: retry_count},
      %{bridge_id: bridge_id, bridge_type: bridge_type, error_type: error_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a webhook received from an external service.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `payload_size`: Size of the webhook payload in bytes
  - `processing_time_ms`: Time taken to process the webhook
  - `metadata`: Additional metadata
  """
  def webhook_received(bridge_id, bridge_type, payload_size, processing_time_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :webhook, :received],
      %{payload_size: payload_size, processing_time_ms: processing_time_ms},
      %{bridge_id: bridge_id, bridge_type: bridge_type} |> Map.merge(metadata)
    )
  end

  @doc """
  Records a webhook processing error.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `error_type`: Type of webhook error (:invalid_signature, :malformed_payload, :processing_error, etc.)
  - `metadata`: Additional metadata
  """
  def webhook_error(bridge_id, bridge_type, error_type, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :webhook, :error],
      %{},
      %{bridge_id: bridge_id, bridge_type: bridge_type, error_type: error_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a successful health check.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `check_type`: Type of health check (:api_connectivity, :message_flow, :rate_limits, etc.)
  - `response_time_ms`: Response time for the health check
  - `metadata`: Additional metadata
  """
  def health_check_passed(bridge_id, bridge_type, check_type, response_time_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :health_check, :passed],
      %{response_time_ms: response_time_ms},
      %{bridge_id: bridge_id, bridge_type: bridge_type, check_type: check_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a failed health check.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `check_type`: Type of health check (:api_connectivity, :message_flow, :rate_limits, etc.)
  - `error_type`: Type of error that caused the failure
  - `metadata`: Additional metadata
  """
  def health_check_failed(bridge_id, bridge_type, check_type, error_type, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :health_check, :failed],
      %{},
      %{
        bridge_id: bridge_id,
        bridge_type: bridge_type,
        check_type: check_type,
        error_type: error_type
      }
      |> Map.merge(metadata)
    )
  end

  @doc """
  Records a rate limit being exceeded.

  ## Parameters
  - `bridge_id`: The bridge ID
  - `bridge_type`: Type of bridge (:telegram, :whatsapp)
  - `limit_type`: Type of rate limit (:messages_per_minute, :api_calls_per_second, etc.)
  - `current_count`: Current usage count
  - `limit`: The rate limit threshold
  - `metadata`: Additional metadata
  """
  def rate_limit_exceeded(
        bridge_id,
        bridge_type,
        limit_type,
        current_count,
        limit,
        metadata \\ %{}
      ) do
    :telemetry.execute(
      [:globalbridge_backend, :bridge, :rate_limit, :exceeded],
      %{current_count: current_count, limit: limit},
      %{bridge_id: bridge_id, bridge_type: bridge_type, limit_type: limit_type}
      |> Map.merge(metadata)
    )
  end

  @doc """
  Telemetry event handler.

  This function processes telemetry events and can be extended to send
  metrics to Prometheus, log to external systems, etc.
  """
  def handle_event(event, measurements, metadata, _config) do
    # Log the event for debugging
    Logger.debug(
      "Bridge Telemetry Event: #{inspect(event)} - #{inspect(measurements)} - #{inspect(metadata)}"
    )

    # Here you would typically send metrics to Prometheus, DataDog, etc.
    # For example:
    # send_to_prometheus(event, measurements, metadata)

    # Example: Log important events at appropriate levels
    case event do
      [:globalbridge_backend, :bridge, :connection, :lost] ->
        Logger.warning(
          "Bridge #{metadata.bridge_id} (#{metadata.bridge_type}) connection lost: #{metadata.reason} after #{measurements.uptime_seconds}s"
        )

      [:globalbridge_backend, :bridge, :connection, :error] ->
        Logger.error(
          "Bridge #{metadata.bridge_id} (#{metadata.bridge_type}) connection error: #{metadata.error_type} (retry ##{measurements.retry_count})"
        )

      [:globalbridge_backend, :bridge, :message, :error] ->
        Logger.warning(
          "Bridge #{metadata.bridge_id} (#{metadata.bridge_type}) message error: #{metadata.error_type}"
        )

      [:globalbridge_backend, :bridge, :health_check, :failed] ->
        Logger.error(
          "Bridge #{metadata.bridge_id} (#{metadata.bridge_type}) health check failed: #{metadata.check_type} - #{metadata.error_type}"
        )

      [:globalbridge_backend, :bridge, :rate_limit, :exceeded] ->
        Logger.warning(
          "Bridge #{metadata.bridge_id} (#{metadata.bridge_type}) rate limit exceeded: #{metadata.limit_type} (#{measurements.current_count}/#{measurements.limit})"
        )

      [:globalbridge_backend, :bridge, :webhook, :error] ->
        Logger.warning(
          "Bridge #{metadata.bridge_id} (#{metadata.bridge_type}) webhook error: #{metadata.error_type}"
        )

      _ ->
        :ok
    end
  end

  # Private functions for metrics export

  # defp send_to_prometheus(event, measurements, metadata) do
  #   # Implementation would depend on your Prometheus client
  #   # For example, using PrometheusEcto or similar
  # end
end
