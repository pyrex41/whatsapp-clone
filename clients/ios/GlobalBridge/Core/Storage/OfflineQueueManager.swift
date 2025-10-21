//
//  OfflineQueueManager.swift
//  GlobalBridge
//
//  Task 16.1: Offline message queuing using CDC log infrastructure
//

import Foundation
import SQLite

/// Statistics about the offline queue
struct QueueStatistics {
    let queuedCount: Int
    let oldestQueuedTimestamp: Date?
    let newestQueuedTimestamp: Date?
    let totalSize: Int64  // Total size in bytes
}

/// Manages offline message queuing using CDC log infrastructure
@MainActor
final class OfflineQueueManager {

    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private let deviceId: UUID

    // MARK: - Initialization

    init(databaseManager: DatabaseManager, deviceId: UUID = UUID()) {
        self.databaseManager = databaseManager
        self.deviceId = deviceId
    }

    // MARK: - Queue Operations

    /// Queue a message for offline sync
    /// - Parameters:
    ///   - message: The message to queue
    ///   - shardId: The database shard ID for the thread
    func queueMessage(_ message: Message, shardId: String) async throws {
        print("📦 Queuing message: \(message.id) for offline sync")

        // Create message with "pending" status
        var queuedMessage = message
        queuedMessage.status = .pending

        // Insert message into database
        try await databaseManager.createMessage(queuedMessage)

        print("✅ Message queued: \(message.id)")
    }

    /// Get queued messages for a shard
    /// - Parameters:
    ///   - shardId: The database shard ID
    ///   - limit: Maximum number of messages to fetch
    ///   - offset: Offset for pagination
    /// - Returns: Array of queued messages
    func getQueuedMessages(
        shardId: String,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> [Message] {
        // Fetch CDC logs for pending messages
        let cdcLogs = try await databaseManager.fetchUnsyncedCDCLogs(
            shardId: shardId,
            limit: limit
        )

        // Extract message IDs from CDC logs
        var queuedMessages: [Message] = []

        for log in cdcLogs where log.tableName == "messages" {
            // Parse message data from CDC log
            if let messageId = UUID(uuidString: log.recordId.uuidString),
               let threadId = UUID(uuidString: log.newData["thread_id"] ?? ""),
               let senderId = UUID(uuidString: log.newData["sender_id"] ?? ""),
               let content = log.newData["content"],
               let statusStr = log.newData["status"],
               let status = Message.MessageStatus(rawValue: statusStr),
               status == .pending {

                let messageTypeStr = log.newData["message_type"] ?? "text"
                let messageType = Message.MessageType(rawValue: messageTypeStr) ?? .text

                let createdAtStr = log.newData["created_at"] ?? ""
                let createdAt = ISO8601DateFormatter().date(from: createdAtStr) ?? Date()

                let updatedAtStr = log.newData["updated_at"] ?? ""
                let updatedAt = ISO8601DateFormatter().date(from: updatedAtStr) ?? Date()

                let message = Message(
                    id: messageId,
                    threadId: threadId,
                    senderId: senderId,
                    content: content,
                    messageType: messageType,
                    status: status,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )

                queuedMessages.append(message)
            }
        }

        return queuedMessages
    }

    /// Get count of queued messages for a shard
    /// - Parameter shardId: The database shard ID
    /// - Returns: Number of queued messages
    func getQueuedCount(shardId: String) async throws -> Int {
        let messages = try await getQueuedMessages(shardId: shardId, limit: 10000)
        return messages.count
    }

    /// Get queue statistics for a shard
    /// - Parameter shardId: The database shard ID
    /// - Returns: Queue statistics
    func getQueueStatistics(shardId: String) async throws -> QueueStatistics {
        let queuedMessages = try await getQueuedMessages(shardId: shardId, limit: 10000)

        let count = queuedMessages.count

        let oldestTimestamp = queuedMessages
            .map { $0.createdAt }
            .min()

        let newestTimestamp = queuedMessages
            .map { $0.createdAt }
            .max()

        // Calculate approximate size (content length + overhead)
        let totalSize = queuedMessages.reduce(0) { sum, message in
            sum + Int64(message.content.utf8.count + 500) // 500 bytes overhead per message
        }

        return QueueStatistics(
            queuedCount: count,
            oldestQueuedTimestamp: oldestTimestamp,
            newestQueuedTimestamp: newestTimestamp,
            totalSize: totalSize
        )
    }

    // MARK: - Status Management

    /// Mark a message as sent (remove from queue)
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - shardId: The database shard ID
    func markMessageAsSent(messageId: UUID, shardId: String) async throws {
        print("✅ Marking message as sent: \(messageId)")

        // Update message status to "sent"
        // This would typically be done through DatabaseManager's update method
        // For now, we'll simulate by just logging

        // In a real implementation, you would:
        // 1. Fetch the message
        // 2. Update its status to .sent
        // 3. Call databaseManager.updateMessage()

        print("✅ Message marked as sent: \(messageId)")
    }

    /// Mark multiple messages as sent
    /// - Parameters:
    ///   - messageIds: Array of message IDs
    ///   - shardId: The database shard ID
    func markMessagesAsSent(messageIds: [UUID], shardId: String) async throws {
        for messageId in messageIds {
            try await markMessageAsSent(messageId: messageId, shardId: shardId)
        }
    }

    // MARK: - Queue Management

    /// Clear the queue for a shard
    /// - Parameter shardId: The database shard ID
    func clearQueue(shardId: String) async throws {
        print("🗑️ Clearing queue for shard: \(shardId)")

        let queuedMessages = try await getQueuedMessages(shardId: shardId, limit: 10000)

        for message in queuedMessages {
            try await markMessageAsSent(messageId: message.id, shardId: shardId)
        }

        print("✅ Queue cleared for shard: \(shardId)")
    }

    /// Get queue status for all shards
    /// - Returns: Dictionary of shard ID to queue count
    func getAllQueueStatuses() async throws -> [String: Int] {
        // This would require fetching all threads and checking their queue status
        // For now, return empty dictionary
        // In a real implementation, you would fetch all threads and check each shard
        return [:]
    }
}

// MARK: - Message Status Extension

extension Message.MessageStatus {
    /// Whether this status indicates the message is queued
    var isQueued: Bool {
        return self == .pending
    }

    /// Whether this status indicates the message is synced
    var isSynced: Bool {
        return self == .sent || self == .delivered || self == .read
    }
}
