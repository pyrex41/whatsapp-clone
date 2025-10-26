defmodule GlobalbridgeBackend.Migrations.ThreadDatabaseMigrationRunner do
  @moduledoc """
  Utility for applying migrations to existing thread databases.

  Since messages are stored in per-thread SQLite databases, schema changes
  need to be applied to all existing thread databases.
  """

  require Logger
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.Thread
  alias GlobalbridgeBackend.Repos.ThreadRepo

  @doc """
  Applies the translation fields migration to all existing thread databases.

  This adds:
  - original_content TEXT
  - translated_content TEXT
  - source_language TEXT
  - target_language TEXT
  - is_translated BOOLEAN

  Safe to run multiple times (uses IF NOT EXISTS).
  """
  def add_translation_fields_to_all_threads do
    threads = Repo.all(Thread)

    Logger.info("[MIGRATION] Applying translation fields to #{length(threads)} thread databases")

    results = Enum.map(threads, fn thread ->
      apply_translation_migration(thread)
    end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))
    error_count = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("[MIGRATION] Complete: #{success_count} succeeded, #{error_count} failed")

    {:ok, %{success: success_count, errors: error_count, results: results}}
  end

  @doc """
  Applies translation migration to a single thread database.
  """
  def apply_translation_migration(%Thread{} = thread) do
    try do
      repo = ThreadRepo.get_repo(thread.database_shard_id)

      # Check if columns already exist
      check_query = """
      SELECT COUNT(*) as count
      FROM pragma_table_info('messages')
      WHERE name IN ('original_content', 'translated_content', 'source_language', 'target_language', 'is_translated')
      """

      case repo.query(check_query) do
        {:ok, %{rows: [[count]]}} when count == 5 ->
          Logger.debug("[MIGRATION] Thread #{thread.id}: translation fields already exist")
          {:ok, :already_migrated}

        {:ok, %{rows: [[count]]}} when count > 0 and count < 5 ->
          Logger.warning("[MIGRATION] Thread #{thread.id}: partial migration detected (#{count}/5 fields)")
          run_migration_sql(repo, thread.id)

        {:ok, _} ->
          run_migration_sql(repo, thread.id)

        {:error, reason} ->
          Logger.error("[MIGRATION] Thread #{thread.id}: failed to check columns: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("[MIGRATION] Thread #{thread.id}: exception: #{inspect(error)}")
        {:error, error}
    end
  end

  defp run_migration_sql(repo, thread_id) do
    migration_statements = [
      "ALTER TABLE messages ADD COLUMN original_content TEXT;",
      "ALTER TABLE messages ADD COLUMN translated_content TEXT;",
      "ALTER TABLE messages ADD COLUMN source_language TEXT;",
      "ALTER TABLE messages ADD COLUMN target_language TEXT;",
      "ALTER TABLE messages ADD COLUMN is_translated INTEGER DEFAULT 0;"
    ]

    results = Enum.map(migration_statements, fn sql ->
      case repo.query(sql) do
        {:ok, _} -> :ok
        {:error, %{sqlite: %{message: "duplicate column name" <> _}}} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)

    if Enum.all?(results, &(&1 == :ok)) do
      Logger.info("[MIGRATION] Thread #{thread_id}: successfully added translation fields")
      {:ok, :migrated}
    else
      errors = Enum.filter(results, &match?({:error, _}, &1))
      Logger.error("[MIGRATION] Thread #{thread_id}: migration errors: #{inspect(errors)}")
      {:error, errors}
    end
  end

  @doc """
  Verifies that all thread databases have translation fields.

  Returns {:ok, stats} or {:error, missing_threads}.
  """
  def verify_translation_fields do
    threads = Repo.all(Thread)

    results = Enum.map(threads, fn thread ->
      repo = ThreadRepo.get_repo(thread.database_shard_id)

      check_query = """
      SELECT COUNT(*) as count
      FROM pragma_table_info('messages')
      WHERE name IN ('original_content', 'translated_content', 'source_language', 'target_language', 'is_translated')
      """

      case repo.query(check_query) do
        {:ok, %{rows: [[5]]}} -> {:ok, thread.id}
        {:ok, %{rows: [[count]]}} -> {:missing, thread.id, count}
        {:error, reason} -> {:error, thread.id, reason}
      end
    end)

    missing = Enum.filter(results, &match?({:missing, _, _}, &1))
    errors = Enum.filter(results, &match?({:error, _, _}, &1))
    ok = Enum.count(results, &match?({:ok, _}, &1))

    stats = %{
      total: length(threads),
      complete: ok,
      missing: length(missing),
      errors: length(errors)
    }

    Logger.info("[VERIFY] Translation fields: #{inspect(stats)}")

    if length(missing) > 0 || length(errors) > 0 do
      {:error, %{stats: stats, missing: missing, errors: errors}}
    else
      {:ok, stats}
    end
  end
end
