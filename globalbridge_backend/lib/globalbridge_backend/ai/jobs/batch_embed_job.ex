defmodule GlobalbridgeBackend.AI.Jobs.BatchEmbedJob do
  @moduledoc """
  Oban job for batch processing embeddings.

  This job processes multiple messages at once for better efficiency
  and to take advantage of OpenAI's batch processing capabilities.
  """

  use Oban.Worker, queue: :embeddings, max_attempts: 3

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.{Repo}
  alias GlobalbridgeBackend.Schemas.Thread

  @batch_size 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    thread_id = args["thread_id"]
    shard_id = args["shard_id"] || get_shard_id(thread_id)

    repo = ThreadRepo.get_repo(shard_id)

    # Get pending messages without embeddings
    case get_pending_messages(repo, @batch_size) do
      [] ->
        # No pending messages
        :ok

      pending_messages ->
        # Extract content from messages
        contents = Enum.map(pending_messages, & &1.content)
        message_ids = Enum.map(pending_messages, & &1.id)

        # Generate embeddings in batch
        case EmbeddingService.generate_batch(contents) do
          {:ok, embeddings} ->
            # Store embeddings for each message
            Enum.zip(message_ids, embeddings)
            |> Enum.each(fn {message_id, embedding} ->
              if embedding do
                EmbeddingService.store_embedding_in_shard(shard_id, message_id, embedding)
              end
            end)

            # If there are more pending messages, enqueue another batch job
            if length(pending_messages) == @batch_size do
              enqueue_batch_job(thread_id, shard_id)
            end

            :ok

          {:error, reason} ->
            require Logger

            Logger.error(
              "Failed to generate batch embeddings for thread #{thread_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 2m, 8m, 18m
    attempt * attempt * 120
  end

  # Private functions

  defp get_pending_messages(repo, limit) do
    sql = """
    SELECT id, content
    FROM messages
    WHERE embedding IS NULL
      AND is_deleted = 0
      AND content IS NOT NULL
      AND content != ''
    ORDER BY inserted_at ASC
    LIMIT ?
    """

    case Ecto.Adapters.SQL.query(repo, sql, [limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [id, content] ->
          %{id: id, content: content}
        end)

      _ ->
        []
    end
  end

  defp enqueue_batch_job(thread_id, shard_id) do
    %{thread_id: thread_id, shard_id: shard_id}
    |> GlobalbridgeBackend.AI.Jobs.BatchEmbedJob.new()
    |> Oban.insert()
  end

  defp get_shard_id(nil), do: nil
  defp get_shard_id(thread_id) do
    case Repo.get(Thread, thread_id) do
      %Thread{database_shard_id: shard_id} -> shard_id
      _ -> thread_id
    end
  end
end
