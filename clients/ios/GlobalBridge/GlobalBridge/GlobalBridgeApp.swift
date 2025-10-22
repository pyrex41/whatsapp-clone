//
//  GlobalBridgeApp.swift
//  GlobalBridge
//
//  Created by Reuben Brooks on 10/20/25.
//

import SwiftUI
import UserNotifications
import Auth0

@main
struct GlobalBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var store = Store(
        initialState: AppState(),
        reducer: appReducer,
        environment: .live
    )

    var body: some Scene {
        WindowGroup {
            if authManager.hasSelectedTestUser {
                AppRootView(store: store)
                    .onAppear {
                        setupNotifications()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .notificationModeChanged)) { _ in
                        setupNotifications()
                    }
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }
            } else {
                UserSelectionView { testUser in
                    authManager.selectTestUser(
                        userId: testUser.id,
                        token: testUser.token,
                        displayName: testUser.displayName
                    )
                }
            }
        }
    }

    private func setupNotifications() {
        let mode = NotificationConfig.current
        print("[Notifications] Mode: \(mode)")

        switch mode {
        case .system:
            // Request OS permissions and register for remote notifications
            Task {
                do {
                    try await notificationManager.requestAuthorization()
                    notificationManager.configureNotificationCategories()

                    // Handle notification taps
                    notificationManager.onNotificationTap { response in
                        handleNotificationTap(response)
                    }
                } catch {
                    print("[Notifications] System setup failed: \(error)")
                }
            }

        case .banner:
            // No OS permission requests; set up tap handling if used by local banners
            notificationManager.onNotificationTap { response in
                handleNotificationTap(response)
            }
            InAppBannerCenter.shared.onTapThread = { threadId in
                print("[Banner] Navigate to conversation: \(threadId.uuidString)")
                openThreadDeepLink(threadId)
            }

        case .auto:
            // Try system; if it fails, continue in banner-only mode
            Task {
                do {
                    try await notificationManager.requestAuthorization()
                    notificationManager.configureNotificationCategories()
                    notificationManager.onNotificationTap { response in
                        handleNotificationTap(response)
                    }
                } catch {
                    print("[Notifications] AUTO fallback to banner due to: \(error)")
                    notificationManager.onNotificationTap { response in
                        handleNotificationTap(response)
                    }
                    InAppBannerCenter.shared.onTapThread = { threadId in
                        print("[Banner] Navigate to conversation: \(threadId.uuidString)")
                        openThreadDeepLink(threadId)
                    }
                }
            }
        }
    }

    private func handleNotificationTap(_ response: UNNotificationResponse) {
        guard let conversationId = response.notification.request.content.userInfo["conversation_id"] as? String else {
            return
        }
        let messageId = response.notification.request.content.userInfo["message_id"] as? String

        if response.actionIdentifier == "MARK_READ_ACTION" {
            if let threadUUID = UUID(uuidString: conversationId), let messageId {
                store.send(.markMessageRead(threadID: threadUUID, messageID: messageId))
            }
            return
        }

        if response.actionIdentifier == "REPLY_ACTION",
           let reply = (response as? UNTextInputNotificationResponse)?.userText,
           let threadUUID = UUID(uuidString: conversationId) {
            store.send(.sendQuickReply(threadID: threadUUID, text: reply))
            return
        }

        print("Navigate to conversation: \(conversationId)")
        if let uuid = UUID(uuidString: conversationId) {
            openThreadDeepLink(uuid)
        }
    }

    private func handleDeepLink(_ url: URL) {
        // Auth0 handles its own callbacks automatically when using custom URL schemes
        // No need to manually handle Auth0 URLs
        
        // Handle other deep links for navigation
        print("Deep link: \(url)")
        let bundleScheme = Bundle.main.bundleIdentifier
        guard let scheme = url.scheme, scheme == bundleScheme || scheme == "globalbridge" else { return }
        // Expected: <scheme>://thread/<uuid>
        let host = url.host
        let components = url.pathComponents.filter { $0 != "/" }
        if host == "thread", let first = components.first, let uuid = UUID(uuidString: first) {
            store.send(.threadSelected(uuid))
            Task { await NotificationManager.shared.clearBadge() }
        }
    }

    private func openThreadDeepLink(_ threadId: UUID) {
        // Build URL using the app's bundle identifier as scheme
        let scheme = Bundle.main.bundleIdentifier ?? "globalbridge"
        if let url = URL(string: "\(scheme)://thread/\(threadId.uuidString)") {
            // Route internally via the same handler (no need to leave the app)
            handleDeepLink(url)
        } else {
            // Fallback: dispatch directly
            store.send(.threadSelected(threadId))
        }
    }
}

// MARK: - AppDelegate for Push Notifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.setDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleRegistrationError(error)
        }
    }
}
