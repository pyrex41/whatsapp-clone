defmodule GlobalbridgeBackend.Sync.CDCLogger do
  @moduledoc """
  Helper module to persist CDC entries into the shared `cdc_logs` table whenever
  message records are created, updated, or deleted. Ensures downstream clients
  can pull the latest changes.
  """

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{CDCLog, Message, Thread}

  @doc """
  Records an insert CDC log for the given message.
  """
  def log_message_insert(%Thread{} = thread, %Message{} = message, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    %CDCLog{}
    |> CDCLog.create_changeset(%{
      table_name: "messages",
      record_id: message.id,
      operation: "INSERT",
      old_data: nil,
      new_data: message_to_map(thread, message),
      changed_fields: nil,
      user_id: Keyword.get(opts, :user_id, message.sender_id),
      device_id: Keyword.get(opts, :device_id),
      timestamp: timestamp
    })
    |> Repo.insert()
  end

  @doc """
  Records an update CDC log for the given message with optional `old_data`.
  """
  def log_message_update(%Thread{} = thread, %Message{} = message, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    user_id = Keyword.get(opts, :user_id, message.sender_id)
    old_data = Keyword.get(opts, :old_data)
    new_data = message_to_map(thread, message)

    changeset =
      %CDCLog{}
      |> CDCLog.create_changeset(%{
        table_name: "messages",
        record_id: message.id,
        operation: "UPDATE",
        old_data: old_data,
        new_data: new_data,
        changed_fields: derive_changed_fields(old_data, new_data),
        user_id: user_id,
        device_id: Keyword.get(opts, :device_id),
        timestamp: timestamp
      })

    Repo.insert(changeset)
  end

  @doc """
  Records a delete CDC log for the given message.
  """
  def log_message_delete(%Thread{} = thread, %Message{} = message, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    user_id = Keyword.get(opts, :user_id, message.sender_id)
    old_data = Keyword.get(opts, :old_data, message_to_map(thread, message))

    %CDCLog{}
    |> CDCLog.create_changeset(%{
      table_name: "messages",
      record_id: message.id,
      operation: "DELETE",
      old_data: old_data,
      new_data: %{"id" => message.id, "thread_id" => thread.id, "is_deleted" => true},
      changed_fields: ["is_deleted", "deleted_at"],
      user_id: user_id,
      device_id: Keyword.get(opts, :device_id),
      timestamp: timestamp
    })
    |> Repo.insert()
  end

  @doc """
  Converts a message struct into a map with string keys suitable for storing in
  `cdc_logs`.
  """
  def message_to_map(%Thread{} = thread, %Message{} = message) do
    %{
      "id" => message.id,
      "thread_id" => thread.id,
      "sender_id" => message.sender_id,
      "content" => message.content,
      "content_type" => message.content_type,
      "media_url" => message.media_url,
      "media_size" => message.media_size,
      "media_mime_type" => message.media_mime_type,
      "is_encrypted" => message.is_encrypted,
      "encryption_key_id" => message.encryption_key_id,
      "reply_to_id" => message.reply_to_id,
      "is_deleted" => message.is_deleted,
      "deleted_at" => format_datetime(message.deleted_at),
      "edited_at" => format_datetime(message.edited_at),
      "client_created_at" => format_datetime(message.client_created_at),
      "inserted_at" => format_datetime(message.inserted_at),
      "updated_at" => format_datetime(message.updated_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_datetime(value), do: value

  defp derive_changed_fields(nil, new_data) when is_map(new_data) do
    Map.keys(new_data)
  end

  defp derive_changed_fields(old_data, new_data) when is_map(old_data) and is_map(new_data) do
    new_data
    |> Enum.reduce([], fn {key, value}, acc ->
      case Map.get(old_data, key) do
        ^value -> acc
        _ -> [key | acc]
      end
    end)
    |> Enum.reverse()
  end
end
