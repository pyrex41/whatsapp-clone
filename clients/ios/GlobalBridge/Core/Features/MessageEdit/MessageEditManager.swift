//
//  MessageEditManager.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  Handles message editing with Phoenix channel sync and offline support
//

import Foundation
@preconcurrency import SwiftPhoenixClient

/// Manages message editing operations with real-time sync
@MainActor
final class MessageEditManager {

    // MARK: - Properties

    private let phoenixChannelManager: PhoenixChannelManager
    private let databaseManager: DatabaseManager
    private let offlineQueueManager: OfflineQueueManager

    /// Edit timeout in seconds (15 minutes)
    static let editTimeoutSeconds: TimeInterval = 15 * 60

    /// Maximum content length for edited messages
    static let maxContentLength: Int = 4096

    // MARK: - Initialization

    init(
        phoenixChannelManager: PhoenixChannelManager,
        databaseManager: DatabaseManager,
        offlineQueueManager: OfflineQueueManager
    ) {
        self.phoenixChannelManager = phoenixChannelManager
        self.databaseManager = databaseManager
        self.offlineQueueManager = offlineQueueManager
    }

    // MARK: - Edit Operations

    /// Check if a message can be edited
    /// - Parameters:
    ///   - message: The message to check
    ///   - currentUserId: The current user's ID
    /// - Returns: True if the message can be edited
    func canEditMessage(_ message: Message, currentUserId: String) -> Bool {
        // Only own messages can be edited
        guard message.senderId == currentUserId else {
            return false
        }

        // Deleted messages cannot be edited
        if message.deletedAt != nil {
            return false
        }

        // Check if within edit timeout (15 minutes)
        let timeSinceSent = Date().timeIntervalSince(message.createdAt)
        return timeSinceSent <= Self.editTimeoutSeconds
    }

    /// Validate edited content
    /// - Parameter content: The new content
    /// - Throws: EditError if content is invalid
    func validateEditedContent(_ content: String) throws {
        // Check if empty
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw EditError.emptyContent
        }

        // Check length
        if content.count > Self.maxContentLength {
            throw EditError.contentTooLong(maxLength: Self.maxContentLength)
        }
    }

    /// Edit a message
    /// - Parameters:
    ///   - messageId: The message ID to edit
    ///   - threadId: The thread ID
    ///   - newContent: The new message content
    ///   - currentUserId: The current user's ID
    /// - Throws: EditError if edit fails
    func editMessage(
        messageId: UUID,
        threadId: UUID,
        newContent: String,
        currentUserId: String
    ) async throws {
        print("✏️ [EDIT] Editing message: \(messageId)")

        // Validate content
        try validateEditedContent(newContent)

        // Fetch the message
        guard let message = try? await databaseManager.getMessage(id: messageId, threadId: threadId) else {
            throw EditError.messageNotFound
        }

        // Check if can edit
        guard canEditMessage(message, currentUserId: currentUserId) else {
            throw EditError.cannotEdit
        }

        // Check if content actually changed
        if message.content == newContent {
            print("ℹ️ [EDIT] Content unchanged, skipping edit")
            return
        }

        // Update message locally (optimistic update)
        var editedMessage = message
        editedMessage.content = newContent
        editedMessage.editedAt = Date()
        editedMessage.updatedAt = Date()

        try await databaseManager.updateMessage(editedMessage)

        print("✅ [EDIT] Message updated locally")

        // Sync with Phoenix if online
        do {
            let conversationId = threadId.uuidString
            try await syncEditToPhoenix(
                conversationId: conversationId,
                messageId: messageId.uuidString,
                newContent: newContent
            )
            print("✅ [EDIT] Message synced to Phoenix")
        } catch {
            print("⚠️ [EDIT] Failed to sync to Phoenix (offline?): \(error)")
            // Queue for offline sync via CDC
            // The CDC triggers will automatically capture this update
        }
    }

    /// Sync edit operation to Phoenix
    private func syncEditToPhoenix(
        conversationId: String,
        messageId: String,
        newContent: String
    ) async throws {
        guard let sendableChannel = await phoenixChannelManager.sendableChannel(for: conversationId) else {
            throw EditError.channelNotJoined
        }
        let channel = sendableChannel.channel

        let payload: [String: Any] = [
            "message_id": messageId,
            "content": newContent,
            "edited_at": ISO8601DateFormatter().string(from: Date())
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.push("edit_message", payload: payload)
                .receive("ok") { response in
                    print("✅ [EDIT] Edit acknowledged by server: \(response.payload)")
                    continuation.resume()
                }
                .receive("error") { message in
                    print("❌ [EDIT] Edit failed on server: \(message.payload)")
                    continuation.resume(throwing: EditError.syncFailed(message.payload.description))
                }
                .receive("timeout") { _ in
                    print("❌ [EDIT] Edit request timed out")
                    continuation.resume(throwing: EditError.timeout)
                }
        }
    }

    /// Handle incoming edit from Phoenix channel
    func handleIncomingEdit(
        messageId: String,
        threadId: String,
        newContent: String,
        editedAt: Date
    ) async throws {
        print("📥 [EDIT] Received edit from Phoenix: \(messageId)")

        guard let msgId = UUID(uuidString: messageId),
              let thrdId = UUID(uuidString: threadId) else {
            print("❌ [EDIT] Invalid UUIDs")
            return
        }

        // Fetch the message
        guard var message = try? await databaseManager.getMessage(id: msgId, threadId: thrdId) else {
            print("⚠️ [EDIT] Message not found locally: \(messageId)")
            return
        }

        // Update message
        message.content = newContent
        message.editedAt = editedAt
        message.updatedAt = Date()

        try await databaseManager.updateMessage(message)

        print("✅ [EDIT] Incoming edit applied locally")
    }

    /// Get edit history for a message (if available)
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - conversationId: The conversation ID
    /// - Returns: Array of edit history entries
    func getEditHistory(messageId: String, conversationId: String) async throws -> [EditHistoryEntry] {
        guard let sendableChannel = await phoenixChannelManager.sendableChannel(for: conversationId) else {
            throw EditError.channelNotJoined
        }
        let channel = sendableChannel.channel

        let payload: [String: Any] = ["message_id": messageId]

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("get_edit_history", payload: payload)
                .receive("ok") { response in
                    guard let history = response.payload["history"] as? [[String: Any]] else {
                        continuation.resume(returning: [])
                        return
                    }

                    let entries = history.compactMap { dict -> EditHistoryEntry? in
                        guard
                            let content = dict["content"] as? String,
                            let timestampStr = dict["edited_at"] as? String,
                            let timestamp = ISO8601DateFormatter().date(from: timestampStr)
                        else {
                            return nil
                        }

                        return EditHistoryEntry(
                            content: content,
                            editedAt: timestamp
                        )
                    }

                    continuation.resume(returning: entries)
                }
                .receive("error") { message in
                    print("⚠️ [EDIT] Failed to fetch edit history: \(message.payload)")
                    continuation.resume(returning: [])
                }
                .receive("timeout") { _ in
                    continuation.resume(throwing: EditError.timeout)
                }
        }
    }
}

// MARK: - Models

/// Represents an edit history entry
struct EditHistoryEntry: Identifiable, Codable {
    var id: UUID { UUID() }
    let content: String
    let editedAt: Date
}

// MARK: - Errors

enum EditError: LocalizedError {
    case messageNotFound
    case cannotEdit
    case emptyContent
    case contentTooLong(maxLength: Int)
    case channelNotJoined
    case syncFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .messageNotFound:
            return "Message not found"
        case .cannotEdit:
            return "Cannot edit this message (not your message or edit timeout expired)"
        case .emptyContent:
            return "Message cannot be empty"
        case .contentTooLong(let maxLength):
            return "Message is too long (max \(maxLength) characters)"
        case .channelNotJoined:
            return "Not connected to conversation"
        case .syncFailed(let reason):
            return "Failed to sync edit: \(reason)"
        case .timeout:
            return "Edit request timed out"
        }
    }
}
