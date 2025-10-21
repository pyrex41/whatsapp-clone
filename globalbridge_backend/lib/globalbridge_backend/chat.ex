defmodule GlobalbridgeBackend.Chat do
  @moduledoc """
  Context module for chat operations.

  Handles message CRUD, thread management, and participant authorization.
  Optimized for per-thread database sharding.
  """

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Message, Thread, ThreadParticipant}
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

        %Message{}
        |> Message.create_changeset(attrs)
        |> shard_repo.insert()
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
              message
              |> Message.edit_changeset(%{content: new_content})
              |> shard_repo.update()
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
              message
              |> Message.delete_changeset()
              |> shard_repo.update()
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
  """
  def mark_message_read(thread_id, message_id, user_id) do
    # TODO: Implement read receipts
    # This would insert/update a read_receipt record
    :ok
  end

  # Private helpers

  defp get_shard_repo(shard_id) do
    # For now, use the main Repo
    # TODO: Implement actual per-thread database sharding
    # This would return a dynamically configured Repo for the specific shard
    Repo
  end
end
