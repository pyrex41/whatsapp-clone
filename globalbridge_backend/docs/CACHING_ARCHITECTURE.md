# Caching Architecture

## Overview

The GlobalBridge Backend uses a **unified caching architecture** with two layers:

1. **Cachex** - Application-level caching for AI embeddings and search results
2. **ETS** - Process-level caching for thread repository connections

This consolidation replaced a previous 4-layer architecture (Redis, Cachex, ETS, persistent_term) with a simpler 2-layer approach.

## Architecture Components

### 1. Unified Cache Module

**Location:** `lib/globalbridge_backend/ai/cache.ex`

**Purpose:** Provides a single interface for all caching operations across the application.

**Key Features:**
- Consolidated API for embeddings, search results, and repository caching
- Automatic TTL management per data type
- Safe concurrent access
- Comprehensive statistics and management functions

### 2. Cachex Layer (Application-Level)

**Use Cases:**
- **Embeddings** - OpenAI text embeddings (3072-dimensional vectors)
- **Search Results** - Semantic search query results
- **Vector Results** - Vector similarity search results

**TTL Configuration:**
```elixir
@embeddings_ttl :timer.hours(1)        # 1 hour
@search_results_ttl :timer.minutes(15) # 15 minutes
```

**Cache Keys:**
- Embeddings: `embedding:{model}:{text_hash}`
- Search results: `search:{thread_id}:{query_hash}:{params}`
- Vector results: `vector:{thread_id}:{embedding_hash}:{limit}`

### 3. ETS Layer (Process-Level)

**Use Cases:**
- **Thread Repositories** - Dynamic Ecto repo connections per thread

**TTL Configuration:**
```elixir
@repos_ttl :timer.hours(24) # 24 hours
```

**Implementation Details:**
- Named ETS table: `:thread_repo_cache`
- Table options: `[:named_table, :public, :set, read_concurrency: true]`
- Manual TTL enforcement via timestamps
- Periodic cleanup via `cleanup_expired_repos/0`

## Migration from Old Architecture

### Removed Components

1. **EmbeddingCache** (`lib/globalbridge_backend/ai/cache/embedding_cache.ex`) - DELETED
   - Replaced by: `Cache.get_embedding/2`, `Cache.put_embedding/3`

2. **SearchCache** (`lib/globalbridge_backend/ai/cache/search_cache.ex`) - DELETED
   - Replaced by: `Cache.get_search_result/3`, `Cache.put_search_result/4`

3. **persistent_term** (in `ThreadRepo`) - REMOVED
   - Replaced by: `Cache.get_repo/1`, `Cache.put_repo/2` (ETS-backed)

4. **Redis/Redix** - DEPENDENCY RETAINED
   - **Status:** Not currently used for caching
   - **Reason:** Kept in `mix.exs` for potential future pub/sub needs
   - **Note:** Can be removed if pub/sub is not required

### Updated Components

1. **EmbeddingService** - Now uses `Cache` module
2. **SemanticSearch** - Now uses `Cache` module
3. **ThreadRepo** - Now uses `Cache` module for repo caching

## API Reference

### Embedding Operations

```elixir
# Get cached embedding
Cache.get_embedding(text, model)
# => [0.1, 0.2, ...] | nil

# Store embedding
Cache.put_embedding(text, embedding, model)
# => :ok

# Check if exists
Cache.embedding_exists?(text, model)
# => true | false
```

### Search Result Operations

```elixir
# Get cached search results
Cache.get_search_result(thread_id, query, opts \\ [])
# => [%{message_id: ..., content: ..., similarity: ...}] | nil

# Store search results
Cache.put_search_result(thread_id, query, results, opts \\ [])
# => :ok

# Get cached vector results
Cache.get_vector_result(thread_id, embedding, limit)
# => [%{message_id: ..., distance: ...}] | nil

# Store vector results
Cache.put_vector_result(thread_id, embedding, results, limit)
# => :ok

# Invalidate all search results for a thread
Cache.invalidate_thread_search(thread_id)
# => :ok
```

### Repository Operations

```elixir
# Get cached repository
Cache.get_repo(shard_id)
# => repo_module | nil

# Store repository
Cache.put_repo(shard_id, repo_module)
# => :ok

# Remove from cache
Cache.uncache_repo(shard_id)
# => :ok

# Check if cached (and not expired)
Cache.repo_cached?(shard_id)
# => true | false

# Cleanup expired entries
Cache.cleanup_expired_repos()
# => :ok
```

### Management Operations

```elixir
# Get comprehensive statistics
Cache.stats()
# => %{cachex: ..., ets_repos: ..., ttls: ...}

# Clear specific cache types
Cache.clear_embeddings()
Cache.clear_search_results()
Cache.clear_repos()

# Clear everything
Cache.clear_all()
```

## Performance Characteristics

### Cachex (In-Memory)
- **Read:** O(1) - Hash table lookup
- **Write:** O(1) - Hash table insertion
- **Memory:** ~1-2 KB per embedding (3072 dimensions)
- **Concurrency:** Lock-free reads, coordinated writes

### ETS (Erlang Term Storage)
- **Read:** O(1) - Direct lookup with `read_concurrency: true`
- **Write:** O(1) - Direct insertion
- **Memory:** ~100 bytes per repo entry
- **Concurrency:** Multiple concurrent readers, single writer

### TTL Enforcement
- **Cachex:** Automatic via built-in TTL mechanism
- **ETS:** Manual via timestamp checking + periodic cleanup

## Cache Hit Rate Optimization

### Embeddings
- **Strategy:** Normalize text before hashing (lowercase, trim)
- **TTL:** 1 hour (embeddings don't change, but queries do)
- **Expected Hit Rate:** 60-80% for typical usage

### Search Results
- **Strategy:** Normalize queries (case-insensitive, whitespace normalization)
- **TTL:** 15 minutes (results may become stale as new messages arrive)
- **Expected Hit Rate:** 40-60% for active threads

### Repositories
- **Strategy:** Long TTL to avoid repeated connection overhead
- **TTL:** 24 hours
- **Expected Hit Rate:** 95%+ (repos rarely change)

## Monitoring & Observability

### Telemetry Events

The cache module emits telemetry events for monitoring:

```elixir
# Cache hits
Telemetry.cache_hit(:embedding, text, %{model: model})

# Cache misses
Telemetry.cache_miss(:embedding, text, %{model: model})
```

### Statistics

Use `Cache.stats/0` to monitor:
- Total cache size
- Hit/miss ratios
- Memory usage
- ETS table size

## Testing

**Location:** `test/globalbridge_backend/ai/cache_test.exs`

**Coverage:**
- ✅ Embedding caching operations
- ✅ Search result caching operations
- ✅ Vector result caching operations
- ✅ Repository caching operations (ETS)
- ✅ Cache invalidation
- ✅ Cache clearing (selective and full)
- ✅ Concurrent access patterns
- ✅ Cache key generation and normalization

**Run Tests:**
```bash
mix test test/globalbridge_backend/ai/cache_test.exs
```

## Best Practices

### When to Invalidate Cache

1. **Thread Search Results:**
   - When new messages are added to a thread
   - When messages are deleted or edited
   - Call: `Cache.invalidate_thread_search(thread_id)`

2. **Embeddings:**
   - Rarely needed (embeddings are deterministic)
   - Clear during model changes: `Cache.clear_embeddings()`

3. **Repositories:**
   - When shutting down thread databases
   - When database connections fail
   - Call: `Cache.uncache_repo(shard_id)`

### Memory Management

Monitor cache size via `Cache.stats/0` and implement cleanup strategies:

```elixir
# Periodic cleanup (every 6 hours)
defp schedule_cache_cleanup do
  Process.send_after(self(), :cleanup_cache, :timer.hours(6))
end

def handle_info(:cleanup_cache, state) do
  Cache.cleanup_expired_repos()
  schedule_cache_cleanup()
  {:noreply, state}
end
```

### Debugging Cache Issues

```elixir
# Check if something is cached
Cache.embedding_exists?("text", "model")
Cache.repo_cached?("shard_id")

# View cache statistics
IO.inspect(Cache.stats())

# Clear cache for testing
Cache.clear_all()
```

## Future Considerations

### Potential Enhancements

1. **Distributed Caching:**
   - If horizontal scaling is needed, consider Redis or Memcached
   - Current architecture is single-node optimized

2. **Cache Warming:**
   - Pre-load frequently used embeddings on startup
   - Implement via `SemanticSearch.warmup_cache/1`

3. **Adaptive TTLs:**
   - Adjust TTLs based on hit rates and data freshness requirements
   - Longer TTLs for stable data, shorter for volatile data

4. **Cache Metrics Dashboard:**
   - Integrate with Telemetry UI
   - Real-time hit/miss rates, memory usage, eviction rates

### Redis Status

**Current Status:** Redix dependency present but NOT used for caching

**Options:**

1. **Remove Completely:** If no pub/sub needs exist
   ```elixir
   # Remove from mix.exs
   {:redix, "~> 1.2"}  # DELETE
   ```

2. **Keep for Future Pub/Sub:** If distributed features are planned
   - Phoenix.PubSub can use Redis adapter for multi-node setups
   - Useful for distributed presence, broadcasts

3. **Use for Distributed Cache:** If scaling horizontally
   - Implement distributed caching layer above Cachex
   - Share cache across nodes

**Recommendation:** Remove Redis dependency if not needed for pub/sub. Phoenix.PubSub works fine with local adapter (PG2) for single-node deployments.

## Summary

The unified caching architecture provides:
- ✅ **Simplicity:** 2 layers instead of 4
- ✅ **Performance:** O(1) operations with minimal overhead
- ✅ **Maintainability:** Single module for all cache operations
- ✅ **Testability:** Comprehensive test coverage
- ✅ **Observability:** Built-in statistics and telemetry
- ✅ **Flexibility:** Easy to extend with new cache types

The architecture is optimized for single-node deployments with potential future expansion to distributed systems if needed.
