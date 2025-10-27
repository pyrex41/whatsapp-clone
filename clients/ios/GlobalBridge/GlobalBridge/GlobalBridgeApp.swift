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
    @StateObject private var launchManager = AppLaunchManager.shared
    @StateObject private var store: Store<AppState, AppAction> = {
        print("🎬 [APP] Initializing app store...")
        let store = Store(
            initialState: AppState(),
            reducer: appReducer,
            environment: .live
        )
        print("✅ [APP] Store initialized")
        return store
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppRootView(store: store)
                    .onAppear {
                        setupNotifications()
                        setupAIBroadcastCoordination()
                    }
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }

                // Splash animation overlay
                if launchManager.shouldShowSplashVideo {
                    SplashAnimationView(isPresented: $launchManager.shouldShowSplashVideo)
                        .zIndex(999)
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

    private func setupAIBroadcastCoordination() {
        // Start AI broadcast coordinator to wire Phoenix AI events to Redux store
        guard let phoenixManager = store.environment.phoenixManager else {
            print("⚠️  [AI_COORDINATOR] PhoenixManager not available in environment")
            return
        }

        Task { @MainActor in
            AIBroadcastCoordinator.shared.start(with: store, phoenixManager: phoenixManager)
            print("✅ [AI_COORDINATOR] AI broadcast coordination started")
        }
    }
}

// MARK: - AppDelegate for Push Notifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("🎯 [APP_DELEGATE] Application did finish launching")
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
