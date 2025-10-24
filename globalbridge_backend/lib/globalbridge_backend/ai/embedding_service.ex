defmodule GlobalbridgeBackend.AI.EmbeddingService do
  @moduledoc """
  Service for generating text embeddings using OpenAI's text-embedding-3-large model.

  Features:
  - Generates 3072-dimensional embeddings
  - Redis caching for deduplication
  - Async background processing via Oban
  - Batch processing for efficiency
  """

  alias GlobalbridgeBackend.AI.VectorStore
  alias GlobalbridgeBackend.AI.Cache.EmbeddingCache
  alias GlobalbridgeBackend.AI.Telemetry
  alias GlobalbridgeBackend.Repos.ThreadRepo

  require Logger

  @embedding_model System.get_env("OPENAI_EMBEDDING_MODEL") || "text-embedding-3-large"
  @dimensions 3072

  @doc """
  Generates an embedding for the given text.

  Checks cache first, then calls OpenAI API if not cached.
  """
  def generate(text) when is_binary(text) do
    case EmbeddingCache.get(text, @embedding_model) do
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

            # Cache the result
            EmbeddingCache.put(text, embedding, @embedding_model)
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
    # Separate cached and uncached texts
    {cached, uncached} =
      Enum.split_with(texts, fn text ->
        EmbeddingCache.exists?(text, @embedding_model)
      end)

    # Record cache hits
    Enum.each(cached, fn text ->
      Telemetry.cache_hit(:embedding, text, %{model: @embedding_model})
    end)

    # Generate embeddings for uncached texts
    uncached_results =
      if length(uncached) > 0 do
        start_time = System.monotonic_time(:millisecond)
        Telemetry.embedding_start(@embedding_model, length(uncached), %{batch: true})

        case generate_embeddings_batch(uncached) do
          {:ok, embeddings} ->
            duration = System.monotonic_time(:millisecond) - start_time
            total_tokens = Enum.reduce(uncached, 0, &(&2 + estimate_tokens(&1)))

            Telemetry.embedding_stop(
              @embedding_model,
              length(uncached),
              total_tokens,
              duration,
              %{batch: true}
            )

            # Cache the new embeddings
            Enum.zip(uncached, embeddings)
            |> Enum.each(fn {text, embedding} ->
              EmbeddingCache.put(text, embedding, @embedding_model)
            end)

            embeddings

          {:error, reason} ->
            duration = System.monotonic_time(:millisecond) - start_time

            Telemetry.embedding_error(@embedding_model, :batch_api_error, duration, %{
              error: reason,
              batch_size: length(uncached)
            })

            # Return nil for failed texts
            List.duplicate(nil, length(uncached))
        end
      else
        []
      end

    # Build final result list
    cached_embeddings =
      Enum.map(cached, fn text ->
        EmbeddingCache.get(text, @embedding_model)
      end)

    {:ok, cached_embeddings ++ uncached_results}
  end

  @doc """
  Stores an embedding for a message in the vector database.

  This is called after generating an embedding for a message.
  """
  def store_embedding(thread_id, message_id, embedding) do
    # Store in vector database
    VectorStore.insert(thread_id, message_id, embedding)

    # Update the message record with embedding metadata
    repo = ThreadRepo.get_repo(thread_id)

    sql = """
    UPDATE messages
    SET embedding = ?, embedding_model = ?, embedding_generated_at = ?
    WHERE id = ?
    """

    embedding_binary = embedding_to_binary(embedding)
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)

    Ecto.Adapters.SQL.query!(repo, sql, [
      embedding_binary,
      @embedding_model,
      timestamp,
      message_id
    ])

    :ok
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

  # Private functions

  defp generate_embedding(text) do
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
        case response do
          %{"data" => [%{"embedding" => embedding}]} ->
            {:ok, embedding}

          _ ->
            Logger.error("Invalid OpenAI embeddings response format: #{inspect(response)}")
            {:error, :invalid_response}
        end

      {:error, reason} ->
        Logger.error("OpenAI embeddings API call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_embeddings_batch(texts) do
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
        case response do
          %{"data" => data} ->
            embeddings = Enum.map(data, & &1["embedding"])
            {:ok, embeddings}

          _ ->
            Logger.error("Invalid OpenAI batch embeddings response format: #{inspect(response)}")
            {:error, :invalid_response}
        end

      {:error, reason} ->
        Logger.error("OpenAI batch embeddings API call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp embedding_to_binary(embedding) when is_list(embedding) do
    # Convert list of floats to binary for storage
    for float <- embedding, into: <<>> do
      <<float::float-32-little>>
    end
  end

  defp estimate_tokens(text) when is_binary(text) do
    # Rough estimation: ~4 characters per token for English text
    # This is a simplified estimation - in production you'd use a proper tokenizer
    max(1, div(String.length(text), 4))
  end
end
