defmodule GlobalbridgeBackend.Repo do
  use Ecto.Repo,
    otp_app: :globalbridge_backend,
    adapter: Ecto.Adapters.SQLite3

  @moduledoc """
  Main repository for GlobalBridge backend using SQLite.

  ## WAL Mode

  This repository automatically enables Write-Ahead Logging (WAL) mode for better
  concurrency. WAL mode allows multiple readers and one writer simultaneously,
  which is essential for Oban job queues and concurrent requests.

  The WAL mode configuration is applied via `after_connect/1` callback on every
  database connection.
  """

  @doc """
  Called after a connection is established to the database.

  Enables WAL mode and optimizes SQLite settings for concurrent access.
  This is idempotent and safe to run on every connection.
  """
  def after_connect(conn) do
    # Enable WAL mode for better concurrency
    Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode=WAL;")

    # Set busy timeout to 10 seconds (allows waiting for locked database)
    Exqlite.Sqlite3.execute(conn, "PRAGMA busy_timeout=10000;")

    # Use NORMAL synchronous mode (faster writes, still safe with WAL)
    Exqlite.Sqlite3.execute(conn, "PRAGMA synchronous=NORMAL;")

    # Set cache size to 64MB for better performance
    Exqlite.Sqlite3.execute(conn, "PRAGMA cache_size=-64000;")

    # Use memory for temporary tables
    Exqlite.Sqlite3.execute(conn, "PRAGMA temp_store=MEMORY;")

    :ok
  end
end
