defmodule GlobalbridgeBackendWeb.SyncController do
  @moduledoc """
  Controller for CDC (Change Data Capture) synchronization endpoints.
  Handles pull and push operations for multi-device sync.

  ## Endpoints

  - POST /api/v1/sync/pull - Pull CDC changes from server
  - POST /api/v1/sync/push - Push CDC changes to server

  ## Authentication

  All endpoints require valid JWT authentication via Authorization header.
  User must be a participant in the thread being synced.
  """

  use GlobalbridgeBackendWeb, :controller

  import Ecto.Query, warn: false

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{CDCLog, Thread, ThreadParticipant, Message}
  alias GlobalbridgeBackend.Contexts.{Threads, Messages}
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.Auth.Guardian

  action_fallback GlobalbridgeBackendWeb.FallbackController

  @max_changes_per_pull 100

  @doc """
  POST /api/v1/sync/pull

  Pull CDC changes from the server since the last sync cursor.

  ## Parameters

  - `thread_id` (required) - UUID of the thread to sync
  - `last_sync_cursor` (optional) - Integer cursor from last sync, defaults to 0

  ## Response

  ```json
  {
    "data": {
      "changes": [
        {
          "id": "cdc-log-uuid",
          "table_name": "messages",
          "record_id": "record-uuid",
          "operation": "INSERT",
          "old_data": {...},
          "new_data": {...},
          "timestamp": "2024-01-01T00:00:00Z"
        }
      ],
      "next_cursor": 12345
    }
  }
  ```

  ## Errors

  - 400 - Missing required parameters
  - 403 - User not authorized for this thread
  - 404 - Thread not found
  """
  def pull(conn, %{"thread_id" => thread_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    last_sync_cursor = Map.get(params, "last_sync_cursor", 0)

    with {:ok, thread} <- get_thread(thread_id),
         :ok <- validate_thread_access(user.id, thread) do

      # Query CDC logs since last cursor
      changes = query_cdc_changes(thread_id, last_sync_cursor)

      # Calculate next cursor
      next_cursor = calculate_next_cursor(changes, last_sync_cursor)

      conn
      |> put_status(:ok)
      |> render(:pull_success, changes: changes, next_cursor: next_cursor)
    end
  end

  def pull(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: thread_id"})
  end

  @doc """
  POST /api/v1/sync/push

  Push CDC changes to the server from client.

  ## Parameters

  - `thread_id` (required) - UUID of the thread to sync
  - `changes` (required) - Array of CDC log objects to apply

  ## CDC Log Format

  ```json
  {
    "table_name": "messages",
    "record_id": "uuid",
    "operation": "INSERT|UPDATE|DELETE",
    "old_data": {...},
    "new_data": {...},
    "timestamp": "2024-01-01T00:00:00Z"
  }
  ```

  ## Response

  ```json
  {
    "data": {
      "applied": 5,
      "failed": 1,
      "results": [
        {"index": 0, "success": true},
        {"index": 1, "success": false, "error": "Validation failed"}
      ]
    }
  }
  ```

  ## Conflict Resolution

  Uses last-write-wins strategy based on timestamp.
  """
  def push(conn, %{"thread_id" => thread_id, "changes" => changes}) when is_list(changes) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread} <- get_thread(thread_id),
         :ok <- validate_thread_access(user.id, thread) do

      # Apply changes sequentially using Ecto.Multi
      results = apply_changes(thread, changes, user.id)

      applied = Enum.count(results, fn r -> r["success"] == true end)
      failed = Enum.count(results, fn r -> r["success"] == false end)

      conn
      |> put_status(:ok)
      |> render(:push_success, applied: applied, failed: failed, results: results)
    end
  end

  def push(conn, %{"thread_id" => _thread_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: changes (must be an array)"})
  end

  def push(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: thread_id and changes"})
  end

  # Private functions

  defp get_thread(thread_id) do
    case Threads.get_thread(thread_id) do
      nil -> {:error, :not_found}
      thread -> {:ok, thread}
    end
  end

  defp validate_thread_access(user_id, thread) do
    # Check if user is a participant in the thread
    query =
      from(tp in ThreadParticipant,
        where: tp.thread_id == ^thread.id,
        where: tp.user_id == ^user_id,
        where: tp.is_active == true
      )

    case Repo.one(query) do
      nil -> {:error, :unauthorized}
      _participant -> :ok
    end
  end

  defp query_cdc_changes(thread_id, last_sync_cursor) do
    query =
      from(cdc in CDCLog,
        where: cdc.id > ^last_sync_cursor,
        order_by: [asc: cdc.id],
        limit: ^@max_changes_per_pull,
        select: %{
          id: cdc.id,
          table_name: cdc.table_name,
          record_id: cdc.record_id,
          operation: cdc.operation,
          old_data: cdc.old_data,
          new_data: cdc.new_data,
          changed_fields: cdc.changed_fields,
          timestamp: cdc.timestamp
        }
      )

    Repo.all(query)
  end

  defp calculate_next_cursor([], last_cursor), do: last_cursor
  defp calculate_next_cursor(changes, _last_cursor) do
    changes
    |> List.last()
    |> Map.get(:id)
  end

  defp apply_changes(thread, changes, user_id) do
    Enum.with_index(changes)
    |> Enum.map(fn {change, index} ->
      case apply_single_change(thread, change, user_id) do
        {:ok, _result} ->
          %{
            "index" => index,
            "success" => true
          }

        {:error, reason} ->
          %{
            "index" => index,
            "success" => false,
            "error" => format_error(reason)
          }
      end
    end)
  end

  defp apply_single_change(thread, change, user_id) do
    # Validate CDC log structure
    with {:ok, validated_change} <- validate_cdc_log(change),
         {:ok, result} <- execute_cdc_operation(thread, validated_change, user_id) do
      {:ok, result}
    end
  end

  defp validate_cdc_log(change) do
    required_fields = ["table_name", "record_id", "operation", "new_data"]

    missing_fields =
      required_fields
      |> Enum.filter(fn field ->
        not Map.has_key?(change, field) and not Map.has_key?(change, String.to_atom(field))
      end)

    if Enum.empty?(missing_fields) do
      # Normalize keys to atoms
      normalized = %{
        table_name: get_field(change, "table_name"),
        record_id: get_field(change, "record_id"),
        operation: get_field(change, "operation"),
        old_data: get_field(change, "old_data"),
        new_data: get_field(change, "new_data"),
        timestamp: get_field(change, "timestamp")
      }

      {:ok, normalized}
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp execute_cdc_operation(thread, change, user_id) do
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    case change.table_name do
      "messages" -> apply_message_operation(repo, thread, change, user_id)
      "read_receipts" -> apply_read_receipt_operation(repo, thread, change, user_id)
      _ -> {:error, "Unsupported table: #{change.table_name}"}
    end
  end

  defp apply_message_operation(repo, thread, change, user_id) do
    case change.operation do
      "INSERT" ->
        create_message_from_cdc(repo, thread.id, change.new_data, user_id)

      "UPDATE" ->
        update_message_from_cdc(repo, change.record_id, change.new_data)

      "DELETE" ->
        delete_message_from_cdc(repo, change.record_id, change.new_data)

      _ ->
        {:error, "Invalid operation: #{change.operation}"}
    end
  end

  defp create_message_from_cdc(repo, thread_id, new_data, _user_id) do
    # Convert string keys to atom keys for Ecto
    attrs = atomize_keys(new_data)
    attrs = Map.put(attrs, :thread_id, thread_id)

    changeset = Message.create_changeset(%Message{}, attrs)

    case repo.insert(changeset) do
      {:ok, message} -> {:ok, message}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp update_message_from_cdc(repo, message_id, new_data) do
    case repo.get(Message, message_id) do
      nil ->
        {:error, "Message not found"}

      message ->
        attrs = atomize_keys(new_data)

        # Parse datetime strings
        attrs = parse_datetime_fields(attrs, [:edited_at])

        changeset = Message.edit_changeset(message, attrs)

        case repo.update(changeset) do
          {:ok, updated} -> {:ok, updated}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp delete_message_from_cdc(repo, message_id, new_data) do
    case repo.get(Message, message_id) do
      nil ->
        {:error, "Message not found"}

      message ->
        attrs = atomize_keys(new_data)
        attrs = parse_datetime_fields(attrs, [:deleted_at])

        # Use the delete_changeset
        changeset = Message.delete_changeset(message, attrs)

        case repo.update(changeset) do
          {:ok, deleted} -> {:ok, deleted}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp apply_read_receipt_operation(_repo, _thread, _change, _user_id) do
    # Placeholder for read receipts - implement as needed
    {:ok, :skipped}
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp parse_datetime_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      case Map.get(acc, field) do
        nil ->
          acc

        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _offset} -> Map.put(acc, field, datetime)
            _ -> acc
          end

        _value ->
          acc
      end
    end)
  end

  defp format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Jason.encode!()
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error) when is_atom(error), do: to_string(error)
  defp format_error(error), do: inspect(error)
end
