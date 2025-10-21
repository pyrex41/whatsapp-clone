//
//  PhoenixChannelManager.swift
//  GlobalBridge
//
//  Main Phoenix Channel Manager for real-time WebSocket connections
//

import Foundation
import SwiftPhoenixClient

private typealias SocketMessage = SwiftPhoenixClient.Message
public typealias MessageHandler = @Sendable (PhoenixMessage) -> Void
public typealias PresenceHandler = @Sendable (String, UserPresence) -> Void
public typealias TypingHandler = @Sendable (TypingIndicator) -> Void
public typealias ReadReceiptHandler = @Sendable (ReadReceipt) -> Void

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
    private var eventHandlers: [String: [MessageHandler]] = [:]
    private var presenceHandlers: [PresenceHandler] = []
    private var typingHandlers: [String: [TypingHandler]] = [:]
    private var readReceiptHandlers: [String: [ReadReceiptHandler]] = [:]
    private var typingTimers: [String: Task<Void, Never>] = [:]

    var currentConnectionState: PhoenixConnectionState {
        connectionState
    }

    func channel(for conversationId: String) -> Channel? {
        channels[topic(for: conversationId)]
    }

    func setChannel(_ channel: Channel, for conversationId: String) {
        channels[topic(for: conversationId)] = channel
    }

    func removeChannel(for conversationId: String) {
        channels.removeValue(forKey: topic(for: conversationId))
    }

    private var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    // MARK: - Initialization

    public init(config: PhoenixConfig) {
        self.config = config
    }

    // MARK: - Connection Management

    /// Connect to Phoenix server
    public func connect(authToken: String? = nil) async throws {
        guard !isConnected else { return }

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
            Task { [weak self] in
                await self?.handleConnect()
            }
        }

        socket?.onClose { [weak self] in
            Task { [weak self] in
                await self?.handleDisconnect()
            }
        }

        socket?.onError { [weak self] error, _ in
            Task { [weak self] in
                guard let self else { return }
                await self.handleError(error)
            }
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

        let topic = topic(for: conversationId)

        // Check if already joined
        if channel(for: conversationId) != nil {
            return
        }

        let channel = socket.channel(topic)
        setChannel(channel, for: conversationId)

        // Set up event handlers
        setupChannelHandlers(channel, conversationId: conversationId)

        // Join channel
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.join()
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.joinFailed(PhoenixPayload(message.payload)))
                }
                .receive("timeout") { _ in
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }

    private func deliverNewMessage(_ message: PhoenixMessage, conversationId: String) async {
        eventHandlers[conversationId]?.forEach { handler in
            handler(message)
        }
    }

    private func deliverMessageUpdate(_ message: PhoenixMessage, conversationId: String) async {
        eventHandlers[conversationId]?.forEach { handler in
            handler(message)
        }
    }

    private func deliverTypingIndicator(_ indicator: TypingIndicator, conversationId: String) async {
        typingHandlers[conversationId]?.forEach { handler in
            handler(indicator)
        }
    }

    private func deliverReadReceipt(_ receipt: ReadReceipt, conversationId: String) async {
        readReceiptHandlers[conversationId]?.forEach { handler in
            handler(receipt)
        }
    }

    private func deliverPresenceDiff(
        conversationId: String,
        joinedUserIds: [String],
        leftUserIds: [String]
    ) async {
        for userId in joinedUserIds {
            let presence = UserPresence(userId: userId, status: .online, lastSeen: nil)
            presenceHandlers.forEach { $0(conversationId, presence) }
        }

        for userId in leftUserIds {
            let presence = UserPresence(userId: userId, status: .offline, lastSeen: Date())
            presenceHandlers.forEach { $0(conversationId, presence) }
        }
    }

    /// Leave a conversation channel
    public func leaveConversation(_ conversationId: String) {
        channel(for: conversationId)?.leave()
        removeChannel(for: conversationId)
    }

    // MARK: - Message Sending

    /// Send a message to a conversation
    public func sendMessage(
        conversationId: String,
        content: String,
        replyToId: String? = nil
    ) async throws -> PhoenixMessage {
        guard let channel = channel(for: conversationId) else {
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
                .receive("ok") { [weak self] response in
                    guard let self else {
                        continuation.resume(throwing: PhoenixError.notConnected)
                        return
                    }

                    do {
                        let message = try self.parsePhoenixMessage(from: response.payload)
                        continuation.resume(returning: message)
                    } catch {
                        continuation.resume(throwing: PhoenixError.decodingFailed(error))
                    }
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                }
                .receive("timeout") { _ in
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }

    /// Mark conversation as read
    public func markAsRead(conversationId: String, messageId: String) async throws {
        guard let channel = channel(for: conversationId) else {
            throw PhoenixError.channelNotJoined
        }

        let payload: [String: Any] = ["message_id": messageId]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.push("mark_read", payload: payload)
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { message in
                    continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                }
        }
    }

    // MARK: - Event Handlers

    /// Register handler for incoming messages
    public func onMessage(conversationId: String, handler: @escaping MessageHandler) {
        if eventHandlers[conversationId] == nil {
            eventHandlers[conversationId] = []
        }
        eventHandlers[conversationId]?.append(handler)
    }

    /// Register handler for presence updates
    public func onPresence(handler: @escaping PresenceHandler) {
        presenceHandlers.append(handler)
    }

    /// Register handler for typing indicators
    public func onTyping(conversationId: String, handler: @escaping TypingHandler) {
        if typingHandlers[conversationId] == nil {
            typingHandlers[conversationId] = []
        }
        typingHandlers[conversationId]?.append(handler)
    }

    /// Register handler for read receipts
    public func onReadReceipt(conversationId: String, handler: @escaping ReadReceiptHandler) {
        if readReceiptHandlers[conversationId] == nil {
            readReceiptHandlers[conversationId] = []
        }
        readReceiptHandlers[conversationId]?.append(handler)
    }

    /// Send typing indicator
    public func sendTypingIndicator(conversationId: String, isTyping: Bool) async {
        guard let channel = channel(for: conversationId) else {
            print("[Phoenix] Cannot send typing indicator - channel not joined")
            return
        }

        let payload: [String: Any] = ["typing": isTyping]

        channel.push("typing", payload: payload)
            .receive("ok") { _ in
                print("[Phoenix] Typing indicator sent: \(isTyping)")
            }
            .receive("error") { message in
                print("[Phoenix] Failed to send typing indicator: \(message.payload)")
            }

        // Auto-stop typing after 5 seconds
        if isTyping {
            let timerKey = "\(conversationId)_typing"
            typingTimers[timerKey]?.cancel()
            typingTimers[timerKey] = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                await sendTypingIndicator(conversationId: conversationId, isTyping: false)
            }
        }
    }

    /// Send read receipt
    public func sendReadReceipt(conversationId: String, messageId: String) async {
        guard let channel = channel(for: conversationId) else {
            print("[Phoenix] Cannot send read receipt - channel not joined")
            return
        }

        let payload: [String: Any] = [
            "message_id": messageId,
            "read_at": ISO8601DateFormatter().string(from: Date())
        ]

        channel.push("read_receipt", payload: payload)
            .receive("ok") { _ in
                print("[Phoenix] Read receipt sent for message: \(messageId)")
            }
            .receive("error") { message in
                print("[Phoenix] Failed to send read receipt: \(message.payload)")
            }
    }

    // MARK: - Private Methods

    private func topic(for conversationId: String) -> String {
        "conversation:\(conversationId)"
    }

    nonisolated private func parsePhoenixMessage(from payload: [String: Any]) throws -> PhoenixMessage {
        guard
            let id = payload["id"] as? String,
            let conversationId = payload["conversation_id"] as? String,
            let senderId = payload["sender_id"] as? String,
            let content = payload["content"] as? String,
            let timestampString = payload["timestamp"] as? String
        else {
            throw PhoenixError.decodingFailed(PhoenixDecodingError.missingRequiredFields)
        }

        let timestamp = parseISO8601Date(timestampString) ?? Date()

        let statusString = (payload["status"] as? String) ?? PhoenixMessage.MessageStatus.sent.rawValue
        guard let status = PhoenixMessage.MessageStatus(rawValue: statusString) else {
            throw PhoenixError.decodingFailed(PhoenixDecodingError.unknownStatus(statusString))
        }

        var metadata: PhoenixMessage.MessageMetadata?
        if let metadataPayload = payload["metadata"] as? [String: Any] {
            let replyToId = metadataPayload["reply_to_id"] as? String
            let edited = metadataPayload["edited"] as? Bool
            let editedAt = (metadataPayload["edited_at"] as? String).flatMap(parseISO8601Date)

            var attachments: [PhoenixMessage.MessageMetadata.Attachment]?
            if let attachmentsPayload = metadataPayload["attachments"] as? [[String: Any]] {
                attachments = attachmentsPayload.compactMap { attachmentDict in
                    guard
                        let attachmentId = attachmentDict["id"] as? String,
                        let type = attachmentDict["type"] as? String,
                        let url = attachmentDict["url"] as? String,
                        let name = attachmentDict["name"] as? String
                    else {
                        return nil
                    }

                    let size: Int?
                    if let intSize = attachmentDict["size"] as? Int {
                        size = intSize
                    } else if let numberSize = attachmentDict["size"] as? NSNumber {
                        size = numberSize.intValue
                    } else {
                        size = nil
                    }

                    return PhoenixMessage.MessageMetadata.Attachment(
                        id: attachmentId,
                        type: type,
                        url: url,
                        name: name,
                        size: size
                    )
                }
            }

            metadata = PhoenixMessage.MessageMetadata(
                replyToId: replyToId,
                edited: edited,
                editedAt: editedAt,
                attachments: attachments
            )
        }

        return PhoenixMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            timestamp: timestamp,
            status: status,
            metadata: metadata
        )
    }

    nonisolated private func parseTypingIndicator(from payload: [String: Any]) throws -> TypingIndicator {
        guard
            let userId = payload["user_id"] as? String,
            let conversationId = payload["conversation_id"] as? String
        else {
            throw PhoenixError.decodingFailed(PhoenixDecodingError.missingRequiredFields)
        }

        let rawTyping = payload["is_typing"]
        let isTyping: Bool
        if let boolValue = rawTyping as? Bool {
            isTyping = boolValue
        } else if let intValue = rawTyping as? Int {
            isTyping = intValue != 0
        } else if let stringValue = rawTyping as? String {
            isTyping = (stringValue as NSString).boolValue
        } else {
            isTyping = true
        }

        let timestampString = payload["timestamp"] as? String
        let timestamp = timestampString.flatMap(parseISO8601Date) ?? Date()

        return TypingIndicator(
            userId: userId,
            conversationId: conversationId,
            isTyping: isTyping,
            timestamp: timestamp
        )
    }

    nonisolated private func parseReadReceipt(from payload: [String: Any]) throws -> ReadReceipt {
        guard
            let userId = payload["user_id"] as? String,
            let conversationId = payload["conversation_id"] as? String,
            let messageId = payload["message_id"] as? String
        else {
            throw PhoenixError.decodingFailed(PhoenixDecodingError.missingRequiredFields)
        }

        let readAtString = payload["read_at"] as? String
        let readAt = readAtString.flatMap(parseISO8601Date) ?? Date()

        return ReadReceipt(
            userId: userId,
            conversationId: conversationId,
            messageId: messageId,
            readAt: readAt
        )
    }

    nonisolated private func parseISO8601Date(_ string: String) -> Date? {
        if let date = iso8601WithFractional.date(from: string) {
            return date
        }
        return iso8601Basic.date(from: string)
    }

    nonisolated private var iso8601WithFractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    nonisolated private var iso8601Basic: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private func setupChannelHandlers(_ channel: Channel, conversationId: String) {
        // Handle new messages
        channel.on("new_message") { [self] socketMessage in
            do {
                let message = try self.parsePhoenixMessage(from: socketMessage.payload)
                Task { await self.deliverNewMessage(message, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode message: \(error)")
            }
        }

        // Handle message updates
        channel.on("message_updated") { [self] socketMessage in
            do {
                let message = try self.parsePhoenixMessage(from: socketMessage.payload)
                Task { await self.deliverMessageUpdate(message, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode message update: \(error)")
            }
        }

        // Handle typing indicators
        channel.on("user_typing") { [self] socketMessage in
            do {
                let indicator = try self.parseTypingIndicator(from: socketMessage.payload)
                Task { await self.deliverTypingIndicator(indicator, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode typing indicator: \(error)")
            }
        }

        // Handle read receipts
        channel.on("read_receipt") { [self] socketMessage in
            do {
                let receipt = try self.parseReadReceipt(from: socketMessage.payload)
                Task { await self.deliverReadReceipt(receipt, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode read receipt: \(error)")
            }
        }

        // Handle presence
        channel.on("presence_diff") { [self] socketMessage in
            let payload = socketMessage.payload
            let joins = (payload["joins"] as? [String: Any])?.keys.map { String($0) } ?? []
            let leaves = (payload["leaves"] as? [String: Any])?.keys.map { String($0) } ?? []

            Task {
                await self.deliverPresenceDiff(
                    conversationId: conversationId,
                    joinedUserIds: joins,
                    leftUserIds: leaves
                )
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

        while !isConnected {
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

public struct PhoenixPayload: Sendable, CustomStringConvertible {
    private let descriptionValue: String

    public nonisolated init(_ raw: [String: Any]) {
        self.descriptionValue = raw.description
    }

    public nonisolated var description: String {
        descriptionValue
    }
}

public enum PhoenixError: Error, LocalizedError, Sendable {
    case notConnected
    case connectionTimeout
    case channelNotJoined
    case joinFailed(PhoenixPayload)
    case sendFailed(PhoenixPayload)
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
            return "Failed to join channel: \(payload.description)"
        case .sendFailed(let payload):
            return "Failed to send message: \(payload.description)"
        case .decodingFailed(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .timeout:
            return "Request timeout"
        }
    }
}

private enum PhoenixDecodingError: Error {
    case missingRequiredFields
    case unknownStatus(String)
}
