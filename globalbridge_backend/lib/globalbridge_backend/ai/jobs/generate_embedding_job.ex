defmodule GlobalbridgeBackend.AI.Jobs.GenerateEmbeddingJob do
  @moduledoc """
  Oban job for asynchronously generating embeddings for messages.

  This job is enqueued whenever a new message is created and processes
  embedding generation in the background to avoid blocking the API response.
  """

  use Oban.Worker, queue: :embeddings, max_attempts: 3

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.Repos.ThreadRepo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"message_id" => message_id, "thread_id" => thread_id}}) do
    repo = ThreadRepo.get_repo(thread_id)

    # Get the message content
    case get_message_content(repo, message_id) do
      {:ok, content} ->
        # Generate embedding
        case EmbeddingService.generate(content) do
          {:ok, embedding} ->
            # Store the embedding
            EmbeddingService.store_embedding(thread_id, message_id, embedding)
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
end
