# ThreadCache Flow Diagram

## Request Lifecycle with ThreadCache

```
┌─────────────────────────────────────────────────────────────────┐
│                    HTTP Request Arrives                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              Router Pipeline (Phoenix)                           │
│  1. :accepts, ["json"]                                          │
│  2. CORSPlug                                                    │
│  3. :put_api_security_headers                                   │
│  4. :rate_limit_api                                             │
│  5. ThreadCache ← ✨ Cache initialized (empty)                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Controller Action                             │
│  Example: GET /api/threads/:thread_id/messages                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              Operation 1: list_messages                          │
│                                                                  │
│  1. get_thread_with_shard(thread_id)                            │
│     ├─ ThreadCache.get_cached_thread(thread_id) → nil ❌       │
│     ├─ Repo.get(Thread, thread_id) → %Thread{} ✅             │
│     └─ ThreadCache.cache_thread(thread) → cached ✨             │
│                                                                  │
│  2. Query messages from thread's shard database                 │
│     └─ Return [messages...]                                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│            Operation 2: get_unread_count                         │
│                                                                  │
│  1. get_thread_with_shard(thread_id)                            │
│     ├─ ThreadCache.get_cached_thread(thread_id) → %Thread{} ✅ │
│     └─ Skip database query! (cache hit) 🚀                     │
│                                                                  │
│  2. Count unread messages in thread's shard                     │
│     └─ Return count                                             │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│            Operation 3: search_messages                          │
│                                                                  │
│  1. get_thread_with_shard(thread_id)                            │
│     ├─ ThreadCache.get_cached_thread(thread_id) → %Thread{} ✅ │
│     └─ Skip database query! (cache hit) 🚀                     │
│                                                                  │
│  2. Search messages in thread's shard                           │
│     └─ Return [matching_messages...]                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│            Operation 4: mark_as_read (multiple)                  │
│                                                                  │
│  For each message:                                              │
│  1. get_thread_with_shard(thread_id)                            │
│     ├─ ThreadCache.get_cached_thread(thread_id) → %Thread{} ✅ │
│     └─ Skip database query! (cache hit) 🚀                     │
│                                                                  │
│  2. Insert/update read receipt                                  │
│     └─ Return {:ok, receipt}                                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                  Response Sent to Client                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              Request Process Terminates                          │
│  ✨ Cache automatically cleared (process dictionary cleaned)    │
│  🗑️  No memory leaks                                            │
│  🔒 No stale data                                                │
└─────────────────────────────────────────────────────────────────┘
```

## Query Comparison

### WITHOUT ThreadCache
```
GET /api/threads/abc123/messages
  ├─ SELECT * FROM threads WHERE id = 'abc123'  ← Query 1
  ├─ SELECT * FROM messages WHERE thread_id = 'abc123' LIMIT 50
  ├─ SELECT * FROM threads WHERE id = 'abc123'  ← Query 2 (duplicate!)
  ├─ SELECT COUNT(*) FROM messages WHERE ...
  ├─ SELECT * FROM threads WHERE id = 'abc123'  ← Query 3 (duplicate!)
  ├─ SELECT * FROM messages WHERE thread_id = 'abc123' AND content LIKE ...
  ├─ SELECT * FROM threads WHERE id = 'abc123'  ← Query 4 (duplicate!)
  └─ INSERT INTO read_receipts ...

Total: 4 thread queries (3 unnecessary!)
```

### WITH ThreadCache
```
GET /api/threads/abc123/messages
  ├─ SELECT * FROM threads WHERE id = 'abc123'  ← Query 1 (cached)
  ├─ SELECT * FROM messages WHERE thread_id = 'abc123' LIMIT 50
  ├─ [cache hit] ✨                              ← No query!
  ├─ SELECT COUNT(*) FROM messages WHERE ...
  ├─ [cache hit] ✨                              ← No query!
  ├─ SELECT * FROM messages WHERE thread_id = 'abc123' AND content LIKE ...
  ├─ [cache hit] ✨                              ← No query!
  └─ INSERT INTO read_receipts ...

Total: 1 thread query (75% reduction!)
```

## Process Isolation

```
┌──────────────────────────────────────────────────────────────┐
│                    Concurrent Requests                        │
└──────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────┴─────────────────────┐
        ↓                                           ↓
┌──────────────────┐                      ┌──────────────────┐
│   Request A      │                      │   Request B      │
│   (Process 1)    │                      │   (Process 2)    │
├──────────────────┤                      ├──────────────────┤
│ Cache:           │                      │ Cache:           │
│ - thread-123 ✅  │                      │ - thread-456 ✅  │
│ - thread-789 ✅  │                      │ - thread-123 ✅  │
└──────────────────┘                      └──────────────────┘
        ↓                                           ↓
  Separate caches                          Separate caches
  No interference                          No race conditions
```

## Cache Management

### Automatic Management (99% of cases)
```elixir
# Just use the Messages context - cache is handled automatically!
Messages.list_messages(thread_id)
Messages.get_unread_count(thread_id, user_id)
Messages.search_messages(thread_id, "hello")
# ✅ Thread only queried once, cached for subsequent calls
```

### Manual Management (rare cases)
```elixir
# After updating a thread
Threads.update(thread_id, params)
ThreadCache.clear_thread(thread_id)  # Clear stale cache

# For testing
ThreadCache.clear_all()  # Clear entire cache

# Debug cache size
size = ThreadCache.cache_size()  # Get number of cached threads
```

## Performance Characteristics

### Time Complexity
- Cache lookup: O(1) - Process dictionary access
- Cache insert: O(1) - Process dictionary write
- Cache clear: O(n) - Where n is number of cached threads (typically < 10)

### Space Complexity
- Per request: O(k) - Where k is unique threads accessed
- Typical: 1-5 threads per request
- Maximum: Bounded by request lifetime (seconds)

### Scalability
- ✅ Scales linearly with concurrent requests (per-process isolation)
- ✅ No global locks or contention
- ✅ No cache invalidation complexity
- ✅ Automatic cleanup on request completion

---

**Key Insight**: The cache is scoped to a single HTTP request process, making it
simple, safe, and highly effective for eliminating N+1 queries without the
complexity of distributed caching or invalidation strategies.
