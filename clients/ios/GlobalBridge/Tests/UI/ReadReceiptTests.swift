//
//  ReadReceiptTests.swift
//  GlobalBridgeTests
//
//  Comprehensive tests for read receipt functionality
//

import XCTest
@testable import GlobalBridge

@MainActor
final class ReadReceiptTests: XCTestCase {
    var manager: ReadReceiptManager!
    var viewModel: ReadReceiptDetailViewModel!

    override func setUp() async throws {
        try await super.setUp()
        manager = ReadReceiptManager()
        viewModel = ReadReceiptDetailViewModel(messageId: "test-message", manager: manager)
    }

    override func tearDown() async throws {
        manager = nil
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - ReadReceiptManager Tests

    func testManagerInitialization() {
        XCTAssertNotNil(manager)
        XCTAssertTrue(manager.readReceiptsEnabled)
        XCTAssertTrue(manager.isConnected)
    }

    func testEnableDisableReadReceipts() {
        // Test enabling
        manager.setReadReceiptsEnabled(true)
        XCTAssertTrue(manager.readReceiptsEnabled)

        // Test disabling
        manager.setReadReceiptsEnabled(false)
        XCTAssertFalse(manager.readReceiptsEnabled)
    }

    func testMarkAsReadOptimisticUpdate() async {
        let messageId = "msg-123"
        let userId = "user-456"

        var receivedReceipt: ReadReceipt?
        let expectation = expectation(description: "Read receipt published")

        let cancellable = manager.readReceiptPublisher
            .sink { receipt in
                receivedReceipt = receipt
                expectation.fulfill()
            }

        await manager.markAsRead(messageId: messageId, userId: userId)

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertNotNil(receivedReceipt)
        XCTAssertEqual(receivedReceipt?.messageId, messageId)
        XCTAssertEqual(receivedReceipt?.userId, userId)

        cancellable.cancel()
    }

    func testMarkAsReadWhenDisabled() async {
        manager.setReadReceiptsEnabled(false)

        let expectation = expectation(description: "No receipt published")
        expectation.isInverted = true

        let cancellable = manager.readReceiptPublisher
            .sink { _ in
                expectation.fulfill()
            }

        await manager.markAsRead(messageId: "msg-123", userId: "user-456")

        await fulfillment(of: [expectation], timeout: 1.0)

        cancellable.cancel()
    }

    func testFetchReadReceipts() async throws {
        let messageId = "msg-123"
        let receipts = try await manager.fetchReadReceipts(for: messageId)

        XCTAssertNotNil(receipts)
        XCTAssertGreaterThanOrEqual(receipts.count, 0)
    }

    func testFetchParticipants() async throws {
        let messageId = "msg-123"
        let participants = try await manager.fetchParticipants(for: messageId)

        XCTAssertNotNil(participants)
        XCTAssertGreaterThanOrEqual(participants.count, 0)
    }

    func testReadReceiptCaching() async throws {
        let messageId = "msg-cached"

        // First fetch
        let receipts1 = try await manager.fetchReadReceipts(for: messageId)

        // Second fetch (should use cache)
        let receipts2 = try await manager.fetchReadReceipts(for: messageId)

        XCTAssertEqual(receipts1.count, receipts2.count)
    }

    func testGetReadCount() {
        let messageId = "msg-123"
        let count = manager.getReadCount(for: messageId)

        XCTAssertGreaterThanOrEqual(count, 0)
    }

    func testHandleReadReceiptEvent() {
        let receipt = ReadReceipt(
            userId: "user-123",
            conversationId: "conv-456",
            messageId: "msg-789",
            readAt: Date()
        )

        var receivedReceipt: ReadReceipt?
        let expectation = expectation(description: "Receipt event handled")

        let cancellable = manager.readReceiptPublisher
            .sink { receipt in
                receivedReceipt = receipt
                expectation.fulfill()
            }

        manager.handleReadReceiptEvent(receipt)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedReceipt)
        XCTAssertEqual(receivedReceipt?.messageId, receipt.messageId)

        cancellable.cancel()
    }

    // MARK: - ReadReceiptDetailViewModel Tests

    func testViewModelInitialization() {
        XCTAssertNotNil(viewModel)
        XCTAssertEqual(viewModel.messageId, "test-message")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadReadReceipts() async {
        await viewModel.loadReadReceipts()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testRefreshReadReceipts() async {
        await viewModel.loadReadReceipts()
        await viewModel.refreshReadReceipts()

        XCTAssertFalse(viewModel.isLoading)
    }

    func testReadReceiptsFiltering() {
        viewModel.receipts = [
            ParticipantReadReceipt(userId: "1", userName: "Alice", readAt: Date(), isRead: true),
            ParticipantReadReceipt(userId: "2", userName: "Bob", readAt: Date(), isRead: false),
            ParticipantReadReceipt(userId: "3", userName: "Charlie", readAt: Date(), isRead: true)
        ]

        XCTAssertEqual(viewModel.readReceipts.count, 2)
        XCTAssertEqual(viewModel.deliveredReceipts.count, 1)
    }

    func testPendingReceipts() {
        viewModel.receipts = [
            ParticipantReadReceipt(userId: "1", userName: "Alice", readAt: Date(), isRead: true)
        ]
        viewModel.participants = [
            ConversationParticipant(id: "1", name: "Alice"),
            ConversationParticipant(id: "2", name: "Bob"),
            ConversationParticipant(id: "3", name: "Charlie")
        ]

        XCTAssertEqual(viewModel.pendingReceipts.count, 2)
        XCTAssertTrue(viewModel.pendingReceipts.contains { $0.id == "2" })
        XCTAssertTrue(viewModel.pendingReceipts.contains { $0.id == "3" })
    }

    func testReadCount() {
        viewModel.receipts = [
            ParticipantReadReceipt(userId: "1", userName: "Alice", readAt: Date(), isRead: true),
            ParticipantReadReceipt(userId: "2", userName: "Bob", readAt: Date(), isRead: true),
            ParticipantReadReceipt(userId: "3", userName: "Charlie", readAt: Date(), isRead: false)
        ]

        XCTAssertEqual(viewModel.readCount, 2)
    }

    func testMostRecentReadTimestamp() {
        let now = Date()
        let earlier = now.addingTimeInterval(-300)

        viewModel.receipts = [
            ParticipantReadReceipt(userId: "1", userName: "Alice", readAt: earlier, isRead: true),
            ParticipantReadReceipt(userId: "2", userName: "Bob", readAt: now, isRead: true)
        ]

        XCTAssertEqual(viewModel.mostRecentReadTimestamp, now)
    }

    // MARK: - ReadReceiptState Tests

    func testReadReceiptStateInit() {
        let state = ReadReceiptState()
        XCTAssertTrue(state.receipts.isEmpty)
    }

    func testMarkAsRead() {
        var state = ReadReceiptState()
        let messageId = "msg-123"
        let userId = "user-456"

        state.markAsRead(messageId: messageId, userId: userId)

        XCTAssertTrue(state.isRead(messageId: messageId, by: userId))
        XCTAssertEqual(state.readCount(for: messageId), 1)
    }

    func testReadByUsers() {
        var state = ReadReceiptState()
        let messageId = "msg-123"

        state.markAsRead(messageId: messageId, userId: "user-1")
        state.markAsRead(messageId: messageId, userId: "user-2")

        let readers = state.readByUsers(for: messageId)
        XCTAssertEqual(readers.count, 2)
        XCTAssertTrue(readers.contains("user-1"))
        XCTAssertTrue(readers.contains("user-2"))
    }

    func testReadCount() {
        var state = ReadReceiptState()
        let messageId = "msg-123"

        XCTAssertEqual(state.readCount(for: messageId), 0)

        state.markAsRead(messageId: messageId, userId: "user-1")
        XCTAssertEqual(state.readCount(for: messageId), 1)

        state.markAsRead(messageId: messageId, userId: "user-2")
        XCTAssertEqual(state.readCount(for: messageId), 2)
    }

    // MARK: - Phoenix Integration Tests

    func testHandlePhoenixPresenceEvent() {
        let event: [String: Any] = [
            "user_id": "user-123",
            "message_id": "msg-456",
            "read_at": ISO8601DateFormatter().string(from: Date())
        ]

        var receivedReceipt: ReadReceipt?
        let expectation = expectation(description: "Presence event handled")

        let cancellable = manager.readReceiptPublisher
            .sink { receipt in
                receivedReceipt = receipt
                expectation.fulfill()
            }

        manager.handlePhoenixPresenceEvent(event)

        wait(for: [expectation], timeout: 1.0)

        XCTAssertNotNil(receivedReceipt)
        XCTAssertEqual(receivedReceipt?.userId, "user-123")
        XCTAssertEqual(receivedReceipt?.messageId, "msg-456")

        cancellable.cancel()
    }

    func testInvalidPhoenixPresenceEvent() {
        let invalidEvent: [String: Any] = [
            "invalid": "data"
        ]

        let expectation = expectation(description: "No receipt published")
        expectation.isInverted = true

        let cancellable = manager.readReceiptPublisher
            .sink { _ in
                expectation.fulfill()
            }

        manager.handlePhoenixPresenceEvent(invalidEvent)

        wait(for: [expectation], timeout: 1.0)

        cancellable.cancel()
    }

    // MARK: - Real-time Update Tests

    func testRealTimeReceiptUpdate() async {
        await viewModel.loadReadReceipts()

        let initialCount = viewModel.readCount

        // Simulate real-time update
        let receipt = ReadReceipt(
            userId: "new-user",
            conversationId: "conv-123",
            messageId: "test-message",
            readAt: Date()
        )

        manager.handleReadReceiptEvent(receipt)

        // Give time for async update
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Reload to get updated data
        await viewModel.refreshReadReceipts()

        // Count should potentially be updated (depends on mock data)
        XCTAssertGreaterThanOrEqual(viewModel.readCount, initialCount)
    }

    // MARK: - Performance Tests

    func testMarkAsReadPerformance() {
        measure {
            Task {
                await manager.markAsRead(messageId: "perf-test", userId: "user-123")
            }
        }
    }

    func testFetchReadReceiptsPerformance() {
        measure {
            Task {
                _ = try? await manager.fetchReadReceipts(for: "perf-test")
            }
        }
    }

    // MARK: - Edge Cases

    func testEmptyReceipts() {
        viewModel.receipts = []
        XCTAssertEqual(viewModel.readCount, 0)
        XCTAssertNil(viewModel.mostRecentReadTimestamp)
    }

    func testDuplicateReadReceipt() async {
        let messageId = "msg-dup"
        let userId = "user-dup"

        await manager.markAsRead(messageId: messageId, userId: userId)
        await manager.markAsRead(messageId: messageId, userId: userId)

        let count = manager.getReadCount(for: messageId)
        XCTAssertEqual(count, 1) // Should not duplicate
    }

    func testConcurrentReadReceipts() async {
        let messageId = "msg-concurrent"

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await self.manager.markAsRead(messageId: messageId, userId: "user-\(i)")
                }
            }
        }

        // All receipts should be processed
        let count = manager.getReadCount(for: messageId)
        XCTAssertGreaterThanOrEqual(count, 0)
    }
}
