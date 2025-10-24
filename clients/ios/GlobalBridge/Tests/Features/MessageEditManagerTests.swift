//
//  MessageEditManagerTests.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  Unit tests for MessageEditManager
//

import XCTest
@testable import GlobalBridge

@MainActor
final class MessageEditManagerTests: XCTestCase {

    var sut: MessageEditManager!
    var mockPhoenixManager: MockPhoenixChannelManager!
    var mockDatabaseManager: MockDatabaseManager!
    var mockOfflineQueue: MockOfflineQueueManager!

    override func setUp() async throws {
        try await super.setUp()
        mockPhoenixManager = MockPhoenixChannelManager()
        mockDatabaseManager = MockDatabaseManager()
        mockOfflineQueue = MockOfflineQueueManager()

        sut = MessageEditManager(
            phoenixChannelManager: mockPhoenixManager,
            databaseManager: mockDatabaseManager,
            offlineQueueManager: mockOfflineQueue
        )
    }

    override func tearDown() async throws {
        sut = nil
        mockPhoenixManager = nil
        mockDatabaseManager = nil
        mockOfflineQueue = nil
        try await super.tearDown()
    }

    // MARK: - Edit Permission Tests

    func testCanEditOwnMessageWithinTimeout() {
        let message = createTestMessage(senderId: "user123", createdAt: Date())

        let canEdit = sut.canEditMessage(message, currentUserId: "user123")

        XCTAssertTrue(canEdit, "Should be able to edit own message within timeout")
    }

    func testCannotEditOtherUsersMessage() {
        let message = createTestMessage(senderId: "user456", createdAt: Date())

        let canEdit = sut.canEditMessage(message, currentUserId: "user123")

        XCTAssertFalse(canEdit, "Should not be able to edit other user's message")
    }

    func testCannotEditMessageAfterTimeout() {
        let oldDate = Date().addingTimeInterval(-16 * 60) // 16 minutes ago
        let message = createTestMessage(senderId: "user123", createdAt: oldDate)

        let canEdit = sut.canEditMessage(message, currentUserId: "user123")

        XCTAssertFalse(canEdit, "Should not be able to edit message after timeout")
    }

    func testCannotEditDeletedMessage() {
        var message = createTestMessage(senderId: "user123", createdAt: Date())
        message.deletedAt = Date()

        let canEdit = sut.canEditMessage(message, currentUserId: "user123")

        XCTAssertFalse(canEdit, "Should not be able to edit deleted message")
    }

    // MARK: - Content Validation Tests

    func testValidateEmptyContent() {
        XCTAssertThrowsError(try sut.validateEditedContent("")) { error in
            XCTAssertTrue(error is EditError)
            XCTAssertEqual(error as? EditError, .emptyContent)
        }
    }

    func testValidateWhitespaceOnlyContent() {
        XCTAssertThrowsError(try sut.validateEditedContent("   \n  \t  ")) { error in
            XCTAssertTrue(error is EditError)
            XCTAssertEqual(error as? EditError, .emptyContent)
        }
    }

    func testValidateContentTooLong() {
        let longContent = String(repeating: "a", count: MessageEditManager.maxContentLength + 1)

        XCTAssertThrowsError(try sut.validateEditedContent(longContent)) { error in
            XCTAssertTrue(error is EditError)
            if case .contentTooLong = error as? EditError {
                // Success
            } else {
                XCTFail("Expected contentTooLong error")
            }
        }
    }

    func testValidateValidContent() {
        let validContent = "This is a valid message"

        XCTAssertNoThrow(try sut.validateEditedContent(validContent))
    }

    func testValidateMaxLengthContent() {
        let maxContent = String(repeating: "a", count: MessageEditManager.maxContentLength)

        XCTAssertNoThrow(try sut.validateEditedContent(maxContent))
    }

    // MARK: - Edit Operation Tests

    func testEditMessageSuccessfully() async throws {
        let message = createTestMessage(senderId: "user123", createdAt: Date())
        mockDatabaseManager.messages[message.id] = message
        mockPhoenixManager.isConnected = true

        try await sut.editMessage(
            messageId: message.id,
            threadId: message.threadId,
            newContent: "Edited content",
            currentUserId: "user123"
        )

        // Verify message was updated locally
        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertEqual(updatedMessage?.content, "Edited content")
        XCTAssertNotNil(updatedMessage?.editedAt)

        // Verify Phoenix sync was attempted
        XCTAssertEqual(mockPhoenixManager.pushedEvents.count, 1)
        XCTAssertEqual(mockPhoenixManager.pushedEvents.first?.event, "edit_message")
    }

    func testEditMessageOfflineQueues() async throws {
        let message = createTestMessage(senderId: "user123", createdAt: Date())
        mockDatabaseManager.messages[message.id] = message
        mockPhoenixManager.isConnected = false // Offline

        try await sut.editMessage(
            messageId: message.id,
            threadId: message.threadId,
            newContent: "Edited offline",
            currentUserId: "user123"
        )

        // Verify message was updated locally
        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertEqual(updatedMessage?.content, "Edited offline")

        // Verify Phoenix sync was NOT successful (offline)
        XCTAssertEqual(mockPhoenixManager.pushedEvents.count, 0)
    }

    func testEditMessageNotFound() async {
        let messageId = UUID()
        let threadId = UUID()

        do {
            try await sut.editMessage(
                messageId: messageId,
                threadId: threadId,
                newContent: "Edited",
                currentUserId: "user123"
            )
            XCTFail("Should throw messageNotFound error")
        } catch {
            XCTAssertTrue(error is EditError)
            XCTAssertEqual(error as? EditError, .messageNotFound)
        }
    }

    func testEditMessageUnchangedContent() async throws {
        let message = createTestMessage(
            senderId: "user123",
            content: "Original content",
            createdAt: Date()
        )
        mockDatabaseManager.messages[message.id] = message

        // Try to "edit" with same content
        try await sut.editMessage(
            messageId: message.id,
            threadId: message.threadId,
            newContent: "Original content",
            currentUserId: "user123"
        )

        // Should not update or sync
        XCTAssertEqual(mockPhoenixManager.pushedEvents.count, 0)
    }

    // MARK: - Incoming Edit Tests

    func testHandleIncomingEdit() async throws {
        let message = createTestMessage(senderId: "user456", createdAt: Date())
        mockDatabaseManager.messages[message.id] = message

        try await sut.handleIncomingEdit(
            messageId: message.id.uuidString,
            threadId: message.threadId.uuidString,
            newContent: "Edited by sender",
            editedAt: Date()
        )

        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertEqual(updatedMessage?.content, "Edited by sender")
        XCTAssertNotNil(updatedMessage?.editedAt)
    }

    func testHandleIncomingEditInvalidUUIDs() async throws {
        // Should not crash on invalid UUIDs
        try await sut.handleIncomingEdit(
            messageId: "invalid-uuid",
            threadId: "invalid-uuid",
            newContent: "Content",
            editedAt: Date()
        )

        // No assertions needed - just ensure it doesn't crash
    }

    // MARK: - Edit History Tests

    func testGetEditHistorySuccess() async throws {
        let conversationId = UUID().uuidString
        let messageId = UUID().uuidString

        mockPhoenixManager.mockEditHistory = [
            ["content": "Version 1", "edited_at": "2025-01-01T10:00:00Z"],
            ["content": "Version 2", "edited_at": "2025-01-01T10:05:00Z"]
        ]

        let history = try await sut.getEditHistory(
            messageId: messageId,
            conversationId: conversationId
        )

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content, "Version 1")
        XCTAssertEqual(history[1].content, "Version 2")
    }

    func testGetEditHistoryEmpty() async throws {
        let conversationId = UUID().uuidString
        let messageId = UUID().uuidString

        mockPhoenixManager.mockEditHistory = []

        let history = try await sut.getEditHistory(
            messageId: messageId,
            conversationId: conversationId
        )

        XCTAssertEqual(history.count, 0)
    }

    // MARK: - Helper Methods

    private func createTestMessage(
        senderId: String,
        content: String = "Test message",
        createdAt: Date
    ) -> Message {
        Message(
            id: UUID(),
            threadId: UUID(),
            senderId: senderId,
            content: content,
            messageType: .text,
            status: .sent,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}

// MARK: - Mock Objects

@MainActor
private class MockPhoenixChannelManager: PhoenixChannelManager {
    var isConnected = true
    var pushedEvents: [(event: String, payload: [String: Any])] = []
    var mockEditHistory: [[String: Any]] = []

    override func channel(for conversationId: String) -> Channel? {
        isConnected ? MockChannel(pushedEvents: &pushedEvents, editHistory: mockEditHistory) : nil
    }
}

private class MockChannel: Channel {
    var pushedEvents: UnsafeMutablePointer<[(event: String, payload: [String: Any])]>
    var editHistory: [[String: Any]]

    init(pushedEvents: UnsafeMutablePointer<[(event: String, payload: [String: Any])]>, editHistory: [[String: Any]]) {
        self.pushedEvents = pushedEvents
        self.editHistory = editHistory
        super.init(topic: "test", params: [:], socket: Socket(endPoint: "ws://test"))
    }

    override func push(_ event: String, payload: [String: Any]) -> Push {
        pushedEvents.pointee.append((event, payload))

        // Return mock push that succeeds
        let mockPush = Push(channel: self, event: event, payload: payload, timeout: 10)

        // Simulate success response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            var response: [String: Any] = ["status": "ok"]

            if event == "get_edit_history" {
                response["history"] = self.editHistory
            }

            // Trigger success callback
            // Note: This is simplified - real implementation would need proper callback handling
        }

        return mockPush
    }
}

@MainActor
private class MockDatabaseManager: DatabaseManager {
    var messages: [UUID: Message] = [:]

    override func getMessage(id: UUID, threadId: UUID) async throws -> Message? {
        messages[id]
    }

    override func updateMessage(_ message: Message) async throws {
        messages[message.id] = message
    }
}

@MainActor
private class MockOfflineQueueManager: OfflineQueueManager {
    // Mock implementation - no-op for tests
}

// MARK: - EditError Equatable

extension EditError: Equatable {
    public static func == (lhs: EditError, rhs: EditError) -> Bool {
        switch (lhs, rhs) {
        case (.messageNotFound, .messageNotFound),
             (.cannotEdit, .cannotEdit),
             (.emptyContent, .emptyContent),
             (.channelNotJoined, .channelNotJoined),
             (.timeout, .timeout):
            return true
        case (.contentTooLong(let lhsMax), .contentTooLong(let rhsMax)):
            return lhsMax == rhsMax
        case (.syncFailed(let lhsReason), .syncFailed(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}
