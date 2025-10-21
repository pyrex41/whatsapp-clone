# Sync API Contract - Backend ↔ iOS Client

**Version:** 1.0.0
**Base URL:** `/api/v1/sync`
**Authentication:** Bearer JWT Token (required for all endpoints)

## Overview

The Sync API provides CDC (Change Data Capture) based synchronization for multi-device messaging. It enables iOS clients to pull server changes and push local changes for conflict-free replication.

## Endpoints

### 1. Pull Changes (Server → Client)

**Endpoint:** `POST /api/v1/sync/pull`

Pull CDC changes from the server since the last sync.

#### Request Headers
```
Authorization: Bearer <access_token>
Content-Type: application/json
```

#### Request Body
```json
{
  "thread_id": "uuid",           // Required: Thread to sync
  "last_sync_cursor": 12345      // Optional: Last cursor (0 if first sync)
}
```

#### Success Response (200 OK)
```json
{
  "data": {
    "changes": [
      {
        "id": "cdc-log-uuid",
        "table_name": "messages",
        "record_id": "record-uuid",
        "operation": "INSERT",      // INSERT, UPDATE, or DELETE
        "old_data": { ... },        // Previous state (null for INSERT)
        "new_data": {               // New state
          "id": "uuid",
          "thread_id": "uuid",
          "sender_id": "uuid",
          "content": "Hello!",
          "content_type": "text",
          "is_encrypted": false,
          "created_at": "2024-01-01T00:00:00Z"
        },
        "changed_fields": ["content", "edited_at"],
        "timestamp": "2024-01-01T00:00:00Z"
      }
    ],
    "next_cursor": 12350           // Use this for next pull
  }
}
```

#### Behavior
- Returns maximum 100 changes per request
- Changes ordered by CDC log ID (chronological)
- `next_cursor` is the ID of the last change returned
- If no new changes, returns empty array with same cursor

#### Error Responses

**400 Bad Request**
```json
{
  "error": "Missing required parameter: thread_id"
}
```

**403 Forbidden**
```json
{
  "error": "Unauthorized"
}
```
User is not a participant in the requested thread.

**404 Not Found**
```json
{
  "error": "not_found"
}
```
Thread does not exist.

---

### 2. Push Changes (Client → Server)

**Endpoint:** `POST /api/v1/sync/push`

Push local CDC changes to the server.

#### Request Headers
```
Authorization: Bearer <access_token>
Content-Type: application/json
```

#### Request Body
```json
{
  "thread_id": "uuid",           // Required: Thread to sync
  "changes": [                   // Required: Array of CDC logs
    {
      "table_name": "messages",
      "record_id": "uuid",
      "operation": "INSERT",
      "old_data": null,
      "new_data": {
        "id": "uuid",
        "thread_id": "uuid",
        "sender_id": "uuid",
        "content": "New message",
        "content_type": "text",
        "client_created_at": "2024-01-01T00:00:00Z"
      },
      "timestamp": "2024-01-01T00:00:00Z"
    },
    {
      "table_name": "messages",
      "record_id": "uuid",
      "operation": "UPDATE",
      "old_data": { "content": "Old" },
      "new_data": {
        "id": "uuid",
        "content": "Updated",
        "edited_at": "2024-01-01T00:01:00Z"
      },
      "timestamp": "2024-01-01T00:01:00Z"
    },
    {
      "table_name": "messages",
      "record_id": "uuid",
      "operation": "DELETE",
      "old_data": { "content": "To delete" },
      "new_data": {
        "id": "uuid",
        "is_deleted": true,
        "deleted_at": "2024-01-01T00:02:00Z"
      },
      "timestamp": "2024-01-01T00:02:00Z"
    }
  ]
}
```

#### Success Response (200 OK)
```json
{
  "data": {
    "applied": 2,                 // Successfully applied changes
    "failed": 1,                  // Failed changes
    "results": [
      {
        "index": 0,
        "success": true
      },
      {
        "index": 1,
        "success": true
      },
      {
        "index": 2,
        "success": false,
        "error": "Validation failed: content can't be blank"
      }
    ]
  }
}
```

#### Conflict Resolution
- **Strategy:** Last-Write-Wins (based on timestamp)
- Server timestamp takes precedence over client timestamp
- Conflicts are resolved automatically during application
- No manual conflict resolution required

#### Error Responses

**400 Bad Request**
```json
{
  "error": "Missing required parameters: thread_id and changes"
}
```

**403 Forbidden**
```json
{
  "error": "Unauthorized"
}
```

---

## CDC Log Structure

### Supported Tables
- `messages` - Chat messages
- `read_receipts` - Message read status

### Operations

#### INSERT
Creates a new record. `old_data` should be `null`.

```json
{
  "operation": "INSERT",
  "old_data": null,
  "new_data": {
    "id": "uuid",
    // ... all required fields
  }
}
```

#### UPDATE
Modifies an existing record. Include changed fields in `new_data`.

```json
{
  "operation": "UPDATE",
  "old_data": {
    "content": "Original"
  },
  "new_data": {
    "id": "uuid",
    "content": "Updated",
    "edited_at": "2024-01-01T00:00:00Z"
  },
  "changed_fields": ["content", "edited_at"]
}
```

#### DELETE
Soft-deletes a record (sets `is_deleted: true`).

```json
{
  "operation": "DELETE",
  "old_data": {
    "content": "To delete"
  },
  "new_data": {
    "id": "uuid",
    "is_deleted": true,
    "deleted_at": "2024-01-01T00:00:00Z"
  }
}
```

---

## Message Schema (for CDC new_data)

### Required Fields (INSERT)
```typescript
{
  id: string;              // UUID
  thread_id: string;       // UUID
  sender_id: string;       // UUID
  content_type: string;    // "text" | "image" | "video" | "audio" | "file" | "location"
  content?: string;        // Required for text messages
  media_url?: string;      // Required for media messages
}
```

### Optional Fields
```typescript
{
  media_size?: number;
  media_mime_type?: string;
  is_encrypted?: boolean;
  encryption_key_id?: string;
  reply_to_id?: string;           // UUID of replied message
  client_created_at?: string;     // ISO8601 timestamp
  edited_at?: string;             // ISO8601 timestamp
  deleted_at?: string;            // ISO8601 timestamp
  is_deleted?: boolean;
}
```

---

## Sync Flow (iOS Client)

### Initial Sync
```
1. Client: POST /api/v1/sync/pull { thread_id, last_sync_cursor: 0 }
2. Server: Returns all CDC changes
3. Client: Applies changes to local DB
4. Client: Stores next_cursor for subsequent syncs
```

### Incremental Sync
```
1. Client: POST /api/v1/sync/pull { thread_id, last_sync_cursor: <stored> }
2. Server: Returns changes since cursor
3. Client: Applies changes
4. Client: Updates stored cursor
```

### Push Local Changes
```
1. Client: Collects local CDC logs not yet synced
2. Client: POST /api/v1/sync/push { thread_id, changes: [...] }
3. Server: Applies changes, returns results
4. Client: Marks successfully applied changes as synced
5. Client: Retries failed changes or logs errors
```

### Bidirectional Sync Pattern
```
while (has_network) {
  // Pull server changes
  pull_response = sync_pull(thread_id, last_cursor)
  apply_remote_changes(pull_response.changes)
  last_cursor = pull_response.next_cursor

  // Push local changes
  local_changes = get_unsynced_local_changes(thread_id)
  if (local_changes.length > 0) {
    push_response = sync_push(thread_id, local_changes)
    mark_synced(push_response.results)
  }

  sleep(sync_interval)
}
```

---

## Performance Considerations

### Pull Endpoint
- Maximum 100 changes per request
- Use pagination with `next_cursor` for large sync operations
- Poll every 5-10 seconds for real-time feel
- Use exponential backoff on errors

### Push Endpoint
- Batch changes up to 50 per request for optimal performance
- Apply transactional guarantees (all-or-nothing not guaranteed)
- Partial success possible (check `results` array)
- Retry failed changes individually

---

## Security

### Authentication
- All requests require valid JWT access token
- Token must be included in `Authorization: Bearer <token>` header

### Authorization
- Users can only sync threads they are participants in
- `thread_id` validated against `thread_participants` table
- 403 Forbidden if user not authorized

### Data Validation
- All CDC logs validated before application
- Invalid changes return error in `results` array
- No cascading failures (one invalid change doesn't block others)

---

## Testing Recommendations

### iOS Client Testing
1. Test initial sync with empty local DB
2. Test incremental sync with existing data
3. Test push of local changes
4. Test conflict resolution (concurrent edits)
5. Test offline queue (changes made while offline)
6. Test reconnection after network failure
7. Test pagination (>100 changes)
8. Test partial push success/failure handling

### Integration Testing
```swift
// Example test flow
func testBidirectionalSync() async throws {
  // 1. Pull initial state
  let pullResponse = try await syncClient.pull(threadId: threadId, cursor: 0)
  XCTAssertEqual(pullResponse.changes.count, 0)

  // 2. Create local message
  let message = try localDB.insertMessage(content: "Test", threadId: threadId)
  let cdcLog = localDB.getCDCLog(for: message)

  // 3. Push to server
  let pushResponse = try await syncClient.push(threadId: threadId, changes: [cdcLog])
  XCTAssertEqual(pushResponse.applied, 1)

  // 4. Pull from another device should get the message
  let pullResponse2 = try await syncClient.pull(threadId: threadId, cursor: 0)
  XCTAssertEqual(pullResponse2.changes.count, 1)
  XCTAssertEqual(pullResponse2.changes[0].new_data["content"], "Test")
}
```

---

## Error Handling

### Client-Side Error Handling
```swift
do {
  let response = try await syncClient.pull(threadId: threadId, cursor: cursor)
  // Process response
} catch let error as SyncError {
  switch error {
    case .unauthorized:
      // Re-authenticate
    case .threadNotFound:
      // Remove thread from local DB
    case .networkError:
      // Retry with exponential backoff
    case .serverError:
      // Log and retry later
  }
}
```

### Server Behavior
- Validation errors return 400 with descriptive message
- Authorization errors return 403
- Missing resources return 404
- Server errors return 500 (rare, log and report)

---

## Version History

### v1.0.0 (2024-01-01)
- Initial sync API implementation
- Pull and push endpoints
- CDC log-based replication
- Last-write-wins conflict resolution
- Message table support

---

## Contact

For implementation questions or issues:
- Backend: Task 14 implementation
- iOS Client: Task 15 integration
- Architecture: See `docs/architecture/multi-device-sync.md`
