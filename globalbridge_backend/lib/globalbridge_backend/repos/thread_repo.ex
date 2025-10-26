defmodule GlobalbridgeBackend.Repos.ThreadRepo do
  @moduledoc """
  Dynamic repository manager for per-thread databases.
  Handles creation and retrieval of database connections for thread shards.

  Uses unified Cache module (Cachex) for repository caching with 24 hour TTL.
  """

  require Logger

  alias GlobalbridgeBackend.AI.Cache

  @doc """
  Gets or creates a repository for a specific thread shard.

  Thread databases are stored in: priv/threads/{shard_id}.db
  Each database includes vector storage with sqlite-vec extension.

  ## Examples

      iex> get_repo("abc-123-def")
      GlobalbridgeBackend.Repos.ThreadRepo.Shard_abc_123_def
  """
  def get_repo(shard_id) do
    repo_module = repo_module_name(shard_id)

    # Check cache first for faster lookups
    case Cache.get_repo(shard_id) do
      nil ->
        # Check active repos list via application env
        active_repos = list_active_repos()

        if repo_module in active_repos do
          # Cache the result for faster future lookups
          Cache.put_repo(shard_id, repo_module)
          repo_module
        else
          # Start the repo and add to active list
          {:ok, _} = start_repo(shard_id)
          Cache.put_repo(shard_id, repo_module)
          repo_module
        end

      cached_repo ->
        cached_repo
    end
  end

  @doc """
  Starts a dynamic repository for a thread shard with sqlite-vec extension.
  """
  def start_repo(shard_id) do
    repo_module = repo_module_name(shard_id)
    db_path = database_path(shard_id)

    # Define the dynamic repo module
    # Prefer loading sqlite-vec via Exqlite's built-in load_extensions hook so the
    # extension is available before any schema initialization or queries run.
    vec_extension_path = get_vec_extension_path()

    load_extension_opts =
      if File.exists?(vec_extension_path) do
        [load_extensions: [vec_extension_path]]
      else
        []
      end

    repo_config =
      [
        adapter: Ecto.Adapters.SQLite3,
        database: db_path,
        # Single connection per thread DB
        pool_size: 1,
        show_sensitive_data_on_connection_error: false
      ] ++ load_extension_opts

    # Create child spec with the repo module and config as two separate arguments
    child_spec = %{
      id: repo_module,
      start: {repo_module, :start_link, [repo_config]},
      type: :supervisor
    }

    case DynamicSupervisor.start_child(
           GlobalbridgeBackend.DynamicRepoSupervisor,
           child_spec
         ) do
      {:ok, _pid} ->
        # Add to active repos list
        active_repos = list_active_repos()
        Application.put_env(:globalbridge_backend, :thread_repos, [repo_module | active_repos])

        # Run migrations if needed
        run_thread_migrations(repo_module)

        {:ok, repo_module}

      {:error, {:already_started, _pid}} ->
        {:ok, repo_module}

      error ->
        error
    end
  end

  @doc """
  Stops a dynamic repository for a thread shard.
  """
  def stop_repo(shard_id) do
    repo_module = repo_module_name(shard_id)

    # Remove from cache
    Cache.uncache_repo(shard_id)

    # Remove from active repos list
    active_repos = list_active_repos()
    updated_repos = List.delete(active_repos, repo_module)
    Application.put_env(:globalbridge_backend, :thread_repos, updated_repos)

    # Stop the repo process
    case Process.whereis(repo_module) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(GlobalbridgeBackend.DynamicRepoSupervisor, pid)
    end
  end

  @doc """
  Returns the database file path for a thread shard.
  Sanitizes shard_id to prevent path traversal attacks.
  """
  def database_path(shard_id) do
    # Sanitize shard_id to prevent path traversal
    sanitized_id = sanitize_shard_id(shard_id)

    thread_dir =
      System.get_env("THREAD_DATABASE_DIR") ||
        Path.join([
          Application.app_dir(:globalbridge_backend),
          "priv",
          "threads"
        ])

    # Ensure the directory exists
    File.mkdir_p!(thread_dir)

    Path.join([thread_dir, "#{sanitized_id}.db"])
  end

  @doc """
  Sanitizes a shard_id to prevent path traversal attacks.
  Only allows alphanumeric characters, hyphens, and underscores.
  Rejects any path-like input containing slashes or dots.
  """
  def sanitize_shard_id(shard_id) when is_binary(shard_id) do
    # First check if the input contains path separators or traversal patterns
    # This prevents any path-like input from being accepted
    if String.contains?(shard_id, ["/", "\\", ".."]) do
      raise ArgumentError, "Invalid shard_id: must not contain path separators or traversal patterns"
    end

    # Validate the shard_id contains only safe characters
    unless String.match?(shard_id, ~r/^[a-zA-Z0-9_-]+$/) do
      raise ArgumentError, "Invalid shard_id: must contain only alphanumeric characters, hyphens, and underscores"
    end

    shard_id
  end

  def sanitize_shard_id(_) do
    raise ArgumentError, "shard_id must be a string"
  end

  @doc """
  Lists all active thread repositories.
  """
  def list_active_repos do
    Application.get_env(:globalbridge_backend, :thread_repos, [])
  end

  @doc """
  Loads the sqlite-vec extension for vector operations.
  Called after database connection is established.
  """
  def load_vec_extension(conn) do
    # Determine the path to the sqlite-vec extension
    vec_extension_path = get_vec_extension_path()

    # Load the extension if the file exists
    if File.exists?(vec_extension_path) do
      # Note: This function can be kept as a fallback, but Exqlite's
      # load_extensions option now handles loading at connect time.
      # We avoid issuing SQL through Ecto.Adapters.SQL with the raw
      # DBConnection struct (which previously caused a MatchError).
      Logger.debug("sqlite-vec path detected at #{vec_extension_path}; relying on load_extensions option")
      :ok
    else
      # Extension not found - log warning but continue
      Logger.warning(
        "sqlite-vec extension not found at #{vec_extension_path}. Vector operations may not work properly."
      )

      :ok
    end
  end

  # Private function to determine the sqlite-vec extension path
  defp get_vec_extension_path do
    # Check for environment variable first
    case System.get_env("SQLITE_VEC_PATH") do
      nil ->
        # Default system paths based on platform
        case :os.type() do
          {:unix, :darwin} ->
            # macOS - check common Homebrew locations
            [
              "/opt/homebrew/lib/vec0.dylib",
              "/usr/local/lib/vec0.dylib",
              "/opt/me/lib/vec0.dylib",
              "/usr/lib/vec0.dylib"
            ]
            |> Enum.find(&File.exists?/1)
            # fallback to most common location
            |> Kernel.||("/opt/homebrew/lib/vec0.dylib")

          {:unix, _} ->
            # Linux - check common system locations
            [
              "/usr/lib/x86_64-linux-gnu/vec0.so",
              "/usr/local/lib/vec0.so",
              "/usr/lib/vec0.so"
            ]
            |> Enum.find(&File.exists?/1)
            # fallback to most common location
            |> Kernel.||("/usr/lib/x86_64-linux-gnu/vec0.so")

          {:win32, _} ->
            # Windows
            [
              "C:/Program Files/sqlite-vec/vec0.dll",
              "C:/sqlite-vec/vec0.dll"
            ]
            |> Enum.find(&File.exists?/1)
            # fallback
            |> Kernel.||("C:/Program Files/sqlite-vec/vec0.dll")
        end

      path ->
        path
    end
  end

  # Private functions

  defp repo_module_name(shard_id) do
    # Create a unique module name for this shard
    # Convert shard_id to valid Elixir module name
    clean_shard_id = String.replace(shard_id, ~r/[^a-zA-Z0-9_]/, "_")
    module_name = Module.concat([GlobalbridgeBackend.Repos.ThreadRepo, "Shard_#{clean_shard_id}"])

    # Define the module dynamically if it doesn't exist
    unless Code.ensure_loaded?(module_name) do
      {:module, _module, _binary, _term} =
        Module.create(
          module_name,
          quote do
            use Ecto.Repo,
              otp_app: :globalbridge_backend,
              adapter: Ecto.Adapters.SQLite3
          end,
          Macro.Env.location(__ENV__)
        )
    end

    module_name
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

    # Ensure runtime columns/indexes exist even when migrations were used
    ensure_column(repo, "messages", "client_message_id", "TEXT")
    ensure_index(repo, "messages_client_message_id_index", "CREATE INDEX IF NOT EXISTS messages_client_message_id_index ON messages(client_message_id)")

    # Always create vector tables for embeddings and feedback
    GlobalbridgeBackend.AI.VectorStore.create_embeddings_table(repo)
    GlobalbridgeBackend.AI.VectorStore.create_feedback_table(repo)
  end

  @doc """
  If a per-thread database has zero messages but the main shared DB has
  historical messages for the thread, backfill them into the shard DB.

  Idempotent: uses INSERT OR IGNORE on message id to avoid duplicates.
  """
  def maybe_backfill_from_main(repo, thread_id) do
    with {:ok, %{rows: [[count]]}} <- Ecto.Adapters.SQL.query(repo, "SELECT COUNT(*) FROM messages", []),
         true <- count == 0 do
      backfill_messages(repo, thread_id)
    else
      _ -> :ok
    end
  end

  defp backfill_messages(repo, thread_id) do
    require Logger
    alias GlobalbridgeBackend.{Repo, Schemas.Message}
    import Ecto.Query

    messages =
      Repo.all(
        from m in Message,
          where: m.thread_id == ^thread_id,
          order_by: [asc: m.inserted_at]
      )

    if messages == [] do
      :ok
    else
      Logger.info("Backfilling #{length(messages)} messages into shard DB for thread #{thread_id}")

      Enum.each(messages, fn m ->
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
          bool_to_int(m.is_encrypted),
          m.encryption_key_id,
          m.reply_to_id,
          bool_to_int(m.is_deleted),
          dt_to_text(m.deleted_at),
          dt_to_text(m.edited_at),
          dt_to_text(m.client_created_at),
          dt_to_text(m.inserted_at) || DateTime.to_iso8601(DateTime.utc_now()),
          dt_to_text(m.updated_at) || DateTime.to_iso8601(DateTime.utc_now())
        ]

        case Ecto.Adapters.SQL.query(repo, sql, params) do
          {:ok, _} -> :ok
          {:error, err} -> Logger.error("Backfill insert failed: #{inspect(err)}")
        end
      end)

      :ok
    end
  end

  defp bool_to_int(nil), do: 0
  defp bool_to_int(true), do: 1
  defp bool_to_int(false), do: 0

  defp dt_to_text(nil), do: nil
  defp dt_to_text(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"
  defp dt_to_text(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

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
      client_message_id TEXT,
      -- Embedding metadata (to align with main Repo schema)
      embedding BLOB,
      embedding_model TEXT DEFAULT 'text-embedding-3-large',
      embedding_generated_at INTEGER,
      -- Language detection for translation
      detected_language TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS messages_thread_id_index ON messages(thread_id);
    CREATE INDEX IF NOT EXISTS messages_sender_id_index ON messages(sender_id);
    CREATE INDEX IF NOT EXISTS messages_inserted_at_index ON messages(inserted_at);
    CREATE INDEX IF NOT EXISTS messages_content_type_index ON messages(content_type);
    CREATE INDEX IF NOT EXISTS messages_client_message_id_index ON messages(client_message_id);
    CREATE INDEX IF NOT EXISTS messages_detected_language_index ON messages(detected_language);
    """

    Ecto.Adapters.SQL.query!(repo, sql)

    # Backward-compatible upgrades for older DBs
    ensure_column(repo, "messages", "client_message_id", "TEXT")
    ensure_index(repo, "messages_client_message_id_index", "CREATE INDEX IF NOT EXISTS messages_client_message_id_index ON messages(client_message_id)")
  end

  defp ensure_column(repo, table, column, type) do
    case Ecto.Adapters.SQL.query(repo, "PRAGMA table_info(#{table})", []) do
      {:ok, %{rows: rows}} ->
        has_column = Enum.any?(rows, fn [_cid, name | _] -> name == column end)
        unless has_column do
          Ecto.Adapters.SQL.query!(repo, "ALTER TABLE #{table} ADD COLUMN #{column} #{type}", [])
        end
      _ -> :ok
    end
  end

  defp ensure_index(repo, index_name, create_sql) do
    case Ecto.Adapters.SQL.query(repo, "PRAGMA index_list(messages)", []) do
      {:ok, %{rows: rows}} ->
        has_index = Enum.any?(rows, fn [_seq, name | _] -> name == index_name end)
        unless has_index do
          Ecto.Adapters.SQL.query!(repo, create_sql, [])
        end
      _ -> :ok
    end
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
