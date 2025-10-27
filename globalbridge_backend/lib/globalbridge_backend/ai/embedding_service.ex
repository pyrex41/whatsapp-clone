defmodule GlobalbridgeBackend.AI.EmbeddingService do
  @moduledoc """
  Service for generating text embeddings using OpenAI's text-embedding-3-small model.

  Features:
  - Generates 1536-dimensional embeddings
  - Cachex caching for deduplication (1 hour TTL)
  - Async background processing via Oban
  - Batch processing for efficiency
  """

  alias GlobalbridgeBackend.AI.VectorStore
  alias GlobalbridgeBackend.AI.Cache
  alias GlobalbridgeBackend.AI.CostOptimizer
  alias GlobalbridgeBackend.AI.CostTracker
  alias GlobalbridgeBackend.AI.Telemetry
  alias GlobalbridgeBackend.Repos.ThreadRepo

  require Logger

  @embedding_model System.get_env("OPENAI_EMBEDDING_MODEL") || "text-embedding-3-small"
  @dimensions 1536
  @test_mode Application.compile_env(:globalbridge_backend, :test_mode, false)

  # Test mode flag for bypassing API calls
  def test_mode? do
    @test_mode
  end

  @doc """
  Generates an embedding for the given text.

  Checks cache first, then calls OpenAI API if not cached.
  """
  def generate(text) when is_binary(text) do
    case Cache.get_embedding(text, @embedding_model) do
      nil ->
        # Not in cache, generate new embedding
        Telemetry.cache_miss(:embedding, text, %{model: @embedding_model})

        start_time = System.monotonic_time(:millisecond)
        Telemetry.embedding_start(@embedding_model, 1, %{text: text})

        case generate_embedding(text) do
          {:ok, embedding} ->
            duration = System.monotonic_time(:millisecond) - start_time
            tokens_used = estimate_tokens(text)

            Telemetry.embedding_stop(@embedding_model, 1, tokens_used, duration, %{text: text})

            # Log cost for the embedding generation
            CostTracker.log_cost(:embedding, @embedding_model, tokens_used, 0, %{text: text})

            # Cache the result
            Cache.put_embedding(text, embedding, @embedding_model)
            {:ok, embedding}

          error ->
            duration = System.monotonic_time(:millisecond) - start_time

            Telemetry.embedding_error(@embedding_model, :api_error, duration, %{
              text: text,
              error: error
            })

            error
        end

      embedding ->
        # Found in cache
        Telemetry.cache_hit(:embedding, text, %{model: @embedding_model})
        {:ok, embedding}
    end
  end

  @doc """
  Generates embeddings for multiple texts in batch.

  More efficient than calling generate/1 multiple times.
  """
  def generate_batch(texts) when is_list(texts) do
    # Use cost optimizer to deduplicate and optimize batch
    optimization_result = CostOptimizer.optimize_batch_queries(texts, :embedding)

    Logger.info("Batch optimization",
      original_count: optimization_result.original_count,
      optimized_count: optimization_result.optimized_count,
      savings_percentage: optimization_result.savings_percentage
    )

    optimized_texts = optimization_result.optimized_queries

    # Separate cached and uncached texts
    {cached, uncached} =
      Enum.split_with(optimized_texts, fn text ->
        Cache.embedding_exists?(text, @embedding_model)
      end)

    # Record cache hits
    Enum.each(cached, fn text ->
      Telemetry.cache_hit(:embedding, text, %{model: @embedding_model})
    end)

    # Get cached embeddings
    cached_embeddings =
      Enum.map(cached, fn text ->
        Cache.get_embedding(text, @embedding_model)
      end)

    # Generate embeddings for uncached texts with early error return
    case generate_uncached_batch(uncached) do
      {:ok, uncached_embeddings} ->
        # Reconstruct full result set (map optimized results back to original queries)
        all_embeddings =
          reconstruct_batch_results(texts, cached, cached_embeddings, uncached, uncached_embeddings)

        if length(all_embeddings) == length(texts) do
          {:ok, all_embeddings}
        else
          {:error, :batch_reconstruction_failed}
        end

      {:error, _reason} = error ->
        # Return error immediately without corrupting data
        error
    end
  end

  @doc """
  Stores an embedding for a message in the vector database.

  This is called after generating an embedding for a message.
  """
  def store_embedding(thread_id, message_id, embedding) do
    # Backwards-compatible: treat thread_id as repo key
    # Update message row metadata first (non-fatal if it fails)
    repo = ThreadRepo.get_repo(thread_id)
    update_message_embedding(repo, message_id, embedding)

    # Best-effort insert into vec0 table; log but don't crash job
    case VectorStore.insert(thread_id, message_id, embedding) do
      :ok -> :ok
      {:error, reason} ->
        require Logger
        Logger.warning("Skipping vec0 insert for #{message_id}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Stores an embedding using an explicit shard (repo key).
  """
  def store_embedding_in_shard(shard_id, message_id, embedding) do
    # Update the message record with embedding metadata
    repo = ThreadRepo.get_repo(shard_id)
    update_message_embedding(repo, message_id, embedding)

    # Try vec0 insert; do not fail the job if vec0 isn't available
    case VectorStore.insert(shard_id, message_id, embedding) do
      :ok -> :ok
      {:error, reason} ->
        require Logger
        Logger.warning("Skipping vec0 insert for #{message_id} on shard #{shard_id}: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  Gets the embedding for a message if it exists.
  """
  def get_message_embedding(thread_id, message_id) do
    VectorStore.get_embedding(thread_id, message_id)
  end

  @doc """
  Returns the current embedding model being used.
  """
  def embedding_model do
    @embedding_model
  end

  @doc """
  Estimates the number of tokens in the given text.

  This is a rough estimation used for cost tracking and telemetry.
  """
  def estimate_tokens(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token for English text
    # This is a simplified estimation - in production you'd use a proper tokenizer
    max(1, div(String.length(text), 4))
  end

  # Private functions

  defp generate_uncached_batch([]), do: {:ok, []}

  defp generate_uncached_batch(uncached_texts) do
    start_time = System.monotonic_time(:millisecond)

    Telemetry.embedding_start(@embedding_model, length(uncached_texts), %{
      batch: true,
      optimized: true
    })

    case generate_embeddings_batch(uncached_texts) do
      {:ok, embeddings} ->
        duration = System.monotonic_time(:millisecond) - start_time
        total_tokens = Enum.reduce(uncached_texts, 0, &(&2 + estimate_tokens(&1)))

        Telemetry.embedding_stop(
          @embedding_model,
          length(uncached_texts),
          total_tokens,
          duration,
          %{batch: true, optimized: true}
        )

        # Log cost for the batch embedding generation
        CostTracker.log_cost(:embedding, @embedding_model, total_tokens, 0, %{
          batch: true,
          count: length(uncached_texts)
        })

        # Cache the results
        Enum.zip(uncached_texts, embeddings)
        |> Enum.each(fn {text, embedding} ->
          Cache.put_embedding(text, embedding, @embedding_model)
        end)

        {:ok, embeddings}

      {:error, reason} = error ->
        duration = System.monotonic_time(:millisecond) - start_time

        Telemetry.embedding_error(@embedding_model, :batch_api_error, duration, %{
          batch_size: length(uncached_texts),
          error: reason
        })

        error
    end
  end

  defp generate_embedding(text) do
    if @test_mode do
      # Return mock embedding for testing
      mock_embedding = for _ <- 1..@dimensions, do: :rand.uniform() - 0.5
      {:ok, mock_embedding}
    else
      Logger.debug("Generating embedding for text using model: #{@embedding_model}")

      # Call OpenAI API
      case OpenAI.embeddings(
             model: @embedding_model,
             input: text,
             dimensions: @dimensions
           ) do
        {:ok, response} ->
          Logger.debug("OpenAI embeddings API call successful")

          # Extract the embedding from the response
          with {:ok, data} <- fetch_key(response, "data"),
               [%{} = first | _] <- data,
               {:ok, embedding} <- fetch_key(first, "embedding") do
            {:ok, embedding}
          else
            _ ->
              Logger.error("Invalid OpenAI embeddings response format: #{inspect(response)}")
              {:error, :invalid_response}
          end

        {:error, reason} ->
          Logger.error("OpenAI embeddings API call failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp generate_embeddings_batch(texts) do
    if @test_mode do
      # Return mock embeddings for testing
      mock_embeddings =
        for _ <- texts do
          for _ <- 1..@dimensions, do: :rand.uniform() - 0.5
        end

      {:ok, mock_embeddings}
    else
      Logger.debug(
        "Generating batch embeddings for #{length(texts)} texts using model: #{@embedding_model}"
      )

      # Call OpenAI API with batch input
      case OpenAI.embeddings(
             model: @embedding_model,
             input: texts,
             dimensions: @dimensions
           ) do
        {:ok, response} ->
          Logger.debug("OpenAI batch embeddings API call successful")

          # Extract embeddings from batch response
          case fetch_key(response, "data") do
            {:ok, data} when is_list(data) ->
              embeddings = Enum.map(data, fn item ->
                case fetch_key(item, "embedding") do
                  {:ok, e} -> e
                  _ -> nil
                end
              end)
              if Enum.all?(embeddings, &is_list/1), do: {:ok, embeddings}, else: {:error, :invalid_response}
            _ ->
              Logger.error("Invalid OpenAI batch embeddings response format: #{inspect(response)}")
              {:error, :invalid_response}
          end

        {:error, reason} ->
          Logger.error("OpenAI batch embeddings API call failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Fetch value by key supporting both string and atom keys
  defp fetch_key(map, key) when is_map(map) and is_binary(key) do
    cond do
      Map.has_key?(map, key) -> {:ok, Map.get(map, key)}
      Map.has_key?(map, String.to_atom(key)) -> {:ok, Map.get(map, String.to_atom(key))}
      true -> :error
    end
  end

  defp embedding_to_binary(embedding) when is_list(embedding) do
    # Convert list of floats to binary for storage
    for float <- embedding, into: <<>> do
      <<float::float-32-little>>
    end
  end

  defp update_message_embedding(repo, message_id, embedding) do
    sql = """
    UPDATE messages
    SET embedding = ?, embedding_model = ?, embedding_generated_at = ?
    WHERE id = ?
    """

    embedding_binary = embedding_to_binary(embedding)
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    case Ecto.Adapters.SQL.query(repo, sql, [embedding_binary, @embedding_model, timestamp, message_id]) do
      {:ok, _} -> :ok
      {:error, err} ->
        require Logger
        Logger.error("Failed to update message embedding metadata for #{message_id}: #{inspect(err)}")
        :ok
    end
  end

  defp reconstruct_batch_results(
         original_texts,
         cached_texts,
         cached_embeddings,
         uncached_texts,
         uncached_embeddings
       ) do
    # Build separate maps for cached and uncached results
    cached_map = Enum.zip(cached_texts, cached_embeddings) |> Map.new()
    uncached_map = Enum.zip(uncached_texts, uncached_embeddings) |> Map.new()

    # Merge into single optimized_text -> embedding map
    # O(n) complexity for map creation
    optimized_to_embedding = Map.merge(cached_map, uncached_map)

    # Reconstruct original order with O(1) map lookup per item = O(n) total
    # This correctly handles duplicates in the original texts list
    Enum.map(original_texts, fn original_text ->
      Map.get(optimized_to_embedding, original_text)
    end)
  end
end
