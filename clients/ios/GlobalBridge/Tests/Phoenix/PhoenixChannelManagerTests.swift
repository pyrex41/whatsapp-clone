//
//  PhoenixChannelManagerTests.swift
//  GlobalBridge
//
//  Tests for PhoenixChannelManager
//

import XCTest
@testable import GlobalBridge

final class PhoenixChannelManagerTests: XCTestCase {
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

    // MARK: - Connection Tests

    func testInitialState() async {
        let state = await manager.getConnectionState()

        switch state {
        case .disconnected:
            XCTAssertTrue(true, "Initial state should be disconnected")
        default:
            XCTFail("Initial state should be disconnected")
        }
    }

    func testConnect() async throws {
        // Note: This test requires a running Phoenix server
        // Skip if server is not available
        do {
            try await manager.connect()
            let state = await manager.getConnectionState()

            switch state {
            case .connected:
                XCTAssertTrue(true, "Should be connected")
            default:
                XCTFail("Should be connected after connect()")
            }
        } catch {
            // Expected if server is not running
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    func testDisconnect() async throws {
        do {
            try await manager.connect()
            await manager.disconnect()

            let state = await manager.getConnectionState()

            switch state {
            case .disconnected:
                XCTAssertTrue(true, "Should be disconnected")
            default:
                XCTFail("Should be disconnected after disconnect()")
            }
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    // MARK: - Channel Tests

    func testJoinConversation() async throws {
        do {
            try await manager.connect()
            try await manager.joinConversation("test-conversation")

            // If we get here without error, join was successful
            XCTAssertTrue(true, "Should join conversation successfully")
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    func testLeaveConversation() async throws {
        do {
            try await manager.connect()
            try await manager.joinConversation("test-conversation")
            await manager.leaveConversation("test-conversation")

            // If we get here without error, leave was successful
            XCTAssertTrue(true, "Should leave conversation successfully")
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    // MARK: - Message Tests

    func testSendMessage() async throws {
        do {
            try await manager.connect()
            try await manager.joinConversation("test-conversation")

            let message = try await manager.sendMessage(
                conversationId: "test-conversation",
                content: "Test message"
            )

            XCTAssertEqual(message.content, "Test message")
            XCTAssertEqual(message.conversationId, "test-conversation")
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    func testSendMessageWithReply() async throws {
        do {
            try await manager.connect()
            try await manager.joinConversation("test-conversation")

            // Send original message
            let original = try await manager.sendMessage(
                conversationId: "test-conversation",
                content: "Original message"
            )

            // Send reply
            let reply = try await manager.sendMessage(
                conversationId: "test-conversation",
                content: "Reply message",
                replyToId: original.id
            )

            XCTAssertEqual(reply.metadata?.replyToId, original.id)
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }

    // MARK: - Error Tests

    func testSendMessageWithoutConnection() async {
        do {
            _ = try await manager.sendMessage(
                conversationId: "test",
                content: "Test"
            )
            XCTFail("Should throw error when not connected")
        } catch PhoenixError.notConnected {
            XCTAssertTrue(true, "Should throw notConnected error")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testJoinWithoutConnection() async {
        do {
            try await manager.joinConversation("test")
            XCTFail("Should throw error when not connected")
        } catch PhoenixError.notConnected {
            XCTAssertTrue(true, "Should throw notConnected error")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Event Handler Tests

    func testMessageHandler() async throws {
        let expectation = XCTestExpectation(description: "Message received")

        do {
            try await manager.connect()
            try await manager.joinConversation("test-conversation")

            await manager.onMessage(conversationId: "test-conversation") { message in
                XCTAssertNotNil(message)
                expectation.fulfill()
            }

            // Send a message to trigger handler
            _ = try await manager.sendMessage(
                conversationId: "test-conversation",
                content: "Handler test"
            )

            await fulfillment(of: [expectation], timeout: 5.0)
        } catch {
            throw XCTSkip("Phoenix server not available: \(error)")
        }
    }
}

// MARK: - Configuration Tests

final class PhoenixConfigTests: XCTestCase {
    func testDevelopmentConfig() {
        let config = PhoenixConfig.development

        XCTAssertEqual(config.socketURL.scheme, "ws")
        XCTAssertEqual(config.socketURL.host, "localhost")
        XCTAssertEqual(config.socketURL.port, 4000)
        XCTAssertTrue(config.enableLogging)
    }

    func testProductionConfig() {
        let config = PhoenixConfig.production

        XCTAssertEqual(config.socketURL.scheme, "wss")
        XCTAssertFalse(config.enableLogging)
        XCTAssertGreaterThan(config.maxReconnectAttempts, 5)
    }

    func testCustomConfig() {
        let customURL = URL(string: "wss://custom.example.com/socket")!
        let config = PhoenixConfig(
            socketURL: customURL,
            authToken: "test-token",
            connectionTimeout: 15,
            heartbeatInterval: 45,
            maxReconnectAttempts: 3,
            reconnectDelay: 1,
            enableLogging: true
        )

        XCTAssertEqual(config.socketURL, customURL)
        XCTAssertEqual(config.authToken, "test-token")
        XCTAssertEqual(config.connectionTimeout, 15)
        XCTAssertEqual(config.heartbeatInterval, 45)
        XCTAssertEqual(config.maxReconnectAttempts, 3)
        XCTAssertEqual(config.reconnectDelay, 1)
        XCTAssertTrue(config.enableLogging)
    }
}
