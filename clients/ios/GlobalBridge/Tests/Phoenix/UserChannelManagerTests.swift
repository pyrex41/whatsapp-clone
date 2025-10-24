//
//  UserChannelManagerTests.swift
//  GlobalBridgeTests
//
//  Comprehensive unit tests for UserChannelManager
//  Tests: presence tracking, typing indicators, privacy settings, reconnection
//

import XCTest
@testable import GlobalBridge

@MainActor
final class UserChannelManagerTests: XCTestCase {
    var phoenixManager: MockPhoenixChannelManager!
    var userChannelManager: UserChannelManager!
    var testUserId: String!

    override func setUp() async throws {
        try await super.setUp()
        phoenixManager = MockPhoenixChannelManager()
        userChannelManager = UserChannelManager(phoenixManager: phoenixManager)
        testUserId = "test-user-123"
    }

    override func tearDown() async throws {
        await userChannelManager.disconnect()
        userChannelManager = nil
        phoenixManager = nil
        testUserId = nil
        try await super.tearDown()
    }

    // MARK: - Connection Tests

    func testConnectSuccess() async throws {
        // Given
        phoenixManager.shouldSucceed = true

        // When
        try await userChannelManager.connect(userId: testUserId)

        // Then
        XCTAssertTrue(phoenixManager.joinUserChannelCalled)
        XCTAssertEqual(phoenixManager.lastJoinedUserId, testUserId)
    }

    func testConnectAlreadyConnected() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)

        // When - try to connect again
        try await userChannelManager.connect(userId: testUserId)

        // Then - should only connect once
        XCTAssertEqual(phoenixManager.joinUserChannelCallCount, 1)
    }

    func testDisconnect() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)

        // When
        await userChannelManager.disconnect()

        // Then
        XCTAssertTrue(phoenixManager.leaveConversationCalled)
        XCTAssertEqual(phoenixManager.lastLeftConversation, "user:\(testUserId)")
    }

    // MARK: - Presence Tests

    func testGetPresenceForUser() async throws {
        // Given
        try await userChannelManager.connect(userId: testUserId)

        let otherUserId = "other-user-456"
        let presence = UserPresence(
            userId: otherUserId,
            status: .online,
            lastSeen: nil
        )

        // When
        await phoenixManager.simulatePresenceUpdate(presence)
        try await Task.sleep(nanoseconds: 100_000_000) // Give time for async update

        let result = await userChannelManager.getPresence(for: otherUserId)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.userId, otherUserId)
        XCTAssertEqual(result?.status, .online)
    }

    func testIsUserOnline() async throws {
        // Given
        try await userChannelManager.connect(userId: testUserId)

        let onlineUserId = "online-user"
        let onlinePresence = UserPresence(userId: onlineUserId, status: .online, lastSeen: nil)

        // When
        await phoenixManager.simulatePresenceUpdate(onlinePresence)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        let isOnline = await userChannelManager.isUserOnline(onlineUserId)
        XCTAssertTrue(isOnline)
    }

    func testIsUserOffline() async throws {
        // Given
        try await userChannelManager.connect(userId: testUserId)

        let offlineUserId = "offline-user"
        let offlinePresence = UserPresence(userId: offlineUserId, status: .offline, lastSeen: Date())

        // When
        await phoenixManager.simulatePresenceUpdate(offlinePresence)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        let isOnline = await userChannelManager.isUserOnline(offlineUserId)
        XCTAssertFalse(isOnline)
    }

    func testBroadcastPresence() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)

        // When
        await userChannelManager.broadcastPresence(status: .online)

        // Then
        // Verify presence was broadcast (check mock implementation)
        XCTAssertTrue(phoenixManager.presenceBroadcastCalled)
    }

    func testPresenceChangeHandler() async throws {
        // Given
        try await userChannelManager.connect(userId: testUserId)

        let otherUserId = "tracked-user"
        var receivedPresence: UserChannelManager.UserPresenceInfo?
        let expectation = XCTestExpectation(description: "Presence handler called")

        await userChannelManager.onPresenceChange(for: otherUserId) { presence in
            receivedPresence = presence
            expectation.fulfill()
        }

        // When
        let presence = UserPresence(userId: otherUserId, status: .online, lastSeen: nil)
        await phoenixManager.simulatePresenceUpdate(presence)

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedPresence)
        XCTAssertEqual(receivedPresence?.userId, otherUserId)
        XCTAssertEqual(receivedPresence?.status, .online)
    }

    // MARK: - Typing Indicator Tests

    func testSendTypingIndicator() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)

        let conversationId = "conv-123"

        // When
        await userChannelManager.sendTypingIndicator(conversationId: conversationId, isTyping: true)

        // Then
        XCTAssertTrue(phoenixManager.sendTypingIndicatorCalled)
        XCTAssertEqual(phoenixManager.lastTypingConversationId, conversationId)
        XCTAssertTrue(phoenixManager.lastTypingStatus ?? false)
    }

    func testTypingIndicatorAutoStop() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)

        let conversationId = "conv-123"

        // When - send typing = true
        await userChannelManager.sendTypingIndicator(conversationId: conversationId, isTyping: true)

        // Wait for auto-stop (5 seconds)
        try await Task.sleep(nanoseconds: 5_500_000_000)

        // Then - should have sent typing = false
        XCTAssertEqual(phoenixManager.typingIndicatorCallCount, 2)
    }

    func testGetTypingState() async throws {
        // Given
        try await userChannelManager.connect(userId: testUserId)

        let conversationId = "conv-123"
        let typingUserId = "typing-user"

        let typingIndicator = TypingIndicator(
            userId: typingUserId,
            conversationId: conversationId,
            isTyping: true
        )

        // When
        await phoenixManager.simulateTypingIndicator(typingIndicator)
        try await Task.sleep(nanoseconds: 100_000_000)

        let typingState = await userChannelManager.getTypingState(for: conversationId)

        // Then
        XCTAssertNotNil(typingState)
        XCTAssertTrue(typingState?.typingUsers.contains(typingUserId) ?? false)
    }

    func testTypingUpdateHandler() async throws {
        // Given
        try await userChannelManager.connect(userId: testUserId)

        let conversationId = "conv-123"
        var receivedState: TypingState?
        let expectation = XCTestExpectation(description: "Typing handler called")

        await userChannelManager.onTypingUpdate(for: conversationId) { state in
            receivedState = state
            expectation.fulfill()
        }

        // When
        let typingIndicator = TypingIndicator(
            userId: "typing-user",
            conversationId: conversationId,
            isTyping: true
        )
        await phoenixManager.simulateTypingIndicator(typingIndicator)

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedState)
        XCTAssertFalse(receivedState?.typingUsers.isEmpty ?? true)
    }

    // MARK: - Privacy Settings Tests

    func testHideOnlineStatus() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)

        // When
        await userChannelManager.setHideOnlineStatus(true)

        // Then
        let settings = await userChannelManager.getPrivacySettings()
        XCTAssertTrue(settings.hideOnlineStatus)

        // Should broadcast offline when hiding
        XCTAssertTrue(phoenixManager.presenceBroadcastCalled)
    }

    func testHideTypingIndicators() async throws {
        // Given
        try await userChannelManager.connect(userId: testUserId)

        // When
        await userChannelManager.setHideTypingIndicators(true)

        // Then
        let settings = await userChannelManager.getPrivacySettings()
        XCTAssertTrue(settings.hideTypingIndicators)
    }

    func testTypingIndicatorRespectPrivacy() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)
        await userChannelManager.setHideTypingIndicators(true)

        // When - try to send typing indicator
        await userChannelManager.sendTypingIndicator(conversationId: "conv-123", isTyping: true)

        // Then - should not send due to privacy setting
        XCTAssertFalse(phoenixManager.sendTypingIndicatorCalled)
    }

    // MARK: - Background Handling Tests

    func testHandleBackground() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)

        // When
        await userChannelManager.handleBackground()

        // Then - should broadcast away status
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(phoenixManager.presenceBroadcastCalled)
    }

    func testHandleForeground() async throws {
        // Given
        phoenixManager.shouldSucceed = true
        try await userChannelManager.connect(userId: testUserId)
        await userChannelManager.handleBackground()

        phoenixManager.presenceBroadcastCalled = false // Reset

        // When
        await userChannelManager.handleForeground()

        // Then - should broadcast online status
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(phoenixManager.presenceBroadcastCalled)
    }

    // MARK: - Utility Tests

    func testFormatLastSeen() {
        // Just now
        let now = Date()
        XCTAssertEqual(UserChannelManager.formatLastSeen(now), "just now")

        // Minutes ago
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        XCTAssertTrue(UserChannelManager.formatLastSeen(fiveMinutesAgo).contains("minute"))

        // Hours ago
        let twoHoursAgo = Date().addingTimeInterval(-7200)
        XCTAssertTrue(UserChannelManager.formatLastSeen(twoHoursAgo).contains("hour"))

        // Days ago
        let threeDaysAgo = Date().addingTimeInterval(-259200)
        XCTAssertTrue(UserChannelManager.formatLastSeen(threeDaysAgo).contains("day"))
    }
}

// MARK: - Mock Phoenix Channel Manager

@MainActor
class MockPhoenixChannelManager: PhoenixChannelManager {
    var shouldSucceed = true
    var joinUserChannelCalled = false
    var joinUserChannelCallCount = 0
    var lastJoinedUserId: String?
    var leaveConversationCalled = false
    var lastLeftConversation: String?
    var sendTypingIndicatorCalled = false
    var lastTypingConversationId: String?
    var lastTypingStatus: Bool?
    var typingIndicatorCallCount = 0
    var presenceBroadcastCalled = false

    private var presenceHandlers: [(String, UserPresence) -> Void] = []
    private var typingHandlers: [String: [(TypingIndicator) -> Void]] = [:]

    override init(config: PhoenixConfig = .development) {
        super.init(config: config)
    }

    override func joinUserChannel(userId: String) async throws {
        joinUserChannelCalled = true
        joinUserChannelCallCount += 1
        lastJoinedUserId = userId

        if !shouldSucceed {
            throw PhoenixError.joinFailed(PhoenixPayload([:]))
        }
    }

    override func leaveConversation(_ conversationId: String) {
        leaveConversationCalled = true
        lastLeftConversation = conversationId
    }

    override func sendTypingIndicator(conversationId: String, isTyping: Bool) async {
        sendTypingIndicatorCalled = true
        lastTypingConversationId = conversationId
        lastTypingStatus = isTyping
        typingIndicatorCallCount += 1
    }

    override func onPresence(handler: @escaping PresenceHandler) {
        presenceHandlers.append(handler)
    }

    override func onTyping(conversationId: String, handler: @escaping TypingHandler) {
        if typingHandlers[conversationId] == nil {
            typingHandlers[conversationId] = []
        }
        typingHandlers[conversationId]?.append(handler)
    }

    // Test helpers
    func simulatePresenceUpdate(_ presence: UserPresence) async {
        for handler in presenceHandlers {
            handler("", presence)
        }
    }

    func simulateTypingIndicator(_ indicator: TypingIndicator) async {
        typingHandlers[indicator.conversationId]?.forEach { handler in
            handler(indicator)
        }
    }

    func simulatePresenceBroadcast() {
        presenceBroadcastCalled = true
    }
}
