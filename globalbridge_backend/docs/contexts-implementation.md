# Messaging Contexts Implementation

**Status:** ✅ **COMPLETED** (Task 5)
**Date:** October 20, 2025
**Author:** Backend Developer Agent

## Overview

This document describes the implementation of Elixir contexts for threads and messages in the WhatsApp Clone backend. The contexts provide a clean business logic layer over the database schemas, with full support for per-thread database sharding.

## Architecture

### Context Layer Structure

```
GlobalbridgeBackend.Contexts.Messaging
├── Threads (Thread CRUD + filtering)
└── Messages (Message CRUD + filtering + sharding)
```

### Sharding Architecture

- **Thread Metadata**: Stored in `users.db` (shared database)
- **Messages**: Stored in per-thread databases at `priv/threads/{shard_id}.db`
- **Dynamic Repos**: Created on-demand via `ThreadRepo.get_repo/1`

## Files Created

### Context Modules

1. **`lib/globalbridge_backend/contexts/messaging.ex`**
   - Main entry point that delegates to Threads and Messages contexts
   - Provides unified API for all messaging operations

2. **`lib/globalbridge_backend/contexts/threads.ex`**
   - Thread CRUD operations
   - Participant management
   - Search and filtering
   - Direct message thread finding/creation

3. **`lib/globalbridge_backend/contexts/messages.ex`**
   - Message CRUD operations with sharding support
   - Read receipts
   - Search and filtering
   - Unread count tracking

4. **`lib/globalbridge_backend/repos/thread_repo.ex`**
   - Dynamic repository manager for per-thread databases
   - Automatic database creation and migration
   - Shard lifecycle management

### Test Files

1. **`test/globalbridge_backend/contexts/threads_test.exs`**
   - Comprehensive tests for Threads context
   - 15+ test cases covering all CRUD operations
   - Tests for filtering, pagination, and search

2. **`test/globalbridge_backend/contexts/messages_test.exs`**
   - Comprehensive tests for Messages context
   - 20+ test cases covering all message operations
   - Tests for sharding, read receipts, and search

3. **`test/support/data_case.ex`**
   - Test helper module for database tests
   - SQL Sandbox setup for isolated tests

## API Reference

### Threads Context

#### Thread Management

```elixir
# List all threads with optional filtering
Threads.list_threads()
Threads.list_threads(is_archived: false, limit: 10)

# Get a specific thread
Threads.get_thread!(id)
Threads.get_thread(id)  # Returns nil if not found

# Create a new thread
Threads.create_thread(%{
  thread_type: "direct",
  participant_ids: [user1_id, user2_id]
})

Threads.create_thread(%{
  thread_type: "group",
  title: "Team Chat",
  participant_ids: [user1_id, user2_id, user3_id]
})

# Update thread
Threads.update_thread(thread, %{title: "New Title"})

# Delete thread
Threads.delete_thread(thread)
```

#### Thread Actions

```elixir
# Archive/Unarchive
Threads.archive_thread(thread)
Threads.unarchive_thread(thread)

# Mute/Unmute
Threads.mute_thread(thread)
Threads.unmute_thread(thread)
```

#### Participant Management

```elixir
# Add participant
Threads.add_participant(thread, user_id, "member")
Threads.add_participant(thread, user_id, "admin")

# Remove participant
Threads.remove_participant(thread, user_id)

# List participants
Threads.list_participants(thread)
```

#### Search and Filtering

```elixir
# Get/create direct message thread
Threads.get_thread_for_direct_message(user1_id, user2_id)

# List user's threads
Threads.list_user_threads(user_id)
Threads.list_user_threads(user_id, is_archived: false, limit: 20)

# Search threads by title
Threads.search_threads("project")
```

#### Supported Filters

- `:is_archived` - Boolean filter for archived status
- `:is_muted` - Boolean filter for muted status
- `:thread_type` - "direct" or "group"
- `:limit` - Number of results (default: 50)
- `:offset` - Pagination offset (default: 0)
- `:order_by` - Ordering field and direction (default: `{:last_message_at, :desc}`)

### Messages Context

#### Message Management

```elixir
# List messages in a thread
Messages.list_messages(thread_id)
Messages.list_messages(thread_id, limit: 50, is_deleted: false)

# Get specific message
Messages.get_message!(thread_id, message_id)
Messages.get_message(thread_id, message_id)  # Returns nil if not found

# Create message
Messages.create_message(thread_id, %{
  sender_id: user_id,
  content_type: "text",
  content: "Hello, world!"
})

Messages.create_message(thread_id, %{
  sender_id: user_id,
  content_type: "image",
  media_url: "https://example.com/image.jpg",
  media_size: 1024,
  media_mime_type: "image/jpeg"
})

# Edit message
Messages.edit_message(thread_id, message, "Updated content")

# Delete message (soft delete)
Messages.delete_message(thread_id, message)
```

#### Read Receipts

```elixir
# Mark message as read
Messages.mark_as_read(thread_id, message_id, user_id)

# Get unread count for user
Messages.get_unread_count(thread_id, user_id)
```

#### Search and Pagination

```elixir
# Search messages
Messages.search_messages(thread_id, "important")
Messages.search_messages(thread_id, "query", limit: 10)

# Get messages after timestamp (for pagination)
Messages.get_thread_messages_after(thread_id, timestamp, 50)

# Get messages before timestamp (for loading older messages)
Messages.get_thread_messages_before(thread_id, timestamp, 50)
```

#### Supported Filters

- `:sender_id` - Filter by sender
- `:content_type` - "text", "image", "video", "audio", "file", "location"
- `:is_deleted` - Boolean filter for deleted status (default: false)
- `:after` - Get messages after timestamp
- `:before` - Get messages before timestamp
- `:limit` - Number of results (default: 50)
- `:offset` - Pagination offset (default: 0)
- `:order_by` - Ordering field and direction (default: `{:inserted_at, :desc}`)

## Database Sharding

### How It Works

1. **Thread Creation**: When a thread is created, a unique `database_shard_id` (UUID) is generated
2. **Dynamic Repository**: First message access triggers creation of the per-thread database
3. **Auto-Migration**: Thread databases are automatically created with messages and read_receipts tables
4. **Routing**: All message operations automatically route to the correct shard via `ThreadRepo.get_repo/1`

### Shard Lifecycle

```elixir
# Get or create repo for a thread
repo = ThreadRepo.get_repo(thread.database_shard_id)

# Start a repo manually (usually automatic)
{:ok, repo_name} = ThreadRepo.start_repo(shard_id)

# Stop a repo
ThreadRepo.stop_repo(shard_id)

# Get database file path
path = ThreadRepo.database_path(shard_id)
# => "priv/threads/{shard_id}.db"
```

### Benefits

- **Horizontal Scaling**: Messages distributed across many small databases
- **Performance**: Smaller databases = faster queries
- **Isolation**: Thread data physically separated
- **Deletion**: Easy to delete entire thread by removing database file

## Validation and Error Handling

### Thread Validations

- `thread_type` must be "direct" or "group"
- `title` maximum length: 100 characters
- `database_shard_id` is automatically generated and required

### Message Validations

- `content_type` must be one of: "text", "image", "video", "audio", "file", "location"
- Text messages require `content` field (1-10,000 characters)
- Media messages require `media_url` field
- All messages require `thread_id` and `sender_id`

### Error Responses

```elixir
# Not found errors
{:error, :not_found}  # From remove_participant when not found
nil                   # From get_thread/1 when not found
raise Ecto.NoResultsError  # From get_thread!/1 when not found

# Validation errors
{:error, %Ecto.Changeset{}}  # From create/update operations
```

## Testing

### Running Tests

```bash
# Run all context tests
cd globalbridge_backend
mix test test/globalbridge_backend/contexts/

# Run specific context tests
mix test test/globalbridge_backend/contexts/threads_test.exs
mix test test/globalbridge_backend/contexts/messages_test.exs

# Run with coverage
mix test --cover
```

### Test Coverage

#### Threads Context (15+ tests)
- ✅ List threads with filtering
- ✅ Get thread by ID
- ✅ Create threads (direct & group)
- ✅ Update threads
- ✅ Delete threads
- ✅ Archive/unarchive operations
- ✅ Mute/unmute operations
- ✅ Participant management
- ✅ Direct message thread finding
- ✅ User thread listing
- ✅ Thread search
- ✅ Pagination and ordering

#### Messages Context (20+ tests)
- ✅ Create messages (text & media)
- ✅ List messages with filtering
- ✅ Get message by ID
- ✅ Edit messages
- ✅ Delete messages (soft delete)
- ✅ Read receipts
- ✅ Unread count tracking
- ✅ Message search
- ✅ Pagination (before/after timestamps)
- ✅ Sharding integration
- ✅ Thread timestamp updates

## Performance Considerations

### Indexing

All sharded databases automatically include:
- Index on `thread_id` for messages
- Index on `sender_id` for messages
- Index on `inserted_at` for messages
- Index on `content_type` for messages
- Index on `message_id` for read receipts
- Index on `user_id` for read receipts

### Query Optimization

- Default limits prevent unbounded queries (50 messages/threads)
- Soft deletes keep message IDs stable for clients
- Read receipts use upserts for idempotency
- Pagination uses timestamp-based queries (more efficient than offset)

### Caching Opportunities (Future)

- Thread participant lists (low change frequency)
- Unread counts (invalidate on new message)
- Thread metadata (invalidate on update)

## Integration with Other Components

### Phoenix Channels (Future)

```elixir
# In ThreadChannel
def handle_in("new_message", params, socket) do
  case Messages.create_message(socket.assigns.thread_id, params) do
    {:ok, message} ->
      broadcast!(socket, "new_message", message)
      {:reply, {:ok, message}, socket}
    {:error, changeset} ->
      {:reply, {:error, changeset}, socket}
  end
end
```

### REST API (Future)

```elixir
# In ThreadController
def index(conn, params) do
  threads = Messaging.list_threads(
    is_archived: params["archived"] == "true",
    limit: params["limit"] || 50
  )
  json(conn, threads)
end
```

### GraphQL API (Future)

```elixir
# In Schema
object :thread do
  field :id, :id
  field :title, :string
  field :messages, list_of(:message) do
    arg :limit, :integer, default_value: 50
    resolve fn thread, args, _ ->
      {:ok, Messages.list_messages(thread.id, limit: args.limit)}
    end
  end
end
```

## Migration Path from Existing Code

If you have existing `GlobalbridgeBackend.Chat` module, migrate to contexts:

```elixir
# Old way
Chat.create_thread(attrs)
Chat.list_threads()
Chat.send_message(attrs)

# New way (via Messaging facade)
Messaging.create_thread(attrs)
Messaging.list_threads()
Messaging.create_message(thread_id, attrs)

# Or directly
Threads.create_thread(attrs)
Threads.list_threads()
Messages.create_message(thread_id, attrs)
```

## Task Completion Status

### Task 5: Create Elixir contexts for threads and messages ✅

#### Subtask 5.1: Set up Messaging module structure ✅
- Created `lib/globalbridge_backend/contexts/messaging.ex`
- Implemented delegation pattern to Threads and Messages contexts

#### Subtask 5.2: Implement Messaging.Threads context with basic CRUD ✅
- Created `lib/globalbridge_backend/contexts/threads.ex`
- Implemented: `list_threads/1`, `get_thread!/1`, `get_thread/1`
- Implemented: `create_thread/1`, `update_thread/2`, `delete_thread/1`

#### Subtask 5.3: Add filtering/querying to Threads context ✅
- Added filtering: `is_archived`, `is_muted`, `thread_type`
- Added pagination: `limit`, `offset`
- Added ordering: `order_by` with custom fields
- Implemented: `search_threads/2`, `list_user_threads/2`
- Implemented: `get_thread_for_direct_message/2`

#### Subtask 5.4: Implement Messaging.Messages context with basic CRUD ✅
- Created `lib/globalbridge_backend/contexts/messages.ex`
- Implemented: `list_messages/2`, `get_message!/2`, `get_message/2`
- Implemented: `create_message/2`, `update_message/3`, `delete_message/2`
- Integrated with sharded database architecture via `ThreadRepo`

#### Subtask 5.5: Add filtering/querying to Messages context ✅
- Added filtering: `sender_id`, `content_type`, `is_deleted`
- Added time-based filtering: `after`, `before`
- Added pagination: `limit`, `offset`, `order_by`
- Implemented: `search_messages/3`
- Implemented: `get_thread_messages_after/3`, `get_thread_messages_before/3`
- Implemented: `mark_as_read/3`, `get_unread_count/2`

### Additional Implementations

- ✅ Created `ThreadRepo` for dynamic per-thread database management
- ✅ Implemented automatic database creation and migration
- ✅ Added comprehensive unit tests (35+ test cases)
- ✅ Created `DataCase` test helper
- ✅ Documented all public APIs with examples
- ✅ Added proper error handling and validations
- ✅ Ensured compatibility with sharded database architecture from Task 2

## Next Steps

Recommended follow-up tasks:

1. **Task 6**: Implement Phoenix Channels for real-time messaging
2. **Task 7**: Add REST/GraphQL API endpoints using these contexts
3. **Task 8**: Implement CDC (Change Data Capture) for sync
4. **Task 9**: Add caching layer for frequently accessed data
5. **Task 10**: Performance testing with large thread counts

## References

- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [Ecto Query Documentation](https://hexdocs.pm/ecto/Ecto.Query.html)
- [Dynamic Supervisors](https://hexdocs.pm/elixir/DynamicSupervisor.html)
- Project PRD: Database sharding architecture
- Task 2 Documentation: Database schemas and migrations
