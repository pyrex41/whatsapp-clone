//
//  CDCManagerTests.swift
//  GlobalBridge
//
//  Task 13: Manual CDC for client-side sync - Test Suite
//  TDD Test-First Approach
//

import XCTest
import SQLite
@testable import GlobalBridge

@MainActor
final class CDCManagerTests: XCTestCase {

    var cdcManager: CDCManager!
    var databaseManager: DatabaseManager!
    var mockPhoenixManager: MockPhoenixChannelManager!
    var testThreadId: UUID!
    var testShardId: String!
    var testDeviceId: UUID!

    override func setUp() async throws {
        try await super.setUp()

        // Initialize components
        databaseManager = DatabaseManager.shared
        try await databaseManager.initialize()

        mockPhoenixManager = MockPhoenixChannelManager()

        testDeviceId = UUID()
        cdcManager = CDCManager(
            databaseManager: databaseManager,
            phoenixManager: mockPhoenixManager,
            deviceId: testDeviceId
        )

        // Create test thread
        testThreadId = UUID()
        testShardId = "test_shard_\(UUID().uuidString)"
        let testThread = Thread(
            id: testThreadId,
            threadType: .direct,
            title: "Test Thread",
            databaseShardId: testShardId
        )
        try await databaseManager.createThread(testThread)
    }

    override func tearDown() async throws {
        try await databaseManager.deleteThread(id: testThreadId)
        databaseManager.closeAllConnections()
        try await super.tearDown()
    }

    // MARK: - Task 13.1: CDC Triggers Tests

    func testCDCTriggerOnInsert() async throws {
        // Given: A new message is created
        let message = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "Test message",
            messageType: .text,
            status: .sent
        )

        // When: Message is inserted into database
        try await databaseManager.createMessage(message)

        // Then: CDC log should be automatically created via trigger
        let logs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)

        XCTAssertGreaterThan(logs.count, 0, "CDC log should be created by trigger")

        let insertLog = logs.first { $0.operation == .insert && $0.recordId == message.id }
        XCTAssertNotNil(insertLog, "Insert CDC log should exist")
        XCTAssertEqual(insertLog?.tableName, "messages")
        XCTAssertEqual(insertLog?.newData["content"], "Test message")
    }

    func testCDCTriggerOnUpdate() async throws {
        // Given: An existing message
        let message = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "Original content",
            messageType: .text,
            status: .sent
        )
        try await databaseManager.createMessage(message)

        // When: Message is updated
        let updatedMessage = Message(
            id: message.id,
            threadId: message.threadId,
            senderId: message.senderId,
            content: "Updated content",
            messageType: message.messageType,
            status: .delivered,
            createdAt: message.createdAt
        )
        try await databaseManager.updateMessage(updatedMessage)

        // Then: Update CDC log should be created
        let logs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)
        let updateLog = logs.first { $0.operation == .update && $0.recordId == message.id }

        XCTAssertNotNil(updateLog, "Update CDC log should exist")
        XCTAssertEqual(updateLog?.newData["content"], "Updated content")
        XCTAssertEqual(updateLog?.oldData?["content"], "Original content")
        XCTAssertTrue(updateLog?.changedFields?.contains("content") ?? false)
    }

    func testCDCTriggerOnDelete() async throws {
        // Given: An existing message
        let message = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "To be deleted",
            messageType: .text,
            status: .sent
        )
        try await databaseManager.createMessage(message)

        // When: Message is deleted
        try await databaseManager.deleteMessage(id: message.id, threadId: testThreadId)

        // Then: Delete CDC log should be created
        let logs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)
        let deleteLog = logs.first { $0.operation == .delete && $0.recordId == message.id }

        XCTAssertNotNil(deleteLog, "Delete CDC log should exist")
        XCTAssertNotNil(deleteLog?.oldData, "Old data should be captured on delete")
    }

    // MARK: - Task 13.2: Pull/Push Logic Tests

    func testPullChangesFromServer() async throws {
        // Given: Server has changes for this thread
        let serverLogs = [
            CDCLog(
                tableName: "messages",
                recordId: UUID(),
                operation: .insert,
                newData: ["content": "Server message 1", "status": "sent"],
                timestamp: Date().addingTimeInterval(-60)
            ),
            CDCLog(
                tableName: "messages",
                recordId: UUID(),
                operation: .insert,
                newData: ["content": "Server message 2", "status": "sent"],
                timestamp: Date().addingTimeInterval(-30)
            )
        ]
        mockPhoenixManager.mockServerLogs = serverLogs

        // When: Pulling changes
        let pulledLogs = try await cdcManager.pullChanges(for: testThreadId)

        // Then: Should receive server logs
        XCTAssertEqual(pulledLogs.count, 2)
        XCTAssertEqual(pulledLogs[0].newData["content"], "Server message 1")
        XCTAssertEqual(pulledLogs[1].newData["content"], "Server message 2")
        XCTAssertEqual(mockPhoenixManager.lastPullThreadId, testThreadId.uuidString)
    }

    func testPushChangesToServer() async throws {
        // Given: Local unsynced changes
        let message = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "Local message",
            messageType: .text,
            status: .pending
        )
        try await databaseManager.createMessage(message)

        let unsyncedLogs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)
        XCTAssertGreaterThan(unsyncedLogs.count, 0)

        // When: Pushing changes to server
        try await cdcManager.pushChanges(unsyncedLogs, for: testThreadId)

        // Then: Changes should be sent and marked as synced
        XCTAssertEqual(mockPhoenixManager.lastPushThreadId, testThreadId.uuidString)
        XCTAssertEqual(mockPhoenixManager.pushedLogs.count, unsyncedLogs.count)

        // Verify logs are marked as synced
        let remainingUnsynced = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)
        XCTAssertLessThan(remainingUnsynced.count, unsyncedLogs.count)
    }

    func testBidirectionalSync() async throws {
        // Given: Both local and server changes
        let localMessage = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "Local message",
            messageType: .text,
            status: .pending
        )
        try await databaseManager.createMessage(localMessage)

        let serverLog = CDCLog(
            tableName: "messages",
            recordId: UUID(),
            operation: .insert,
            newData: ["content": "Server message", "status": "sent"],
            timestamp: Date()
        )
        mockPhoenixManager.mockServerLogs = [serverLog]

        // When: Performing bidirectional sync
        try await cdcManager.syncThread(testThreadId)

        // Then: Both operations should complete
        XCTAssertTrue(mockPhoenixManager.didPush, "Local changes should be pushed")
        XCTAssertTrue(mockPhoenixManager.didPull, "Server changes should be pulled")
    }

    // MARK: - Task 13.3: Conflict Resolution Tests

    func testConflictResolutionLastWriteWins() async throws {
        // Given: Local and server updates to the same message
        let messageId = UUID()
        let localTimestamp = Date()
        let serverTimestamp = localTimestamp.addingTimeInterval(60) // Server is newer

        // Local change
        let localLog = CDCLog(
            tableName: "messages",
            recordId: messageId,
            operation: .update,
            oldData: ["content": "Original"],
            newData: ["content": "Local update"],
            timestamp: localTimestamp
        )

        // Server change (newer)
        let serverLog = CDCLog(
            tableName: "messages",
            recordId: messageId,
            operation: .update,
            oldData: ["content": "Original"],
            newData: ["content": "Server update"],
            timestamp: serverTimestamp
        )

        // When: Resolving conflict
        let winner = try await cdcManager.resolveConflict(local: localLog, remote: serverLog)

        // Then: Server change should win (newer timestamp)
        XCTAssertEqual(winner.newData["content"], "Server update")
        XCTAssertEqual(winner.timestamp, serverTimestamp)
    }

    func testConflictResolutionLocalWins() async throws {
        // Given: Local change is newer than server
        let messageId = UUID()
        let serverTimestamp = Date()
        let localTimestamp = serverTimestamp.addingTimeInterval(60) // Local is newer

        let localLog = CDCLog(
            tableName: "messages",
            recordId: messageId,
            operation: .update,
            newData: ["content": "Local update"],
            timestamp: localTimestamp
        )

        let serverLog = CDCLog(
            tableName: "messages",
            recordId: messageId,
            operation: .update,
            newData: ["content": "Server update"],
            timestamp: serverTimestamp
        )

        // When: Resolving conflict
        let winner = try await cdcManager.resolveConflict(local: localLog, remote: serverLog)

        // Then: Local change should win
        XCTAssertEqual(winner.newData["content"], "Local update")
        XCTAssertEqual(winner.timestamp, localTimestamp)
    }

    func testApplyRemoteChangesWithConflicts() async throws {
        // Given: Existing local message
        let messageId = UUID()
        let message = Message(
            id: messageId,
            threadId: testThreadId,
            senderId: UUID(),
            content: "Local version",
            messageType: .text,
            status: .sent,
            createdAt: Date().addingTimeInterval(-120)
        )
        try await databaseManager.createMessage(message)

        // Server has a newer update
        let serverLog = CDCLog(
            tableName: "messages",
            recordId: messageId,
            operation: .update,
            newData: [
                "id": messageId.uuidString,
                "content": "Server version",
                "status": "delivered"
            ],
            timestamp: Date() // Newer
        )

        // When: Applying remote changes
        try await cdcManager.applyRemoteChanges([serverLog], for: testThreadId)

        // Then: Local database should have server version
        let messages = try await databaseManager.fetchMessages(threadId: testThreadId)
        let updatedMessage = messages.first { $0.id == messageId }

        XCTAssertNotNil(updatedMessage)
        XCTAssertEqual(updatedMessage?.content, "Server version")
        XCTAssertEqual(updatedMessage?.status, .delivered)
    }

    // MARK: - Offline Sync Tests

    func testOfflineChangesQueuedForSync() async throws {
        // Given: Device is offline
        mockPhoenixManager.isConnected = false

        // When: Creating messages offline
        let message1 = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "Offline message 1",
            messageType: .text,
            status: .pending
        )
        let message2 = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "Offline message 2",
            messageType: .text,
            status: .pending
        )

        try await databaseManager.createMessage(message1)
        try await databaseManager.createMessage(message2)

        // Then: Changes should be logged locally
        let unsyncedLogs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)
        XCTAssertGreaterThanOrEqual(unsyncedLogs.count, 2)
    }

    func testReconnectSyncsOfflineChanges() async throws {
        // Given: Offline changes exist
        mockPhoenixManager.isConnected = false

        let message = Message(
            id: UUID(),
            threadId: testThreadId,
            senderId: UUID(),
            content: "Offline message",
            messageType: .text,
            status: .pending
        )
        try await databaseManager.createMessage(message)

        let unsyncedBefore = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)
        XCTAssertGreaterThan(unsyncedBefore.count, 0)

        // When: Reconnecting to network
        mockPhoenixManager.isConnected = true
        try await cdcManager.syncThread(testThreadId)

        // Then: Offline changes should be synced
        XCTAssertTrue(mockPhoenixManager.didPush)
        XCTAssertGreaterThan(mockPhoenixManager.pushedLogs.count, 0)
    }

    // MARK: - Edge Cases

    func testEmptyPullReturnsNoChanges() async throws {
        // Given: Server has no changes
        mockPhoenixManager.mockServerLogs = []

        // When: Pulling changes
        let logs = try await cdcManager.pullChanges(for: testThreadId)

        // Then: Should return empty array
        XCTAssertEqual(logs.count, 0)
    }

    func testPushWithNoLocalChanges() async throws {
        // Given: No local changes
        let unsyncedLogs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)

        // When: Attempting to push
        try await cdcManager.pushChanges(unsyncedLogs, for: testThreadId)

        // Then: Should complete without error
        XCTAssertEqual(mockPhoenixManager.pushedLogs.count, 0)
    }

    func testConcurrentSyncOperations() async throws {
        // Given: Multiple sync operations
        let operations = (0..<5).map { index in
            Message(
                id: UUID(),
                threadId: testThreadId,
                senderId: UUID(),
                content: "Concurrent message \(index)",
                messageType: .text,
                status: .pending
            )
        }

        // When: Creating messages concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for message in operations {
                group.addTask {
                    try await self.databaseManager.createMessage(message)
                }
            }
            try await group.waitForAll()
        }

        // Then: All changes should be logged
        let logs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: testShardId)
        XCTAssertGreaterThanOrEqual(logs.count, 5)
    }
}

// MARK: - Mock Phoenix Manager

@MainActor
class MockPhoenixChannelManager {
    var isConnected = true
    var mockServerLogs: [CDCLog] = []
    var pushedLogs: [CDCLog] = []
    var didPush = false
    var didPull = false
    var lastPullThreadId: String?
    var lastPushThreadId: String?

    func pullCDCLogs(threadId: String, since: Date?) async throws -> [CDCLog] {
        didPull = true
        lastPullThreadId = threadId
        return mockServerLogs
    }

    func pushCDCLogs(_ logs: [CDCLog], threadId: String) async throws {
        guard isConnected else {
            throw PhoenixError.notConnected
        }

        didPush = true
        lastPushThreadId = threadId
        pushedLogs.append(contentsOf: logs)
    }

    func isNetworkAvailable() async -> Bool {
        return isConnected
    }
}
