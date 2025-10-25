//
//  UserChannelManager.swift
//  GlobalBridge
//
//  User Channel Manager for presence tracking and online status
//  Handles user:USER_ID channel for real-time presence via Phoenix Presence
//

import Foundation
@preconcurrency import SwiftPhoenixClient
import Combine

/// User presence manager for tracking online/offline status
public actor UserChannelManager {
    // MARK: - Properties

    private let phoenixManager: PhoenixChannelManager
    private var userChannel: Channel?
    private var currentUserId: String?
    private var presenceState: [String: UserPresenceInfo] = [:]
    private var typingState: [String: TypingState] = [:] // conversationId -> TypingState
    private var typingDebounceTimers: [String: Task<Void, Never>] = [:]
    private var backgroundTask: Task<Void, Never>?
    private var isActive: Bool = true

    // Privacy settings
    private var hideOnlineStatus: Bool = false
    private var hideTypingIndicators: Bool = false

    // Handlers
    private var presenceHandlers: [String: [PresenceHandler]] = [:] // userId -> handlers
    private var typingHandlers: [String: [TypingUpdateHandler]] = [:] // conversationId -> handlers
    private var statusChangeHandlers: [StatusChangeHandler] = []

    // Connection state
    private var isConnected: Bool = false
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 10
    private let reconnectDelay: TimeInterval = 3.0

    // MARK: - Types

    public typealias PresenceHandler = @Sendable (UserPresenceInfo) -> Void
    public typealias TypingUpdateHandler = @Sendable (TypingState) -> Void
    public typealias StatusChangeHandler = @Sendable (PresenceStatus) -> Void

    /// Detailed user presence information
    public struct UserPresenceInfo: Sendable, Equatable {
        public let userId: String
        public let status: PresenceStatus
        public let lastSeen: Date?
        public let isTyping: Bool
        public let typingInConversation: String?

        public init(
            userId: String,
            status: PresenceStatus,
            lastSeen: Date? = nil,
            isTyping: Bool = false,
            typingInConversation: String? = nil
        ) {
            self.userId = userId
            self.status = status
            self.lastSeen = lastSeen
            self.isTyping = isTyping
            self.typingInConversation = typingInConversation
        }

        /// Create from UserPresence model
        public init(from presence: UserPresence) {
            self.userId = presence.userId
            self.status = PresenceStatus(from: presence.status)
            self.lastSeen = presence.lastSeen
            self.isTyping = false
            self.typingInConversation = nil
        }
    }

    public enum PresenceStatus: String, Sendable, Equatable {
        case online
        case offline
        case away

        public init(from userPresenceStatus: UserPresence.PresenceStatus) {
            switch userPresenceStatus {
            case .online: self = .online
            case .offline: self = .offline
            case .away: self = .away
            }
        }
    }

    // MARK: - Initialization

    public init(phoenixManager: PhoenixChannelManager) {
        self.phoenixManager = phoenixManager
    }

    // MARK: - Connection Management

    /// Connect to user channel for presence tracking
    public func connect(userId: String) async throws {
        guard !isConnected else {
            print("✅ [USER_CHANNEL] Already connected")
            return
        }

        self.currentUserId = userId

        print("🔌 [USER_CHANNEL] Connecting user presence channel for: \(userId)")

        // Join user channel via PhoenixChannelManager
        try await phoenixManager.joinUserChannel(userId: userId)

        // Set up presence tracking
        try await setupPresenceTracking()

        isConnected = true
        reconnectAttempts = 0

        // Broadcast own online status
        await broadcastPresence(status: .online)

        print("✅ [USER_CHANNEL] User channel connected successfully")
    }

    /// Disconnect from user channel
    public func disconnect() async {
        guard let userId = currentUserId else { return }

        print("🔌 [USER_CHANNEL] Disconnecting user channel")

        // Broadcast offline status before disconnect
        await broadcastPresence(status: .offline)

        // Leave channel
        await phoenixManager.leaveConversation("user:\(userId)")

        // Cleanup
        userChannel = nil
        isConnected = false
        presenceState.removeAll()
        typingState.removeAll()

        // Cancel all timers
        for (_, timer) in typingDebounceTimers {
            timer.cancel()
        }
        typingDebounceTimers.removeAll()

        print("✅ [USER_CHANNEL] User channel disconnected")
    }

    /// Handle app backgrounding
    public func handleBackground() {
        isActive = false

        // Broadcast away status
        backgroundTask = Task {
            await broadcastPresence(status: .away)
        }

        print("🔄 [USER_CHANNEL] App backgrounded, status set to away")
    }

    /// Handle app foregrounding
    public func handleForeground() async {
        isActive = true
        backgroundTask?.cancel()

        // Reconnect if needed
        if !isConnected, let userId = currentUserId {
            print("🔄 [USER_CHANNEL] App foregrounded, reconnecting...")
            do {
                try await connect(userId: userId)
            } catch {
                print("❌ [USER_CHANNEL] Reconnection failed: \(error)")
                await attemptReconnect()
            }
        } else {
            // Just update status to online
            await broadcastPresence(status: .online)
        }

        print("✅ [USER_CHANNEL] App foregrounded, status updated")
    }

    // MARK: - Presence Management

    /// Get presence info for a user
    public func getPresence(for userId: String) -> UserPresenceInfo? {
        return presenceState[userId]
    }

    /// Get all tracked presence info
    public func getAllPresence() -> [String: UserPresenceInfo] {
        return presenceState
    }

    /// Check if user is online
    public func isUserOnline(_ userId: String) -> Bool {
        return presenceState[userId]?.status == .online
    }

    /// Register handler for user presence changes
    public func onPresenceChange(for userId: String, handler: @escaping PresenceHandler) {
        if presenceHandlers[userId] == nil {
            presenceHandlers[userId] = []
        }
        presenceHandlers[userId]?.append(handler)

        // Immediately call with current state if available
        if let presence = presenceState[userId] {
            handler(presence)
        }
    }

    /// Register handler for own status changes
    public func onStatusChange(handler: @escaping StatusChangeHandler) {
        statusChangeHandlers.append(handler)
    }

    /// Broadcast own presence status
    public func broadcastPresence(status: PresenceStatus) async {
        guard isConnected, let userId = currentUserId else {
            print("⚠️ [USER_CHANNEL] Cannot broadcast presence - not connected")
            return
        }

        // Don't broadcast if privacy setting is enabled
        guard !hideOnlineStatus else {
            print("🔒 [USER_CHANNEL] Online status hidden by privacy setting")
            return
        }

        let payload: [String: Any] = [
            "status": status.rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        // This would typically be sent via Phoenix Presence track
        // For now, we'll use a custom event
        if let sendableChannel = await phoenixManager.sendableChannel(for: "user:\(userId)") {
            await MainActor.run {
                let channel = sendableChannel.channel
                channel.push("presence_update", payload: payload)
                    .receive("ok") { _ in
                        print("✅ [USER_CHANNEL] Presence broadcast: \(status.rawValue)")
                    }
                    .receive("error") { message in
                        print("❌ [USER_CHANNEL] Failed to broadcast presence: \(message.payload)")
                    }
            }
        }

        // Notify handlers
        for handler in statusChangeHandlers {
            handler(status)
        }
    }

    // MARK: - Typing Indicators

    /// Send typing indicator for a conversation
    public func sendTypingIndicator(conversationId: String, isTyping: Bool) async {
        guard isConnected else {
            print("⚠️ [USER_CHANNEL] Cannot send typing - not connected")
            return
        }

        // Check privacy setting
        guard !hideTypingIndicators else {
            print("🔒 [USER_CHANNEL] Typing indicators hidden by privacy setting")
            return
        }

        // Cancel existing debounce timer
        let timerKey = conversationId
        typingDebounceTimers[timerKey]?.cancel()

        // Send typing indicator
        await phoenixManager.sendTypingIndicator(conversationId: conversationId, isTyping: isTyping)

        // Set up auto-stop timer if typing
        if isTyping {
            typingDebounceTimers[timerKey] = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                await sendTypingIndicator(conversationId: conversationId, isTyping: false)
            }
        }
    }

    /// Get typing state for a conversation
    public func getTypingState(for conversationId: String) -> TypingState? {
        return typingState[conversationId]
    }

    /// Register handler for typing updates
    public func onTypingUpdate(for conversationId: String, handler: @escaping TypingUpdateHandler) {
        if typingHandlers[conversationId] == nil {
            typingHandlers[conversationId] = []
        }
        typingHandlers[conversationId]?.append(handler)

        // Immediately call with current state if available
        if let state = typingState[conversationId] {
            handler(state)
        }
    }

    // MARK: - Privacy Settings

    /// Hide online status from others
    public func setHideOnlineStatus(_ hide: Bool) async {
        hideOnlineStatus = hide

        // If hiding, broadcast offline status
        if hide {
            await broadcastPresence(status: .offline)
        } else if isActive {
            await broadcastPresence(status: .online)
        }

        print("🔒 [USER_CHANNEL] Hide online status: \(hide)")
    }

    /// Hide typing indicators from others
    public func setHideTypingIndicators(_ hide: Bool) {
        hideTypingIndicators = hide
        print("🔒 [USER_CHANNEL] Hide typing indicators: \(hide)")
    }

    /// Get current privacy settings
    public func getPrivacySettings() -> (hideOnlineStatus: Bool, hideTypingIndicators: Bool) {
        return (hideOnlineStatus, hideTypingIndicators)
    }

    // MARK: - Private Methods

    private func setupPresenceTracking() async throws {
        guard let userId = currentUserId else {
            throw PhoenixError.notConnected
        }

        print("📍 [USER_CHANNEL] Setting up presence tracking")

        // Register presence handler with PhoenixChannelManager
        await phoenixManager.onPresence { [weak self] conversationId, presence in
            guard let self else { return }

            Task {
                await self.handlePresenceUpdate(presence)
            }
        }

        // Register typing handler
        await phoenixManager.onTyping(conversationId: "user:\(userId)") { [weak self] indicator in
            guard let self else { return }

            Task {
                await self.handleTypingIndicator(indicator)
            }
        }
    }

    private func handlePresenceUpdate(_ presence: UserPresence) {
        let presenceInfo = UserPresenceInfo(from: presence)
        presenceState[presence.userId] = presenceInfo

        print("📍 [USER_CHANNEL] Presence update: \(presence.userId) - \(presence.status.rawValue)")

        // Notify handlers for this user
        presenceHandlers[presence.userId]?.forEach { handler in
            handler(presenceInfo)
        }
    }

    private func handleTypingIndicator(_ indicator: TypingIndicator) {
        let conversationId = indicator.conversationId

        // Update typing state
        if typingState[conversationId] == nil {
            typingState[conversationId] = TypingState()
        }

        if indicator.isTyping {
            typingState[conversationId]?.typingUsers.insert(indicator.userId)
        } else {
            typingState[conversationId]?.typingUsers.remove(indicator.userId)
        }

        typingState[conversationId]?.lastUpdate = Date()

        print("⌨️ [USER_CHANNEL] Typing update: \(indicator.userId) in \(conversationId) - \(indicator.isTyping)")

        // Notify handlers
        if let state = typingState[conversationId] {
            typingHandlers[conversationId]?.forEach { handler in
                handler(state)
            }
        }
    }

    private func attemptReconnect() async {
        guard let userId = currentUserId else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ [USER_CHANNEL] Max reconnect attempts reached")
            return
        }

        reconnectAttempts += 1
        print("🔄 [USER_CHANNEL] Reconnect attempt \(reconnectAttempts)/\(maxReconnectAttempts)")

        do {
            try await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
            try await connect(userId: userId)
            print("✅ [USER_CHANNEL] Reconnected successfully")
        } catch {
            print("❌ [USER_CHANNEL] Reconnect failed: \(error)")
            await attemptReconnect()
        }
    }
}

// MARK: - Supporting Extensions

extension UserChannelManager {
    /// Format last seen timestamp
    public static func formatLastSeen(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if interval < 604800 { // 7 days
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
