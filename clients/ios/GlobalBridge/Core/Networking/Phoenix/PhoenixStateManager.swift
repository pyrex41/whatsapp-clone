//
//  PhoenixStateManager.swift
//  GlobalBridge
//
//  State management integration for Phoenix channels
//

import Foundation
import Observation

/// Observable state manager for Phoenix connection and messages
@Observable
@MainActor
public class PhoenixStateManager {
    // MARK: - Published State

    public private(set) var connectionState: PhoenixConnectionState = .disconnected
    public private(set) var messages: [String: [PhoenixMessage]] = [:] // conversationId -> messages
    public private(set) var presences: [String: [String: UserPresence]] = [:] // conversationId -> userId -> presence
    public private(set) var typingUsers: [String: Set<String>] = [:] // conversationId -> userIds

    // MARK: - Private Properties

    private let channelManager: PhoenixChannelManager
    private var updateTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(config: PhoenixConfig = .development) {
        self.channelManager = PhoenixChannelManager(config: config)
        setupHandlers()
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Public Methods

    /// Connect to Phoenix server
    public func connect(authToken: String? = nil) async throws {
        try await channelManager.connect(authToken: authToken)
        await updateConnectionState()
    }

    /// Disconnect from Phoenix server
    public func disconnect() async {
        await channelManager.disconnect()
        connectionState = .disconnected
    }

    /// Join a conversation channel
    public func joinConversation(_ conversationId: String) async throws {
        try await channelManager.joinConversation(conversationId)

        // Initialize message storage
        if messages[conversationId] == nil {
            messages[conversationId] = []
        }

        // Set up message handler
        await channelManager.onMessage(conversationId: conversationId) { [weak self] message in
            Task { @MainActor in
                self?.handleMessage(message, conversationId: conversationId)
            }
        }
    }

    /// Leave a conversation channel
    public func leaveConversation(_ conversationId: String) async {
        await channelManager.leaveConversation(conversationId)
        messages.removeValue(forKey: conversationId)
        presences.removeValue(forKey: conversationId)
        typingUsers.removeValue(forKey: conversationId)
    }

    /// Send a message
    public func sendMessage(
        conversationId: String,
        content: String,
        replyToId: String? = nil
    ) async throws {
        let message = try await channelManager.sendMessage(
            conversationId: conversationId,
            content: content,
            replyToId: replyToId
        )

        handleMessage(message, conversationId: conversationId)
    }

    /// Mark conversation as read
    public func markAsRead(conversationId: String, messageId: String) async throws {
        try await channelManager.markAsRead(conversationId: conversationId, messageId: messageId)
    }

    /// Get messages for a conversation
    public func getMessages(for conversationId: String) -> [PhoenixMessage] {
        return messages[conversationId] ?? []
    }

    /// Get presence for users in a conversation
    public func getPresence(for conversationId: String) -> [String: UserPresence] {
        return presences[conversationId] ?? [:]
    }

    // MARK: - Private Methods

    private func setupHandlers() {
        // Set up presence handler
        Task {
            await channelManager.onPresence { [weak self] conversationId, presence in
                Task { @MainActor in
                    self?.handlePresence(conversationId: conversationId, presence: presence)
                }
            }
        }

        // Start state update task
        updateTask = Task {
            while !Task.isCancelled {
                await updateConnectionState()
                try? await Task.sleep(nanoseconds: 1_000_000_000) // Update every second
            }
        }
    }

    private func handleMessage(_ message: PhoenixMessage, conversationId: String) {
        if messages[conversationId] == nil {
            messages[conversationId] = []
        }

        // Check if message already exists (update case)
        if let index = messages[conversationId]?.firstIndex(where: { $0.id == message.id }) {
            messages[conversationId]?[index] = message
        } else {
            // Add new message and sort by timestamp
            messages[conversationId]?.append(message)
            messages[conversationId]?.sort { $0.timestamp < $1.timestamp }
        }
    }

    private func handlePresence(conversationId: String, presence: UserPresence) {
        if presences[conversationId] == nil {
            presences[conversationId] = [:]
        }

        presences[conversationId]?[presence.userId] = presence
    }

    private func updateConnectionState() async {
        connectionState = await channelManager.getConnectionState()
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension PhoenixStateManager {
    /// Create a mock state manager for previews
    public static var preview: PhoenixStateManager {
        let manager = PhoenixStateManager(config: .development)

        // Add mock messages
        manager.messages["conv1"] = [
            PhoenixMessage(
                id: "1",
                conversationId: "conv1",
                senderId: "user1",
                content: "Hello!",
                timestamp: Date().addingTimeInterval(-3600),
                status: .delivered,
                metadata: nil
            ),
            PhoenixMessage(
                id: "2",
                conversationId: "conv1",
                senderId: "user2",
                content: "Hi there!",
                timestamp: Date().addingTimeInterval(-1800),
                status: .read,
                metadata: nil
            )
        ]

        return manager
    }
}
#endif
