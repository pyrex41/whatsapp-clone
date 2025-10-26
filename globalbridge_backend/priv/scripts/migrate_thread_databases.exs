# Script to add translation fields to all thread databases
# Run with: mix run priv/scripts/migrate_thread_databases.exs

require Logger

# SQL to add translation columns
migration_sql = [
  "ALTER TABLE messages ADD COLUMN original_content TEXT;",
  "ALTER TABLE messages ADD COLUMN translated_content TEXT;",
  "ALTER TABLE messages ADD COLUMN source_language TEXT;",
  "ALTER TABLE messages ADD COLUMN target_language TEXT;",
  "ALTER TABLE messages ADD COLUMN is_translated INTEGER DEFAULT 0;"
]

# Get all threads
threads = GlobalbridgeBackend.Repo.all(GlobalbridgeBackend.Schemas.Thread)

Logger.info("[MIGRATION] Found #{length(threads)} thread databases to migrate")

results = Enum.map(threads, fn thread ->
  try do
    repo = GlobalbridgeBackend.Repos.ThreadRepo.get_repo(thread.database_shard_id)

    # Check if columns exist
    {:ok, %{rows: rows}} = repo.query("PRAGMA table_info(messages)")
    existing_columns = Enum.map(rows, fn [_cid, name, _type, _notnull, _dflt_value, _pk] -> name end)

    translation_columns = ["original_content", "translated_content", "source_language", "target_language", "is_translated"]
    missing_columns = translation_columns -- existing_columns

    if length(missing_columns) == 0 do
      Logger.info("[MIGRATION] ✅ Thread #{thread.id}: Already has all translation columns")
      {:ok, :already_migrated}
    else
      Logger.info("[MIGRATION] 🔄 Thread #{thread.id}: Adding #{length(missing_columns)} columns...")

      # Run each SQL statement
      results = Enum.map(migration_sql, fn sql ->
        case repo.query(sql) do
          {:ok, _} -> :ok
          {:error, %{sqlite: %{message: "duplicate column name" <> _}}} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end)

      if Enum.all?(results, &(&1 == :ok)) do
        Logger.info("[MIGRATION] ✅ Thread #{thread.id}: Successfully migrated")
        {:ok, :migrated}
      else
        errors = Enum.filter(results, &match?({:error, _}, &1))
        Logger.error("[MIGRATION] ❌ Thread #{thread.id}: Migration failed: #{inspect(errors)}")
        {:error, errors}
      end
    end
  rescue
    error ->
      Logger.error("[MIGRATION] ❌ Thread #{thread.id}: Exception: #{inspect(error)}")
      {:error, error}
  end
end)

success_count = Enum.count(results, &match?({:ok, _}, &1))
error_count = Enum.count(results, &match?({:error, _}, &1))

Logger.info("[MIGRATION] ✅ Complete: #{success_count} succeeded, #{error_count} failed")
IO.puts("\n=== Migration Summary ===")
IO.puts("Total threads: #{length(threads)}")
IO.puts("Successfully migrated: #{success_count}")
IO.puts("Errors: #{error_count}")
