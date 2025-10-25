//
//  PhoenixChannelManager+MessageEdit.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  Phoenix Channel extensions for message editing and deletion
//

import Foundation
@preconcurrency import SwiftPhoenixClient

extension PhoenixChannelManager {

    // MARK: - Message Editing

    /// Set up edit/delete message handlers for a channel
    func setupEditDeleteHandlers(
        _ channel: Channel,
        conversationId: String,
        editManager: MessageEditManager,
        deletionHandler: MessageDeletionHandler,
        currentUserId: String
    ) {
        // Handle incoming message edits
        channel.on("message_edited") { [weak self] (message: SwiftPhoenixClient.Message) in
            guard let self else { return }
            Task {
                await self.handleMessageEdit(
                    payload: message.payload,
                    conversationId: conversationId,
                    editManager: editManager
                )
            }
        }

        // Handle incoming message deletions
        channel.on("message_deleted") { [weak self] (message: SwiftPhoenixClient.Message) in
            guard let self else { return }
            Task {
                await self.handleMessageDeletion(
                    payload: message.payload,
                    conversationId: conversationId,
                    deletionHandler: deletionHandler,
                    currentUserId: currentUserId
                )
            }
        }
    }

    /// Handle incoming message edit
    private func handleMessageEdit(
        payload: [String: Any],
        conversationId: String,
        editManager: MessageEditManager
    ) async {
        guard
            let messageId = payload["message_id"] as? String,
            let newContent = payload["content"] as? String
        else {
            print("❌ [EDIT] Invalid edit payload: \(payload)")
            return
        }

        let editedAtStr = payload["edited_at"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let editedAt = ISO8601DateFormatter().date(from: editedAtStr) ?? Date()

        print("📥 [EDIT] Received edit: messageId=\(messageId), content=\(newContent)")

        do {
            try await editManager.handleIncomingEdit(
                messageId: messageId,
                threadId: conversationId,
                newContent: newContent,
                editedAt: editedAt
            )
        } catch {
            print("❌ [EDIT] Failed to handle incoming edit: \(error)")
        }
    }

    /// Handle incoming message deletion
    private func handleMessageDeletion(
        payload: [String: Any],
        conversationId: String,
        deletionHandler: MessageDeletionHandler,
        currentUserId: String
    ) async {
        guard
            let messageId = payload["message_id"] as? String
        else {
            print("❌ [DELETE] Invalid deletion payload: \(payload)")
            return
        }

        let deletedAtStr = payload["deleted_at"] as? String ?? ISO8601DateFormatter().string(from: Date())
        let deletedAt = ISO8601DateFormatter().date(from: deletedAtStr) ?? Date()

        let scopeStr = payload["scope"] as? String ?? "everyone"
        let scope: DeletionScope = scopeStr == "everyone" ? .forEveryone : .forMe

        print("📥 [DELETE] Received deletion: messageId=\(messageId), scope=\(scope)")

        do {
            try await deletionHandler.handleIncomingDeletion(
                messageId: messageId,
                threadId: conversationId,
                deletedAt: deletedAt,
                scope: scope,
                currentUserId: currentUserId
            )
        } catch {
            print("❌ [DELETE] Failed to handle incoming deletion: \(error)")
        }
    }
}
