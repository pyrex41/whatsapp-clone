defmodule Mix.Tasks.MigrateVectorDimensions do
  @moduledoc """
  Migrates all vector embedding tables from 3072 to 1536 dimensions.

  This task:
  1. Finds all thread databases
  2. Drops the old vector tables (message_embeddings, user_style_embeddings, feedback_embeddings)
  3. Recreates them with correct 1536 dimensions using VectorStore functions

  Usage:
      mix migrate_vector_dimensions
  """
  use Mix.Task

  require Logger

  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.AI.VectorStore

  @shortdoc "Migrate vector tables from 3072 to 1536 dimensions"

  def run(_args) do
    # Start necessary applications
    Mix.Task.run("app.start")

    Logger.info("🔧 Starting vector dimension migration...")
    Logger.info("")

    # Find all thread database files
    thread_dir = Path.join([File.cwd!(), "priv", "threads"])
    db_files = Path.wildcard(Path.join(thread_dir, "*.db"))

    total = length(db_files)
    Logger.info("📊 Found #{total} thread databases")
    Logger.info("")

    Enum.with_index(db_files, 1)
    |> Enum.each(fn {db_path, index} ->
      # Extract shard_id from filename (remove .db extension)
      shard_id = Path.basename(db_path, ".db")

      Logger.info("[#{index}/#{total}] 🔨 Migrating #{shard_id}...")

      migrate_shard(shard_id)
    end)

    Logger.info("")
    Logger.info("✅ Vector dimension migration complete!")
    Logger.info("")
  end

  defp migrate_shard(shard_id) do
    # Get the repo for this shard
    repo = ThreadRepo.get_repo(shard_id)

    # Drop all three vector tables
    drop_table(repo, "message_embeddings")
    drop_table(repo, "user_style_embeddings")
    drop_table(repo, "feedback_embeddings")

    # Recreate with correct dimensions using VectorStore
    VectorStore.create_embeddings_table(repo)
    VectorStore.create_user_style_table(repo)
    VectorStore.create_feedback_table(repo)

    Logger.info("  ✅ Migrated to 1536 dimensions")
  rescue
    e ->
      Logger.error("  ❌ Failed: #{inspect(e)}")
  end

  defp drop_table(repo, table_name) do
    sql = "DROP TABLE IF EXISTS #{table_name};"

    case Ecto.Adapters.SQL.query(repo, sql) do
      {:ok, _} ->
        :ok
      {:error, %Exqlite.Error{message: message}} ->
        if String.contains?(String.downcase(message), "no such module: vec0") do
          Logger.warning("  ⚠️  sqlite-vec not available for #{table_name}")
          :ok
        else
          Logger.error("  ❌ Failed to drop #{table_name}: #{message}")
          {:error, message}
        end
      {:error, reason} ->
        Logger.error("  ❌ Failed to drop #{table_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
