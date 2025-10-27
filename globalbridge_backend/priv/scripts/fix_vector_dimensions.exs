# Fix vector dimension mismatch for user_style_embeddings table
# Run with: mix run priv/scripts/fix_vector_dimensions.exs

require Logger

defmodule VectorDimensionFixer do
  @moduledoc """
  Drops and recreates user_style_embeddings table with correct dimensions (1536).

  The table was previously created with 3072 dimensions but should be 1536
  to match the text-embedding-3-large model output.
  """

  def fix_all_shards do
    Logger.info("Starting vector dimension fix for all shards...")

    # Get all shard databases
    shard_pattern = Application.get_env(:globalbridge_backend, :database_path_pattern)
    base_dir = Path.dirname(shard_pattern)

    # Find all shard database files
    shard_files = Path.wildcard(Path.join(base_dir, "shard_*.db"))

    Logger.info("Found #{length(shard_files)} shard databases")

    Enum.each(shard_files, fn shard_file ->
      fix_shard(shard_file)
    end)

    Logger.info("Vector dimension fix complete!")
  end

  defp fix_shard(shard_file) do
    Logger.info("Fixing #{Path.basename(shard_file)}...")

    # Connect to the shard database
    {:ok, conn} = Exqlite.Sqlite3.open(shard_file)

    try do
      # Drop the existing table
      case Exqlite.Sqlite3.execute(conn, "DROP TABLE IF EXISTS user_style_embeddings;") do
        :ok ->
          Logger.info("  Dropped existing table")
        {:error, reason} ->
          Logger.warning("  Could not drop table: #{inspect(reason)}")
      end

      # Recreate with correct dimensions
      create_sql = """
      CREATE VIRTUAL TABLE IF NOT EXISTS user_style_embeddings USING vec0(
        embedding_id TEXT PRIMARY KEY,
        user_id TEXT,
        style_aspect TEXT,
        embedding float[1536]
      );
      """

      case Exqlite.Sqlite3.execute(conn, create_sql) do
        :ok ->
          Logger.info("  ✅ Recreated table with 1536 dimensions")
        {:error, %Exqlite.Error{message: message}} ->
          if String.contains?(String.downcase(message), "no such module: vec0") do
            Logger.warning("  ⚠️  sqlite-vec not available, skipping")
          else
            Logger.error("  ❌ Failed to create table: #{message}")
          end
        {:error, reason} ->
          Logger.error("  ❌ Failed to create table: #{inspect(reason)}")
      end
    after
      Exqlite.Sqlite3.close(conn)
    end
  end
end

# Run the fix
VectorDimensionFixer.fix_all_shards()
