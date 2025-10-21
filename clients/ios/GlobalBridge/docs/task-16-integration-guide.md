# Task 16 Integration Guide

## Integration with Task 13 (CDCManager)

### Overview
Task 16 (Offline Queuing) depends on Task 13 (CDCManager) for the actual sync logic. Once Task 13 is complete, integrate as follows:

### 1. Update SyncActor.sendMessage()

**Current (Simulated):**
```swift
private func sendMessage(_ message: Message) async throws {
    // Simulate network delay
    try await Task.sleep(nanoseconds: 100_000_000)
    print("📤 Sending message: \(message.id)")
}
```

**After Task 13 Integration:**
```swift
private func sendMessage(_ message: Message) async throws {
    // Use CDCManager to push changes
    let cdcManager = CDCManager(
        databaseManager: databaseManager,
        phoenixClient: phoenixClient
    )

    // Push the message change
    try await cdcManager.pushChanges(
        shardId: message.threadId.uuidString,
        changes: [
            CDCLog(
                tableName: "messages",
                recordId: message.id,
                operation: .insert,
                newData: messageToDictionary(message)
            )
        ]
    )
}

private func messageToDictionary(_ message: Message) -> [String: String] {
    var dict: [String: String] = [
        "id": message.id.uuidString,
        "thread_id": message.threadId.uuidString,
        "sender_id": message.senderId.uuidString,
        "content": message.content,
        "message_type": message.messageType.rawValue,
        "status": message.status.rawValue,
        "created_at": ISO8601DateFormatter().string(from: message.createdAt),
        "updated_at": ISO8601DateFormatter().string(from: message.updatedAt)
    ]

    if let replyToId = message.replyToId {
        dict["reply_to_id"] = replyToId.uuidString
    }

    return dict
}
```

### 2. Add CDCManager to SyncActor

**Update SyncActor initialization:**
```swift
actor SyncActor {
    private let queueManager: OfflineQueueManager
    private let stateManager: PhoenixStateManager
    private let databaseManager: DatabaseManager
    private let cdcManager: CDCManager  // NEW

    init(
        queueManager: OfflineQueueManager,
        stateManager: PhoenixStateManager,
        databaseManager: DatabaseManager,
        cdcManager: CDCManager  // NEW
    ) {
        self.queueManager = queueManager
        self.stateManager = stateManager
        self.databaseManager = databaseManager
        self.cdcManager = cdcManager  // NEW
    }
}
```

### 3. Update performSync() to Use CDCManager

**Enhanced sync logic:**
```swift
private func performSync(shardId: String, attemptNumber: Int) async -> SyncResult {
    print("📤 Performing sync for shard: \(shardId) (attempt \(attemptNumber + 1))")

    do {
        // Fetch queued messages from CDC log
        let cdcLogs = try await databaseManager.fetchUnsyncedCDCLogs(
            shardId: shardId,
            limit: batchSize
        )

        if cdcLogs.isEmpty {
            return SyncResult(
                success: true,
                syncedCount: 0,
                failedCount: 0,
                batchSize: batchSize,
                error: nil,
                duration: 0
            )
        }

        // Push changes using CDCManager
        let pushResult = try await cdcManager.pushChanges(
            shardId: shardId,
            changes: cdcLogs
        )

        // Pull any remote changes
        let pullResult = try await cdcManager.pullChanges(
            shardId: shardId,
            since: Date().addingTimeInterval(-3600) // Last hour
        )

        // Mark successfully synced messages
        for log in cdcLogs {
            if let messageId = UUID(uuidString: log.recordId.uuidString) {
                try await queueManager.markMessageAsSent(
                    messageId: messageId,
                    shardId: shardId
                )
            }
        }

        return SyncResult(
            success: true,
            syncedCount: cdcLogs.count,
            failedCount: 0,
            batchSize: batchSize,
            error: nil,
            duration: 0
        )

    } catch {
        // Retry logic remains the same
        if attemptNumber < maxRetryAttempts {
            let delay = calculateRetryDelay(attemptNumber: attemptNumber)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            return await performSync(shardId: shardId, attemptNumber: attemptNumber + 1)
        } else {
            return SyncResult(
                success: false,
                syncedCount: 0,
                failedCount: 0,
                batchSize: batchSize,
                error: error.localizedDescription,
                duration: 0
            )
        }
    }
}
```

## Integration with Task 14 (Backend Sync API)

### API Endpoints Used

Task 14 provides these endpoints:
- `POST /api/sync/push` - Push local CDC changes
- `POST /api/sync/pull` - Pull remote CDC changes

### Request/Response Format

**Push Request:**
```json
{
  "thread_id": "uuid",
  "device_id": "uuid",
  "changes": [
    {
      "id": "uuid",
      "table_name": "messages",
      "record_id": "uuid",
      "operation": "insert",
      "new_data": {
        "id": "uuid",
        "thread_id": "uuid",
        "sender_id": "uuid",
        "content": "Hello",
        "status": "pending"
      },
      "timestamp": "2025-10-20T12:00:00Z"
    }
  ]
}
```

**Push Response:**
```json
{
  "success": true,
  "synced_count": 5,
  "failed_count": 0,
  "errors": []
}
```

**Pull Request:**
```json
{
  "thread_id": "uuid",
  "device_id": "uuid",
  "since": "2025-10-20T11:00:00Z"
}
```

**Pull Response:**
```json
{
  "changes": [
    {
      "id": "uuid",
      "table_name": "messages",
      "record_id": "uuid",
      "operation": "insert",
      "new_data": {...},
      "timestamp": "2025-10-20T12:00:00Z"
    }
  ],
  "has_more": false
}
```

## Complete Integration Example

### App Initialization

```swift
@MainActor
class AppCoordinator {
    let databaseManager: DatabaseManager
    let phoenixClient: PhoenixClient
    let stateManager: PhoenixStateManager
    let cdcManager: CDCManager
    let queueManager: OfflineQueueManager
    let syncActor: SyncActor

    init() async throws {
        // Initialize database
        databaseManager = DatabaseManager.shared
        try await databaseManager.initialize()

        // Initialize Phoenix
        phoenixClient = PhoenixClient(config: .production)
        stateManager = PhoenixStateManager(config: .production)

        // Initialize CDC manager (Task 13)
        cdcManager = CDCManager(
            databaseManager: databaseManager,
            phoenixClient: phoenixClient
        )

        // Initialize queue manager (Task 16.1)
        queueManager = OfflineQueueManager(
            databaseManager: databaseManager
        )

        // Initialize sync actor (Task 16.2)
        syncActor = SyncActor(
            queueManager: queueManager,
            stateManager: stateManager,
            databaseManager: databaseManager,
            cdcManager: cdcManager
        )

        // Start monitoring
        await syncActor.startMonitoring()
    }

    func sendMessage(_ message: Message, threadShardId: String) async throws {
        // Queue message (will be synced when online)
        try await queueManager.queueMessage(message, shardId: threadShardId)

        // Trigger immediate sync if online
        if stateManager.connectionState.isConnected {
            let result = await syncActor.triggerSync(shardId: threadShardId)
            print("Sync result: \(result.syncedCount) synced, \(result.failedCount) failed")
        }
    }
}
```

### View Model Integration

```swift
@MainActor
@Observable
class ChatViewModel {
    private let coordinator: AppCoordinator
    private let thread: Thread

    var messages: [Message] = []
    var isSyncing = false
    var syncError: String?

    func sendMessage(_ content: String) async {
        let message = Message(
            threadId: thread.id,
            senderId: currentUserId,
            content: content,
            status: .pending
        )

        do {
            // Queue and sync
            try await coordinator.sendMessage(
                message,
                threadShardId: thread.databaseShardId
            )

            // Update UI
            messages.append(message)

        } catch {
            syncError = error.localizedDescription
        }
    }

    func refreshMessages() async {
        do {
            messages = try await coordinator.databaseManager.fetchMessages(
                threadId: thread.id,
                limit: 50
            )
        } catch {
            print("Failed to refresh messages: \(error)")
        }
    }
}
```

## Testing Integration

### Integration Test

```swift
@MainActor
final class SyncIntegrationTests: XCTestCase {
    var coordinator: AppCoordinator!
    var testThread: Thread!

    override func setUp() async throws {
        coordinator = try await AppCoordinator()

        testThread = Thread(
            id: UUID(),
            threadType: .direct,
            databaseShardId: "test-\(UUID().uuidString)"
        )

        try await coordinator.databaseManager.createThread(testThread)
    }

    func testOfflineToOnlineSync() async throws {
        // 1. Simulate offline state
        await coordinator.stateManager.disconnect()

        // 2. Send messages while offline
        let messages = [
            Message(threadId: testThread.id, senderId: UUID(), content: "Msg 1"),
            Message(threadId: testThread.id, senderId: UUID(), content: "Msg 2"),
            Message(threadId: testThread.id, senderId: UUID(), content: "Msg 3")
        ]

        for message in messages {
            try await coordinator.sendMessage(
                message,
                threadShardId: testThread.databaseShardId
            )
        }

        // 3. Verify messages are queued
        let stats = try await coordinator.queueManager.getQueueStatistics(
            shardId: testThread.databaseShardId
        )
        XCTAssertEqual(stats.queuedCount, 3)

        // 4. Reconnect
        try await coordinator.stateManager.connect()

        // 5. Wait for auto-sync (or trigger manually)
        try await Task.sleep(nanoseconds: 6_000_000_000) // 6 seconds

        // 6. Verify queue is empty
        let finalStats = try await coordinator.queueManager.getQueueStatistics(
            shardId: testThread.databaseShardId
        )
        XCTAssertEqual(finalStats.queuedCount, 0)
    }
}
```

## Memory Notes for Task Coordination

Store this information for inter-task coordination:

**Memory Key:** `swarm/mobile-dev/task-16`

**Content:**
```json
{
  "task": "Task 16: Offline Message Queuing",
  "status": "completed",
  "components": {
    "OfflineQueueManager": {
      "path": "clients/ios/GlobalBridge/Core/Storage/OfflineQueueManager.swift",
      "public_api": {
        "queueMessage": "async throws -> Void",
        "getQueuedMessages": "async throws -> [Message]",
        "getQueueStatistics": "async throws -> QueueStatistics",
        "markMessageAsSent": "async throws -> Void"
      }
    },
    "SyncActor": {
      "path": "clients/ios/GlobalBridge/Core/Sync/SyncActor.swift",
      "public_api": {
        "startMonitoring": "async -> Void",
        "stopMonitoring": "async -> Void",
        "triggerSync": "async -> SyncResult",
        "calculateRetryDelay": "-> TimeInterval"
      },
      "configuration": {
        "batchSize": 100,
        "maxRetryAttempts": 5,
        "baseRetryDelay": 1.0,
        "maxRetryDelay": 60.0
      }
    }
  },
  "integration_requirements": {
    "task_13": {
      "needs": "CDCManager.pushChanges() and CDCManager.pullChanges()",
      "integration_point": "SyncActor.performSync()"
    },
    "task_14": {
      "needs": "Backend sync endpoints (/api/sync/push, /api/sync/pull)",
      "used_by": "CDCManager (Task 13)"
    }
  },
  "testing": {
    "unit_tests": [
      "OfflineQueueManagerTests",
      "SyncActorTests"
    ],
    "integration_tests": "Pending Task 13 completion"
  }
}
```

## Checklist for Integration

- [ ] Task 13 (CDCManager) is completed
- [ ] Update SyncActor to use CDCManager.pushChanges()
- [ ] Update SyncActor to use CDCManager.pullChanges()
- [ ] Add CDCManager to SyncActor initialization
- [ ] Update tests to use actual CDCManager
- [ ] Test offline→online sync flow
- [ ] Test retry logic with real network calls
- [ ] Test conflict resolution (if applicable)
- [ ] Update documentation with actual API calls
- [ ] Performance test with large queues (1000+ messages)
