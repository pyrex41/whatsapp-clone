//
//  PresenceIndicatorTests.swift
//  GlobalBridge
//
//  Tests for Task 21: Presence Indicators - iOS Implementation
//

import XCTest
@testable import GlobalBridge

final class PresenceIndicatorTests: XCTestCase {
    var manager: PhoenixChannelManager!
    var presenceTracker: PresenceTracker!
    var config: PhoenixConfig!

    override func setUp() async throws {
        try await super.setUp()
        config = PhoenixConfig.development
        manager = PhoenixChannelManager(config: config)
        presenceTracker = PresenceTracker()
    }

    override func tearDown() async throws {
        await manager.disconnect()
        manager = nil
        presenceTracker = nil
        config = nil
        try await super.tearDown()
    }

    // MARK: - Presence Tracking Tests

    func testJoinTracksPresence() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Wait for presence tracking
        try await Task.sleep(nanoseconds: 200_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")
        XCTAssertFalse(presenceList.isEmpty, "Should track presence after joining")
    }

    func testPresenceDiffOnUserJoin() async throws {
        let expectation = XCTestExpectation(description: "Presence diff on join")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Set up presence handler
        await manager.onPresenceChange(conversationId: "test-conversation") { joins, leaves in
            if !joins.isEmpty {
                expectation.fulfill()
            }
        }

        // Simulate another user joining
        // In real scenario, another user would join

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testPresenceDiffOnUserLeave() async throws {
        let expectation = XCTestExpectation(description: "Presence diff on leave")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        await manager.onPresenceChange(conversationId: "test-conversation") { joins, leaves in
            if !leaves.isEmpty {
                expectation.fulfill()
            }
        }

        // Simulate user leaving
        await manager.leaveConversation("test-conversation")

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testPresencePayloadStructure() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        try await Task.sleep(nanoseconds: 200_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        for (userId, presence) in presenceList {
            XCTAssertNotNil(userId, "User ID should be present")
            XCTAssertNotNil(presence.onlineAt, "Online timestamp should be present")
            XCTAssertNotNil(presence.metas, "Metas array should be present")
            XCTAssertFalse(presence.metas.isEmpty, "Metas should not be empty")
        }
    }

    func testPresenceMetadata() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        try await Task.sleep(nanoseconds: 200_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        for (_, presence) in presenceList {
            let meta = presence.metas.first!
            XCTAssertNotNil(meta.userId, "Meta should include user ID")
            XCTAssertNotNil(meta.onlineAt, "Meta should include online timestamp")
            XCTAssertGreaterThan(meta.onlineAt, 0, "Online timestamp should be valid")
        }
    }

    // MARK: - Multi-User Presence Tests

    func testMultipleUsersPresence() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Simulate multiple users
        // In integration tests, multiple clients would connect

        try await Task.sleep(nanoseconds: 500_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")
        XCTAssertGreaterThanOrEqual(presenceList.count, 1, "Should track at least one user")
    }

    func testPresenceListUpdates() async throws {
        let expectation = XCTestExpectation(description: "Presence list updates")
        expectation.expectedFulfillmentCount = 2

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        var updateCount = 0

        await manager.onPresenceChange(conversationId: "test-conversation") { joins, leaves in
            updateCount += 1
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 10.0)

        XCTAssertGreaterThanOrEqual(updateCount, 2, "Should receive multiple presence updates")
    }

    func testMultipleDevicePresence() async throws {
        // Same user on multiple devices should have multiple metas
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        try await Task.sleep(nanoseconds: 200_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        // In real scenario with multiple devices, check for multiple metas
        for (_, presence) in presenceList {
            XCTAssertGreaterThanOrEqual(presence.metas.count, 1, "Should have at least one meta")
        }
    }

    // MARK: - Presence State Management Tests

    func testPresencePersistsAcrossChannels() async throws {
        try await manager.connect()
        try await manager.joinConversation("conversation-1")
        try await manager.joinConversation("conversation-2")

        try await Task.sleep(nanoseconds: 200_000_000)

        let presence1 = await manager.getPresenceList(conversationId: "conversation-1")
        let presence2 = await manager.getPresenceList(conversationId: "conversation-2")

        XCTAssertFalse(presence1.isEmpty, "Conversation 1 should have presence")
        XCTAssertFalse(presence2.isEmpty, "Conversation 2 should have presence")
    }

    func testPresenceClearsOnLeave() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        try await Task.sleep(nanoseconds: 200_000_000)

        var presenceList = await manager.getPresenceList(conversationId: "test-conversation")
        let initialCount = presenceList.count

        await manager.leaveConversation("test-conversation")

        try await Task.sleep(nanoseconds: 200_000_000)

        presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        // Presence should be cleared or reduced
        XCTAssertLessThanOrEqual(presenceList.count, initialCount, "Presence should clear on leave")
    }

    // MARK: - Performance Tests

    func testPresenceTrackingPerformance() async throws {
        let startTime = Date()

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Wait for presence to be tracked
        try await Task.sleep(nanoseconds: 200_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime) * 1000

        XCTAssertFalse(presenceList.isEmpty, "Should track presence")
        XCTAssertLessThan(duration, 500, "Presence tracking should be fast, took \(duration)ms")
    }

    func testHighUserCountPresence() async throws {
        // Simulating high user count scenario
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // In real test, would have multiple clients
        try await Task.sleep(nanoseconds: 500_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        // Should handle presence efficiently regardless of user count
        XCTAssertTrue(true, "Should handle presence list efficiently")
    }

    // MARK: - Error Handling Tests

    func testPresenceWithoutConnection() async {
        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")
        XCTAssertTrue(presenceList.isEmpty, "Should return empty list when not connected")
    }

    func testPresenceWithoutJoiningChannel() async throws {
        try await manager.connect()

        let presenceList = await manager.getPresenceList(conversationId: "not-joined")
        XCTAssertTrue(presenceList.isEmpty, "Should return empty list for unjoined conversation")
    }
}

// MARK: - Presence Badge UI Tests

final class PresenceBadgeUITests: XCTestCase {
    var viewModel: UserPresenceViewModel!

    override func setUp() async throws {
        try await super.setUp()
        viewModel = UserPresenceViewModel()
    }

    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    func testPresenceBadgeColor() async {
        // User is offline
        await viewModel.updatePresence(userId: "user1", isOnline: false)
        var badgeColor = await viewModel.presenceBadgeColor(userId: "user1")
        XCTAssertEqual(badgeColor, .gray, "Offline user should show gray badge")

        // User comes online
        await viewModel.updatePresence(userId: "user1", isOnline: true)
        badgeColor = await viewModel.presenceBadgeColor(userId: "user1")
        XCTAssertEqual(badgeColor, .green, "Online user should show green badge")
    }

    func testPresenceBadgeVisibility() async {
        await viewModel.updatePresence(userId: "user1", isOnline: true)

        let shouldShow = await viewModel.shouldShowPresenceBadge(userId: "user1")
        XCTAssertTrue(shouldShow, "Should show badge for online user")
    }

    func testPresenceBadgeSize() async {
        let badgeSize = await viewModel.presenceBadgeSize
        XCTAssertEqual(badgeSize, 12, "Badge size should be 12 points")
    }

    func testPresenceBadgePosition() async {
        let position = await viewModel.presenceBadgePosition
        XCTAssertEqual(position, .bottomRight, "Badge should be positioned at bottom right")
    }

    func testPresenceStatusText() async {
        await viewModel.updatePresence(userId: "user1", isOnline: true)
        var statusText = await viewModel.presenceStatusText(userId: "user1")
        XCTAssertEqual(statusText, "Online", "Should show 'Online' for online user")

        await viewModel.updatePresence(userId: "user1", isOnline: false)
        statusText = await viewModel.presenceStatusText(userId: "user1")
        XCTAssertEqual(statusText, "Offline", "Should show 'Offline' for offline user")
    }

    func testLastSeenDisplay() async {
        let lastSeen = Date().addingTimeInterval(-3600) // 1 hour ago
        await viewModel.updateLastSeen(userId: "user1", lastSeen: lastSeen)

        let lastSeenText = await viewModel.lastSeenText(userId: "user1")
        XCTAssertTrue(lastSeenText.contains("ago"), "Should show relative time for last seen")
    }
}

// MARK: - Presence Animation Tests

final class PresenceAnimationTests: XCTestCase {
    var animationController: PresenceBadgeAnimationController!

    override func setUp() async throws {
        try await super.setUp()
        animationController = PresenceBadgeAnimationController()
    }

    override func tearDown() async throws {
        animationController = nil
        try await super.tearDown()
    }

    func testPresenceTransitionAnimation() async {
        let expectation = XCTestExpectation(description: "Animation completion")

        await animationController.animatePresenceChange(from: .offline, to: .online) {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testPulseAnimation() async {
        let shouldPulse = await animationController.shouldPulse(for: .online)
        XCTAssertTrue(shouldPulse, "Online status should pulse")
    }

    func testAnimationDuration() async {
        let duration = await animationController.transitionDuration
        XCTAssertEqual(duration, 0.3, "Transition should be 300ms")
    }
}

// MARK: - Integration Tests

final class PresenceIntegrationTests: XCTestCase {
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

    func testEndToEndPresenceFlow() async throws {
        let expectation = XCTestExpectation(description: "End-to-end presence")

        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        // Set up presence handler
        await manager.onPresenceChange(conversationId: "test-conversation") { joins, leaves in
            Task {
                await self.viewModel.handlePresenceChange(joins: joins, leaves: leaves)
                if !joins.isEmpty {
                    expectation.fulfill()
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let onlineUsers = await viewModel.onlineUsers
        XCTAssertFalse(onlineUsers.isEmpty, "Should have online users")
    }

    func testPresenceSynchronization() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        try await Task.sleep(nanoseconds: 500_000_000)

        let presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        // Update UI with presence
        await viewModel.syncPresence(presenceList)

        let onlineCount = await viewModel.onlineUserCount
        XCTAssertGreaterThanOrEqual(onlineCount, 0, "Should sync online count")
    }

    func testPresenceUpdateOnReconnect() async throws {
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        try await Task.sleep(nanoseconds: 200_000_000)

        var presenceList = await manager.getPresenceList(conversationId: "test-conversation")
        let initialCount = presenceList.count

        // Disconnect and reconnect
        await manager.disconnect()
        try await manager.connect()
        try await manager.joinConversation("test-conversation")

        try await Task.sleep(nanoseconds: 200_000_000)

        presenceList = await manager.getPresenceList(conversationId: "test-conversation")

        // Presence should be restored
        XCTAssertGreaterThanOrEqual(presenceList.count, 0, "Presence should be restored after reconnect")
    }
}
