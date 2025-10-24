# SQLite Vector Extension Setup

This document explains how to set up the sqlite-vec extension for the AI backend's vector search capabilities.

## Overview

The GlobalBridge AI backend uses per-thread SQLite databases with the sqlite-vec extension (vec0) for efficient vector similarity search. This enables semantic search, RAG (Retrieval-Augmented Generation), and embedding-based features.

## Installation

### macOS (Homebrew)

```bash
# Install sqlite-vec via Homebrew
brew install sqlite-vec

# The shared library will typically be at:
# /opt/homebrew/lib/vec0.dylib (Apple Silicon)
# /usr/local/lib/vec0.dylib (Intel)
```

### Linux

```bash
# Download pre-built binary
wget https://github.com/asg017/sqlite-vec/releases/latest/download/vec0.so

# Or build from source
git clone https://github.com/asg017/sqlite-vec.git
cd sqlite-vec
make
sudo make install
```

### From Source

```bash
git clone https://github.com/asg017/sqlite-vec.git
cd sqlite-vec
make
# The shared library will be in ./dist/vec0.{so,dylib,dll}
```

## Configuration

### Setting SQLITE_VEC_PATH

The application requires the `SQLITE_VEC_PATH` environment variable to point to your vec0 shared library:

```bash
# macOS (Apple Silicon)
export SQLITE_VEC_PATH=/opt/homebrew/lib/vec0.dylib

# macOS (Intel)
export SQLITE_VEC_PATH=/usr/local/lib/vec0.dylib

# Linux
export SQLITE_VEC_PATH=/usr/local/lib/vec0.so

# Custom installation
export SQLITE_VEC_PATH=/path/to/your/vec0.so
```

### Development (.env)

Add to your `.env` file:

```bash
SQLITE_VEC_PATH=/opt/homebrew/lib/vec0.dylib
```

### Production

Set the environment variable in your deployment configuration:

- **Docker**: Add to your `docker-compose.yml` or Dockerfile
- **Heroku**: `heroku config:set SQLITE_VEC_PATH=/app/lib/vec0.so`
- **Fly.io**: Add to `fly.toml` env section
- **Kubernetes**: Add to your ConfigMap or Secret

## Verification

### Startup Validation

The application validates the sqlite-vec extension on startup:

- ✅ **Success**: `[info] sqlite-vec extension found at /path/to/vec0.dylib`
- ⚠️ **Warning**: `SQLITE_VEC_PATH not set. Vector operations may fail.`
- ❌ **Error**: `SQLITE_VEC_PATH points to non-existent file.`

### Manual Testing

```bash
# Start IEx
iex -S mix

# Verify extension loads
iex> {:ok, conn} = Exqlite.Sqlite3.open(":memory:")
iex> Exqlite.Sqlite3.enable_load_extension(conn, true)
iex> Exqlite.Sqlite3.execute(conn, "SELECT load_extension('#{System.get_env("SQLITE_VEC_PATH")}')")
iex> {:ok, [[version]]} = Exqlite.Sqlite3.execute(conn, "SELECT vec_version()")
iex> IO.puts("sqlite-vec version: #{version}")
```

## Per-Thread Database Architecture

### How It Works

1. Each chat thread gets its own SQLite database
2. On first message, a ThreadRepo is created dynamically
3. The `after_connect` hook loads the vec0 extension
4. Vector operations (embeddings, semantic search) work within that thread's database

### Schema

Per-thread messages table includes:

```sql
CREATE TABLE messages (
  id INTEGER PRIMARY KEY,
  content TEXT,
  sender_id TEXT,
  -- Vector embedding columns
  embedding BLOB,
  embedding_model TEXT,
  embedding_version INTEGER,
  embedded_at TIMESTAMP
);

-- Virtual table for vector search
CREATE VIRTUAL TABLE vec_messages USING vec0(
  embedding FLOAT[3072]
);
```

## Troubleshooting

### Extension Not Found

```
** (RuntimeError) SQLITE_VEC_PATH points to non-existent file.
```

**Solution**: Verify the path is correct and the file exists:

```bash
ls -la $SQLITE_VEC_PATH
```

### Permission Denied

```
** (Exqlite.Error) unable to open shared library
```

**Solution**: Ensure the shared library has execute permissions:

```bash
chmod +x $SQLITE_VEC_PATH
```

### Wrong Architecture

```
** (Exqlite.Error) incompatible library version
```

**Solution**: Ensure you're using the correct architecture (x86_64 vs ARM64). Rebuild for your platform.

### Path Traversal Warning

```
** (RuntimeError) Invalid SQLITE_VEC_PATH: path contains '..'
```

**Solution**: Use absolute paths only, no relative paths with `..`

## Development

### Running Tests

```bash
# Set the env var
export SQLITE_VEC_PATH=/opt/homebrew/lib/vec0.dylib

# Run AI tests
mix test test/globalbridge_backend/ai/
mix test test/integration/ai_pipeline_integration_test.exs

# Run concurrent repo tests
mix test test/globalbridge_backend/contexts/concurrent_repo_test.exs
```

### Skipping Vector Tests

If you don't have sqlite-vec installed, some tests will be skipped automatically:

```elixir
if System.get_env("SQLITE_VEC_PATH") do
  # Vector-specific tests
end
```

## Production Deployment

### Checklist

- [ ] Install sqlite-vec on production servers
- [ ] Set `SQLITE_VEC_PATH` environment variable
- [ ] Verify file permissions (readable + executable)
- [ ] Test extension loading in production environment
- [ ] Monitor startup logs for validation messages
- [ ] Set up alerts for vector operation failures

### Docker Example

```dockerfile
FROM elixir:1.16-alpine

# Install sqlite-vec
RUN wget https://github.com/asg017/sqlite-vec/releases/latest/download/vec0.so \
    -O /usr/local/lib/vec0.so && \
    chmod +x /usr/local/lib/vec0.so

ENV SQLITE_VEC_PATH=/usr/local/lib/vec0.so

# ... rest of Dockerfile
```

## References

- [sqlite-vec GitHub](https://github.com/asg017/sqlite-vec)
- [sqlite-vec Documentation](https://alexgarcia.xyz/sqlite-vec/)
- [Exqlite Documentation](https://hexdocs.pm/exqlite)

## Support

If you encounter issues:

1. Check the startup logs for validation messages
2. Verify `SQLITE_VEC_PATH` points to a valid file
3. Run manual testing commands above
4. Check file permissions and architecture compatibility
5. Open an issue with error logs
