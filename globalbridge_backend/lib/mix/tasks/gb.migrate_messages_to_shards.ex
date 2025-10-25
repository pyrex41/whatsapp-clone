defmodule Mix.Tasks.Gb.MigrateMessagesToShards do
  @moduledoc """
  Migrates legacy message rows from the main users.db to per-thread shard databases.

  The current architecture stores thread metadata in users.db and message payloads
  in per-thread SQLite files (priv/threads/<shard>.db). Early development left
  some messages in users.db; this task backfills each thread's shard and (optionally)
  renames or drops the legacy table.

  Usage:

      mix gb.migrate_messages_to_shards [--dry-run] [--rename-legacy] [--drop-legacy]
                                        [--thread <thread_id>]...

  Options:
    --dry-run        Perform analysis only; prints what would change
    --rename-legacy  After successful migration, rename users.db messages -> messages_legacy
    --drop-legacy    After successful migration, drop users.db messages table (dangerous)
    --thread ID      Migrate only the specified thread(s); may be provided multiple times

  Notes:
    - Idempotent: uses INSERT OR IGNORE by message id in shard DBs
    - Preserves timestamps and content fields; embedding columns are left nil in shards
    - Run during a quiet window to minimize WAL contention
  """

  use Mix.Task
  require Logger
  import Ecto.Query

  alias GlobalbridgeBackend.{Repo}
  alias GlobalbridgeBackend.Schemas.{Message, Thread}
  alias GlobalbridgeBackend.Repos.ThreadRepo

  @shortdoc "Backfill messages from users.db to per-thread shard DBs"
  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        switches: [dry_run: :boolean, rename_legacy: :boolean, drop_legacy: :boolean, thread: :keep]
      )

    dry_run = opts[:dry_run] || false
    rename_legacy = opts[:rename_legacy] || false
    drop_legacy = opts[:drop_legacy] || false
    thread_filters = List.wrap(opts[:thread]) |> Enum.uniq()

    if rename_legacy and drop_legacy do
      Mix.raise("Use either --rename-legacy or --drop-legacy, not both")
    end

    threads = load_threads(thread_filters)
    total = length(threads)
    Mix.shell().info("Found #{total} thread(s) to process")

    {migrated, skipped, errors} =
      Enum.reduce(threads, {0, 0, 0}, fn thread, {mig, sk, err} ->
        case migrate_thread(thread, dry_run) do
          {:ok, :migrated} -> {mig + 1, sk, err}
          {:ok, :skipped} -> {mig, sk + 1, err}
          {:error, reason} ->
            Mix.shell().error("[ERROR] thread=#{thread.id} shard=#{thread.database_shard_id}: #{inspect(reason)}")
            {mig, sk, err + 1}
        end
      end)

    Mix.shell().info("Summary: migrated=#{migrated}, skipped=#{skipped}, errors=#{errors}")

    cond do
      dry_run -> :ok
      errors > 0 -> Mix.shell().info("Legacy table left intact due to errors")
      drop_legacy -> maybe_drop_legacy_messages_table()
      rename_legacy -> maybe_rename_legacy_messages_table()
      true -> :ok
    end
  end

  defp load_threads([]) do
    Repo.all(from t in Thread, order_by: [asc: t.inserted_at])
  end

  defp load_threads(ids) do
    Repo.all(from t in Thread, where: t.id in ^ids)
  end

  defp migrate_thread(%Thread{id: thread_id, database_shard_id: shard_id} = thread, dry_run) do
    users_count =
      Repo.one(from m in Message, where: m.thread_id == ^thread_id, select: count(m.id)) || 0

    shard_repo = ThreadRepo.get_repo(shard_id)

    shard_count =
      case Ecto.Adapters.SQL.query(shard_repo, "SELECT COUNT(*) FROM messages WHERE thread_id = ?", [thread_id]) do
        {:ok, %{rows: [[c]]}} -> c
        _ -> 0
      end

    cond do
      users_count == 0 and shard_count > 0 ->
        Mix.shell().info("[SKIP] thread=#{thread_id} shard=#{shard_id} (no legacy rows)")
        {:ok, :skipped}

      users_count == 0 and shard_count == 0 ->
        Mix.shell().info("[SKIP] thread=#{thread_id} shard=#{shard_id} (empty)")
        {:ok, :skipped}

      shard_count >= users_count ->
        Mix.shell().info("[SKIP] thread=#{thread_id} shard=#{shard_id} (already migrated: shard=#{shard_count} >= legacy=#{users_count})")
        {:ok, :skipped}

      true ->
        Mix.shell().info("[MIGRATE] thread=#{thread_id} shard=#{shard_id} legacy_rows=#{users_count} shard_rows=#{shard_count}")
        if dry_run do
          {:ok, :migrated}
        else
          do_backfill(thread, shard_repo)
        end
    end
  end

  defp do_backfill(%Thread{id: thread_id} = _thread, shard_repo) do
    # Stream messages from users.db to avoid big memory spikes
    query =
      from m in Message,
        where: m.thread_id == ^thread_id,
        order_by: [asc: m.inserted_at]

    Repo.transaction(fn ->
      Repo.stream(query)
      |> Enum.reduce(0, fn m, acc ->
        sql = """
        INSERT OR IGNORE INTO messages (
          id, thread_id, sender_id, content, content_type,
          media_url, media_size, media_mime_type,
          is_encrypted, encryption_key_id, reply_to_id,
          is_deleted, deleted_at, edited_at, client_created_at,
          inserted_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        params = [
          m.id,
          m.thread_id,
          m.sender_id,
          m.content,
          m.content_type,
          m.media_url,
          m.media_size,
          m.media_mime_type,
          bool_to_int(Map.get(m, :is_encrypted)),
          m.encryption_key_id,
          m.reply_to_id,
          bool_to_int(Map.get(m, :is_deleted)),
          dt_to_text(Map.get(m, :deleted_at)),
          dt_to_text(Map.get(m, :edited_at)),
          dt_to_text(Map.get(m, :client_created_at)),
          dt_to_text(Map.get(m, :inserted_at)) || DateTime.to_iso8601(DateTime.utc_now()),
          dt_to_text(Map.get(m, :updated_at)) || DateTime.to_iso8601(DateTime.utc_now())
        ]

        case Ecto.Adapters.SQL.query(shard_repo, sql, params) do
          {:ok, _} -> acc + 1
          {:error, err} ->
            Logger.error("Backfill insert failed for message #{m.id}: #{inspect(err)}")
            acc
        end
      end)
    end)
    |> case do
      {:ok, inserted} ->
        Mix.shell().info("[OK] thread=#{thread_id} inserted=#{inserted}")
        {:ok, :migrated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_rename_legacy_messages_table do
    case Ecto.Adapters.SQL.query(Repo, "ALTER TABLE messages RENAME TO messages_legacy", []) do
      {:ok, _} -> Mix.shell().info("Renamed users.db messages -> messages_legacy")
      {:error, e} -> Mix.shell().error("Rename failed: #{inspect(e)}")
    end
  end

  defp maybe_drop_legacy_messages_table do
    case Ecto.Adapters.SQL.query(Repo, "DROP TABLE IF EXISTS messages", []) do
      {:ok, _} -> Mix.shell().info("Dropped users.db messages table")
      {:error, e} -> Mix.shell().error("Drop failed: #{inspect(e)}")
    end
  end

  defp bool_to_int(nil), do: 0
  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0
  defp bool_to_int(v) when is_integer(v), do: if(v == 0, do: 0, else: 1)
  defp bool_to_int(_), do: 0

  defp dt_to_text(nil), do: nil
  defp dt_to_text(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"
  defp dt_to_text(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp dt_to_text(v) when is_binary(v), do: v
  defp dt_to_text(_), do: nil
end
