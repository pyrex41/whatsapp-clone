defmodule GlobalbridgeBackend.Chat do
  @moduledoc """
  Context module for chat operations.

  Handles message CRUD, thread management, and participant authorization.
  Optimized for per-thread database sharding.
  """

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Message, Thread, ThreadParticipant}
  alias GlobalbridgeBackend.Sync.CDCLogger
  import Ecto.Query

  @doc """
  Get a thread by ID.
  """
  def get_thread(thread_id) do
    Repo.get(Thread, thread_id)
  end

  @doc """
  Check if a user is a participant in a thread.
  """
  def is_thread_participant?(thread_id, user_id) do
    query =
      from(tp in ThreadParticipant,
        where: tp.thread_id == ^thread_id and tp.user_id == ^user_id
      )

    Repo.exists?(query)
  end

  @doc """
  Create a new message in a thread.

  Messages are stored in per-thread databases for sharding.
  """
  def create_message(thread_id, attrs) do
    # Get thread to determine which shard database to use
    case get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        # Use the thread's shard database
        shard_repo = get_shard_repo(thread.database_shard_id)

        attrs = Map.put(attrs, :thread_id, thread_id)

        %Message{}
        |> Message.create_changeset(attrs)
        |> shard_repo.insert()
        |> case do
          {:ok, message} ->
            CDCLogger.log_message_insert(thread, message, user_id: message.sender_id)

            # Enqueue embedding generation job for the new message
            enqueue_embedding_job(thread_id, message.id)

            {:ok, message}

          error ->
            error
        end
    end
  end

  @doc """
  Edit a message.

  Only the sender can edit their own messages.
  """
  def edit_message(thread_id, message_id, user_id, new_content) do
    case get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        shard_repo = get_shard_repo(thread.database_shard_id)

        case shard_repo.get(Message, message_id) do
          nil ->
            {:error, :not_found}

          message ->
            if message.sender_id == user_id do
              old_snapshot = CDCLogger.message_to_map(thread, message)

              message
              |> Message.edit_changeset(%{content: new_content})
              |> shard_repo.update()
              |> case do
                {:ok, updated} ->
                  CDCLogger.log_message_update(
                    thread,
                    updated,
                    user_id: user_id,
                    old_data: old_snapshot
                  )

                  {:ok, updated}

                error ->
                  error
              end
            else
              {:error, :unauthorized}
            end
        end
    end
  end

  @doc """
  Delete a message (soft delete).

  Only the sender can delete their own messages.
  """
  def delete_message(thread_id, message_id, user_id) do
    case get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        shard_repo = get_shard_repo(thread.database_shard_id)

        case shard_repo.get(Message, message_id) do
          nil ->
            {:error, :not_found}

          message ->
            if message.sender_id == user_id do
              old_snapshot = CDCLogger.message_to_map(thread, message)

              message
              |> Message.delete_changeset()
              |> shard_repo.update()
              |> case do
                {:ok, deleted} ->
                  CDCLogger.log_message_delete(
                    thread,
                    deleted,
                    user_id: user_id,
                    old_data: old_snapshot
                  )

                  {:ok, deleted}

                error ->
                  error
              end
            else
              {:error, :unauthorized}
            end
        end
    end
  end

  @doc """
  Update thread's last_message_at timestamp.
  """
  def update_thread_timestamp(thread_id) do
    case get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        thread
        |> Thread.update_changeset(%{last_message_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc """
  Mark a message as read by a user.

  Creates or updates a read receipt for the specified message.
  Uses upsert to handle duplicate read attempts gracefully.
  """
  def mark_message_read(thread_id, message_id, user_id) do
    alias GlobalbridgeBackend.Schemas.ReadReceipt

    case get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        shard_repo = get_shard_repo(thread.database_shard_id)

        # Use insert with on_conflict to handle upserts
        attrs = %{
          message_id: message_id,
          user_id: user_id,
          read_at: DateTime.utc_now()
        }

        %ReadReceipt{}
        |> ReadReceipt.create_changeset(attrs)
        |> shard_repo.insert(
          on_conflict: {:replace, [:read_at, :updated_at]},
          conflict_target: [:message_id, :user_id]
        )
    end
  end

  @doc """
  Get read receipts for a message.

  Returns list of users who have read the message with timestamps.
  """
  def get_message_read_receipts(thread_id, message_id) do
    alias GlobalbridgeBackend.Schemas.ReadReceipt

    case get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        shard_repo = get_shard_repo(thread.database_shard_id)

        query =
          from(rr in ReadReceipt,
            where: rr.message_id == ^message_id,
            order_by: [asc: rr.read_at],
            select: rr
          )

        {:ok, shard_repo.all(query)}
    end
  end

  @doc """
  Get last read message ID for a user in a thread.

  Useful for showing "read up to here" indicators.
  """
  def get_last_read_message(thread_id, user_id) do
    alias GlobalbridgeBackend.Schemas.ReadReceipt

    case get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        shard_repo = get_shard_repo(thread.database_shard_id)

        query =
          from(rr in ReadReceipt,
            where: rr.user_id == ^user_id,
            order_by: [desc: rr.read_at],
            limit: 1,
            select: rr.message_id
          )

        case shard_repo.one(query) do
          nil -> {:ok, nil}
          message_id -> {:ok, message_id}
        end
    end
  end

  @doc """
  Enqueue an embedding generation job for a new message.
  """
  def enqueue_embedding_job(thread_id, message_id) do
    if Mix.env() != :test do
      %{thread_id: thread_id, message_id: message_id}
      |> GlobalbridgeBackend.AI.Jobs.GenerateEmbeddingJob.new()
      |> Oban.insert()
    end
  end

  # Private helpers

  defp get_shard_repo(_shard_id) do
    # For now, use the main Repo
    # TODO: Implement actual per-thread database sharding
    # This would return a dynamically configured Repo for the specific shard
    Repo
  end
end
