defmodule GlobalbridgeBackend.Sync do
  @moduledoc """
  Shared sync utilities for CDC (Change Data Capture) operations between the
  Phoenix controllers and channels. Responsible for querying CDC logs and
  applying inbound changes from clients in a consistent way.
  """

  import Ecto.Query, warn: false

  alias GlobalbridgeBackend.Contexts.Threads
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{CDCLog, Message, Thread, ThreadParticipant}

  @max_changes_per_pull 100

  @doc """
  Fetches CDC changes for a thread since a particular timestamp.

  Returns a tuple `{changes, next_cursor}` where `changes` is a list of `%CDCLog{}`
  structs ordered by timestamp ascending and `next_cursor` is the timestamp of
  the last change (or the provided `since` when there are no new changes).
  """
  def pull_changes(%Thread{} = thread, opts \\ []) do
    since = Keyword.get(opts, :since)
    limit = Keyword.get(opts, :limit, @max_changes_per_pull)

    # Build query with timestamp filter if provided
    query =
      from(c in CDCLog,
        where: fragment("json_extract(?, '$.thread_id') = ?", c.new_data, ^thread.id),
        order_by: [asc: c.timestamp, asc: c.inserted_at]
      )

    query_with_since =
      case since do
        %DateTime{} = timestamp ->
          # Use strict > to exclude already-seen changes at exactly this timestamp
          from(c in query, where: c.timestamp > ^timestamp)

        _ ->
          query
      end

    # Apply limit after timestamp filter
    final_query = from(c in query_with_since, limit: ^limit)

    changes = Repo.all(final_query)

    next_cursor =
      case {List.last(changes), since} do
        {nil, nil} ->
          # No changes and no since - return current time
          DateTime.utc_now()

        {nil, %DateTime{} = s} ->
          # No new changes - return the same cursor
          s

        {%CDCLog{timestamp: timestamp}, _} ->
          # Return last change timestamp
          timestamp
      end

    {changes, next_cursor}
  end

  @doc """
  Applies a list of CDC change maps coming from a client to the given thread.

  Each change is validated before being applied. The resulting list contains a
  per-change status map with `index`, `success`, and optionally an `error`.
  """
  def apply_changes(%Thread{} = thread, changes, user_id) when is_list(changes) do
    Enum.with_index(changes)
    |> Enum.map(fn {change, index} ->
      case apply_single_change(thread, change, user_id) do
        {:ok, _result} ->
          %{"index" => index, "success" => true}

        {:error, reason} ->
          %{
            "index" => index,
            "success" => false,
            "error" => format_error(reason)
          }
      end
    end)
  end

  @doc """
  Formats a CDC change struct into a plain map suitable for JSON responses.
  """
  def format_change(%CDCLog{} = change) do
    %{
      id: change.id,
      table_name: change.table_name,
      record_id: change.record_id,
      operation: change.operation,
      old_data: change.old_data,
      new_data: change.new_data,
      changed_fields: change.changed_fields,
      timestamp: format_timestamp(change.timestamp)
    }
  end

  @doc """
  Loads a thread by ID and returns `{:ok, thread}` or `{:error, :not_found}`.
  """
  def fetch_thread(thread_id) do
    case Threads.get_thread(thread_id) do
      nil -> {:error, :not_found}
      thread -> {:ok, thread}
    end
  end

  @doc """
  Ensures the given `user_id` participates in the `thread`. Returns `:ok` when
  authorized or `{:error, :unauthorized}` otherwise.
  """
  def authorize_thread_access(user_id, %Thread{} = thread) do
    query =
      from(tp in ThreadParticipant,
        where: tp.thread_id == ^thread.id,
        where: tp.user_id == ^user_id,
        where: tp.is_active == true
      )

    case Repo.one(query) do
      nil -> {:error, :forbidden}
      _participant -> :ok
    end
  end

  # -- Internal helpers ------------------------------------------------------

  defp apply_single_change(%Thread{} = thread, change, user_id) do
    with {:ok, normalized} <- validate_cdc_log(change),
         {:ok, result} <- execute_cdc_operation(thread, normalized, user_id) do
      {:ok, result}
    end
  end

  defp validate_cdc_log(change) do
    required_fields = ["table_name", "record_id", "operation", "new_data"]

    missing_fields =
      required_fields
      |> Enum.reject(fn field ->
        Map.has_key?(change, field) or Map.has_key?(change, String.to_atom(field))
      end)

    if missing_fields == [] do
      {:ok,
       %{
         table_name: get_field(change, "table_name"),
         record_id: get_field(change, "record_id"),
         operation: get_field(change, "operation"),
         old_data: get_field(change, "old_data"),
         new_data: get_field(change, "new_data"),
         timestamp: parse_timestamp(change)
       }}
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp parse_timestamp(change) do
    case get_field(change, "timestamp") do
      nil ->
        DateTime.utc_now()

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
          _ -> DateTime.utc_now() |> DateTime.truncate(:second)
        end

      %DateTime{} = datetime ->
        DateTime.truncate(datetime, :second)

      _ ->
        DateTime.utc_now() |> DateTime.truncate(:second)
    end
  end

  defp get_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  end

  defp execute_cdc_operation(%Thread{} = thread, change, user_id) do
    repo = Repo

    case change.table_name do
      "messages" -> apply_message_operation(repo, thread, change, user_id)
      _ -> {:error, "Unsupported table: #{change.table_name}"}
    end
  end

  defp apply_message_operation(repo, thread, change, user_id) do
    case change.operation do
      op when op in ["INSERT", "insert"] ->
        create_message_from_cdc(repo, thread, change.new_data, user_id, change.timestamp)

      op when op in ["UPDATE", "update"] ->
        update_message_from_cdc(
          repo,
          thread,
          change.record_id,
          change.new_data,
          user_id,
          change.timestamp
        )

      op when op in ["DELETE", "delete"] ->
        delete_message_from_cdc(
          repo,
          thread,
          change.record_id,
          change.new_data,
          user_id,
          change.timestamp
        )

      _ ->
        {:error, "Invalid operation: #{change.operation}"}
    end
  end

  defp create_message_from_cdc(repo, thread, new_data, _user_id, timestamp) do
    attrs =
      new_data
      |> atomize_keys()
      |> normalize_uuid(:id)
      |> normalize_uuid(:sender_id)
      |> normalize_uuid(:reply_to_id)
      |> Map.put(:thread_id, thread.id)
      |> normalize_datetimes([:client_created_at, :inserted_at, :updated_at])
      |> ensure_timestamp_fields(timestamp)
      |> Map.put_new(:content_type, "text")

    message_struct =
      case attrs[:id] do
        nil -> %Message{}
        uuid -> %Message{id: uuid}
      end

    changeset = Message.create_changeset(message_struct, attrs)

    case repo.insert(changeset) do
      {:ok, message} ->
        GlobalbridgeBackend.Sync.CDCLogger.log_message_insert(thread, message,
          timestamp: timestamp
        )

        {:ok, message}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp update_message_from_cdc(repo, thread, record_id, new_data, user_id, timestamp) do
    case repo.get(Message, record_id) do
      nil ->
        {:error, "Message not found"}

      message ->
        old_snapshot = GlobalbridgeBackend.Sync.CDCLogger.message_to_map(thread, message)

        attrs =
          new_data
          |> atomize_keys()
          |> normalize_uuid(:reply_to_id)
          |> normalize_datetimes([:edited_at, :updated_at])
          |> Map.put_new(:updated_at, DateTime.truncate(timestamp || DateTime.utc_now(), :second))

        changeset = Message.edit_changeset(message, attrs)

        case repo.update(changeset) do
          {:ok, updated} ->
            GlobalbridgeBackend.Sync.CDCLogger.log_message_update(
              thread,
              updated,
              user_id: user_id,
              old_data: old_snapshot,
              timestamp: timestamp
            )

            {:ok, updated}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp delete_message_from_cdc(repo, thread, record_id, new_data, user_id, timestamp) do
    case repo.get(Message, record_id) do
      nil ->
        {:error, "Message not found"}

      message ->
        snapshot = GlobalbridgeBackend.Sync.CDCLogger.message_to_map(thread, message)

        attrs =
          new_data
          |> atomize_keys()
          |> normalize_datetimes([:deleted_at, :updated_at])
          |> Map.put_new(:updated_at, DateTime.truncate(timestamp || DateTime.utc_now(), :second))

        changeset = Message.delete_changeset(message, attrs)

        case repo.update(changeset) do
          {:ok, deleted} ->
            GlobalbridgeBackend.Sync.CDCLogger.log_message_delete(
              thread,
              deleted,
              user_id: user_id,
              old_data: snapshot,
              timestamp: timestamp
            )

            {:ok, deleted}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_uuid(attrs, field) do
    Map.update(attrs, field, nil, fn
      nil ->
        nil

      value when is_binary(value) ->
        case Ecto.UUID.cast(value) do
          {:ok, uuid} -> uuid
          :error -> value
        end

      value ->
        value
    end)
  end

  defp normalize_datetimes(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      case Map.get(acc, field) do
        nil ->
          acc

        %DateTime{} = dt ->
          Map.put(acc, field, DateTime.truncate(dt, :second))

        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, dt, _} -> Map.put(acc, field, DateTime.truncate(dt, :second))
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp format_error(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_error(error) when is_binary(error), do: error
  defp format_error(error) when is_atom(error), do: Atom.to_string(error)
  defp format_error(error), do: inspect(error)

  defp format_timestamp(nil), do: nil
  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_timestamp(timestamp), do: timestamp

  defp ensure_timestamp_fields(attrs, timestamp) do
    trimmed = DateTime.truncate(timestamp || DateTime.utc_now(), :second)

    attrs
    |> Map.put_new(:inserted_at, trimmed)
    |> Map.put_new(:updated_at, trimmed)
  end
end
