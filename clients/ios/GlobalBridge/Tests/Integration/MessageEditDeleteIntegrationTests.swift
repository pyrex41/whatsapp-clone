//
//  MessageEditDeleteIntegrationTests.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  Integration tests for message edit/delete with Phoenix sync
//

import XCTest
@testable import GlobalBridge

@MainActor
final class MessageEditDeleteIntegrationTests: XCTestCase {

    var phoenixManager: PhoenixChannelManager!
    var databaseManager: DatabaseManager!
    var offlineQueue: OfflineQueueManager!
    var editManager: MessageEditManager!
    var deletionHandler: MessageDeletionHandler!

    override func setUp() async throws {
        try await super.setUp()

        // Setup database
        databaseManager = DatabaseManager()
        try await databaseManager.initialize()

        // Setup offline queue
        offlineQueue = OfflineQueueManager(databaseManager: databaseManager)

        // Setup Phoenix manager
        let config = PhoenixConfig(
            socketURL: URL(string: "ws://localhost:4000/socket")!,
            enableLogging: true
        )
        phoenixManager = PhoenixChannelManager(config: config)

        // Setup managers
        editManager = MessageEditManager(
            phoenixChannelManager: phoenixManager,
            databaseManager: databaseManager,
            offlineQueueManager: offlineQueue
        )

        deletionHandler = MessageDeletionHandler(
            phoenixChannelManager: phoenixManager,
            databaseManager: databaseManager,
            offlineQueueManager: offlineQueue
        )
    }

    override func tearDown() async throws {
        await phoenixManager.disconnect()
        phoenixManager = nil
        editManager = nil
        deletionHandler = nil
        offlineQueue = nil
        databaseManager = nil
        try await super.tearDown()
    }

    // MARK: - Edit Integration Tests

    func testEditMessageEndToEnd() async throws {
        // Skip if backend not available
        try XCTSkipUnless(isBackendAvailable(), "Backend not available")

        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create and save message
        let message = Message(
            id: UUID(),
            threadId: threadId,
            senderId: currentUserId,
            content: "Original message",
            messageType: .text,
            status: .sent
        )

        try await databaseManager.createMessage(message)

        // Connect to Phoenix
        try await phoenixManager.connect(authToken: "test-token")
        try await phoenixManager.joinConversation(threadId.uuidString)

        // Edit the message
        try await editManager.editMessage(
            messageId: message.id,
            threadId: threadId,
            newContent: "Edited message",
            currentUserId: currentUserId
        )

        // Verify local update
        let updatedMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertEqual(updatedMessage?.content, "Edited message")
        XCTAssertNotNil(updatedMessage?.editedAt)

        // Wait for Phoenix sync confirmation
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Verify message is still edited after sync
        let syncedMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertEqual(syncedMessage?.content, "Edited message")
    }

    func testEditMessageWhileOffline() async throws {
        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create message
        let message = Message(
            id: UUID(),
            threadId: threadId,
            senderId: currentUserId,
            content: "Original message",
            messageType: .text,
            status: .sent
        )

        try await databaseManager.createMessage(message)

        // Edit while offline (don't connect to Phoenix)
        try await editManager.editMessage(
            messageId: message.id,
            threadId: threadId,
            newContent: "Edited offline",
            currentUserId: currentUserId
        )

        // Verify local update
        let updatedMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertEqual(updatedMessage?.content, "Edited offline")
        XCTAssertNotNil(updatedMessage?.editedAt)

        // Now connect and verify CDC would sync
        try await phoenixManager.connect(authToken: "test-token")

        // In real app, CDC would sync the edit
        // For test, just verify the message is in the correct state
        let finalMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertEqual(finalMessage?.content, "Edited offline")
    }

    // MARK: - Delete Integration Tests

    func testDeleteMessageForEveryoneEndToEnd() async throws {
        // Skip if backend not available
        try XCTSkipUnless(isBackendAvailable(), "Backend not available")

        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create message
        let message = Message(
            id: UUID(),
            threadId: threadId,
            senderId: currentUserId,
            content: "Message to delete",
            messageType: .text,
            status: .sent
        )

        try await databaseManager.createMessage(message)

        // Connect to Phoenix
        try await phoenixManager.connect(authToken: "test-token")
        try await phoenixManager.joinConversation(threadId.uuidString)

        // Delete message for everyone
        try await deletionHandler.deleteMessage(
            messageId: message.id,
            threadId: threadId,
            scope: .forEveryone,
            currentUserId: currentUserId
        )

        // Verify local deletion
        let deletedMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertNotNil(deletedMessage?.deletedAt)

        // Wait for Phoenix sync
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Verify still deleted
        let syncedMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertNotNil(syncedMessage?.deletedAt)
    }

    func testDeleteMessageForMeEndToEnd() async throws {
        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create message from another user
        let message = Message(
            id: UUID(),
            threadId: threadId,
            senderId: "another-user",
            content: "Someone else's message",
            messageType: .text,
            status: .sent
        )

        try await databaseManager.createMessage(message)

        // Delete for me only
        try await deletionHandler.deleteMessage(
            messageId: message.id,
            threadId: threadId,
            scope: .forMe,
            currentUserId: currentUserId
        )

        // Verify deletion for current user
        let deletedMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertTrue(deletionHandler.isDeleted(message: deletedMessage!, currentUserId: currentUserId))
        XCTAssertNil(deletedMessage?.deletedAt) // Not globally deleted
    }

    func testDeleteMessageWhileOffline() async throws {
        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create message
        let message = Message(
            id: UUID(),
            threadId: threadId,
            senderId: currentUserId,
            content: "Message to delete",
            messageType: .text,
            status: .sent
        )

        try await databaseManager.createMessage(message)

        // Delete while offline
        try await deletionHandler.deleteMessage(
            messageId: message.id,
            threadId: threadId,
            scope: .forEveryone,
            currentUserId: currentUserId
        )

        // Verify local deletion
        let deletedMessage = try await databaseManager.getMessage(id: message.id, threadId: threadId)
        XCTAssertNotNil(deletedMessage?.deletedAt)

        // CDC would sync when online
        try await phoenixManager.connect(authToken: "test-token")
    }

    // MARK: - Multi-Device Sync Tests

    func testEditSyncBetweenDevices() async throws {
        // Skip if backend not available
        try XCTSkipUnless(isBackendAvailable(), "Backend not available")

        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create message on device 1
        let message = Message(
            id: UUID(),
            threadId: threadId,
            senderId: currentUserId,
            content: "Original",
            messageType: .text,
            status: .sent
        )

        try await databaseManager.createMessage(message)

        // Simulate device 1 editing
        try await phoenixManager.connect(authToken: "test-token")
        try await phoenixManager.joinConversation(threadId.uuidString)

        try await editManager.editMessage(
            messageId: message.id,
            threadId: threadId,
            newContent: "Edited on device 1",
            currentUserId: currentUserId
        )

        // Simulate device 2 receiving edit
        let expectation = XCTestExpectation(description: "Receive edit on device 2")

        phoenixManager.onMessage(conversationId: threadId.uuidString) { phoenixMessage in
            if phoenixMessage.metadata?.edited == true {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - Performance Tests

    func testEditMessagePerformance() async throws {
        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create 100 messages
        var messages: [Message] = []
        for i in 0..<100 {
            let message = Message(
                id: UUID(),
                threadId: threadId,
                senderId: currentUserId,
                content: "Message \(i)",
                messageType: .text,
                status: .sent
            )
            try await databaseManager.createMessage(message)
            messages.append(message)
        }

        // Measure edit performance
        measure {
            Task {
                for message in messages {
                    try? await editManager.editMessage(
                        messageId: message.id,
                        threadId: threadId,
                        newContent: "Edited \(message.content)",
                        currentUserId: currentUserId
                    )
                }
            }
        }
    }

    func testBulkDeletionPerformance() async throws {
        let currentUserId = "test-user-\(UUID().uuidString)"
        let threadId = UUID()

        // Create 100 messages
        var messages: [Message] = []
        for i in 0..<100 {
            let message = Message(
                id: UUID(),
                threadId: threadId,
                senderId: currentUserId,
                content: "Message \(i)",
                messageType: .text,
                status: .sent
            )
            try await databaseManager.createMessage(message)
            messages.append(message)
        }

        // Measure deletion performance
        measure {
            Task {
                for message in messages {
                    try? await deletionHandler.deleteMessage(
                        messageId: message.id,
                        threadId: threadId,
                        scope: .forEveryone,
                        currentUserId: currentUserId
                    )
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func isBackendAvailable() -> Bool {
        // Check if Phoenix backend is running
        // In real tests, you might ping the backend or check environment variable
        return ProcessInfo.processInfo.environment["BACKEND_AVAILABLE"] == "true"
    }
}
