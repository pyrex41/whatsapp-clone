defmodule GlobalbridgeBackend.Repos.ThreadRepo do
  @moduledoc """
  Dynamic repository manager for per-thread databases.
  Handles creation and retrieval of database connections for thread shards.
  """

  @doc """
  Gets or creates a repository for a specific thread shard.

  Thread databases are stored in: priv/threads/{shard_id}.db

  ## Examples

      iex> get_repo("abc-123-def")
      GlobalbridgeBackend.Repos.ThreadRepo.Shard_abc_123_def
  """
  def get_repo(shard_id) do
    repo_name = repo_module_name(shard_id)

    # Check if repo is already started
    case Process.whereis(repo_name) do
      nil ->
        # Start the repo dynamically
        start_repo(shard_id)
        repo_name

      _pid ->
        repo_name
    end
  end

  @doc """
  Starts a dynamic repository for a thread shard.
  """
  def start_repo(shard_id) do
    repo_name = repo_module_name(shard_id)
    db_path = database_path(shard_id)

    # Ensure the threads directory exists
    ensure_threads_directory()

    # Define the repo module dynamically with config
    repo_config = [
      adapter: Ecto.Adapters.SQLite3,
      database: db_path,
      pool_size: 5,
      name: repo_name
    ]

    # Start the repo directly without dynamic module definition
    # The repo module is created on-demand by Supervisor
    case DynamicSupervisor.start_child(
           GlobalbridgeBackend.DynamicRepoSupervisor,
           {Ecto.Repo, [otp_app: :globalbridge_backend] ++ repo_config}
         ) do
      {:ok, _pid} ->
        # Run migrations on the new database
        run_thread_migrations(repo_name)
        {:ok, repo_name}

      {:error, {:already_started, _pid}} ->
        {:ok, repo_name}

      error ->
        error
    end
  end

  @doc """
  Stops a dynamic repository for a thread shard.
  """
  def stop_repo(shard_id) do
    repo_name = repo_module_name(shard_id)

    case Process.whereis(repo_name) do
      nil -> :ok
      _pid -> Supervisor.stop(repo_name)
    end
  end

  @doc """
  Returns the database file path for a thread shard.
  """
  def database_path(shard_id) do
    Path.join([
      Application.app_dir(:globalbridge_backend),
      "priv",
      "threads",
      "#{shard_id}.db"
    ])
  end

  @doc """
  Lists all active thread repositories.
  """
  def list_active_repos do
    Application.get_env(:globalbridge_backend, :thread_repos, [])
  end

  # Private functions

  defp repo_module_name(shard_id) do
    # Convert shard_id to a valid module name
    # Replace hyphens with underscores
    sanitized_id = String.replace(shard_id, "-", "_")
    Module.concat([GlobalbridgeBackend.Repos.ThreadRepo, "Shard_#{sanitized_id}"])
  end

  defp ensure_threads_directory do
    threads_dir =
      Path.join([
        Application.app_dir(:globalbridge_backend),
        "priv",
        "threads"
      ])

    File.mkdir_p!(threads_dir)
  end

  defp run_thread_migrations(repo) do
    # Run the messages table migration
    migrations_path =
      Path.join([
        Application.app_dir(:globalbridge_backend),
        "priv",
        "repo",
        "migrations",
        "thread_migrations"
      ])

    if File.dir?(migrations_path) do
      Ecto.Migrator.run(repo, migrations_path, :up, all: true)
    else
      # Create the messages table directly if no migrations exist
      create_messages_table(repo)
      create_read_receipts_table(repo)
    end
  end

  defp create_messages_table(repo) do
    # SQL to create messages table
    sql = """
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      thread_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      content TEXT,
      content_type TEXT NOT NULL,
      media_url TEXT,
      media_size INTEGER,
      media_mime_type TEXT,
      is_encrypted BOOLEAN DEFAULT 0,
      encryption_key_id TEXT,
      reply_to_id TEXT,
      is_deleted BOOLEAN DEFAULT 0,
      deleted_at TEXT,
      edited_at TEXT,
      client_created_at TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS messages_thread_id_index ON messages(thread_id);
    CREATE INDEX IF NOT EXISTS messages_sender_id_index ON messages(sender_id);
    CREATE INDEX IF NOT EXISTS messages_inserted_at_index ON messages(inserted_at);
    CREATE INDEX IF NOT EXISTS messages_content_type_index ON messages(content_type);
    """

    Ecto.Adapters.SQL.query!(repo, sql)
  end

  defp create_read_receipts_table(repo) do
    # SQL to create read_receipts table
    sql = """
    CREATE TABLE IF NOT EXISTS read_receipts (
      id TEXT PRIMARY KEY,
      message_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      read_at TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(message_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS read_receipts_message_id_index ON read_receipts(message_id);
    CREATE INDEX IF NOT EXISTS read_receipts_user_id_index ON read_receipts(user_id);
    """

    Ecto.Adapters.SQL.query!(repo, sql)
  end
end
