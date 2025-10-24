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
- **Input Validation**: Comprehensive validation to prevent DoS attacks

### Caching Architecture

The application uses a **unified 2-layer caching system**:

- **Cachex**: Application-level caching for embeddings (1h TTL) and search results (15m TTL)
- **ETS**: Process-level caching for thread repository connections (24h TTL)

See [docs/CACHING_ARCHITECTURE.md](docs/CACHING_ARCHITECTURE.md) for detailed documentation.

**Key Points:**
- No Redis dependency required for caching
- All cache operations via unified `GlobalbridgeBackend.AI.Cache` module
- Automatic TTL management per data type
- Comprehensive test coverage

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

## API Documentation

### AI Endpoints

All AI endpoints include comprehensive input validation to prevent DoS attacks and ensure data quality.

#### POST /api/ai/translate
Translates text to a target language.

**Input Validation:**
- `text`: String, max 10,000 characters (required)
- `target_language`: Valid language code - en, es, fr, de, it, pt, ja, zh, ko, ru, ar, hi (required)
- `source_language`: Valid language code or "auto" (optional, defaults to "auto")

#### POST /api/ai/analyze_tone
Analyzes the tone of given text.

**Input Validation:**
- `text`: String, max 10,000 characters (required)
- `language`: Valid language code (optional, defaults to "en")

#### POST /api/ai/summarize_thread
Summarizes a message thread using RAG.

**Input Validation:**
- `thread_id`: Valid UUID (required)
- `max_length`: Integer between 1 and 1,000 (optional, defaults to 200)

#### POST /api/ai/search_semantic
Performs semantic search across messages.

**Input Validation:**
- `query`: String, max 1,000 characters (required)
- `thread_id`: Valid UUID (optional)
- `limit`: Integer between 1 and 50 (optional, defaults to 10)
- `recency_bias`: Boolean (optional, defaults to true)
- `translate`: Boolean (optional, defaults to false)

#### POST /api/ai/extract_tasks
Extracts actionable tasks from a thread.

**Input Validation:**
- `thread_id`: Valid UUID (required)
- `query`: String, max 1,000 characters (optional)

#### POST /api/ai/vec_health
Checks vector extension health for a thread.

**Input Validation:**
- `thread_id`: Valid UUID (required)

### Error Responses

All validation failures return **400 Bad Request** with clear error messages:
```json
{
  "error": "Text must not exceed 10,000 characters"
}
```

Authorization failures return **403 Forbidden**:
```json
{
  "error": "Access denied to this thread"
}
```

## Documentation

- [SQLite Vector Setup](../docs/SQLITE_VEC_SETUP.md) - Detailed sqlite-vec installation and configuration
- [Known Issues](../docs/KNOWN_ISSUES.md) - Current known issues and workarounds

## Learn More

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
