//
//  PhoenixStateManagerTests.swift
//  GlobalBridge
//
//  Tests for PhoenixStateManager
//

import XCTest
@testable import GlobalBridge

@MainActor
final class PhoenixStateManagerTests: XCTestCase {
    var stateManager: PhoenixStateManager!

    override func setUp() async throws {
        try await super.setUp()
        stateManager = PhoenixStateManager(config: .development)
    }

    override func tearDown() async throws {
        await stateManager.disconnect()
        stateManager = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialState() {
        switch stateManager.connectionState {
        case .disconnected:
            XCTAssertTrue(true, "Initial state should be disconnected")
        default:
            XCTFail("Initial state should be disconnected")
        }

        XCTAssertTrue(stateManager.messages.isEmpty)
        XCTAssertTrue(stateManager.presences.isEmpty)
        XCTAssertTrue(stateManager.typingUsers.isEmpty)
    }

    // MARK: - Connection Tests

    func testConnect() async throws {
        do {
            try await stateManager.connect()

            switch stateManager.connectionState {
            case .connected:
                XCTAssertTrue(true, "Should be connected")
            default:
                XCTFail("Should be connected after connect()")
            }
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    func testDisconnect() async throws {
        do {
            try await stateManager.connect()
            await stateManager.disconnect()

            switch stateManager.connectionState {
            case .disconnected:
                XCTAssertTrue(true, "Should be disconnected")
            default:
                XCTFail("Should be disconnected after disconnect()")
            }
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    // MARK: - Conversation Tests

    func testJoinConversation() async throws {
        do {
            try await stateManager.connect()
            try await stateManager.joinConversation("test-conversation")

            XCTAssertNotNil(stateManager.messages["test-conversation"])
            XCTAssertTrue(stateManager.messages["test-conversation"]?.isEmpty ?? false)
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    func testLeaveConversation() async throws {
        do {
            try await stateManager.connect()
            try await stateManager.joinConversation("test-conversation")
            await stateManager.leaveConversation("test-conversation")

            XCTAssertNil(stateManager.messages["test-conversation"])
            XCTAssertNil(stateManager.presences["test-conversation"])
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    // MARK: - Message Tests

    func testSendMessage() async throws {
        do {
            try await stateManager.connect()
            try await stateManager.joinConversation("test-conversation")

            try await stateManager.sendMessage(
                conversationId: "test-conversation",
                content: "Test message"
            )

            let messages = stateManager.getMessages(for: "test-conversation")
            XCTAssertFalse(messages.isEmpty)

            let lastMessage = messages.last
            XCTAssertEqual(lastMessage?.content, "Test message")
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    func testGetMessages() {
        // Test with empty messages
        let emptyMessages = stateManager.getMessages(for: "nonexistent")
        XCTAssertTrue(emptyMessages.isEmpty)

        // Add mock messages
        let mockMessage = PhoenixMessage(
            id: "1",
            conversationId: "test",
            senderId: "user1",
            senderDisplayName: nil,
            content: "Test",
            timestamp: Date(),
            status: .sent,
            metadata: nil,
            clientMessageId: nil
        )

        stateManager.messages["test"] = [mockMessage]

        let messages = stateManager.getMessages(for: "test")
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.id, "1")
    }

    func testMessageOrdering() {
        let now = Date()
        let message1 = PhoenixMessage(
            id: "1",
            conversationId: "test",
            senderId: "user1",
            senderDisplayName: nil,
            content: "First",
            timestamp: now.addingTimeInterval(-100),
            status: .sent,
            metadata: nil,
            clientMessageId: nil
        )

        let message2 = PhoenixMessage(
            id: "2",
            conversationId: "test",
            senderId: "user1",
            senderDisplayName: nil,
            content: "Second",
            timestamp: now.addingTimeInterval(-50),
            status: .sent,
            metadata: nil,
            clientMessageId: nil
        )

        let message3 = PhoenixMessage(
            id: "3",
            conversationId: "test",
            senderId: "user1",
            senderDisplayName: nil,
            content: "Third",
            timestamp: now,
            status: .sent,
            metadata: nil,
            clientMessageId: nil
        )

        // Add messages in random order
        stateManager.messages["test"] = [message3, message1, message2]

        let messages = stateManager.getMessages(for: "test")

        // Messages should be ordered by timestamp
        XCTAssertEqual(messages[0].id, "1")
        XCTAssertEqual(messages[1].id, "2")
        XCTAssertEqual(messages[2].id, "3")
    }

    // MARK: - Presence Tests

    func testGetPresence() {
        // Test with empty presence
        let emptyPresence = stateManager.getPresence(for: "nonexistent")
        XCTAssertTrue(emptyPresence.isEmpty)

        // Add mock presence
        let mockPresence = UserPresence(
            userId: "user1",
            status: .online,
            lastSeen: nil
        )

        stateManager.presences["test"] = ["user1": mockPresence]

        let presence = stateManager.getPresence(for: "test")
        XCTAssertEqual(presence.count, 1)
        XCTAssertEqual(presence["user1"]?.status, .online)
    }

    // MARK: - Preview Helper Tests

    func testPreviewHelper() {
        let preview = PhoenixStateManager.preview

        XCTAssertFalse(preview.messages.isEmpty)
        XCTAssertNotNil(preview.messages["conv1"])

        let messages = preview.messages["conv1"]
        XCTAssertEqual(messages?.count, 2)
    }
}
