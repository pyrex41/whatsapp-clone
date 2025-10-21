//
//  NotificationManagerTests.swift
//  GlobalBridgeTests
//
//  Tests for push notification management
//

import XCTest
import UserNotifications
@testable import GlobalBridge

@MainActor
final class NotificationManagerTests: XCTestCase {
    var notificationManager: NotificationManager!

    override func setUp() async throws {
        notificationManager = NotificationManager.shared
    }

    func testDeviceTokenConversion() {
        let tokenData = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef])
        notificationManager.setDeviceToken(tokenData)

        XCTAssertEqual(notificationManager.deviceToken, "0123456789abcdef")
    }

    func testNotificationHandlerRegistration() {
        var handlerCalled = false

        notificationManager.onNotificationTap { _ in
            handlerCalled = true
        }

        // Note: Can't actually trigger notification tap in unit test
        // This just verifies the handler is registered without errors
        XCTAssertFalse(handlerCalled)
    }

    func testBadgeCountOperations() async {
        // Clear badge
        await notificationManager.clearBadge()
        let count = await notificationManager.getBadgeCount()

        XCTAssertEqual(count, 0)
    }

    func testNotificationErrorHandling() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        notificationManager.handleRegistrationError(error)

        XCTAssertNotNil(notificationManager.lastError)
    }
}
