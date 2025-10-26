//
//  AIBroadcastCoordinator.swift
//  GlobalBridge
//
//  Task 23: Coordinator for AI suggestion broadcasts
//  Bridges ConversationMonitorService notifications to PhoenixChannelManager subscriptions
//  and routes AI broadcast events to the Redux store
//

import Foundation
import Combine

/// Coordinates AI monitoring notifications with Phoenix channel subscriptions
/// and routes broadcast events to the Redux store
@MainActor
final class AIBroadcastCoordinator {

    // MARK: - Singleton

    static let shared = AIBroadcastCoordinator()

    // MARK: - Dependencies

    private var phoenixManager: PhoenixChannelManager?
    private var store: Store<AppState, AppAction>?

    // MARK: - State

    private var notificationObservers: [NSObjectProtocol] = []
    private var activeSubscriptions: Set<String> = []

    // MARK: - Initialization

    init() {
        print("🤖 [AI_BROADCAST_COORDINATOR] Initialized")
    }

    // MARK: - Public Methods

    /// Start coordinating AI broadcasts
    /// - Parameters:
    ///   - store: Redux store to dispatch actions to
    ///   - phoenixManager: Phoenix channel manager for subscriptions
    func start(with store: Store<AppState, AppAction>, phoenixManager: PhoenixChannelManager) {
        self.store = store
        self.phoenixManager = phoenixManager
        setupNotificationObservers()
        print("✅ [AI_BROADCAST_COORDINATOR] Started with store and phoenixManager")
    }

    /// Stop coordinating and clean up
    func stop() {
        teardownNotificationObservers()
        activeSubscriptions.removeAll()
        store = nil
        print("✅ [AI_BROADCAST_COORDINATOR] Stopped")
    }

    // MARK: - Private Methods

    private func setupNotificationObservers() {
        // Observer for when AI monitoring starts
        let monitoringStartedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AIMonitoringStarted"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            if let threadId = notification.userInfo?["threadId"] as? UUID {
                Task {
                    await self.handleMonitoringStarted(threadId: threadId)
                }
            }
        }
        notificationObservers.append(monitoringStartedObserver)

        // Observer for when AI monitoring stops
        let monitoringStoppedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AIMonitoringStopped"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            if let threadId = notification.userInfo?["threadId"] as? UUID {
                Task {
                    await self.handleMonitoringStopped(threadId: threadId)
                }
            }
        }
        notificationObservers.append(monitoringStoppedObserver)

        // Observer for proactive AI suggestions
        let suggestionObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AIProactiveSuggestion"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            if let threadId = notification.userInfo?["threadId"] as? String,
               let suggestion = notification.userInfo?["suggestion"] as? SmartReplySuggestion {
                Task { @MainActor in
                    self.handleProactiveSuggestion(threadId: threadId, suggestion: suggestion)
                }
            }
        }
        notificationObservers.append(suggestionObserver)

        print("✅ [AI_BROADCAST_COORDINATOR] Notification observers set up")
    }

    private func teardownNotificationObservers() {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        print("✅ [AI_BROADCAST_COORDINATOR] Notification observers removed")
    }

    private func handleMonitoringStarted(threadId: UUID) async {
        let threadIdString = threadId.uuidString
        print("🤖 [AI_BROADCAST_COORDINATOR] Monitoring started for thread: \(threadIdString)")

        guard let phoenixManager = phoenixManager else {
            print("❌ [AI_BROADCAST_COORDINATOR] PhoenixManager not available")
            return
        }

        // Check if already subscribed
        guard !activeSubscriptions.contains(threadIdString) else {
            print("⚠️  [AI_BROADCAST_COORDINATOR] Already subscribed to thread: \(threadIdString)")
            return
        }

        // Subscribe to AI suggestions via Phoenix
        do {
            try await phoenixManager.subscribeToAISuggestions(threadId: threadIdString) { suggestion in
                Task { @MainActor in
                    // Note: subscribeToAISuggestions already posts to NotificationCenter,
                    // so this handler is redundant but we keep it for logging
                    print("📥 [AI_BROADCAST_COORDINATOR] Received suggestion via handler: \(suggestion.id)")
                }
            }

            activeSubscriptions.insert(threadIdString)
            print("✅ [AI_BROADCAST_COORDINATOR] Subscribed to AI suggestions for thread: \(threadIdString)")
        } catch {
            print("❌ [AI_BROADCAST_COORDINATOR] Failed to subscribe to AI suggestions: \(error)")
        }
    }

    private func handleMonitoringStopped(threadId: UUID) async {
        let threadIdString = threadId.uuidString
        print("🤖 [AI_BROADCAST_COORDINATOR] Monitoring stopped for thread: \(threadIdString)")

        guard let phoenixManager = phoenixManager else {
            print("❌ [AI_BROADCAST_COORDINATOR] PhoenixManager not available")
            return
        }

        // Unsubscribe from AI suggestions
        await phoenixManager.unsubscribeFromAISuggestions(threadId: threadIdString)
        activeSubscriptions.remove(threadIdString)

        print("✅ [AI_BROADCAST_COORDINATOR] Unsubscribed from AI suggestions for thread: \(threadIdString)")
    }

    private func handleProactiveSuggestion(threadId: String, suggestion: SmartReplySuggestion) {
        print("📥 [AI_BROADCAST_COORDINATOR] Received proactive suggestion for thread: \(threadId)")
        print("   - Suggestion ID: \(suggestion.id)")
        print("   - Type: \(suggestion.type)")
        print("   - Content: \(suggestion.content)")
        print("   - Confidence: \(suggestion.confidence)")

        // Dispatch action to Redux store
        guard let store = store else {
            print("⚠️  [AI_BROADCAST_COORDINATOR] No store available to dispatch action")
            return
        }

        store.send(.aiSuggestionBroadcast(threadId: threadId, suggestion: suggestion))
        print("✅ [AI_BROADCAST_COORDINATOR] Dispatched aiSuggestionBroadcast action to store")
    }
}
