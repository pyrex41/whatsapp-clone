# GlobalbridgeBackend

Phoenix backend for GlobalBridge with AI-powered features including translation, summarization, semantic search, and task extraction.

## Prerequisites

### SQLite Vector Extension (Required for AI Features)

The AI backend requires the sqlite-vec extension for vector similarity search. See detailed setup instructions in [docs/SQLITE_VEC_SETUP.md](../docs/SQLITE_VEC_SETUP.md).

**Quick setup**:

```bash
# macOS (Homebrew)
brew install sqlite-vec
export SQLITE_VEC_PATH=/opt/homebrew/lib/vec0.dylib

# Linux
wget https://github.com/asg017/sqlite-vec/releases/latest/download/vec0.so
export SQLITE_VEC_PATH=/path/to/vec0.so
```

**⚠️ Important**: Set `SQLITE_VEC_PATH` environment variable before starting the application, or vector operations will fail.

## Getting Started

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Set required environment variables (see Configuration below)
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Configuration

### Required Environment Variables

```bash
# SQLite vector extension path (REQUIRED for AI features)
export SQLITE_VEC_PATH=/opt/homebrew/lib/vec0.dylib

# OpenAI API key (for embeddings and AI features)
export OPENAI_API_KEY=your_api_key_here

# Anthropic API key (for Claude models)
export ANTHROPIC_API_KEY=your_api_key_here

# Redis URL (for caching)
export REDIS_URL=redis://localhost:6379

# Database configuration
export DATABASE_URL=postgresql://user:pass@localhost/globalbridge_dev
```

### Optional Configuration

```bash
# AI feature flags
export ENABLE_AI_TRANSLATION=true
export ENABLE_AI_SUMMARIZATION=true
export ENABLE_SEMANTIC_SEARCH=true

# Cost tracking
export AI_BUDGET_DAILY_LIMIT_USD=50.00
export AI_COST_ALERT_THRESHOLD_USD=40.00
```

## Architecture

### Per-Thread SQLite Databases

This backend uses a **per-thread repository architecture**:

- Each chat thread gets its own SQLite database
- Databases are created dynamically on first message
- sqlite-vec extension loaded per-thread for vector operations
- Enables efficient vector search and RAG within thread context

### AI Features

- **Translation**: Real-time multilingual translation with cultural context
- **Summarization**: Conversation summaries using RAG
- **Semantic Search**: Vector-based message search
- **Task Extraction**: Automatic task detection from conversations
- **Cost Tracking**: Budget monitoring and alerts

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run specific test suites
mix test test/globalbridge_backend/ai/
mix test test/integration/

# Exclude notifications tests (known issues)
mix test --exclude notifications
```

See [docs/KNOWN_ISSUES.md](../docs/KNOWN_ISSUES.md) for known test failures.

### Database Migrations

```bash
# Run migrations for main repo
mix ecto.migrate

# Per-thread databases are migrated automatically on creation
```

### Code Quality

```bash
# Format code
mix format

# Run Credo
mix credo

# Run Dialyzer
mix dialyzer
```

## Deployment

Ready to run in production? Please check:

- [Phoenix deployment guides](https://hexdocs.pm/phoenix/deployment.html)
- [SQLite vec setup documentation](../docs/SQLITE_VEC_SETUP.md)
- [Known issues tracker](../docs/KNOWN_ISSUES.md)

### Production Checklist

- [ ] Set all required environment variables
- [ ] Install sqlite-vec extension on production servers
- [ ] Configure Redis for caching
- [ ] Set up monitoring and alerting
- [ ] Configure AI budget limits
- [ ] Test vector operations in production environment

## Documentation

- [SQLite Vector Setup](../docs/SQLITE_VEC_SETUP.md) - Detailed sqlite-vec installation and configuration
- [Known Issues](../docs/KNOWN_ISSUES.md) - Current known issues and workarounds

## Learn More

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
