//
//  TypingIndicatorTests.swift
//  GlobalBridge
//
//  Tests for Task 17: Typing Indicators - iOS Implementation
//

import XCTest
@testable import GlobalBridge

final class TypingIndicatorTests: XCTestCase {
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

    // MARK: - Typing Event Sending Tests

    func testSendTypingStarted() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send typing started event
        let result = try await manager.sendTypingIndicator(
            conversationId: "test-conversation",
            isTyping: true
        )

        XCTAssertTrue(result, "Should successfully send typing started event")
    }

    func testSendTypingStopped() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send typing stopped event
        let result = try await manager.sendTypingIndicator(
            conversationId: "test-conversation",
            isTyping: false
        )

        XCTAssertTrue(result, "Should successfully send typing stopped event")
    }

    func testRapidTypingStateChanges() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Send multiple rapid state changes
        for i in 0..<10 {
            let isTyping = i % 2 == 0
            let result = try await manager.sendTypingIndicator(
                conversationId: "test-conversation",
                isTyping: isTyping
            )
            XCTAssertTrue(result, "Rapid typing change \(i) should succeed")
        }
    }

    // MARK: - Typing Event Receiving Tests

    func testReceiveTypingIndicator() async throws {
        let expectation = XCTestExpectation(description: "Receive typing indicator")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Set up typing indicator handler
        await manager.onTypingIndicator(conversationId: "test-conversation") { userId, isTyping in
            XCTAssertNotNil(userId)
            XCTAssertTrue(isTyping)
            expectation.fulfill()
        }

        // In real scenario, another user would send typing event
        // For testing, we simulate receiving the event

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testTypingIndicatorIncludesTimestamp() async throws {
        let expectation = XCTestExpectation(description: "Receive typing with timestamp")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        await manager.onTypingIndicator(conversationId: "test-conversation") { userId, isTyping, timestamp in
            XCTAssertNotNil(timestamp)
            XCTAssertGreaterThan(timestamp ?? 0, 0)
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testMultipleUsersTyping() async throws {
        let expectation = XCTestExpectation(description: "Multiple users typing")
        expectation.expectedFulfillmentCount = 2

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        var typingUsers = Set<String>()

        await manager.onTypingIndicator(conversationId: "test-conversation") { userId, isTyping, _ in
            if isTyping {
                typingUsers.insert(userId)
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        XCTAssertGreaterThanOrEqual(typingUsers.count, 1, "Should track at least one typing user")
    }

    // MARK: - Performance Tests

    func testTypingIndicatorLatency() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        let startTime = Date()

        _ = try await manager.sendTypingIndicator(
            conversationId: "test-conversation",
            isTyping: true
        )

        let endTime = Date()
        let latency = endTime.timeIntervalSince(startTime) * 1000 // Convert to milliseconds

        XCTAssertLessThan(latency, 50, "Typing indicator latency should be under 50ms, got \(latency)ms")
    }

    func testHighFrequencyTypingEvents() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        let startTime = Date()

        // Send 20 typing events rapidly
        for i in 0..<20 {
            _ = try await manager.sendTypingIndicator(
                conversationId: "test-conversation",
                isTyping: i % 2 == 0
            )
        }

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime) * 1000

        XCTAssertLessThan(totalTime, 500, "20 typing events should complete in under 500ms")
    }

    // MARK: - Error Handling Tests

    func testTypingWithoutConnection() async {
        do {
            _ = try await manager.sendTypingIndicator(
                conversationId: "test",
                isTyping: true
            )
            XCTFail("Should throw error when not connected")
        } catch PhoenixError.notConnected {
            XCTAssertTrue(true, "Should throw notConnected error")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testTypingWithoutJoiningConversation() async {
        do {
            try await manager.connect()

            _ = try await manager.sendTypingIndicator(
                conversationId: "not-joined",
                isTyping: true
            )
            XCTFail("Should throw error when conversation not joined")
        } catch PhoenixError.channelNotJoined {
            XCTAssertTrue(true, "Should throw channelNotJoined error")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - State Management Tests

    func testTypingStateCleanupOnDisconnect() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Start typing
        _ = try await manager.sendTypingIndicator(
            conversationId: "test-conversation",
            isTyping: true
        )

        // Disconnect
        await manager.disconnect()

        // Verify typing state is cleared
        let typingState = await manager.getTypingUsers(conversationId: "test-conversation")
        XCTAssertTrue(typingState.isEmpty, "Typing state should be cleared on disconnect")
    }

    func testTypingStatePerConversation() async throws {
        try await manager.connect()
        try await manager.joinConversation("conversation-1")
        try await manager.joinConversation("conversation-2")

        // Set typing state for conversation-1
        _ = try await manager.sendTypingIndicator(
            conversationId: "conversation-1",
            isTyping: true
        )

        // Typing state should be independent
        let typingConv1 = await manager.getTypingUsers(conversationId: "conversation-1")
        let typingConv2 = await manager.getTypingUsers(conversationId: "conversation-2")

        XCTAssertNotEqual(typingConv1, typingConv2, "Typing state should be independent per conversation")
    }
}

// MARK: - Typing Indicator UI Tests

final class TypingIndicatorUITests: XCTestCase {
    var viewModel: ConversationViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = ConversationViewModel(conversationId: "test-conversation")
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - UI State Tests

    func testTypingIndicatorUIState() async {
        // Simulate receiving typing indicator
        await viewModel.handleTypingIndicator(userId: "user1", isTyping: true)

        let isUserTyping = await viewModel.isUserTyping(userId: "user1")
        XCTAssertTrue(isUserTyping, "UI should reflect typing state")
    }

    func testTypingIndicatorDisplayText() async {
        // Single user typing
        await viewModel.handleTypingIndicator(userId: "user1", isTyping: true)

        let displayText = await viewModel.typingIndicatorText
        XCTAssertEqual(displayText, "user1 is typing...", "Should show single user typing")
    }

    func testMultipleUsersTypingDisplay() async {
        // Multiple users typing
        await viewModel.handleTypingIndicator(userId: "user1", isTyping: true)
        await viewModel.handleTypingIndicator(userId: "user2", isTyping: true)

        let displayText = await viewModel.typingIndicatorText
        XCTAssertTrue(displayText.contains("are typing"), "Should show multiple users typing")
    }

    func testTypingIndicatorTimeout() async {
        // Start typing
        await viewModel.handleTypingIndicator(userId: "user1", isTyping: true)

        // Wait for timeout (typically 5 seconds)
        try? await Task.sleep(nanoseconds: 6_000_000_000)

        let isUserTyping = await viewModel.isUserTyping(userId: "user1")
        XCTAssertFalse(isUserTyping, "Typing indicator should timeout after 5 seconds")
    }

    func testTypingIndicatorAnimation() async {
        // Verify typing indicator animates
        await viewModel.handleTypingIndicator(userId: "user1", isTyping: true)

        let shouldAnimate = await viewModel.shouldShowTypingAnimation
        XCTAssertTrue(shouldAnimate, "Should show typing animation")
    }
}

// MARK: - Integration Tests

final class TypingIndicatorIntegrationTests: XCTestCase {
    var manager: PhoenixChannelManager!
    var viewModel: ConversationViewModel!

    override func setUp() async throws {
        try await super.setUp()
        manager = PhoenixChannelManager(config: .development)
        viewModel = ConversationViewModel(conversationId: "test-conversation")
        viewModel.channelManager = manager
    }

    override func tearDown() async throws {
        await manager.disconnect()
        manager = nil
        viewModel = nil
        try await super.tearDown()
    }

    func testEndToEndTypingFlow() async throws {
        let expectation = XCTestExpectation(description: "End-to-end typing flow")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Set up handler
        await manager.onTypingIndicator(conversationId: "test-conversation") { userId, isTyping, _ in
            Task {
                await self.viewModel.handleTypingIndicator(userId: userId, isTyping: isTyping)
                expectation.fulfill()
            }
        }

        // Send typing event
        _ = try await manager.sendTypingIndicator(
            conversationId: "test-conversation",
            isTyping: true
        )

        await fulfillment(of: [expectation], timeout: 5.0)

        let hasTypingUsers = await viewModel.typingUsers.count > 0
        XCTAssertTrue(hasTypingUsers, "UI should reflect typing users")
    }
}
