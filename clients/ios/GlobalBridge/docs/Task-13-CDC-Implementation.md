# Task 13: Manual CDC (Change Data Capture) Implementation

## Overview

This document describes the implementation of Manual CDC for client-side synchronization in the GlobalBridge iOS application. CDC enables offline-first operation with automatic conflict resolution using a last-write-wins strategy.

## Architecture

### Components

1. **CDCManager** (`CDCManager.swift`)
   - Orchestrates bidirectional sync between client and server
   - Manages pull/push operations
   - Implements conflict resolution logic

2. **DatabaseManager** (`DatabaseManager.swift`)
   - SQLite triggers for automatic CDC event logging
   - Per-thread database sharding
   - CDC log storage and retrieval

3. **PhoenixChannelManager Extension** (`PhoenixChannelManager+CDC.swift`)
   - Network integration for CDC sync
   - Phoenix Channel communication
   - CDC log serialization/deserialization

## Task 13.1: SQLite Triggers for Automatic CDC Logging

### Implementation

SQLite triggers automatically capture INSERT, UPDATE, and DELETE operations on the messages table:

```sql
-- INSERT Trigger
CREATE TRIGGER messages_insert_cdc_trigger
AFTER INSERT ON messages
BEGIN
    INSERT INTO cdc_logs (...)
    VALUES (...);
END;

-- UPDATE Trigger
CREATE TRIGGER messages_update_cdc_trigger
AFTER UPDATE ON messages
BEGIN
    INSERT INTO cdc_logs (...)
    VALUES (...);
END;

-- DELETE Trigger
CREATE TRIGGER messages_delete_cdc_trigger
AFTER DELETE ON messages
BEGIN
    INSERT INTO cdc_logs (...)
    VALUES (...);
END;
```

### Benefits

- **Automatic**: No manual CDC logging required in application code
- **Reliable**: Database-level guarantees all changes are captured
- **Efficient**: Minimal performance overhead
- **Complete**: Captures old and new data for conflict resolution

## Task 13.2: Pull/Push Logic

### Pull Changes from Server

```swift
func pullChanges(for threadId: UUID) async throws -> [CDCLog] {
    // 1. Get last sync timestamp
    let since = lastSyncTimestamp[threadId.uuidString]

    // 2. Fetch changes from server via Phoenix
    let serverLogs = try await phoenixManager.pullCDCLogs(
        threadId: threadId.uuidString,
        since: since
    )

    // 3. Update last sync timestamp
    if let latestTimestamp = serverLogs.map(\.timestamp).max() {
        lastSyncTimestamp[threadId.uuidString] = latestTimestamp
    }

    return serverLogs
}
```

### Push Changes to Server

```swift
func pushChanges(_ logs: [CDCLog], for threadId: UUID) async throws {
    // 1. Send changes to server via Phoenix
    try await phoenixManager.pushCDCLogs(logs, threadId: threadId.uuidString)

    // 2. Mark logs as synced in local database
    try await markLogsAsSynced(logs, threadId: threadId)
}
```

### Bidirectional Sync

```swift
func syncThread(_ threadId: UUID) async throws {
    // 1. Check network availability
    guard phoenixManager.isNetworkAvailable() else { return }

    // 2. Pull server changes
    let serverLogs = try await pullChanges(for: threadId)

    // 3. Apply server changes locally
    if !serverLogs.isEmpty {
        try await applyRemoteChanges(serverLogs, for: threadId)
    }

    // 4. Get unsynced local changes
    let localLogs = try await databaseManager.fetchUnsyncedCDCLogs(...)

    // 5. Push local changes to server
    if !localLogs.isEmpty {
        try await pushChanges(localLogs, for: threadId)
    }
}
```

## Task 13.3: Conflict Resolution (Last-Write-Wins)

### Strategy

When both client and server have modified the same record, the change with the most recent timestamp wins.

### Implementation

```swift
func resolveConflict(local: CDCLog, remote: CDCLog) async throws -> CDCLog {
    // Compare timestamps - most recent wins
    let winner = local.timestamp > remote.timestamp ? local : remote

    print("🏆 Conflict resolution:")
    print("   Local timestamp:  \(local.timestamp)")
    print("   Remote timestamp: \(remote.timestamp)")
    print("   Winner: \(winner.timestamp == local.timestamp ? "Local" : "Remote")")

    return winner
}
```

### Conflict Detection

```swift
private func findLocalConflict(_ remoteLog: CDCLog, shardId: String) async throws -> CDCLog? {
    let localLogs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: shardId)

    // Look for log affecting the same record
    return localLogs.first { log in
        log.tableName == remoteLog.tableName &&
        log.recordId == remoteLog.recordId
    }
}
```

### Applying Changes with Conflict Resolution

```swift
func applyRemoteChanges(_ remoteLogs: [CDCLog], for threadId: UUID) async throws {
    for remoteLog in remoteLogs {
        // Check for local conflicts
        if let localLog = try await findLocalConflict(remoteLog, shardId: shardId) {
            // Resolve conflict using last-write-wins
            let winner = try await resolveConflict(local: localLog, remote: remoteLog)
            try await applyChange(winner, threadId: threadId)
        } else {
            // No conflict, apply directly
            try await applyChange(remoteLog, threadId: threadId)
        }
    }
}
```

## Usage Examples

### Basic Sync

```swift
let cdcManager = CDCManager(
    databaseManager: DatabaseManager.shared,
    phoenixManager: PhoenixChannelManager(config: config),
    deviceId: UIDevice.current.identifierForVendor ?? UUID()
)

// Sync a specific thread
try await cdcManager.syncThread(threadId)
```

### Offline-First Operation

```swift
// 1. User creates message while offline
let message = Message(...)
try await databaseManager.createMessage(message)
// CDC trigger automatically logs the change

// 2. When network becomes available
if phoenixManager.isNetworkAvailable() {
    try await cdcManager.syncThread(threadId)
    // Local changes are pushed, server changes are pulled
}
```

### Handling Conflicts

```swift
// Device A: Updates message at 10:00:00
let messageA = Message(id: id, content: "Version A", updatedAt: date1)
try await databaseManager.updateMessage(messageA)

// Device B: Updates same message at 10:00:30 (30 seconds later)
let messageB = Message(id: id, content: "Version B", updatedAt: date2)

// On sync, Device B's version wins (more recent timestamp)
try await cdcManager.syncThread(threadId)
// Result: All devices will have "Version B"
```

## Testing Strategy

### Test Coverage

1. **CDC Triggers** (`testCDCTriggerOnInsert`, `testCDCTriggerOnUpdate`, `testCDCTriggerOnDelete`)
   - Verify triggers fire on all operations
   - Validate CDC logs are created automatically
   - Check old_data and new_data are captured correctly

2. **Pull/Push Logic** (`testPullChangesFromServer`, `testPushChangesToServer`, `testBidirectionalSync`)
   - Test fetching changes from server
   - Test sending local changes to server
   - Verify bidirectional sync works correctly

3. **Conflict Resolution** (`testConflictResolutionLastWriteWins`, `testConflictResolutionLocalWins`)
   - Test last-write-wins strategy
   - Verify correct winner selection
   - Test applying winning changes

4. **Offline Scenarios** (`testOfflineChangesQueuedForSync`, `testReconnectSyncsOfflineChanges`)
   - Test offline change queuing
   - Test reconnection triggers sync
   - Verify all offline changes are synced

5. **Edge Cases** (`testEmptyPullReturnsNoChanges`, `testPushWithNoLocalChanges`, `testConcurrentSyncOperations`)
   - Test empty result sets
   - Test concurrent operations
   - Verify error handling

### Running Tests

```bash
# Run all CDC tests
xcodebuild test -scheme GlobalBridge -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:GlobalBridgeTests/CDCManagerTests

# Run specific test
xcodebuild test -scheme GlobalBridge -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:GlobalBridgeTests/CDCManagerTests/testBidirectionalSync
```

## Performance Considerations

### Optimization Strategies

1. **Batch Operations**
   - Pull/push multiple CDC logs in single network call
   - Configurable batch size (default: 100)

2. **Incremental Sync**
   - Track last sync timestamp per thread
   - Only fetch changes since last sync

3. **Database Sharding**
   - Per-thread databases reduce lock contention
   - Parallel sync operations for different threads

4. **Index Optimization**
   - Index on `is_synced` for fast unsynced log queries
   - Index on `timestamp` for chronological ordering
   - Composite index on `(table_name, record_id)` for conflict detection

### Memory Management

- CDC logs are marked as synced (not deleted) for audit trail
- Implement periodic cleanup of old synced logs
- Configurable retention policy

## Security Considerations

1. **Authentication**
   - Phoenix Channel authentication via JWT
   - Device ID tracking for audit

2. **Data Validation**
   - Validate CDC log structure before applying
   - Sanitize user input in message content

3. **Conflict Resolution**
   - Last-write-wins prevents malicious timestamp manipulation (server validates timestamps)
   - Audit trail preserves all changes

## Future Enhancements

1. **Advanced Conflict Resolution**
   - Support for custom conflict resolution strategies
   - Three-way merge for complex conflicts

2. **Optimistic Locking**
   - Version numbers for change detection
   - Prevent lost updates

3. **Compression**
   - Compress CDC logs for network transmission
   - Reduce bandwidth usage

4. **Selective Sync**
   - Sync only specific message types
   - Priority-based sync queue

## Files Created/Modified

### New Files
- `/clients/ios/GlobalBridge/Core/Storage/CDCManager.swift`
- `/clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixChannelManager+CDC.swift`
- `/clients/ios/GlobalBridge/Tests/Storage/CDCManagerTests.swift`
- `/clients/ios/GlobalBridge/docs/Task-13-CDC-Implementation.md`

### Modified Files
- `/clients/ios/GlobalBridge/Core/Storage/DatabaseManager.swift`
  - Added SQLite triggers for CDC logging
  - Added `markCDCLogAsSynced` method
  - Added `updateMessage` method
  - Added `deleteMessage` method
  - Modified `fetchUnsyncedCDCLogs` to filter by `is_synced`

## Conclusion

The CDC implementation provides robust offline-first synchronization with automatic conflict resolution. SQLite triggers ensure all changes are captured, while the last-write-wins strategy provides predictable conflict resolution. The system is designed for scalability, performance, and reliability.
