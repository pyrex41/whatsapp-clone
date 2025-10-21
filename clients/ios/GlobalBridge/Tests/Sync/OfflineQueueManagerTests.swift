//
//  OfflineQueueManagerTests.swift
//  GlobalBridge
//
//  Task 16.1: Tests for offline message queuing with CDC log
//

import XCTest
import SQLite
@testable import GlobalBridge

@MainActor
final class OfflineQueueManagerTests: XCTestCase {

    var queueManager: OfflineQueueManager!
    var databaseManager: DatabaseManager!
    var testThread: Thread!

    override func setUp() async throws {
        try await super.setUp()

        // Initialize DatabaseManager
        databaseManager = DatabaseManager.shared
        try await databaseManager.initialize()

        // Create test thread
        testThread = Thread(
            id: UUID(),
            threadType: .direct,
            title: "Test Thread",
            avatarUrl: nil,
            lastMessageAt: nil,
            isArchived: false,
            isMuted: false,
            databaseShardId: "test-shard-\(UUID().uuidString)",
            createdAt: Date(),
            updatedAt: Date()
        )

        try await databaseManager.createThread(testThread)

        // Initialize queue manager
        queueManager = OfflineQueueManager(databaseManager: databaseManager)
    }

    override func tearDown() async throws {
        // Clean up test data
        try? await databaseManager.deleteThread(id: testThread.id)
        databaseManager.closeAllConnections()

        queueManager = nil
        testThread = nil

        try await super.tearDown()
    }

    // MARK: - Queue Message Tests

    func testQueueMessage_WhenOffline_ShouldAddToQueue() async throws {
        // Given
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: UUID(),
            content: "Test message",
            status: .pending
        )

        // When
        try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)

        // Then
        let queuedCount = try await queueManager.getQueuedCount(shardId: testThread.databaseShardId)
        XCTAssertEqual(queuedCount, 1, "Should have 1 queued message")
    }

    func testQueueMessage_ShouldCreateCDCLogEntry() async throws {
        // Given
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: UUID(),
            content: "Test message with CDC"
        )

        // When
        try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)

        // Then
        let cdcLogs = try await databaseManager.fetchUnsyncedCDCLogs(
            shardId: testThread.databaseShardId,
            limit: 10
        )

        XCTAssertGreaterThan(cdcLogs.count, 0, "Should create CDC log entry")
        XCTAssertEqual(cdcLogs.first?.operation, .insert, "Operation should be insert")
        XCTAssertEqual(cdcLogs.first?.tableName, "messages", "Table name should be messages")
    }

    func testQueueMultipleMessages_ShouldMaintainOrder() async throws {
        // Given
        let message1 = Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "First")
        let message2 = Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Second")
        let message3 = Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Third")

        // When
        try await queueManager.queueMessage(message1, shardId: testThread.databaseShardId)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
        try await queueManager.queueMessage(message2, shardId: testThread.databaseShardId)
        try await Task.sleep(nanoseconds: 10_000_000)
        try await queueManager.queueMessage(message3, shardId: testThread.databaseShardId)

        // Then
        let queuedMessages = try await queueManager.getQueuedMessages(
            shardId: testThread.databaseShardId,
            limit: 10
        )

        XCTAssertEqual(queuedMessages.count, 3, "Should have 3 queued messages")
        XCTAssertEqual(queuedMessages[0].content, "First", "First message should be first")
        XCTAssertEqual(queuedMessages[1].content, "Second", "Second message should be second")
        XCTAssertEqual(queuedMessages[2].content, "Third", "Third message should be third")
    }

    // MARK: - Queue Statistics Tests

    func testGetQueueStatistics_ShouldReturnCorrectCounts() async throws {
        // Given
        let messages = [
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 1"),
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 2"),
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 3")
        ]

        for message in messages {
            try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)
            try await Task.sleep(nanoseconds: 5_000_000) // Small delay
        }

        // When
        let stats = try await queueManager.getQueueStatistics(shardId: testThread.databaseShardId)

        // Then
        XCTAssertEqual(stats.queuedCount, 3, "Should have 3 queued messages")
        XCTAssertNotNil(stats.oldestQueuedTimestamp, "Should have oldest timestamp")
        XCTAssertNotNil(stats.newestQueuedTimestamp, "Should have newest timestamp")
    }

    func testGetQueueStatistics_WhenEmpty_ShouldReturnZeroCounts() async throws {
        // When
        let stats = try await queueManager.getQueueStatistics(shardId: testThread.databaseShardId)

        // Then
        XCTAssertEqual(stats.queuedCount, 0, "Should have 0 queued messages")
        XCTAssertNil(stats.oldestQueuedTimestamp, "Should not have oldest timestamp")
        XCTAssertNil(stats.newestQueuedTimestamp, "Should not have newest timestamp")
    }

    // MARK: - Mark as Sent Tests

    func testMarkMessageAsSent_ShouldUpdateStatus() async throws {
        // Given
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: UUID(),
            content: "Test message",
            status: .pending
        )

        try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)

        // When
        try await queueManager.markMessageAsSent(
            messageId: message.id,
            shardId: testThread.databaseShardId
        )

        // Then
        let queuedCount = try await queueManager.getQueuedCount(shardId: testThread.databaseShardId)
        XCTAssertEqual(queuedCount, 0, "Should have 0 queued messages after marking as sent")
    }

    func testMarkMultipleMessagesAsSent_ShouldUpdateAllStatuses() async throws {
        // Given
        let messages = [
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 1"),
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 2")
        ]

        for message in messages {
            try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)
        }

        // When
        for message in messages {
            try await queueManager.markMessageAsSent(
                messageId: message.id,
                shardId: testThread.databaseShardId
            )
        }

        // Then
        let queuedCount = try await queueManager.getQueuedCount(shardId: testThread.databaseShardId)
        XCTAssertEqual(queuedCount, 0, "Should have 0 queued messages")
    }

    // MARK: - Clear Queue Tests

    func testClearQueue_ShouldRemoveAllQueuedMessages() async throws {
        // Given
        let messages = [
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 1"),
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 2"),
            Message(id: UUID(), threadId: testThread.id, senderId: UUID(), content: "Msg 3")
        ]

        for message in messages {
            try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)
        }

        // When
        try await queueManager.clearQueue(shardId: testThread.databaseShardId)

        // Then
        let queuedCount = try await queueManager.getQueuedCount(shardId: testThread.databaseShardId)
        XCTAssertEqual(queuedCount, 0, "Queue should be empty after clearing")
    }

    // MARK: - Batch Operations Tests

    func testGetQueuedMessagesBatch_ShouldReturnLimitedResults() async throws {
        // Given
        let messageCount = 150
        for i in 0..<messageCount {
            let message = Message(
                id: UUID(),
                threadId: testThread.id,
                senderId: UUID(),
                content: "Message \(i)"
            )
            try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)
        }

        // When
        let batch1 = try await queueManager.getQueuedMessages(
            shardId: testThread.databaseShardId,
            limit: 100
        )

        let batch2 = try await queueManager.getQueuedMessages(
            shardId: testThread.databaseShardId,
            limit: 100,
            offset: 100
        )

        // Then
        XCTAssertEqual(batch1.count, 100, "First batch should have 100 messages")
        XCTAssertEqual(batch2.count, 50, "Second batch should have 50 messages")
    }

    // MARK: - Error Handling Tests

    func testQueueMessage_WithInvalidShard_ShouldThrowError() async throws {
        // Given
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: UUID(),
            content: "Test message"
        )

        // When/Then
        do {
            try await queueManager.queueMessage(message, shardId: "invalid-shard")
            XCTFail("Should throw error for invalid shard")
        } catch {
            XCTAssertTrue(error is DatabaseError, "Should throw DatabaseError")
        }
    }

    func testGetQueuedMessages_WithInvalidShard_ShouldThrowError() async throws {
        // When/Then
        do {
            _ = try await queueManager.getQueuedMessages(
                shardId: "invalid-shard",
                limit: 10
            )
            XCTFail("Should throw error for invalid shard")
        } catch {
            XCTAssertTrue(error is DatabaseError, "Should throw DatabaseError")
        }
    }

    // MARK: - Performance Tests

    func testQueuePerformance_ShouldHandleLargeVolume() async throws {
        // Given
        let messageCount = 1000

        // When
        let startTime = Date()

        for i in 0..<messageCount {
            let message = Message(
                id: UUID(),
                threadId: testThread.id,
                senderId: UUID(),
                content: "Perf test message \(i)"
            )
            try await queueManager.queueMessage(message, shardId: testThread.databaseShardId)
        }

        let duration = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(duration, 10.0, "Should queue 1000 messages in under 10 seconds")

        let queuedCount = try await queueManager.getQueuedCount(shardId: testThread.databaseShardId)
        XCTAssertEqual(queuedCount, messageCount, "Should have all messages queued")
    }
}
