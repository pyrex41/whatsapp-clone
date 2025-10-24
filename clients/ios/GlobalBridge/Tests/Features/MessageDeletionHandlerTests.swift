//
//  MessageDeletionHandlerTests.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  Unit tests for MessageDeletionHandler
//

import XCTest
@testable import GlobalBridge

@MainActor
final class MessageDeletionHandlerTests: XCTestCase {

    var sut: MessageDeletionHandler!
    var mockPhoenixManager: MockPhoenixChannelManager!
    var mockDatabaseManager: MockDatabaseManager!
    var mockOfflineQueue: MockOfflineQueueManager!

    override func setUp() async throws {
        try await super.setUp()
        mockPhoenixManager = MockPhoenixChannelManager()
        mockDatabaseManager = MockDatabaseManager()
        mockOfflineQueue = MockOfflineQueueManager()

        sut = MessageDeletionHandler(
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

    // MARK: - Delete Permission Tests

    func testCanDeleteForEveryoneOwnMessage() {
        let message = createTestMessage(senderId: "user123")

        let canDelete = sut.canDeleteForEveryone(message, currentUserId: "user123")

        XCTAssertTrue(canDelete, "Should be able to delete own message for everyone")
    }

    func testCannotDeleteForEveryoneOthersMessage() {
        let message = createTestMessage(senderId: "user456")

        let canDelete = sut.canDeleteForEveryone(message, currentUserId: "user123")

        XCTAssertFalse(canDelete, "Should not be able to delete other's message for everyone")
    }

    func testCannotDeleteForEveryoneAlreadyDeleted() {
        var message = createTestMessage(senderId: "user123")
        message.deletedAt = Date()

        let canDelete = sut.canDeleteForEveryone(message, currentUserId: "user123")

        XCTAssertFalse(canDelete, "Should not be able to delete already deleted message")
    }

    func testCanDeleteForMeAnyMessage() {
        let ownMessage = createTestMessage(senderId: "user123")
        let othersMessage = createTestMessage(senderId: "user456")

        XCTAssertTrue(sut.canDeleteForMe(ownMessage), "Should be able to delete own message for self")
        XCTAssertTrue(sut.canDeleteForMe(othersMessage), "Should be able to delete other's message for self")
    }

    func testCannotDeleteForMeAlreadyDeleted() {
        var message = createTestMessage(senderId: "user123")
        message.deletedAt = Date()

        let canDelete = sut.canDeleteForMe(message)

        XCTAssertFalse(canDelete, "Should not be able to delete already deleted message")
    }

    // MARK: - Delete For Me Tests

    func testDeleteMessageForMe() async throws {
        let message = createTestMessage(senderId: "user456")
        mockDatabaseManager.messages[message.id] = message
        mockPhoenixManager.isConnected = true

        try await sut.deleteMessage(
            messageId: message.id,
            threadId: message.threadId,
            scope: .forMe,
            currentUserId: "user123"
        )

        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertNotNil(updatedMessage?.metadata?["deleted_for_user_user123"])
        XCTAssertEqual(updatedMessage?.metadata?["deleted_for_user_user123"], "true")

        // Verify Phoenix sync
        XCTAssertEqual(mockPhoenixManager.pushedEvents.count, 1)
        let event = mockPhoenixManager.pushedEvents.first
        XCTAssertEqual(event?.event, "delete_message")
        XCTAssertEqual(event?.payload["scope"] as? String, "me")
    }

    // MARK: - Delete For Everyone Tests

    func testDeleteMessageForEveryone() async throws {
        let message = createTestMessage(senderId: "user123")
        mockDatabaseManager.messages[message.id] = message
        mockPhoenixManager.isConnected = true

        try await sut.deleteMessage(
            messageId: message.id,
            threadId: message.threadId,
            scope: .forEveryone,
            currentUserId: "user123"
        )

        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertNotNil(updatedMessage?.deletedAt)

        // Verify Phoenix sync
        XCTAssertEqual(mockPhoenixManager.pushedEvents.count, 1)
        let event = mockPhoenixManager.pushedEvents.first
        XCTAssertEqual(event?.event, "delete_message")
        XCTAssertEqual(event?.payload["scope"] as? String, "everyone")
    }

    func testDeleteForEveryoneNotOwner() async {
        let message = createTestMessage(senderId: "user456")
        mockDatabaseManager.messages[message.id] = message

        do {
            try await sut.deleteMessage(
                messageId: message.id,
                threadId: message.threadId,
                scope: .forEveryone,
                currentUserId: "user123"
            )
            XCTFail("Should throw cannotDeleteForEveryone error")
        } catch {
            XCTAssertTrue(error is DeletionError)
            XCTAssertEqual(error as? DeletionError, .cannotDeleteForEveryone)
        }
    }

    // MARK: - Offline Tests

    func testDeleteMessageOfflineQueues() async throws {
        let message = createTestMessage(senderId: "user123")
        mockDatabaseManager.messages[message.id] = message
        mockPhoenixManager.isConnected = false // Offline

        try await sut.deleteMessage(
            messageId: message.id,
            threadId: message.threadId,
            scope: .forEveryone,
            currentUserId: "user123"
        )

        // Verify local deletion
        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertNotNil(updatedMessage?.deletedAt)

        // Verify no Phoenix sync (offline)
        XCTAssertEqual(mockPhoenixManager.pushedEvents.count, 0)
    }

    // MARK: - Incoming Deletion Tests

    func testHandleIncomingDeletionForEveryone() async throws {
        let message = createTestMessage(senderId: "user456")
        mockDatabaseManager.messages[message.id] = message

        try await sut.handleIncomingDeletion(
            messageId: message.id.uuidString,
            threadId: message.threadId.uuidString,
            deletedAt: Date(),
            scope: .forEveryone,
            currentUserId: "user123"
        )

        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertNotNil(updatedMessage?.deletedAt)
    }

    func testHandleIncomingDeletionForMe() async throws {
        let message = createTestMessage(senderId: "user456")
        mockDatabaseManager.messages[message.id] = message

        try await sut.handleIncomingDeletion(
            messageId: message.id.uuidString,
            threadId: message.threadId.uuidString,
            deletedAt: Date(),
            scope: .forMe,
            currentUserId: "user123"
        )

        let updatedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertNotNil(updatedMessage?.metadata?["deleted_for_user_user123"])
        XCTAssertNil(updatedMessage?.deletedAt) // Should not be globally deleted
    }

    // MARK: - Deletion Check Tests

    func testIsDeletedGloballyDeleted() {
        var message = createTestMessage(senderId: "user456")
        message.deletedAt = Date()

        let isDeleted = sut.isDeleted(message: message, currentUserId: "user123")

        XCTAssertTrue(isDeleted)
    }

    func testIsDeletedForUser() {
        var message = createTestMessage(senderId: "user456")
        message.metadata = ["deleted_for_user_user123": "true"]

        let isDeleted = sut.isDeleted(message: message, currentUserId: "user123")

        XCTAssertTrue(isDeleted)
    }

    func testIsNotDeleted() {
        let message = createTestMessage(senderId: "user456")

        let isDeleted = sut.isDeleted(message: message, currentUserId: "user123")

        XCTAssertFalse(isDeleted)
    }

    // MARK: - Tombstone Tests

    func testTombstoneMessageOwnMessage() {
        var message = createTestMessage(senderId: "user123")
        message.deletedAt = Date()

        let tombstone = sut.getTombstoneMessage(message: message, currentUserId: "user123")

        XCTAssertEqual(tombstone, "You deleted this message")
    }

    func testTombstoneMessageOthersMessage() {
        var message = createTestMessage(senderId: "user456")
        message.deletedAt = Date()

        let tombstone = sut.getTombstoneMessage(message: message, currentUserId: "user123")

        XCTAssertEqual(tombstone, "This message was deleted")
    }

    // MARK: - Already Deleted Tests

    func testDeleteAlreadyDeletedMessage() async throws {
        var message = createTestMessage(senderId: "user123")
        message.deletedAt = Date()
        mockDatabaseManager.messages[message.id] = message

        // Should not throw, just return early
        try await sut.deleteMessage(
            messageId: message.id,
            threadId: message.threadId,
            scope: .forEveryone,
            currentUserId: "user123"
        )

        // Should not attempt Phoenix sync
        XCTAssertEqual(mockPhoenixManager.pushedEvents.count, 0)
    }

    // MARK: - Permanent Deletion Tests

    func testPermanentlyDeleteMessage() async throws {
        let message = createTestMessage(senderId: "user123")
        mockDatabaseManager.messages[message.id] = message

        try await sut.permanentlyDeleteMessage(
            messageId: message.id,
            threadId: message.threadId
        )

        let deletedMessage = mockDatabaseManager.messages[message.id]
        XCTAssertNotNil(deletedMessage?.deletedAt)
        XCTAssertEqual(deletedMessage?.content, "") // Content cleared
    }

    // MARK: - Helper Methods

    private func createTestMessage(senderId: String) -> Message {
        Message(
            id: UUID(),
            threadId: UUID(),
            senderId: senderId,
            content: "Test message",
            messageType: .text,
            status: .sent,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Mock Objects

@MainActor
private class MockPhoenixChannelManager: PhoenixChannelManager {
    var isConnected = true
    var pushedEvents: [(event: String, payload: [String: Any])] = []

    override func channel(for conversationId: String) -> Channel? {
        isConnected ? MockChannel(pushedEvents: &pushedEvents) : nil
    }
}

private class MockChannel: Channel {
    var pushedEvents: UnsafeMutablePointer<[(event: String, payload: [String: Any])]>

    init(pushedEvents: UnsafeMutablePointer<[(event: String, payload: [String: Any])]>) {
        self.pushedEvents = pushedEvents
        super.init(topic: "test", params: [:], socket: Socket(endPoint: "ws://test"))
    }

    override func push(_ event: String, payload: [String: Any]) -> Push {
        pushedEvents.pointee.append((event, payload))
        return Push(channel: self, event: event, payload: payload, timeout: 10)
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
    // Mock implementation
}

// MARK: - DeletionError Equatable

extension DeletionError: Equatable {
    public static func == (lhs: DeletionError, rhs: DeletionError) -> Bool {
        switch (lhs, rhs) {
        case (.messageNotFound, .messageNotFound),
             (.cannotDeleteForEveryone, .cannotDeleteForEveryone),
             (.channelNotJoined, .channelNotJoined),
             (.timeout, .timeout):
            return true
        case (.syncFailed(let lhsReason), .syncFailed(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}
