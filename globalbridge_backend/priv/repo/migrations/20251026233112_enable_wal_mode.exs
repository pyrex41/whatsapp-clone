defmodule GlobalbridgeBackend.Repo.Migrations.EnableWalMode do
  use Ecto.Migration

  @moduledoc """
  Enable SQLite WAL (Write-Ahead Logging) mode for better concurrency.

  WAL mode allows multiple readers and one writer to access the database simultaneously,
  which is essential for Oban job queues and concurrent requests.

  This migration is idempotent - it can be run multiple times safely.
  """

  def up do
    execute("PRAGMA journal_mode=WAL;")
    execute("PRAGMA busy_timeout=10000;")  # 10 second busy timeout
    execute("PRAGMA synchronous=NORMAL;")  # Faster writes, still safe with WAL
    execute("PRAGMA cache_size=-64000;")   # 64MB cache
    execute("PRAGMA temp_store=MEMORY;")   # Use RAM for temp tables

    IO.puts("\n✅ SQLite WAL mode enabled:")
    IO.puts("   - journal_mode: WAL (better concurrency)")
    IO.puts("   - busy_timeout: 10000ms (10 seconds)")
    IO.puts("   - synchronous: NORMAL (balanced safety/speed)")
    IO.puts("   - cache_size: 64MB")
    IO.puts("   - temp_store: MEMORY\n")
  end

  def down do
    # Reverting to DELETE mode (default) - generally not needed
    execute("PRAGMA journal_mode=DELETE;")
    IO.puts("\n⚠️  Reverted to DELETE journal mode (default SQLite behavior)")
  end
end
