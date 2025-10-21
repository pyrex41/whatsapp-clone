//
//  NotificationManager.swift
//  GlobalBridge
//
//  Push notification management for iOS
//

import Foundation
import UserNotifications
import UIKit
import Combine

/// Manages push notifications for the app
@MainActor
public class NotificationManager: NSObject, ObservableObject {
    // MARK: - Published State

    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published public private(set) var deviceToken: String?
    @Published public private(set) var lastError: Error?

    // MARK: - Properties

    public static let shared = NotificationManager()
    private let notificationCenter = UNUserNotificationCenter.current()
    private var notificationHandlers: [(UNNotificationResponse) -> Void] = []

    // MARK: - Initialization

    private override init() {
        super.init()
        notificationCenter.delegate = self
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Public Methods

    /// Request notification permissions from user
    public func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]

        do {
            let granted = try await notificationCenter.requestAuthorization(options: options)
            await checkAuthorizationStatus()

            if granted {
                print("[Notifications] Authorization granted")
                await registerForRemoteNotifications()
            } else {
                print("[Notifications] Authorization denied")
                throw NotificationError.permissionDenied
            }
        } catch {
            lastError = error
            print("[Notifications] Authorization error: \(error)")
            throw error
        }
    }

    /// Register for remote notifications (APNs)
    public func registerForRemoteNotifications() async {
        await UIApplication.shared.registerForRemoteNotifications()
    }

    /// Set device token from AppDelegate
    public func setDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString
        print("[Notifications] Device token: \(tokenString)")
    }

    /// Handle registration error from AppDelegate
    public func handleRegistrationError(_ error: Error) {
        lastError = error
        print("[Notifications] Registration error: \(error)")
    }

    /// Schedule a local notification
    public func scheduleLocalNotification(
        title: String,
        body: String,
        conversationId: String,
        messageId: String,
        delay: TimeInterval = 0
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: await getBadgeCount() + 1)
        content.userInfo = [
            "conversation_id": conversationId,
            "message_id": messageId,
            "type": "message"
        ]

        let trigger = delay > 0
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try await notificationCenter.add(request)
    }

    /// Clear badge count
    public func clearBadge() async {
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    /// Get current badge count
    public func getBadgeCount() async -> Int {
        UIApplication.shared.applicationIconBadgeNumber
    }

    /// Remove all delivered notifications
    public func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }

    /// Remove specific notification
    public func removeDeliveredNotification(withIdentifier identifier: String) {
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Register handler for notification taps
    public func onNotificationTap(handler: @escaping (UNNotificationResponse) -> Void) {
        notificationHandlers.append(handler)
    }

    // MARK: - Private Methods

    private func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo

        print("[Notifications] Notification tapped: \(userInfo)")

        // Notify all handlers
        notificationHandlers.forEach { handler in
            handler(response)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("[Notifications] Foreground notification: \(notification.request.content.userInfo)")

        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(response)
        completionHandler()
    }
}

// MARK: - Error Types

public enum NotificationError: Error, LocalizedError {
    case permissionDenied
    case registrationFailed
    case notificationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission denied by user"
        case .registrationFailed:
            return "Failed to register for remote notifications"
        case .notificationFailed(let error):
            return "Notification failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Notification Categories

public extension NotificationManager {
    /// Configure notification categories and actions
    func configureNotificationCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY_ACTION",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type a message..."
        )

        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ_ACTION",
            title: "Mark as Read",
            options: []
        )

        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE_CATEGORY",
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([messageCategory])
    }
}
