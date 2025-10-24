defmodule GlobalbridgeBackend.AI.Telemetry do
  @moduledoc """
  Telemetry and metrics for AI services.

  This module provides telemetry events and Prometheus metrics for monitoring
  AI service performance, costs, cache hits, and other operational metrics.
  """

  require Logger

  @doc """
  Attaches telemetry handlers for AI metrics.

  Call this function during application startup to set up telemetry collection.
  """
  def setup do
    # Attach handlers for AI service events
    events = [
      [:globalbridge_backend, :ai, :embedding, :start],
      [:globalbridge_backend, :ai, :embedding, :stop],
      [:globalbridge_backend, :ai, :embedding, :error],
      [:globalbridge_backend, :ai, :llm, :start],
      [:globalbridge_backend, :ai, :llm, :stop],
      [:globalbridge_backend, :ai, :llm, :error],
      [:globalbridge_backend, :ai, :cache, :hit],
      [:globalbridge_backend, :ai, :cache, :miss],
      [:globalbridge_backend, :ai, :cost, :logged]
    ]

    :telemetry.attach_many(
      "ai-metrics-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )

    Logger.info("AI telemetry handlers attached")
  end

  @doc """
  Records the start of an embedding operation.

  ## Parameters
  - `model`: The embedding model used
  - `input_count`: Number of inputs being processed
  - `metadata`: Additional metadata
  """
  def embedding_start(model, input_count, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :embedding, :start],
      %{input_count: input_count},
      %{model: model} |> Map.merge(metadata)
    )
  end

  @doc """
  Records the completion of an embedding operation.

  ## Parameters
  - `model`: The embedding model used
  - `input_count`: Number of inputs processed
  - `tokens_used`: Total tokens processed
  - `duration_ms`: Operation duration in milliseconds
  - `metadata`: Additional metadata
  """
  def embedding_stop(model, input_count, tokens_used, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :embedding, :stop],
      %{
        input_count: input_count,
        tokens_used: tokens_used,
        duration_ms: duration_ms
      },
      %{model: model} |> Map.merge(metadata)
    )
  end

  @doc """
  Records an embedding operation error.

  ## Parameters
  - `model`: The embedding model used
  - `error_type`: Type of error that occurred
  - `duration_ms`: Operation duration before error
  - `metadata`: Additional metadata
  """
  def embedding_error(model, error_type, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :embedding, :error],
      %{duration_ms: duration_ms},
      %{model: model, error_type: error_type} |> Map.merge(metadata)
    )
  end

  @doc """
  Records the start of an LLM operation.

  ## Parameters
  - `model`: The LLM model used
  - `operation`: The operation type (:completion, :chat, etc.)
  - `metadata`: Additional metadata
  """
  def llm_start(model, operation, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :llm, :start],
      %{operation: operation},
      %{model: model} |> Map.merge(metadata)
    )
  end

  @doc """
  Records the completion of an LLM operation.

  ## Parameters
  - `model`: The LLM model used
  - `operation`: The operation type
  - `input_tokens`: Number of input tokens
  - `output_tokens`: Number of output tokens
  - `duration_ms`: Operation duration in milliseconds
  - `metadata`: Additional metadata
  """
  def llm_stop(model, operation, input_tokens, output_tokens, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :llm, :stop],
      %{
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        duration_ms: duration_ms
      },
      %{model: model, operation: operation} |> Map.merge(metadata)
    )
  end

  @doc """
  Records an LLM operation error.

  ## Parameters
  - `model`: The LLM model used
  - `operation`: The operation type
  - `error_type`: Type of error that occurred
  - `duration_ms`: Operation duration before error
  - `metadata`: Additional metadata
  """
  def llm_error(model, operation, error_type, duration_ms, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :llm, :error],
      %{duration_ms: duration_ms},
      %{model: model, operation: operation, error_type: error_type} |> Map.merge(metadata)
    )
  end

  @doc """
  Records a cache hit.

  ## Parameters
  - `cache_type`: Type of cache (:embedding, :translation, etc.)
  - `key`: Cache key that was hit
  - `metadata`: Additional metadata
  """
  def cache_hit(cache_type, key, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :cache, :hit],
      %{cache_type: cache_type, key: key},
      metadata
    )
  end

  @doc """
  Records a cache miss.

  ## Parameters
  - `cache_type`: Type of cache (:embedding, :translation, etc.)
  - `key`: Cache key that was missed
  - `metadata`: Additional metadata
  """
  def cache_miss(cache_type, key, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :cache, :miss],
      %{cache_type: cache_type, key: key},
      metadata
    )
  end

  @doc """
  Records a cost logging event.

  ## Parameters
  - `service`: AI service type (:embedding, :llm, etc.)
  - `model`: Model used
  - `cost_usd`: Cost in USD
  - `metadata`: Additional metadata
  """
  def cost_logged(service, model, cost_usd, metadata \\ %{}) do
    :telemetry.execute(
      [:globalbridge_backend, :ai, :cost, :logged],
      %{cost_usd: cost_usd},
      %{service: service, model: model} |> Map.merge(metadata)
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
      "AI Telemetry Event: #{inspect(event)} - #{inspect(measurements)} - #{inspect(metadata)}"
    )

    # Here you would typically send metrics to Prometheus, DataDog, etc.
    # For example:
    # send_to_prometheus(event, measurements, metadata)

    # Example: Log cost events at info level
    case event do
      [:globalbridge_backend, :ai, :cost, :logged] ->
        Logger.info(
          "AI Cost: $#{Float.round(measurements.cost_usd, 6)} for #{metadata.service}:#{metadata.model}"
        )

      [:globalbridge_backend, :ai, :embedding, :error] ->
        Logger.warning("AI Embedding Error: #{metadata.error_type} for model #{metadata.model}")

      [:globalbridge_backend, :ai, :llm, :error] ->
        Logger.warning(
          "AI LLM Error: #{metadata.error_type} for model #{metadata.model} operation #{metadata.operation}"
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
