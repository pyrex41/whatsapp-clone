# SQLite WAL Mode Setup

## What Was Done

We've configured SQLite to use **Write-Ahead Logging (WAL) mode** to fix the "Database busy" errors you were experiencing with Oban job queues.

### Changes Made:

1. **Migration**: Created `20251026233112_enable_wal_mode.exs`
   - Enables WAL mode on database
   - Sets optimal SQLite pragmas for concurrency
   - Can be run safely multiple times (idempotent)

2. **Repo Module**: Updated `lib/globalbridge_backend/repo.ex`
   - Added `after_connect/1` callback
   - **Automatically applies WAL mode** on every database connection
   - Works in dev, test, and production

3. **Config Files**: Updated all environment configs
   - `config/dev.exs` - Development environment
   - `config/test.exs` - Test environment
   - `config/runtime.exs` - Production environment
   - All use `after_connect: {GlobalbridgeBackend.Repo, :after_connect, []}`

4. **Oban Concurrency**: Reduced queue limits
   - `default: 10 → 3` workers
   - `embeddings: 5 → 2` workers
   - `ai_processing: 3 → 1` worker
   - Total: 18 → 6 concurrent workers (safer for SQLite)

---

## How to Apply

### Step 1: Run the migration

```bash
cd globalbridge_backend
source .env  # Load Auth0 environment variables
mix ecto.migrate
```

You should see:
```
✅ SQLite WAL mode enabled:
   - journal_mode: WAL (better concurrency)
   - busy_timeout: 10000ms (10 seconds)
   - synchronous: NORMAL (balanced safety/speed)
   - cache_size: 64MB
   - temp_store: MEMORY
```

### Step 2: Verify WAL mode is active

```bash
sqlite3 priv/shared_dbs/users.db "PRAGMA journal_mode;"
```

Should output: `wal`

### Step 3: Restart your Phoenix server

```bash
# Kill any running server
pkill -f "beam.smp.*globalbridge"

# Start fresh
mix phx.server
```

---

## What is WAL Mode?

**WAL (Write-Ahead Logging)** changes how SQLite handles writes:

### Before (DELETE mode):
- ❌ Only **1 connection** can access database at a time (reader OR writer)
- ❌ Writers block all readers
- ❌ Readers block all writers
- ❌ **Result**: "Database busy" errors with Oban's 18 concurrent workers

### After (WAL mode):
- ✅ **Multiple readers** + **1 writer** can access database simultaneously
- ✅ Readers don't block writers
- ✅ Writers don't block readers
- ✅ **Result**: Oban job queue works smoothly

---

## Why This Fixes the "Database Busy" Error

Your error was:
```elixir
** (Exqlite.Error) Database busy
```

**Root Cause**: Oban was configured for 18 concurrent workers (10+5+3), but SQLite in DELETE mode only allows 1 connection at a time.

**Fix**:
1. WAL mode allows concurrent reads + 1 write
2. Reduced workers to 6 total (safer)
3. 10-second busy timeout (waits instead of failing)

---

## Benefits of WAL Mode

| Setting | Value | Benefit |
|---------|-------|---------|
| `journal_mode` | `WAL` | Multiple readers + 1 writer |
| `busy_timeout` | `10000ms` | Waits 10s for lock instead of failing |
| `synchronous` | `NORMAL` | Faster writes, still crash-safe with WAL |
| `cache_size` | `-64000` (64MB) | Faster queries |
| `temp_store` | `MEMORY` | Faster temp table operations |

---

## Automatic Setup on Every Connection

The `after_connect/1` callback in `Repo` ensures WAL mode is **always enabled**, even if:
- Database file is recreated
- Database is copied from another machine
- New connection pool is started

**Code**:
```elixir
# In lib/globalbridge_backend/repo.ex
def after_connect(conn) do
  Exqlite.Sqlite3.execute(conn, "PRAGMA journal_mode=WAL;")
  Exqlite.Sqlite3.execute(conn, "PRAGMA busy_timeout=10000;")
  # ... other optimizations
  :ok
end
```

**Config** (all environments):
```elixir
config :globalbridge_backend, GlobalbridgeBackend.Repo,
  database: "path/to/db.db",
  after_connect: {GlobalbridgeBackend.Repo, :after_connect, []}
```

---

## Testing

### Check current mode:
```bash
sqlite3 priv/shared_dbs/users.db "PRAGMA journal_mode;"
```

### Check busy timeout:
```bash
sqlite3 priv/shared_dbs/users.db "PRAGMA busy_timeout;"
```

### Check all settings:
```bash
sqlite3 priv/shared_dbs/users.db <<EOF
PRAGMA journal_mode;
PRAGMA busy_timeout;
PRAGMA synchronous;
PRAGMA cache_size;
PRAGMA temp_store;
EOF
```

Expected output:
```
wal
10000
1
-64000
2
```

---

## Production Considerations

### When to use SQLite + WAL:
- ✅ Single-server deployments
- ✅ Low-to-medium traffic (<100 concurrent users)
- ✅ Development and testing

### When to switch to PostgreSQL:
- ⚠️ Multi-server deployments (SQLite is local file, can't share)
- ⚠️ High traffic (>100 concurrent users)
- ⚠️ Heavy write workloads (Oban with many jobs/second)

**For production at scale**, consider migrating to PostgreSQL:
```bash
brew install postgresql@14
# Update config to use Ecto.Adapters.Postgres
```

---

## Rollback (if needed)

If you need to revert to DELETE mode:

```bash
mix ecto.rollback
```

Or manually:
```bash
sqlite3 priv/shared_dbs/users.db "PRAGMA journal_mode=DELETE;"
```

**Note**: You probably don't want to do this - WAL mode is better in almost all cases.

---

## Files Changed

```
globalbridge_backend/
├── priv/repo/migrations/
│   └── 20251026233112_enable_wal_mode.exs  (NEW)
├── lib/globalbridge_backend/
│   └── repo.ex  (UPDATED - added after_connect/1)
├── config/
│   ├── dev.exs  (UPDATED - added after_connect)
│   ├── test.exs  (UPDATED - added after_connect)
│   └── runtime.exs  (UPDATED - added after_connect + reduced Oban limits)
└── WAL_MODE_SETUP.md  (NEW - this file)
```

---

## Troubleshooting

### Still seeing "Database busy" errors?

1. **Check WAL mode is enabled**:
   ```bash
   sqlite3 priv/shared_dbs/users.db "PRAGMA journal_mode;"
   ```

2. **Check Oban queue limits**:
   ```bash
   grep "queues:" config/runtime.exs
   ```
   Should show `default: 3, embeddings: 2, ai_processing: 1`

3. **Restart server completely**:
   ```bash
   pkill -f beam.smp
   mix phx.server
   ```

4. **Check for stale connections**:
   ```bash
   lsof priv/shared_dbs/users.db
   ```

5. **Nuclear option - rebuild database**:
   ```bash
   mix ecto.drop
   mix ecto.create
   mix ecto.migrate
   ```

### WAL files (-wal, -shm) are normal!

After enabling WAL mode, you'll see two extra files:
- `users.db-wal` - Write-ahead log
- `users.db-shm` - Shared memory index

**This is normal and expected** - don't delete them!

---

## Summary

✅ **WAL mode enabled** via migration + config
✅ **Automatic setup** on every connection via `after_connect`
✅ **Reduced concurrency** to 6 total Oban workers
✅ **Works in all environments** (dev, test, prod)

**Result**: No more "Database busy" errors! 🎉
