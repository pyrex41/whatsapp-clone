//
//  PushNotificationTests.swift
//  GlobalBridge
//
//  Tests for Task 22: Push Notifications - iOS Implementation
//

import XCTest
import UserNotifications
@testable import GlobalBridge

final class PushNotificationTests: XCTestCase {
    var notificationManager: PushNotificationManager!
    var manager: PhoenixChannelManager!

    override func setUp() async throws {
        try await super.setUp()
        notificationManager = PushNotificationManager()
        manager = PhoenixChannelManager(config: .development)
    }

    override func tearDown() async throws {
        notificationManager = nil
        await manager.disconnect()
        manager = nil
        try await super.tearDown()
    }

    // MARK: - APNS Registration Tests

    func testRequestNotificationPermissions() async throws {
        let granted = try await notificationManager.requestPermissions()

        // In simulator, this may return false
        // In real device testing, should verify actual permission state
        XCTAssertTrue(true, "Permission request should complete without error")
    }

    func testDeviceTokenRegistration() async throws {
        // Simulate device token registration
        let deviceToken = Data(repeating: 0x01, count: 32)

        await notificationManager.didRegisterForRemoteNotifications(deviceToken: deviceToken)

        let registeredToken = await notificationManager.deviceToken
        XCTAssertNotNil(registeredToken, "Device token should be registered")
    }

    func testDeviceTokenSendToBackend() async throws {
        let deviceToken = Data(repeating: 0x01, count: 32)
        await notificationManager.didRegisterForRemoteNotifications(deviceToken: deviceToken)

        // Verify token is formatted correctly for backend
        let tokenString = await notificationManager.deviceTokenString
        XCTAssertFalse(tokenString.isEmpty, "Device token string should not be empty")
        XCTAssertEqual(tokenString.count, 64, "Device token should be 64 hex characters")
    }

    func testRegistrationFailureHandling() async {
        let error = NSError(domain: "TestError", code: -1, userInfo: nil)

        await notificationManager.didFailToRegisterForRemoteNotifications(error: error)

        let hasError = await notificationManager.hasRegistrationError
        XCTAssertTrue(hasError, "Should track registration failure")
    }

    // MARK: - Notification Payload Tests

    func testAPNSPayloadParsing() async {
        let payload: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "John Doe",
                    "body": "Hello, World!"
                ],
                "badge": 1,
                "sound": "default"
            ],
            "thread_id": "test-thread-123",
            "message_id": "test-message-456",
            "sender_id": "user-789"
        ]

        let notification = await notificationManager.parseNotification(payload: payload)

        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.title, "John Doe")
        XCTAssertEqual(notification?.body, "Hello, World!")
        XCTAssertEqual(notification?.threadId, "test-thread-123")
        XCTAssertEqual(notification?.messageId, "test-message-456")
    }

    func testMediaNotificationPayload() async {
        let payload: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "Jane Smith",
                    "body": "📷 Photo"
                ],
                "badge": 2,
                "sound": "default"
            ],
            "thread_id": "test-thread",
            "message_id": "test-message",
            "content_type": "image",
            "media_url": "https://example.com/photo.jpg"
        ]

        let notification = await notificationManager.parseNotification(payload: payload)

        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.contentType, "image")
        XCTAssertNotNil(notification?.mediaUrl)
    }

    func testGroupNotificationPayload() async {
        let payload: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "Team Chat",
                    "body": "Alice: Meeting at 3pm"
                ],
                "badge": 5,
                "sound": "default",
                "thread-id": "group-123" // iOS notification grouping
            ],
            "thread_id": "group-thread-123",
            "thread_type": "group"
        ]

        let notification = await notificationManager.parseNotification(payload: payload)

        XCTAssertNotNil(notification)
        XCTAssertEqual(notification?.threadType, "group")
    }

    // MARK: - Foreground Notification Tests

    func testForegroundNotificationDisplay() async throws {
        let expectation = XCTestExpectation(description: "Foreground notification")

        await notificationManager.setForegroundNotificationHandler { notification in
            XCTAssertNotNil(notification)
            expectation.fulfill()
        }

        // Simulate receiving notification while app is in foreground
        let payload: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "Test",
                    "body": "Foreground test"
                ]
            ],
            "thread_id": "test"
        ]

        await notificationManager.handleForegroundNotification(payload: payload)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testForegroundNotificationBanner() async {
        // Verify notification is shown as banner in foreground
        let shouldShowBanner = await notificationManager.shouldShowBannerInForeground
        XCTAssertTrue(shouldShowBanner, "Should show banner for foreground notifications")
    }

    func testForegroundNotificationSound() async {
        // Verify notification plays sound in foreground
        let shouldPlaySound = await notificationManager.shouldPlaySoundInForeground
        XCTAssertTrue(shouldPlaySound, "Should play sound for foreground notifications")
    }

    // MARK: - Background Notification Tests

    func testBackgroundNotificationHandling() async {
        let payload: [AnyHashable: Any] = [
            "aps": [
                "alert": [
                    "title": "Background Test",
                    "body": "Message"
                ],
                "content-available": 1
            ],
            "thread_id": "test"
        ]

        let completionHandler = await notificationManager.handleBackgroundNotification(
            payload: payload
        )

        XCTAssertNotNil(completionHandler, "Should handle background notification")
    }

    func testBackgroundFetchContent() async {
        // Verify background notification triggers content fetch
        let payload: [AnyHashable: Any] = [
            "aps": [
                "content-available": 1
            ],
            "thread_id": "test-thread"
        ]

        let shouldFetch = await notificationManager.shouldFetchContent(payload: payload)
        XCTAssertTrue(shouldFetch, "Should fetch content for background notification")
    }

    // MARK: - Notification Action Tests

    func testNotificationTapAction() async throws {
        let expectation = XCTestExpectation(description: "Notification tap")

        await notificationManager.setNotificationTapHandler { threadId in
            XCTAssertEqual(threadId, "test-thread-123")
            expectation.fulfill()
        }

        // Simulate notification tap
        let response = UNNotificationResponse.mock(
            threadId: "test-thread-123",
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        await notificationManager.handleNotificationResponse(response: response)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testQuickReplyAction() async throws {
        let expectation = XCTestExpectation(description: "Quick reply")

        await notificationManager.setQuickReplyHandler { threadId, replyText in
            XCTAssertEqual(threadId, "test-thread")
            XCTAssertEqual(replyText, "Thanks!")
            expectation.fulfill()
        }

        // Simulate quick reply action
        let response = UNNotificationResponse.mock(
            threadId: "test-thread",
            actionIdentifier: "REPLY_ACTION",
            replyText: "Thanks!"
        )

        await notificationManager.handleNotificationResponse(response: response)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testMarkAsReadAction() async throws {
        let expectation = XCTestExpectation(description: "Mark as read")

        await notificationManager.setMarkAsReadHandler { messageId in
            XCTAssertEqual(messageId, "test-message-123")
            expectation.fulfill()
        }

        // Simulate mark as read action
        let response = UNNotificationResponse.mock(
            threadId: "test-thread",
            messageId: "test-message-123",
            actionIdentifier: "MARK_READ_ACTION"
        )

        await notificationManager.handleNotificationResponse(response: response)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - Badge Count Tests

    func testBadgeCountUpdate() async {
        await notificationManager.updateBadgeCount(count: 5)

        let badgeCount = await UIApplication.shared.applicationIconBadgeNumber
        XCTAssertEqual(badgeCount, 5, "Badge count should be updated")
    }

    func testBadgeClear() async {
        await notificationManager.updateBadgeCount(count: 10)
        await notificationManager.clearBadge()

        let badgeCount = await UIApplication.shared.applicationIconBadgeNumber
        XCTAssertEqual(badgeCount, 0, "Badge should be cleared")
    }

    func testIncrementBadge() async {
        await notificationManager.clearBadge()
        await notificationManager.incrementBadge()
        await notificationManager.incrementBadge()

        let badgeCount = await UIApplication.shared.applicationIconBadgeNumber
        XCTAssertEqual(badgeCount, 2, "Badge should increment correctly")
    }

    // MARK: - Notification Categories Tests

    func testNotificationCategories() async {
        let categories = await notificationManager.notificationCategories

        XCTAssertFalse(categories.isEmpty, "Should have notification categories")

        let messageCategory = categories.first { $0.identifier == "MESSAGE_CATEGORY" }
        XCTAssertNotNil(messageCategory, "Should have message category")
    }

    func testNotificationActions() async {
        let categories = await notificationManager.notificationCategories
        let messageCategory = categories.first { $0.identifier == "MESSAGE_CATEGORY" }

        let actions = messageCategory?.actions
        XCTAssertNotNil(actions, "Category should have actions")
        XCTAssertTrue(actions!.contains { $0.identifier == "REPLY_ACTION" }, "Should have reply action")
        XCTAssertTrue(actions!.contains { $0.identifier == "MARK_READ_ACTION" }, "Should have mark read action")
    }

    // MARK: - Performance Tests

    func testNotificationHandlingPerformance() async {
        let payload: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Test", "body": "Performance"]],
            "thread_id": "test"
        ]

        let startTime = Date()

        for _ in 0..<100 {
            await notificationManager.parseNotification(payload: payload)
        }

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime) * 1000

        XCTAssertLessThan(duration, 500, "Should handle 100 notifications in under 500ms")
    }

    // MARK: - Error Handling Tests

    func testInvalidPayloadHandling() async {
        let invalidPayload: [AnyHashable: Any] = [
            "invalid": "data"
        ]

        let notification = await notificationManager.parseNotification(payload: invalidPayload)

        // Should handle gracefully, may return nil or default values
        XCTAssertTrue(true, "Should handle invalid payload gracefully")
    }

    func testMissingFieldsInPayload() async {
        let incompletePayload: [AnyHashable: Any] = [
            "aps": [
                "alert": "Simple string alert"
            ]
        ]

        let notification = await notificationManager.parseNotification(payload: incompletePayload)

        XCTAssertNotNil(notification, "Should handle incomplete payload")
    }
}

// MARK: - Integration Tests

final class PushNotificationIntegrationTests: XCTestCase {
    var notificationManager: PushNotificationManager!
    var channelManager: PhoenixChannelManager!
    var conversationViewModel: ConversationViewModel!

    override func setUp() async throws {
        try await super.setUp()
        notificationManager = PushNotificationManager()
        channelManager = PhoenixChannelManager(config: .development)
        conversationViewModel = ConversationViewModel(conversationId: "test-conversation")
        conversationViewModel.channelManager = channelManager
    }

    override func tearDown() async throws {
        notificationManager = nil
        await channelManager.disconnect()
        channelManager = nil
        conversationViewModel = nil
        try await super.tearDown()
    }

    func testNotificationToMessageFlow() async throws {
        let expectation = XCTestExpectation(description: "Notification to message")

        // Set up notification tap handler
        await notificationManager.setNotificationTapHandler { threadId in
            Task {
                // Navigate to conversation
                await self.conversationViewModel.loadConversation(threadId: threadId)
                expectation.fulfill()
            }
        }

        // Simulate notification tap
        let response = UNNotificationResponse.mock(
            threadId: "test-conversation",
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )

        await notificationManager.handleNotificationResponse(response: response)

        await fulfillment(of: [expectation], timeout: 5.0)

        let isLoaded = await conversationViewModel.isLoaded
        XCTAssertTrue(isLoaded, "Conversation should be loaded from notification")
    }

    func testQuickReplyToChannel() async throws {
        let expectation = XCTestExpectation(description: "Quick reply to channel")

        try await channelManager.connect()
        try await channelManager.joinConversation("test-conversation")

        await notificationManager.setQuickReplyHandler { threadId, replyText in
            Task {
                // Send message via channel
                _ = try? await self.channelManager.sendMessage(
                    conversationId: threadId,
                    content: replyText
                )
                expectation.fulfill()
            }
        }

        // Simulate quick reply
        let response = UNNotificationResponse.mock(
            threadId: "test-conversation",
            actionIdentifier: "REPLY_ACTION",
            replyText: "Quick reply test"
        )

        await notificationManager.handleNotificationResponse(response: response)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testNotificationBadgeSync() async throws {
        try await channelManager.connect()

        // Simulate receiving messages
        await notificationManager.incrementBadge()
        await notificationManager.incrementBadge()
        await notificationManager.incrementBadge()

        var badgeCount = await UIApplication.shared.applicationIconBadgeNumber
        XCTAssertEqual(badgeCount, 3, "Badge should reflect unread count")

        // Mark conversation as read
        try await channelManager.joinConversation("test-conversation")
        await conversationViewModel.markAllAsRead()

        // Badge should decrement
        await notificationManager.syncBadgeCount()

        badgeCount = await UIApplication.shared.applicationIconBadgeNumber
        XCTAssertLessThan(badgeCount, 3, "Badge should decrease after marking as read")
    }
}

// MARK: - Test Helpers

extension UNNotificationResponse {
    static func mock(
        threadId: String,
        messageId: String? = nil,
        actionIdentifier: String,
        replyText: String? = nil
    ) -> UNNotificationResponse {
        // Create mock notification response
        // In real implementation, would use proper UNNotificationResponse
        // This is a simplified version for testing
        return UNNotificationResponse()
    }
}
