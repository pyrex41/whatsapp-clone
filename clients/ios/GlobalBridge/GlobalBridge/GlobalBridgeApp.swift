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
        // Request notification permissions
        Task {
            do {
                try await notificationManager.requestAuthorization()
                notificationManager.configureNotificationCategories()

                // Handle notification taps
                notificationManager.onNotificationTap { response in
                    handleNotificationTap(response)
                }
            } catch {
                print("Failed to setup notifications: \(error)")
            }
        }
    }

    private func handleNotificationTap(_ response: UNNotificationResponse) {
        guard let conversationId = response.notification.request.content.userInfo["conversation_id"] as? String else {
            return
        }

        // TODO: Navigate to conversation
        print("Navigate to conversation: \(conversationId)")
    }

    private func handleDeepLink(_ url: URL) {
        // Auth0 handles its own callbacks automatically when using custom URL schemes
        // No need to manually handle Auth0 URLs
        
        // Handle other deep links for navigation
        print("Deep link: \(url)")
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
