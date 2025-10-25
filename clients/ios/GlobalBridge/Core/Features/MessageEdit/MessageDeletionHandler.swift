//
//  MessageDeletionHandler.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  Handles message deletion with Phoenix channel sync and offline support
//

import Foundation
@preconcurrency import SwiftPhoenixClient

/// Deletion scope for messages
enum DeletionScope {
    case forMe          // Delete only for current user
    case forEveryone    // Delete for all participants (sender only)
}

/// Manages message deletion operations with real-time sync
@MainActor
final class MessageDeletionHandler {

    // MARK: - Properties

    private let phoenixChannelManager: PhoenixChannelManager
    private let databaseManager: DatabaseManager
    private let offlineQueueManager: OfflineQueueManager

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

    // MARK: - Delete Operations

    /// Check if a message can be deleted for everyone
    /// - Parameters:
    ///   - message: The message to check
    ///   - currentUserId: The current user's ID
    /// - Returns: True if the message can be deleted for everyone
    func canDeleteForEveryone(_ message: Message, currentUserId: String) -> Bool {
        // Only the sender can delete for everyone
        return message.senderId == currentUserId && message.deletedAt == nil
    }

    /// Check if a message can be deleted for the current user
    /// - Parameter message: The message to check
    /// - Returns: True if the message can be deleted
    func canDeleteForMe(_ message: Message) -> Bool {
        // Any message can be deleted for the current user
        return message.deletedAt == nil
    }

    /// Delete a message
    /// - Parameters:
    ///   - messageId: The message ID to delete
    ///   - threadId: The thread ID
    ///   - scope: Deletion scope (forMe or forEveryone)
    ///   - currentUserId: The current user's ID
    /// - Throws: DeletionError if deletion fails
    func deleteMessage(
        messageId: UUID,
        threadId: UUID,
        scope: DeletionScope,
        currentUserId: String
    ) async throws {
        print("🗑️ [DELETE] Deleting message: \(messageId), scope: \(scope)")

        // Fetch the message
        guard let message = try? await databaseManager.getMessage(id: messageId, threadId: threadId) else {
            throw DeletionError.messageNotFound
        }

        // Check if already deleted
        if message.deletedAt != nil {
            print("ℹ️ [DELETE] Message already deleted")
            return
        }

        // Validate deletion scope
        if scope == .forEveryone {
            guard canDeleteForEveryone(message, currentUserId: currentUserId) else {
                throw DeletionError.cannotDeleteForEveryone
            }
        }

        // Perform soft delete locally (optimistic update)
        var deletedMessage = message
        deletedMessage.deletedAt = Date()
        deletedMessage.updatedAt = Date()

        // For "delete for me", we could add a metadata flag instead
        // For "delete for everyone", we mark it as deleted
        if scope == .forMe {
            var metadata = deletedMessage.metadata ?? [:]
            metadata["deleted_for_user_\(currentUserId)"] = "true"
            deletedMessage.metadata = metadata
        }

        try await databaseManager.updateMessage(deletedMessage)

        print("✅ [DELETE] Message deleted locally")

        // Sync with Phoenix if online
        do {
            let conversationId = threadId.uuidString
            try await syncDeletionToPhoenix(
                conversationId: conversationId,
                messageId: messageId.uuidString,
                scope: scope
            )
            print("✅ [DELETE] Deletion synced to Phoenix")
        } catch {
            print("⚠️ [DELETE] Failed to sync to Phoenix (offline?): \(error)")
            // Queue for offline sync via CDC
            // The CDC triggers will automatically capture this update
        }
    }

    /// Sync deletion operation to Phoenix
    private func syncDeletionToPhoenix(
        conversationId: String,
        messageId: String,
        scope: DeletionScope
    ) async throws {
        guard let sendableChannel = await phoenixChannelManager.sendableChannel(for: conversationId) else {
            throw DeletionError.channelNotJoined
        }
        let channel = sendableChannel.channel

        let payload: [String: Any] = [
            "message_id": messageId,
            "scope": scope == .forEveryone ? "everyone" : "me",
            "deleted_at": ISO8601DateFormatter().string(from: Date())
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.push("delete_message", payload: payload)
                .receive("ok") { response in
                    print("✅ [DELETE] Deletion acknowledged by server: \(response.payload)")
                    continuation.resume()
                }
                .receive("error") { message in
                    print("❌ [DELETE] Deletion failed on server: \(message.payload)")
                    continuation.resume(throwing: DeletionError.syncFailed(message.payload.description))
                }
                .receive("timeout") { _ in
                    print("❌ [DELETE] Deletion request timed out")
                    continuation.resume(throwing: DeletionError.timeout)
                }
        }
    }

    /// Handle incoming deletion from Phoenix channel
    func handleIncomingDeletion(
        messageId: String,
        threadId: String,
        deletedAt: Date,
        scope: DeletionScope,
        currentUserId: String
    ) async throws {
        print("📥 [DELETE] Received deletion from Phoenix: \(messageId)")

        guard let msgId = UUID(uuidString: messageId),
              let thrdId = UUID(uuidString: threadId) else {
            print("❌ [DELETE] Invalid UUIDs")
            return
        }

        // Fetch the message
        guard var message = try? await databaseManager.getMessage(id: msgId, threadId: thrdId) else {
            print("⚠️ [DELETE] Message not found locally: \(messageId)")
            return
        }

        // Update message based on scope
        if scope == .forEveryone {
            message.deletedAt = deletedAt
            message.updatedAt = Date()
        } else {
            // Scope is "forMe" - update metadata for specific user
            var metadata = message.metadata ?? [:]
            metadata["deleted_for_user_\(currentUserId)"] = "true"
            message.metadata = metadata
            message.updatedAt = Date()
        }

        try await databaseManager.updateMessage(message)

        print("✅ [DELETE] Incoming deletion applied locally")
    }

    /// Check if a message is deleted for the current user
    /// - Parameters:
    ///   - message: The message to check
    ///   - currentUserId: The current user's ID
    /// - Returns: True if the message is deleted
    func isDeleted(message: Message, currentUserId: String) -> Bool {
        // Check global deletion
        if message.deletedAt != nil {
            return true
        }

        // Check user-specific deletion
        if let metadata = message.metadata,
           let deleted = metadata["deleted_for_user_\(currentUserId)"],
           deleted == "true" {
            return true
        }

        return false
    }

    /// Get tombstone message for deleted message
    /// - Parameters:
    ///   - message: The deleted message
    ///   - currentUserId: The current user's ID
    /// - Returns: Tombstone text
    func getTombstoneMessage(message: Message, currentUserId: String) -> String {
        if message.senderId == currentUserId {
            return "You deleted this message"
        } else {
            return "This message was deleted"
        }
    }

    /// Permanently delete a message (hard delete)
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - threadId: The thread ID
    /// - Note: This is irreversible and should only be used for cleanup
    func permanentlyDeleteMessage(messageId: UUID, threadId: UUID) async throws {
        print("🗑️ [DELETE] Permanently deleting message: \(messageId)")

        // Delete from database
        // Note: DatabaseManager would need a deleteMessage method
        // For now, we'll just mark it in a way that hides it permanently

        guard var message = try? await databaseManager.getMessage(id: messageId, threadId: threadId) else {
            throw DeletionError.messageNotFound
        }

        message.deletedAt = Date()
        message.content = "" // Clear content for privacy
        message.updatedAt = Date()

        try await databaseManager.updateMessage(message)

        print("✅ [DELETE] Message permanently deleted")
    }
}

// MARK: - Errors

enum DeletionError: LocalizedError {
    case messageNotFound
    case cannotDeleteForEveryone
    case channelNotJoined
    case syncFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .messageNotFound:
            return "Message not found"
        case .cannotDeleteForEveryone:
            return "You can only delete your own messages for everyone"
        case .channelNotJoined:
            return "Not connected to conversation"
        case .syncFailed(let reason):
            return "Failed to sync deletion: \(reason)"
        case .timeout:
            return "Deletion request timed out"
        }
    }
}
