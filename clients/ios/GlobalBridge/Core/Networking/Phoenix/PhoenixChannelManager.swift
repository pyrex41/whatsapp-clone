//
//  PhoenixChannelManager.swift
//  GlobalBridge
//
//  Main Phoenix Channel Manager for real-time WebSocket connections
//

import Foundation
@preconcurrency import SwiftPhoenixClient

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
    private var channelJoinStates: [String: Bool] = [:] // Track if channel is fully joined
    private var connectionState: PhoenixConnectionState = .disconnected
    private var reconnectAttempts = 0
    private var eventHandlers: [String: [MessageHandler]] = [:]
    private var presenceHandlers: [PresenceHandler] = []
    private var typingHandlers: [String: [TypingHandler]] = [:]
    private var readReceiptHandlers: [String: [ReadReceiptHandler]] = [:]
    private var typingTimers: [String: Task<Void, Never>] = [:]
    private var currentUserId: String?

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

    // MARK: - User Channel (Bootstrap)
    
    /// Join user channel for bootstrap operations
    public func joinUserChannel(userId: String) async throws {
        self.currentUserId = userId
        let topic = "user:\(userId)"
        
        print("📥 [USER_CHANNEL] Joining user channel: \(topic)")
        
        guard let socket = socket else {
            print("❌ [USER_CHANNEL] Socket not connected!")
            throw PhoenixError.notConnected
        }
        
        let channel = socket.channel(topic)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var hasResumed = false
            
            channel.join()
                .receive("ok") { response in
                    print("✅ [USER_CHANNEL] Successfully joined: \(topic)")
                    print("✅ [USER_CHANNEL] Response: \(response.payload)")
                    
                    guard !hasResumed else {
                        print("⚠️ [USER_CHANNEL] Continuation already resumed, ignoring ok")
                        return
                    }
                    hasResumed = true
                    continuation.resume()
                }
                .receive("error") { message in
                    print("❌ [USER_CHANNEL] Failed to join: \(topic)")
                    print("❌ [USER_CHANNEL] Error: \(message.payload)")
                    
                    guard !hasResumed else {
                        print("⚠️ [USER_CHANNEL] Continuation already resumed, ignoring error")
                        return
                    }
                    hasResumed = true
                    continuation.resume(throwing: PhoenixError.joinFailed(PhoenixPayload(message.payload)))
                }
                .receive("timeout") { _ in
                    print("❌ [USER_CHANNEL] Timeout joining: \(topic)")
                    
                    guard !hasResumed else {
                        print("⚠️ [USER_CHANNEL] Continuation already resumed, ignoring timeout")
                        return
                    }
                    hasResumed = true
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
        
        // Store user channel
        setChannel(channel, for: "user:\(userId)")
        channelJoinStates[topic] = true
    }
    
    /// Fetch bootstrap data via user channel
    public func fetchBootstrap() async throws -> BootstrapResponse {
        guard let userId = currentUserId else {
            throw PhoenixError.notConnected
        }
        
        let topic = "user:\(userId)"
        print("📥 [BOOTSTRAP] Fetching bootstrap data from channel: \(topic)")
        
        guard let channel = channel(for: "user:\(userId)") else {
            print("❌ [BOOTSTRAP] User channel not joined!")
            throw PhoenixError.channelNotJoined
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            channel.push("bootstrap", payload: [:])
                .receive("ok") { response in
                    let payload = response.payload
                    print("✅ [BOOTSTRAP] Received response: \(payload)")
                    
                    do {
                        let data = try JSONSerialization.data(withJSONObject: payload)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .custom { decoder in
                            let container = try decoder.singleValueContainer()
                            let dateString = try container.decode(String.self)
                            
                            let formatter = ISO8601DateFormatter()
                            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            
                            if let date = formatter.date(from: dateString) {
                                return date
                            }
                            
                            formatter.formatOptions = [.withInternetDateTime]
                            if let date = formatter.date(from: dateString) {
                                return date
                            }
                            
                            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
                        }
                        
                        let bootstrap = try decoder.decode(BootstrapResponse.self, from: data)
                        print("✅ [BOOTSTRAP] Parsed \(bootstrap.threads.count) threads")
                        continuation.resume(returning: bootstrap)
                    } catch {
                        print("❌ [BOOTSTRAP] Failed to parse response: \(error)")
                        continuation.resume(throwing: PhoenixError.decodingFailed(error))
                    }
                }
                .receive("error") { message in
                    print("❌ [BOOTSTRAP] Error response: \(message.payload)")
                    continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                }
                .receive("timeout") { _ in
                    print("❌ [BOOTSTRAP] Request timed out")
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }
    
    /// Create thread via user channel
    public func createThread(
        threadType: String,
        title: String?,
        participantIds: [String]
    ) async throws -> ThreadData {
        guard let userId = currentUserId else {
            throw PhoenixError.notConnected
        }
        
        guard let channel = channel(for: "user:\(userId)") else {
            throw PhoenixError.channelNotJoined
        }
        
        var payload: [String: Any] = [
            "thread_type": threadType,
            "participant_ids": participantIds
        ]
        
        if let title = title {
            payload["title"] = title
        }
        
        print("🆕 [CREATE_THREAD] Creating thread: type=\(threadType), participants=\(participantIds)")
        
        return try await withCheckedThrowingContinuation { continuation in
            channel.push("create_thread", payload: payload)
                .receive("ok") { response in
                    let payload = response.payload
                    print("✅ [CREATE_THREAD] Thread created: \(payload)")
                    
                    do {
                        let data = try JSONSerialization.data(withJSONObject: payload)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .custom { decoder in
                            let container = try decoder.singleValueContainer()
                            let dateString = try container.decode(String.self)
                            
                            let formatter = ISO8601DateFormatter()
                            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                            
                            if let date = formatter.date(from: dateString) {
                                return date
                            }
                            
                            formatter.formatOptions = [.withInternetDateTime]
                            if let date = formatter.date(from: dateString) {
                                return date
                            }
                            
                            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
                        }
                        
                        let thread = try decoder.decode(ThreadData.self, from: data)
                        continuation.resume(returning: thread)
                    } catch {
                        print("❌ [CREATE_THREAD] Failed to parse: \(error)")
                        continuation.resume(throwing: PhoenixError.decodingFailed(error))
                    }
                }
                .receive("error") { message in
                    print("❌ [CREATE_THREAD] Error: \(message.payload)")
                    continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                }
                .receive("timeout") { _ in
                    print("❌ [CREATE_THREAD] Timeout")
                    continuation.resume(throwing: PhoenixError.timeout)
                }
        }
    }

    // MARK: - Channel Management

    /// Join a conversation channel
    public func joinConversation(_ conversationId: String) async throws {
        print("📥 [JOIN] joinConversation called for: \(conversationId)")

        guard let socket = socket else {
            print("❌ [JOIN] Socket not connected!")
            throw PhoenixError.notConnected
        }

        let topic = topic(for: conversationId)
        print("📥 [JOIN] Topic: \(topic)")
        print("📥 [JOIN] Current state - channel exists: \(channel(for: conversationId) != nil), join state: \(channelJoinStates[topic] as Any)")

        // Check if already joined and in good state
        if let _ = channel(for: conversationId), channelJoinStates[topic] == true {
            print("✅ [JOIN] Already joined channel with confirmed state: \(topic)")
            return
        }

        // If channel exists but join state is not confirmed, clean up and rejoin
        if channel(for: conversationId) != nil && channelJoinStates[topic] != true {
            print("⚠️ [JOIN] Channel exists but not in joined state, cleaning up: \(topic)")
            removeChannel(for: conversationId)
            channelJoinStates.removeValue(forKey: topic)
        }

        print("📥 [JOIN] Creating new channel for topic: \(topic)")
        let channel = socket.channel(topic)
        setChannel(channel, for: conversationId)
        channelJoinStates[topic] = false // Mark as joining but not yet joined

        print("📥 [JOIN] Setting up event handlers...")
        // Set up event handlers
        setupChannelHandlers(channel, conversationId: conversationId)

        print("📥 [JOIN] Attempting to join channel...")
        // Join channel
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var hasResumed = false

                channel.join()
                    .receive("ok") { response in
                        print("✅ [JOIN] Successfully joined channel: \(topic)")
                        print("✅ [JOIN] Join response: \(response.payload)")

                        guard !hasResumed else {
                            print("⚠️ [JOIN] Continuation already resumed, ignoring ok")
                            return
                        }
                        hasResumed = true

                        // Resume continuation immediately
                        continuation.resume()
                    }
                    .receive("error") { message in
                        print("❌ [JOIN] Failed to join channel: \(topic)")
                        print("❌ [JOIN] Error payload: \(message.payload)")

                        guard !hasResumed else {
                            print("⚠️ [JOIN] Continuation already resumed, ignoring error")
                            return
                        }
                        hasResumed = true

                        // Resume continuation with error
                        continuation.resume(throwing: PhoenixError.joinFailed(PhoenixPayload(message.payload)))
                    }
                    .receive("timeout") { _ in
                        print("❌ [JOIN] Timeout joining channel: \(topic)")

                        guard !hasResumed else {
                            print("⚠️ [JOIN] Continuation already resumed, ignoring timeout")
                            return
                        }
                        hasResumed = true

                        // Resume continuation with timeout error
                        continuation.resume(throwing: PhoenixError.timeout)
                    }
            }

            // Mark channel as joined - this runs on the actor's executor
            markChannelAsJoined(topic)
        } catch {
            // Clean up on join failure
            markChannelAsFailed(topic)
            removeChannel(for: conversationId)
            channelJoinStates.removeValue(forKey: topic)
            throw error
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
        let topic = topic(for: conversationId)
        channel(for: conversationId)?.leave()
        removeChannel(for: conversationId)
        channelJoinStates.removeValue(forKey: topic)
    }

    // MARK: - Private Channel State Helpers

    private func markChannelAsJoined(_ topic: String) {
        channelJoinStates[topic] = true
        print("✅ [STATE] Channel marked as joined: \(topic)")
    }

    private func markChannelAsFailed(_ topic: String) {
        channelJoinStates[topic] = false
        print("❌ [STATE] Channel marked as failed: \(topic)")
    }

    private func isChannelJoined(for conversationId: String) -> Bool {
        let topic = topic(for: conversationId)
        return channelJoinStates[topic] == true
    }

    /// Wait for channel to be joined with timeout
    private func waitForChannelJoin(conversationId: String, timeout: TimeInterval = 5.0) async throws {
        let topic = topic(for: conversationId)
        let startTime = Date()
        var waitCount = 0

        print("⏳ [WAIT] Starting to wait for channel join: \(topic)")
        print("⏳ [WAIT] Current join state: \(channelJoinStates[topic] as Any)")

        while !isChannelJoined(for: conversationId) {
            waitCount += 1
            let elapsed = Date().timeIntervalSince(startTime)

            if elapsed > timeout {
                print("⏱️ [WAIT] Timeout after \(waitCount) checks (\(elapsed)s) waiting for channel join: \(topic)")
                print("⏱️ [WAIT] Final join state: \(channelJoinStates[topic] as Any)")
                throw PhoenixError.timeout
            }

            // Check if channel join failed
            if channelJoinStates[topic] == false && channel(for: conversationId) != nil {
                print("❌ [WAIT] Channel join failed (state=false, channel exists): \(topic)")
                throw PhoenixError.channelNotJoined
            }

            if waitCount % 10 == 0 {
                print("⏳ [WAIT] Still waiting... (\(waitCount) checks, \(String(format: "%.2f", elapsed))s elapsed, state: \(channelJoinStates[topic] as Any))")
            }

            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        print("✅ [WAIT] Channel join confirmed after \(waitCount) checks (\(Date().timeIntervalSince(startTime))s): \(topic)")
    }

    // MARK: - Message Sending

    /// Send a message to a conversation
    public func sendMessage(
        conversationId: String,
        content: String,
        replyToId: String? = nil
    ) async throws -> PhoenixMessage {
        let topic = topic(for: conversationId)
        print("📤 [PHOENIX] sendMessage called - conversationId: \(conversationId), content: \"\(content)\", replyToId: \(replyToId ?? "nil")")
        print("📤 [PHOENIX] Topic: \(topic)")
        print("📤 [PHOENIX] Current join state: \(channelJoinStates[topic] as Any)")
        print("📤 [PHOENIX] Channel exists: \(channel(for: conversationId) != nil)")

        // Wait for channel to be fully joined before sending
        if !isChannelJoined(for: conversationId) {
            print("⏳ [PHOENIX] Channel not yet joined, waiting...")
            try await waitForChannelJoin(conversationId: conversationId)
            print("✅ [PHOENIX] Wait completed, channel should now be joined")
        } else {
            print("✅ [PHOENIX] Channel already joined, proceeding immediately")
        }

        guard let channel = channel(for: conversationId) else {
            print("❌ [PHOENIX] Channel not joined for conversation: \(conversationId)")
            print("❌ [PHOENIX] Available channels: \(channels.keys)")
            throw PhoenixError.channelNotJoined
        }
        print("✅ [PHOENIX] Channel found and joined for conversation: \(conversationId)")

        var payload: [String: Any] = [
            "content": content,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        if let replyToId = replyToId {
            payload["reply_to_id"] = replyToId
        }

        print("📤 [PHOENIX] Pushing 'new_message' to channel with payload: \(payload)")
        print("📤 [PHOENIX] Channel state before push: \(channel)")

        return try await withCheckedThrowingContinuation { continuation in
            let push = channel.push("new_message", payload: payload)
            print("📤 [PHOENIX] Push object created: \(push)")

            push.receive("ok") { [weak self] response in
                    print("✅ [PHOENIX] Received 'ok' response: \(response.payload)")
                    guard let self else {
                        print("❌ [PHOENIX] Self is nil in ok handler")
                        continuation.resume(throwing: PhoenixError.notConnected)
                        return
                    }

                    do {
                        print("📤 [PHOENIX] Parsing response payload...")
                        let message = try self.parsePhoenixMessage(from: response.payload)
                        print("✅ [PHOENIX] Message parsed successfully: id=\(message.id), conversationId=\(message.conversationId), senderId=\(message.senderId), content=\"\(message.content)\", status=\(message.status.rawValue)")
                        continuation.resume(returning: message)
                    } catch {
                        print("❌ [PHOENIX] Failed to parse message: \(error)")
                        continuation.resume(throwing: PhoenixError.decodingFailed(error))
                    }
                }
                .receive("error") { message in
                    print("❌ [PHOENIX] Received 'error' response: \(message.payload)")
                    continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                }
                .receive("timeout") { _ in
                    print("❌ [PHOENIX] Request timed out")
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
        // Wait for channel to be joined (with a shorter timeout for typing)
        if !isChannelJoined(for: conversationId) {
            print("⏳ [TYPING] Channel not yet joined, waiting...")
            do {
                try await waitForChannelJoin(conversationId: conversationId, timeout: 2.0)
            } catch {
                print("⚠️ [TYPING] Channel join timeout, skipping typing indicator")
                return
            }
        }

        guard let channel = channel(for: conversationId) else {
            print("[Phoenix] Cannot send typing indicator - channel not joined")
            return
        }

        let payload: [String: Any] = ["is_typing": isTyping]

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
        "thread:\(conversationId)"
    }

    nonisolated private func parsePhoenixMessage(from payload: [String: Any]) throws -> PhoenixMessage {
        print("📦 [PHOENIX] Parsing payload: \(payload)")

        guard
            let id = payload["id"] as? String,
            let threadId = payload["thread_id"] as? String,
            let senderId = payload["sender_id"] as? String,
            let content = payload["content"] as? String
        else {
            print("❌ [PHOENIX] Missing required fields in payload")
            throw PhoenixError.decodingFailed(PhoenixDecodingError.missingRequiredFields)
        }

        // Backend sends created_at, not timestamp
        let timestampString = (payload["created_at"] as? String) ?? (payload["timestamp"] as? String) ?? ISO8601DateFormatter().string(from: Date())

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
            conversationId: threadId,
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
        channel.on("new_message") { [weak self] socketMessage in
            guard let self else { return }
            do {
                let message = try self.parsePhoenixMessage(from: socketMessage.payload)
                Task { await self.deliverNewMessage(message, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode message: \(error)")
            }
        }

        // Handle message updates
        channel.on("message_updated") { [weak self] socketMessage in
            guard let self else { return }
            do {
                let message = try self.parsePhoenixMessage(from: socketMessage.payload)
                Task { await self.deliverMessageUpdate(message, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode message update: \(error)")
            }
        }

        // Handle typing indicators
        channel.on("user_typing") { [weak self] socketMessage in
            guard let self else { return }
            do {
                let indicator = try self.parseTypingIndicator(from: socketMessage.payload)
                Task { await self.deliverTypingIndicator(indicator, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode typing indicator: \(error)")
            }
        }

        // Handle read receipts
        channel.on("read_receipt") { [weak self] socketMessage in
            guard let self else { return }
            do {
                let receipt = try self.parseReadReceipt(from: socketMessage.payload)
                Task { await self.deliverReadReceipt(receipt, conversationId: conversationId) }
            } catch {
                print("[Phoenix] Failed to decode read receipt: \(error)")
            }
        }

        // Handle presence
        channel.on("presence_diff") { [weak self] socketMessage in
            guard let self else { return }
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
