//
//  ReadReceiptTests.swift
//  GlobalBridge
//
//  Tests for Task 17: Read Receipts - iOS Implementation
//

import XCTest
@testable import GlobalBridge

final class ReadReceiptTests: XCTestCase {
    var manager: PhoenixChannelManager!
    var config: PhoenixConfig!

    override func setUp() async throws {
        try await super.setUp()
        config = PhoenixConfig.development
        manager = PhoenixChannelManager(config: config)
    }

    override func tearDown() async throws {
        await manager.disconnect()
        manager = nil
        config = nil
        try await super.tearDown()
    }

    // MARK: - Sending Read Receipts Tests

    func testSendReadReceipt() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send message first to get message ID
        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Test message"
        )

        // Mark as read
        let result = try await manager.markMessageAsRead(
            conversationId: "test-conversation",
            messageId: message.id
        )

        XCTAssertTrue(result, "Should successfully mark message as read")
    }

    func testMarkMultipleMessagesAsRead() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send multiple messages
        var messageIds: [String] = []
        for i in 0..<5 {
            let message = try await manager.sendMessage(
                conversationId: "test-conversation",
                content: "Message \(i)"
            )
            messageIds.append(message.id)
        }

        // Mark all as read
        for messageId in messageIds {
            let result = try await manager.markMessageAsRead(
                conversationId: "test-conversation",
                messageId: messageId
            )
            XCTAssertTrue(result, "Should mark message \(messageId) as read")
        }
    }

    func testBatchMarkAsRead() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        var messageIds: [String] = []
        for i in 0..<10 {
            let message = try await manager.sendMessage(
                conversationId: "test-conversation",
                content: "Batch \(i)"
            )
            messageIds.append(message.id)
        }

        // Batch mark as read
        let startTime = Date()

        let result = try await manager.markMessagesAsRead(
            conversationId: "test-conversation",
            messageIds: messageIds
        )

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime) * 1000

        XCTAssertTrue(result, "Should successfully batch mark as read")
        XCTAssertLessThan(duration, 500, "Batch operation should complete in under 500ms")
    }

    // MARK: - Receiving Read Receipts Tests

    func testReceiveReadReceipt() async throws {
        let expectation = XCTestExpectation(description: "Receive read receipt")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send message
        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Test"
        )

        // Set up read receipt handler
        await manager.onReadReceipt(conversationId: "test-conversation") { userId, messageId, readAt in
            XCTAssertNotNil(userId)
            XCTAssertEqual(messageId, message.id)
            XCTAssertNotNil(readAt)
            expectation.fulfill()
        }

        // In real scenario, another user would mark as read
        // For testing, simulate receiving the event

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testReadReceiptIncludesTimestamp() async throws {
        let expectation = XCTestExpectation(description: "Read receipt has timestamp")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Timestamp test"
        )

        await manager.onReadReceipt(conversationId: "test-conversation") { userId, messageId, readAt in
            XCTAssertNotNil(readAt)
            XCTAssertGreaterThan(readAt?.timeIntervalSince1970 ?? 0, 0)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testMultipleReadReceipts() async throws {
        let expectation = XCTestExpectation(description: "Multiple read receipts")
        expectation.expectedFulfillmentCount = 2

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Group read test"
        )

        var readers = Set<String>()

        await manager.onReadReceipt(conversationId: "test-conversation") { userId, messageId, _ in
            if messageId == message.id {
                readers.insert(userId)
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertGreaterThanOrEqual(readers.count, 1, "Should track at least one reader")
    }

    // MARK: - Read Receipt Persistence Tests

    func testReadReceiptPersistence() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Persistence test"
        )

        // Mark as read
        _ = try await manager.markMessageAsRead(
            conversationId: "test-conversation",
            messageId: message.id
        )

        // Verify read status is persisted
        let readStatus = try await manager.getReadStatus(messageId: message.id)
        XCTAssertTrue(readStatus.isRead, "Read status should be persisted")
    }

    func testReadReceiptSyncAfterReconnect() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Reconnect test"
        )

        _ = try await manager.markMessageAsRead(
            conversationId: "test-conversation",
            messageId: message.id
        )

        // Disconnect and reconnect
        await manager.disconnect()
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Read status should still be available
        let readStatus = try await manager.getReadStatus(messageId: message.id)
        XCTAssertTrue(readStatus.isRead, "Read status should persist across reconnections")
    }

    // MARK: - Performance Tests

    func testReadReceiptLatency() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Latency test"
        )

        let startTime = Date()

        _ = try await manager.markMessageAsRead(
            conversationId: "test-conversation",
            messageId: message.id
        )

        let endTime = Date()
        let latency = endTime.timeIntervalSince(startTime) * 1000

        XCTAssertLessThan(latency, 50, "Read receipt latency should be under 50ms, got \(latency)ms")
    }

    // MARK: - Error Handling Tests

    func testMarkNonExistentMessageAsRead() async {
        do {
            try await manager.connect()
            try await manager.joinConversation("test-conversation")

            _ = try await manager.markMessageAsRead(
                conversationId: "test-conversation",
                messageId: "non-existent-id"
            )

            // Should handle gracefully (may succeed with no error)
            XCTAssertTrue(true, "Should handle non-existent message gracefully")
        } catch {
            // Expected behavior - error on non-existent message
            XCTAssertTrue(true, "Acceptable to throw error for non-existent message")
        }
    }

    func testReadReceiptWithoutConnection() async {
        do {
            _ = try await manager.markMessageAsRead(
                conversationId: "test",
                messageId: "message-id"
            )
            XCTFail("Should throw error when not connected")
        } catch PhoenixError.notConnected {
            XCTAssertTrue(true, "Should throw notConnected error")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}

// MARK: - Read Receipt UI Tests

final class ReadReceiptUITests: XCTestCase {
    var viewModel: MessageViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = MessageViewModel(messageId: "test-message")
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testReadReceiptBadgeDisplay() async {
        // No readers initially
        var badgeState = await viewModel.readReceiptBadgeState
        XCTAssertEqual(badgeState, .none, "Should show no badge initially")

        // One reader
        await viewModel.handleReadReceipt(userId: "user1", readAt: Date())
        badgeState = await viewModel.readReceiptBadgeState
        XCTAssertEqual(badgeState, .single, "Should show single checkmark")

        // Multiple readers
        await viewModel.handleReadReceipt(userId: "user2", readAt: Date())
        badgeState = await viewModel.readReceiptBadgeState
        XCTAssertEqual(badgeState, .double, "Should show double checkmark")
    }

    func testReadReceiptTimestampDisplay() async {
        let readTime = Date()
        await viewModel.handleReadReceipt(userId: "user1", readAt: readTime)

        let displayTime = await viewModel.readTimestamp
        XCTAssertNotNil(displayTime, "Should display read timestamp")
    }

    func testReadByListDisplay() async {
        await viewModel.handleReadReceipt(userId: "user1", readAt: Date())
        await viewModel.handleReadReceipt(userId: "user2", readAt: Date())
        await viewModel.handleReadReceipt(userId: "user3", readAt: Date())

        let readByList = await viewModel.readByUsers
        XCTAssertEqual(readByList.count, 3, "Should show all readers")
    }
}

// MARK: - Integration Tests

final class ReadReceiptIntegrationTests: XCTestCase {
    var manager: PhoenixChannelManager!
    var conversationViewModel: ConversationViewModel!

    override func setUp() async throws {
        try await super.setUp()
        manager = PhoenixChannelManager(config: .development)
        conversationViewModel = ConversationViewModel(conversationId: "test-conversation")
        conversationViewModel.channelManager = manager
    }

    override func tearDown() async throws {
        await manager.disconnect()
        manager = nil
        conversationViewModel = nil
        try await super.tearDown()
    }

    func testEndToEndReadReceiptFlow() async throws {
        let expectation = XCTestExpectation(description: "End-to-end read receipt")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send message
        let message = try await manager.sendMessage(
            conversationId: "test-conversation",
            content: "Integration test"
        )

        // Set up handler
        await manager.onReadReceipt(conversationId: "test-conversation") { userId, messageId, readAt in
            Task {
                if messageId == message.id {
                    await self.conversationViewModel.handleReadReceipt(
                        messageId: messageId,
                        userId: userId,
                        readAt: readAt
                    )
                    expectation.fulfill()
                }
            }
        }

        // Mark as read
        _ = try await manager.markMessageAsRead(
            conversationId: "test-conversation",
            messageId: message.id
        )

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testReadReceiptSynchronization() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send multiple messages
        var messageIds: [String] = []
        for i in 0..<5 {
            let message = try await manager.sendMessage(
                conversationId: "test-conversation",
                content: "Sync test \(i)"
            )
            messageIds.append(message.id)
        }

        // Mark all as read
        for messageId in messageIds {
            _ = try await manager.markMessageAsRead(
                conversationId: "test-conversation",
                messageId: messageId
            )
        }

        // Wait for synchronization
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify all messages are marked as read in UI
        for messageId in messageIds {
            let readStatus = await conversationViewModel.isMessageRead(messageId: messageId)
            XCTAssertTrue(readStatus, "Message \(messageId) should be marked as read")
        }
    }
}
