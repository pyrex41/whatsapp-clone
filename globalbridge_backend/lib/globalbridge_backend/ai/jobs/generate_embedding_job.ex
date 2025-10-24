defmodule GlobalbridgeBackend.AI.Jobs.GenerateEmbeddingJob do
  @moduledoc """
  Oban job for asynchronously generating embeddings for messages.

  This job is enqueued whenever a new message is created and processes
  embedding generation in the background to avoid blocking the API response.
  """

  use Oban.Worker, queue: :embeddings, max_attempts: 3

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.{Repo}
  alias GlobalbridgeBackend.Schemas.Thread

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    message_id = args["message_id"]
    thread_id = args["thread_id"]
    shard_id = args["shard_id"] || get_shard_id(thread_id)

    repo = ThreadRepo.get_repo(shard_id)

    # Get the message content
    case get_message_content(repo, message_id) do
      {:ok, content} ->
        # Generate embedding
        case EmbeddingService.generate(content) do
          {:ok, embedding} ->
            # Store the embedding using the shard id
            EmbeddingService.store_embedding_in_shard(shard_id, message_id, embedding)
            :ok

          {:error, reason} ->
            # Log error and retry
            require Logger

            Logger.error(
              "Failed to generate embedding for message #{message_id}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      {:error, :not_found} ->
        # Message not found, might have been deleted
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 1m, 4m, 9m
    attempt * attempt * 60
  end

  # Private functions

  defp get_message_content(repo, message_id) do
    sql = "SELECT content FROM messages WHERE id = ? AND is_deleted = 0"

    case Ecto.Adapters.SQL.query(repo, sql, [message_id]) do
      {:ok, %{rows: [[content]]}} ->
        {:ok, content}

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_shard_id(nil), do: nil
  defp get_shard_id(thread_id) do
    case Repo.get(Thread, thread_id) do
      %Thread{database_shard_id: shard_id} -> shard_id
      _ -> thread_id
    end
  end
end
