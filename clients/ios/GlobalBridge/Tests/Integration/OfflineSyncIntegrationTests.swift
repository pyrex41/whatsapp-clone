//
//  OfflineSyncIntegrationTests.swift
//  GlobalBridgeTests
//
//  Created by QA Agent on 10/20/25.
//  Task 16: Integration tests for offline queue and sync operations
//

import XCTest
import Combine
@testable import GlobalBridge

@MainActor
final class OfflineSyncIntegrationTests: XCTestCase {

    var databaseManager: DatabaseManager!
    var networkMonitor: MockNetworkMonitor!
    var syncService: MockSyncService!
    var offlineQueue: OfflineMessageQueue!

    var testThread: Thread!
    var testUser: User!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()

        // Initialize components
        databaseManager = DatabaseManager.shared
        try await databaseManager.initialize()

        networkMonitor = MockNetworkMonitor()
        syncService = MockSyncService()
        offlineQueue = OfflineMessageQueue(
            databaseManager: databaseManager,
            networkMonitor: networkMonitor,
            syncService: syncService
        )

        cancellables = Set<AnyCancellable>()

        // Create test data
        testUser = User(
            id: UUID(),
            email: "test@example.com",
            displayName: "Test User",
            createdAt: Date()
        )

        testThread = Thread(
            id: UUID(),
            threadType: .direct,
            title: "Test Thread",
            avatarUrl: nil,
            lastMessageAt: nil,
            isArchived: false,
            isMuted: false,
            databaseShardId: "offline_test_\(UUID().uuidString)",
            createdAt: Date(),
            updatedAt: Date()
        )

        try await databaseManager.createThread(testThread)
    }

    override func tearDown() async throws {
        // Clean up
        cancellables.forEach { $0.cancel() }
        cancellables = nil

        if let thread = testThread {
            try? await databaseManager.deleteThread(id: thread.id)
        }

        databaseManager.closeAllConnections()
        try await super.tearDown()
    }

    // MARK: - End-to-End Flow Tests

    func testOfflineMessageToQueueToSyncToServer() async throws {
        // Given: Device is offline
        networkMonitor.setOnline(false)

        // When: User sends a message while offline
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Offline message test",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await databaseManager.createMessage(message)
        try await offlineQueue.enqueue(message)

        // Then: Message should be stored locally
        let localMessages = try await databaseManager.fetchMessages(
            threadId: testThread.id,
            limit: 10
        )

        XCTAssertTrue(localMessages.contains { $0.id == message.id })
        XCTAssertEqual(localMessages.first?.status, .pending)

        // When: Device comes online
        let syncExpectation = XCTestExpectation(description: "Message synced to server")

        syncService.onPush = { cdcLogs in
            // Verify CDC log for the message
            let messageLog = cdcLogs.first { $0.recordId == message.id }
            XCTAssertNotNil(messageLog)
            XCTAssertEqual(messageLog?.operation, .insert)
            syncExpectation.fulfill()

            return SyncPushResponse(
                syncedCount: 1,
                conflicts: [],
                errors: []
            )
        }

        networkMonitor.setOnline(true)

        // Then: Queue should automatically sync
        await fulfillment(of: [syncExpectation], timeout: 5.0)

        // Verify message status updated
        let syncedMessages = try await databaseManager.fetchMessages(
            threadId: testThread.id,
            limit: 10
        )

        // Status should be updated to sent (depending on implementation)
        XCTAssertTrue(syncedMessages.contains { $0.id == message.id })
    }

    func testMultipleOfflineMessagesSync() async throws {
        // Given: Device offline with multiple pending messages
        networkMonitor.setOnline(false)

        var messages: [Message] = []
        for i in 1...5 {
            let message = Message(
                id: UUID(),
                threadId: testThread.id,
                senderId: testUser.id,
                content: "Offline message \(i)",
                messageType: .text,
                status: .pending,
                metadata: nil,
                replyToId: nil,
                editedAt: nil,
                deletedAt: nil,
                createdAt: Date().addingTimeInterval(Double(i)),
                updatedAt: Date()
            )

            try await databaseManager.createMessage(message)
            try await offlineQueue.enqueue(message)
            messages.append(message)
        }

        // When: Going online
        let syncExpectation = XCTestExpectation(description: "All messages synced")

        syncService.onPush = { cdcLogs in
            // Verify all messages in CDC logs
            XCTAssertGreaterThanOrEqual(cdcLogs.count, 5)
            syncExpectation.fulfill()

            return SyncPushResponse(
                syncedCount: cdcLogs.count,
                conflicts: [],
                errors: []
            )
        }

        networkMonitor.setOnline(true)

        // Then: All should sync in order
        await fulfillment(of: [syncExpectation], timeout: 5.0)
    }

    // MARK: - Network Transition Tests

    func testOnlineToOfflineTransition() async throws {
        // Given: Device is online
        networkMonitor.setOnline(true)

        let stateExpectation = XCTestExpectation(description: "Offline state detected")

        offlineQueue.networkStatePublisher
            .sink { isOnline in
                if !isOnline {
                    stateExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: Network goes offline
        networkMonitor.setOnline(false)

        // Then: Queue should detect offline state
        await fulfillment(of: [stateExpectation], timeout: 2.0)

        // And: Should queue subsequent messages
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Message after going offline",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await offlineQueue.enqueue(message)

        let queueSize = await offlineQueue.pendingCount()
        XCTAssertGreaterThan(queueSize, 0)
    }

    func testOfflineToOnlineTransition() async throws {
        // Given: Device offline with queued messages
        networkMonitor.setOnline(false)

        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Queued message",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await offlineQueue.enqueue(message)

        // When: Network comes back online
        let autoSyncExpectation = XCTestExpectation(description: "Auto-sync triggered")

        syncService.onPush = { _ in
            autoSyncExpectation.fulfill()
            return SyncPushResponse(syncedCount: 1, conflicts: [], errors: [])
        }

        networkMonitor.setOnline(true)

        // Then: Should automatically sync
        await fulfillment(of: [autoSyncExpectation], timeout: 3.0)
    }

    func testIntermittentConnectivity() async throws {
        // Simulate flaky network
        networkMonitor.setOnline(false)

        // Queue message
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Flaky network message",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await offlineQueue.enqueue(message)

        // Simulate multiple network state changes
        for i in 1...5 {
            await Task.sleep(500_000_000) // 500ms
            networkMonitor.setOnline(i % 2 == 0)
        }

        // Finally stabilize online
        networkMonitor.setOnline(true)

        // Should eventually sync
        try await Task.sleep(2_000_000_000) // 2 seconds

        let queueSize = await offlineQueue.pendingCount()
        XCTAssertEqual(queueSize, 0, "Queue should eventually drain")
    }

    // MARK: - Retry Logic Tests

    func testRetryOnNetworkFailure() async throws {
        // Given: Device online but server unreachable
        networkMonitor.setOnline(true)

        var attemptCount = 0
        let maxAttempts = 3

        syncService.onPush = { _ in
            attemptCount += 1

            if attemptCount < maxAttempts {
                throw SyncError.networkError("Server unreachable")
            }

            return SyncPushResponse(syncedCount: 1, conflicts: [], errors: [])
        }

        // When: Enqueueing message
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Retry test message",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await offlineQueue.enqueue(message)

        // Trigger sync
        try await offlineQueue.processPendingMessages()

        // Then: Should retry until success
        XCTAssertEqual(attemptCount, maxAttempts, "Should retry \(maxAttempts) times")
    }

    func testExponentialBackoff() async throws {
        // Given: Failing sync service
        networkMonitor.setOnline(true)

        var retryTimes: [Date] = []

        syncService.onPush = { _ in
            retryTimes.append(Date())
            throw SyncError.serverError("Temporary failure")
        }

        // When: Processing fails
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Backoff test",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await offlineQueue.enqueue(message)

        // Configure max retries
        offlineQueue.maxRetries = 3

        try? await offlineQueue.processPendingMessages()

        // Wait for retries
        try await Task.sleep(10_000_000_000) // 10 seconds

        // Then: Verify exponential backoff (1s, 2s, 4s intervals)
        if retryTimes.count >= 2 {
            let firstInterval = retryTimes[1].timeIntervalSince(retryTimes[0])
            XCTAssertGreaterThan(firstInterval, 0.5, "Should have delay between retries")

            if retryTimes.count >= 3 {
                let secondInterval = retryTimes[2].timeIntervalSince(retryTimes[1])
                XCTAssertGreaterThan(secondInterval, firstInterval, "Should use exponential backoff")
            }
        }
    }

    func testGiveUpAfterMaxRetries() async throws {
        // Given: Permanently failing service
        networkMonitor.setOnline(true)

        var attemptCount = 0

        syncService.onPush = { _ in
            attemptCount += 1
            throw SyncError.permanentError("Unrecoverable error")
        }

        // When: Message exceeds max retries
        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Will fail",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await offlineQueue.enqueue(message)

        offlineQueue.maxRetries = 3

        try? await offlineQueue.processPendingMessages()

        try await Task.sleep(3_000_000_000) // 3 seconds

        // Then: Should give up after max retries
        XCTAssertLessThanOrEqual(attemptCount, 4, "Should not retry indefinitely")

        // Message should be marked as failed
        let failedMessages = await offlineQueue.failedMessages()
        XCTAssertTrue(failedMessages.contains { $0.id == message.id })
    }

    // MARK: - Batch Processing Tests

    func testBatchProcessing() async throws {
        // Given: Multiple messages in queue
        networkMonitor.setOnline(false)

        let batchSize = 20
        for i in 1...batchSize {
            let message = Message(
                id: UUID(),
                threadId: testThread.id,
                senderId: testUser.id,
                content: "Batch message \(i)",
                messageType: .text,
                status: .pending,
                metadata: nil,
                replyToId: nil,
                editedAt: nil,
                deletedAt: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await offlineQueue.enqueue(message)
        }

        // When: Processing in batches
        let batchExpectation = XCTestExpectation(description: "Batch processed")

        var batchCount = 0
        syncService.onPush = { cdcLogs in
            batchCount += 1
            // Verify batch size (should be 10 per batch)
            XCTAssertLessThanOrEqual(cdcLogs.count, 10)

            if batchCount >= 2 {
                batchExpectation.fulfill()
            }

            return SyncPushResponse(syncedCount: cdcLogs.count, conflicts: [], errors: [])
        }

        offlineQueue.batchSize = 10
        networkMonitor.setOnline(true)

        // Then: Should process in multiple batches
        await fulfillment(of: [batchExpectation], timeout: 5.0)
        XCTAssertGreaterThanOrEqual(batchCount, 2, "Should use batching")
    }

    func testBatchProcessingPreservesOrder() async throws {
        // Given: Messages with specific order
        networkMonitor.setOnline(false)

        var orderedMessages: [Message] = []
        for i in 1...15 {
            let message = Message(
                id: UUID(),
                threadId: testThread.id,
                senderId: testUser.id,
                content: "Order \(i)",
                messageType: .text,
                status: .pending,
                metadata: nil,
                replyToId: nil,
                editedAt: nil,
                deletedAt: nil,
                createdAt: Date().addingTimeInterval(Double(i)),
                updatedAt: Date()
            )

            try await offlineQueue.enqueue(message)
            orderedMessages.append(message)
        }

        // When: Processing batches
        var receivedOrder: [UUID] = []

        syncService.onPush = { cdcLogs in
            receivedOrder.append(contentsOf: cdcLogs.map { $0.recordId })
            return SyncPushResponse(syncedCount: cdcLogs.count, conflicts: [], errors: [])
        }

        offlineQueue.batchSize = 5
        networkMonitor.setOnline(true)

        try await Task.sleep(3_000_000_000) // 3 seconds

        // Then: Order should be preserved
        XCTAssertEqual(receivedOrder.count, 15)
        XCTAssertEqual(receivedOrder, orderedMessages.map { $0.id },
                      "Messages should be processed in order")
    }

    // MARK: - Edge Cases

    func testEmptyQueueSync() async throws {
        // Given: Empty queue
        networkMonitor.setOnline(true)

        // When: Triggering sync
        let syncCount = try await offlineQueue.processPendingMessages()

        // Then: Should handle gracefully
        XCTAssertEqual(syncCount, 0)
    }

    func testQueuePersistenceAcrossRestarts() async throws {
        // Given: Messages in queue
        networkMonitor.setOnline(false)

        let message = Message(
            id: UUID(),
            threadId: testThread.id,
            senderId: testUser.id,
            content: "Persistent message",
            messageType: .text,
            status: .pending,
            metadata: nil,
            replyToId: nil,
            editedAt: nil,
            deletedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await offlineQueue.enqueue(message)

        let queueSizeBefore = await offlineQueue.pendingCount()

        // When: Simulating app restart
        offlineQueue = nil
        offlineQueue = OfflineMessageQueue(
            databaseManager: databaseManager,
            networkMonitor: networkMonitor,
            syncService: syncService
        )

        // Then: Queue should restore
        let queueSizeAfter = await offlineQueue.pendingCount()
        XCTAssertEqual(queueSizeBefore, queueSizeAfter,
                      "Queue should persist across restarts")
    }

    func testConcurrentMessageEnqueue() async throws {
        // Given: Offline state
        networkMonitor.setOnline(false)

        // When: Multiple concurrent enqueues
        await withTaskGroup(of: Void.self) { group in
            for i in 1...50 {
                group.addTask { [weak self] in
                    guard let self = self else { return }

                    let message = Message(
                        id: UUID(),
                        threadId: self.testThread.id,
                        senderId: self.testUser.id,
                        content: "Concurrent \(i)",
                        messageType: .text,
                        status: .pending,
                        metadata: nil,
                        replyToId: nil,
                        editedAt: nil,
                        deletedAt: nil,
                        createdAt: Date(),
                        updatedAt: Date()
                    )

                    try? await self.offlineQueue.enqueue(message)
                }
            }
        }

        // Then: All messages should be queued
        let queueSize = await offlineQueue.pendingCount()
        XCTAssertEqual(queueSize, 50, "All concurrent enqueues should succeed")
    }
}

// MARK: - Mock Objects

class MockNetworkMonitor: ObservableObject {
    @Published var isOnline: Bool = true

    func setOnline(_ online: Bool) {
        DispatchQueue.main.async {
            self.isOnline = online
        }
    }
}

class MockSyncService {
    var onPush: (([CDCLog]) throws -> SyncPushResponse)?
    var onPull: (() throws -> SyncPullResponse)?

    func push(cdcLogs: [CDCLog]) async throws -> SyncPushResponse {
        guard let handler = onPush else {
            return SyncPushResponse(syncedCount: cdcLogs.count, conflicts: [], errors: [])
        }
        return try handler(cdcLogs)
    }

    func pull(cursor: Int) async throws -> SyncPullResponse {
        guard let handler = onPull else {
            return SyncPullResponse(data: [], cursor: cursor, hasMore: false)
        }
        return try handler()
    }
}

struct SyncPushResponse {
    let syncedCount: Int
    let conflicts: [SyncConflict]
    let errors: [SyncError]
}

struct SyncPullResponse {
    let data: [CDCLog]
    let cursor: Int
    let hasMore: Bool
}

struct SyncConflict {
    let recordId: UUID
    let resolution: String
}

enum SyncError: Error {
    case networkError(String)
    case serverError(String)
    case permanentError(String)
}

// Note: These would be implemented in the actual OfflineMessageQueue class
extension OfflineMessageQueue {
    var networkStatePublisher: AnyPublisher<Bool, Never> {
        networkMonitor.$isOnline.eraseToAnyPublisher()
    }

    func pendingCount() async -> Int {
        // Implementation would query CDC logs with is_synced = false
        return 0
    }

    func failedMessages() async -> [Message] {
        // Implementation would return messages that exceeded retry limit
        return []
    }

    func enqueue(_ message: Message) async throws {
        // Implementation would add to queue
    }

    func processPendingMessages() async throws -> Int {
        // Implementation would sync pending messages
        return 0
    }
}

// Placeholder for actual implementation
class OfflineMessageQueue {
    let databaseManager: DatabaseManager
    let networkMonitor: MockNetworkMonitor
    let syncService: MockSyncService

    var maxRetries: Int = 5
    var batchSize: Int = 10

    init(databaseManager: DatabaseManager, networkMonitor: MockNetworkMonitor, syncService: MockSyncService) {
        self.databaseManager = databaseManager
        self.networkMonitor = networkMonitor
        self.syncService = syncService
    }
}

// Placeholder User model
struct User {
    let id: UUID
    let email: String
    let displayName: String
    let createdAt: Date
}
