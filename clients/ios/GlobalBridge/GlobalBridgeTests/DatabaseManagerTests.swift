//
//  DatabaseManagerTests.swift
//  GlobalBridgeTests
//
//  Created by DatabaseManager on 10/20/25.
//  Tests for DatabaseManager persistence
//

import XCTest
@testable import GlobalBridge

@MainActor
final class DatabaseManagerTests: XCTestCase {

    var databaseManager: DatabaseManager!

    override func setUp() async throws {
        try await super.setUp()
        databaseManager = DatabaseManager.shared
        try await databaseManager.initialize()
    }

    override func tearDown() async throws {
        databaseManager.closeAllConnections()
        try await super.tearDown()
    }

    // MARK: - Thread Tests

    func testCreateThread() async throws {
        let thread = Thread(
            threadType: .direct,
            title: "Test Thread",
            isArchived: false,
            isMuted: false
        )

        try await databaseManager.createThread(thread)

        let threads = try await databaseManager.fetchThreads()
        XCTAssertTrue(threads.contains(where: { $0.id == thread.id }))
        XCTAssertEqual(threads.first?.title, "Test Thread")
    }

    func testFetchThreads() async throws {
        // Create multiple threads
        let thread1 = Thread(threadType: .direct, title: "Thread 1")
        let thread2 = Thread(threadType: .group, title: "Thread 2")

        try await databaseManager.createThread(thread1)
        try await databaseManager.createThread(thread2)

        let threads = try await databaseManager.fetchThreads()
        XCTAssertGreaterThanOrEqual(threads.count, 2)
    }

    func testUpdateThread() async throws {
        var thread = Thread(threadType: .direct, title: "Original Title")
        try await databaseManager.createThread(thread)

        thread.title = "Updated Title"
        thread.isArchived = true
        try await databaseManager.updateThread(thread)

        let threads = try await databaseManager.fetchThreads()
        let updatedThread = threads.first { $0.id == thread.id }

        XCTAssertEqual(updatedThread?.title, "Updated Title")
        XCTAssertTrue(updatedThread?.isArchived ?? false)
    }

    func testDeleteThread() async throws {
        let thread = Thread(threadType: .direct, title: "To Delete")
        try await databaseManager.createThread(thread)

        var threads = try await databaseManager.fetchThreads()
        XCTAssertTrue(threads.contains(where: { $0.id == thread.id }))

        try await databaseManager.deleteThread(id: thread.id)

        threads = try await databaseManager.fetchThreads()
        XCTAssertFalse(threads.contains(where: { $0.id == thread.id }))
    }

    // MARK: - Message Tests

    func testCreateMessage() async throws {
        // Create thread first
        let thread = Thread(threadType: .direct, title: "Message Thread")
        try await databaseManager.createThread(thread)

        let message = Message(
            threadId: thread.id,
            senderId: UUID(),
            content: "Test message",
            messageType: .text,
            status: .sent
        )

        try await databaseManager.createMessage(message)

        let messages = try await databaseManager.fetchMessages(threadId: thread.id)
        XCTAssertTrue(messages.contains(where: { $0.id == message.id }))
        XCTAssertEqual(messages.first?.content, "Test message")
    }

    func testFetchMessages() async throws {
        let thread = Thread(threadType: .group, title: "Chat Thread")
        try await databaseManager.createThread(thread)

        // Create multiple messages
        let senderId = UUID()
        let message1 = Message(threadId: thread.id, senderId: senderId, content: "Message 1")
        let message2 = Message(threadId: thread.id, senderId: senderId, content: "Message 2")
        let message3 = Message(threadId: thread.id, senderId: senderId, content: "Message 3")

        try await databaseManager.createMessage(message1)
        try await databaseManager.createMessage(message2)
        try await databaseManager.createMessage(message3)

        let messages = try await databaseManager.fetchMessages(threadId: thread.id)
        XCTAssertGreaterThanOrEqual(messages.count, 3)
    }

    func testMessagePagination() async throws {
        let thread = Thread(threadType: .group, title: "Pagination Thread")
        try await databaseManager.createThread(thread)

        // Create 10 messages
        let senderId = UUID()
        for i in 1...10 {
            let message = Message(
                threadId: thread.id,
                senderId: senderId,
                content: "Message \(i)"
            )
            try await databaseManager.createMessage(message)
        }

        // Fetch first 5
        let firstPage = try await databaseManager.fetchMessages(threadId: thread.id, limit: 5, offset: 0)
        XCTAssertEqual(firstPage.count, 5)

        // Fetch next 5
        let secondPage = try await databaseManager.fetchMessages(threadId: thread.id, limit: 5, offset: 5)
        XCTAssertEqual(secondPage.count, 5)

        // Ensure no overlap
        let firstIds = Set(firstPage.map { $0.id })
        let secondIds = Set(secondPage.map { $0.id })
        XCTAssertTrue(firstIds.isDisjoint(with: secondIds))
    }

    // MARK: - CDC Tests

    func testCDCLogCreation() async throws {
        let thread = Thread(threadType: .direct, title: "CDC Thread")
        try await databaseManager.createThread(thread)

        let message = Message(
            threadId: thread.id,
            senderId: UUID(),
            content: "CDC test message"
        )
        try await databaseManager.createMessage(message)

        // Fetch CDC logs
        let logs = try await databaseManager.fetchUnsyncedCDCLogs(
            shardId: thread.databaseShardId,
            limit: 10
        )

        XCTAssertGreaterThan(logs.count, 0)
        XCTAssertTrue(logs.contains(where: { $0.tableName == "messages" }))
    }

    // MARK: - Persistence Tests

    func testDataPersistsAcrossInitializations() async throws {
        // Create data
        let thread = Thread(threadType: .direct, title: "Persistent Thread")
        try await databaseManager.createThread(thread)

        let message = Message(
            threadId: thread.id,
            senderId: UUID(),
            content: "Persistent message"
        )
        try await databaseManager.createMessage(message)

        // Close connections
        databaseManager.closeAllConnections()

        // Reinitialize
        try await databaseManager.initialize()

        // Verify data still exists
        let threads = try await databaseManager.fetchThreads()
        XCTAssertTrue(threads.contains(where: { $0.id == thread.id }))

        let messages = try await databaseManager.fetchMessages(threadId: thread.id)
        XCTAssertTrue(messages.contains(where: { $0.id == message.id }))
    }

    // MARK: - Sharding Tests

    func testPerThreadDatabaseSharding() async throws {
        let thread1 = Thread(threadType: .direct, title: "Shard 1")
        let thread2 = Thread(threadType: .direct, title: "Shard 2")

        try await databaseManager.createThread(thread1)
        try await databaseManager.createThread(thread2)

        // Verify different shard IDs
        XCTAssertNotEqual(thread1.databaseShardId, thread2.databaseShardId)

        // Create messages in different shards
        let message1 = Message(threadId: thread1.id, senderId: UUID(), content: "Shard 1 message")
        let message2 = Message(threadId: thread2.id, senderId: UUID(), content: "Shard 2 message")

        try await databaseManager.createMessage(message1)
        try await databaseManager.createMessage(message2)

        // Verify messages are isolated per shard
        let thread1Messages = try await databaseManager.fetchMessages(threadId: thread1.id)
        let thread2Messages = try await databaseManager.fetchMessages(threadId: thread2.id)

        XCTAssertTrue(thread1Messages.contains(where: { $0.id == message1.id }))
        XCTAssertFalse(thread1Messages.contains(where: { $0.id == message2.id }))

        XCTAssertTrue(thread2Messages.contains(where: { $0.id == message2.id }))
        XCTAssertFalse(thread2Messages.contains(where: { $0.id == message1.id }))
    }

    // MARK: - Error Handling Tests

    func testCreateMessageWithInvalidThread() async throws {
        let invalidThreadId = UUID()
        let message = Message(
            threadId: invalidThreadId,
            senderId: UUID(),
            content: "Invalid thread message"
        )

        do {
            try await databaseManager.createMessage(message)
            XCTFail("Should throw error for invalid thread")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func testUpdateNonexistentThread() async throws {
        let thread = Thread(
            id: UUID(),
            threadType: .direct,
            title: "Nonexistent"
        )

        do {
            try await databaseManager.updateThread(thread)
            XCTFail("Should throw error for nonexistent thread")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }
}
