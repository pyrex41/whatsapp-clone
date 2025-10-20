# GlobalBridge Database Architecture

## Database Sharding Strategy

This project uses a sharding strategy where each thread/conversation gets its own SQLite database file for granular backup, sharing, and End-to-End Encryption (E2EE) support.

## Database Organization

### Thread Databases (Sharded)
- **Location**: `priv/threads/{thread_id}.db`
- **Purpose**: Each conversation/thread has its own isolated database
- **Benefits**:
  - Granular backup and restore per conversation
  - Easy sharing of individual conversations
  - Per-thread encryption for E2EE
  - Better performance isolation

### Shared Databases
- **users.db**: User accounts, authentication, profiles
- **bridges.db**: Bridge configurations, platform integrations
- **sync_state.db**: Cross-device synchronization state

## Configuration

### Development
Database location: `priv/shared_dbs/users.db`
See `config/dev.exs` for configuration.

### Test
Database location: `priv/repo/test.db`
Uses SQL Sandbox for isolated tests.

### Production
Database location: Set via `DATABASE_PATH` environment variable
Example: `/etc/globalbridge_backend/shared_dbs/users.db`

## Migration Strategy

Migrations for shared databases are run via `mix ecto.migrate`.
Thread-specific databases are created dynamically when a new conversation is started.
