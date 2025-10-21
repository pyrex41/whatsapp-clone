//
//  PhoenixChannelManager.swift
//  GlobalBridge
//
//  Main Phoenix Channel Manager for real-time WebSocket connections
//

import Foundation
import SwiftPhoenixClient

/// Connection state for Phoenix channels
public enum PhoenixConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(Error)
}

/// Main actor managing Phoenix Channel connections
public actor PhoenixChannelManager {
    // MARK: - Properties

    private let config: PhoenixConfig
    private var socket: Socket?
    private var channels: [String: Channel] = [:]
    private var connectionState: PhoenixConnectionState = .disconnected
    private var reconnectAttempts = 0
    private var eventHandlers: [String: [(PhoenixMessage) -> Void]] = [:]
    private var presenceHandlers: [(String, UserPresence) -> Void] = []

    // MARK: - Initialization

    public init(config: PhoenixConfig) {
        self.config = config
    }

    // MARK: - Connection Management

    /// Connect to Phoenix server
    public func connect(authToken: String? = nil) async throws {
        guard connectionState != .connected else { return }

        connectionState = .connecting

        var params: [String: Any] = [:]
        if let token = authToken ?? config.authToken {
            params["token"] = token
        }

        socket = Socket(
            endPoint: config.socketURL.absoluteString,
            transport: { URLSessionTransport(url: $0) },
            paramsClosure: { params }
        )

        socket?.logger = config.enableLogging ? { message in
            print("[Phoenix] \(message)")
        } : nil

        socket?.onOpen { [weak self] in
            Task { await self?.handleConnect() }
        }

        socket?.onClose { [weak self] in
            Task { await self?.handleDisconnect() }
        }

        socket?.onError { [weak self] error in
            Task { await self?.handleError(error) }
        }

        socket?.connect()

        // Wait for connection with timeout
        try await waitForConnection()
    }

    /// Disconnect from Phoenix server
    public func disconnect() {
        socket?.disconnect()
        channels.removeAll()
        connectionState = .disconnected
        reconnectAttempts = 0
    }

    /// Get current connection state
    public func getConnectionState() -> PhoenixConnectionState {
        return connectionState
    }

    // MARK: - Channel Management

    /// Join a conversation channel
    public func joinConversation(_ conversationId: String) async throws {
        guard let socket = socket else {
            throw PhoenixError.notConnected
        }

        let topic = "conversation:\(conversationId)"

        // Check if already joined
        if channels[topic] != nil {
            return
        }

        let channel = socket.channel(topic)
        channels[topic] = channel

        // Set up event handlers
        setupChannelHandlers(channel, conversationId: conversationId)

        // Join channel
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.join()
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.joinFailed(message.payload))
                }
                .receive("timeout") { _ in
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }

    /// Leave a conversation channel
    public func leaveConversation(_ conversationId: String) {
        let topic = "conversation:\(conversationId)"
        channels[topic]?.leave()
        channels.removeValue(forKey: topic)
    }

    // MARK: - Message Sending

    /// Send a message to a conversation
    public func sendMessage(
        conversationId: String,
        content: String,
        replyToId: String? = nil
    ) async throws -> PhoenixMessage {
        guard let channel = channels["conversation:\(conversationId)"] else {
            throw PhoenixError.channelNotJoined
        }

        var payload: [String: Any] = [
            "content": content,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        if let replyToId = replyToId {
            payload["reply_to_id"] = replyToId
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("new_message", payload: payload)
                .receive("ok") { response in
                    do {
                        let data = try JSONSerialization.data(withJSONObject: response.payload)
                        let message = try JSONDecoder().decode(PhoenixMessage.self, from: data)
                        continuation.resume(returning: message)
                    } catch {
                        continuation.resume(throwing: PhoenixError.decodingFailed(error))
                    }
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.sendFailed(message.payload))
                }
                .receive("timeout") { _ in
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }

    /// Mark conversation as read
    public func markAsRead(conversationId: String, messageId: String) async throws {
        guard let channel = channels["conversation:\(conversationId)"] else {
            throw PhoenixError.channelNotJoined
        }

        let payload: [String: Any] = ["message_id": messageId]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.push("mark_read", payload: payload)
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.sendFailed(message.payload))
                }
        }
    }

    // MARK: - Event Handlers

    /// Register handler for incoming messages
    public func onMessage(conversationId: String, handler: @escaping (PhoenixMessage) -> Void) {
        if eventHandlers[conversationId] == nil {
            eventHandlers[conversationId] = []
        }
        eventHandlers[conversationId]?.append(handler)
    }

    /// Register handler for presence updates
    public func onPresence(handler: @escaping (String, UserPresence) -> Void) {
        presenceHandlers.append(handler)
    }

    // MARK: - Private Methods

    private func setupChannelHandlers(_ channel: Channel, conversationId: String) {
        // Handle new messages
        channel.on("new_message") { [weak self] message in
            Task {
                await self?.handleNewMessage(message, conversationId: conversationId)
            }
        }

        // Handle message updates
        channel.on("message_updated") { [weak self] message in
            Task {
                await self?.handleMessageUpdate(message, conversationId: conversationId)
            }
        }

        // Handle typing indicators
        channel.on("user_typing") { message in
            // Handle typing indicator
            print("[Phoenix] User typing in \(conversationId): \(message.payload)")
        }

        // Handle presence
        channel.on("presence_diff") { [weak self] message in
            Task {
                await self?.handlePresenceDiff(message, conversationId: conversationId)
            }
        }
    }

    private func handleNewMessage(_ message: Message, conversationId: String) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message.payload)
            let phoenixMessage = try JSONDecoder().decode(PhoenixMessage.self, from: data)

            // Notify handlers
            eventHandlers[conversationId]?.forEach { handler in
                handler(phoenixMessage)
            }
        } catch {
            print("[Phoenix] Failed to decode message: \(error)")
        }
    }

    private func handleMessageUpdate(_ message: Message, conversationId: String) {
        do {
            let data = try JSONSerialization.data(withJSONObject: message.payload)
            let phoenixMessage = try JSONDecoder().decode(PhoenixMessage.self, from: data)

            // Notify handlers
            eventHandlers[conversationId]?.forEach { handler in
                handler(phoenixMessage)
            }
        } catch {
            print("[Phoenix] Failed to decode message update: \(error)")
        }
    }

    private func handlePresenceDiff(_ message: Message, conversationId: String) {
        // Parse presence diff and notify handlers
        if let joins = message.payload["joins"] as? [String: Any] {
            for (userId, _) in joins {
                let presence = UserPresence(
                    userId: userId,
                    status: .online,
                    lastSeen: nil
                )
                presenceHandlers.forEach { $0(conversationId, presence) }
            }
        }

        if let leaves = message.payload["leaves"] as? [String: Any] {
            for (userId, _) in leaves {
                let presence = UserPresence(
                    userId: userId,
                    status: .offline,
                    lastSeen: Date()
                )
                presenceHandlers.forEach { $0(conversationId, presence) }
            }
        }
    }

    private func handleConnect() {
        connectionState = .connected
        reconnectAttempts = 0
        print("[Phoenix] Connected successfully")
    }

    private func handleDisconnect() {
        connectionState = .disconnected
        print("[Phoenix] Disconnected")

        // Attempt reconnection
        Task {
            await attemptReconnect()
        }
    }

    private func handleError(_ error: Error) {
        connectionState = .error(error)
        print("[Phoenix] Error: \(error)")
    }

    private func attemptReconnect() async {
        guard reconnectAttempts < config.maxReconnectAttempts else {
            print("[Phoenix] Max reconnection attempts reached")
            return
        }

        reconnectAttempts += 1
        connectionState = .reconnecting

        print("[Phoenix] Attempting reconnection (\(reconnectAttempts)/\(config.maxReconnectAttempts))")

        try? await Task.sleep(nanoseconds: UInt64(config.reconnectDelay * 1_000_000_000))

        do {
            try await connect()
        } catch {
            print("[Phoenix] Reconnection failed: \(error)")
            await attemptReconnect()
        }
    }

    private func waitForConnection() async throws {
        let timeout = config.connectionTimeout
        let startTime = Date()

        while connectionState != .connected {
            if Date().timeIntervalSince(startTime) > timeout {
                throw PhoenixError.connectionTimeout
            }

            if case .error(let error) = connectionState {
                throw error
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
}

// MARK: - Error Types

public enum PhoenixError: Error, LocalizedError {
    case notConnected
    case connectionTimeout
    case channelNotJoined
    case joinFailed([String: Any])
    case sendFailed([String: Any])
    case decodingFailed(Error)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to Phoenix server"
        case .connectionTimeout:
            return "Connection timeout"
        case .channelNotJoined:
            return "Channel not joined"
        case .joinFailed(let payload):
            return "Failed to join channel: \(payload)"
        case .sendFailed(let payload):
            return "Failed to send message: \(payload)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .timeout:
            return "Request timeout"
        }
    }
}
