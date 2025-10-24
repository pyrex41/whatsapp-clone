//
//  CDCManager.swift
//  GlobalBridge
//
//  Task 13: Manual CDC for client-side sync
//  Handles pull/push logic and conflict resolution
//

import Foundation
import SQLite

/// Manages Change Data Capture synchronization between client and server
@MainActor
final class CDCManager {

    // MARK: - Properties

    private let databaseManager: DatabaseManager
    private let phoenixManager: PhoenixChannelManagerProtocol
    private let deviceId: UUID
    private var lastSyncTimestamp: [String: Date] = [:] // threadId -> timestamp

    // MARK: - Initialization

    init(
        databaseManager: DatabaseManager,
        phoenixManager: PhoenixChannelManagerProtocol,
        deviceId: UUID
    ) {
        self.databaseManager = databaseManager
        self.phoenixManager = phoenixManager
        self.deviceId = deviceId
    }

    // MARK: - Task 13.2: Pull/Push Logic

    /// Pull changes from server for a specific thread
    /// - Parameter threadId: The thread to pull changes for
    /// - Returns: Array of CDC logs from server
    func pullChanges(for threadId: UUID) async throws -> [CDCLog] {
        print("📥 Pulling changes from server for thread: \(threadId)")

        // Get last sync timestamp for this thread
        let since = lastSyncTimestamp[threadId.uuidString]

        // Fetch changes from server via Phoenix
        let serverLogs = try await phoenixManager.pullCDCLogs(
            threadId: threadId.uuidString,
            since: since
        )

        print("📥 Pulled \(serverLogs.count) changes from server")

        // Update last sync timestamp
        if let latestTimestamp = serverLogs.map(\.timestamp).max() {
            lastSyncTimestamp[threadId.uuidString] = latestTimestamp
        }

        return serverLogs
    }

    /// Push local changes to server for a specific thread
    /// - Parameters:
    ///   - logs: CDC logs to push
    ///   - threadId: The thread these changes belong to
    func pushChanges(_ logs: [CDCLog], for threadId: UUID) async throws {
        guard !logs.isEmpty else {
            print("📤 No changes to push")
            return
        }

        print("📤 Pushing \(logs.count) changes to server for thread: \(threadId)")

        // Send changes to server via Phoenix
        try await phoenixManager.pushCDCLogs(logs, threadId: threadId.uuidString)

        // Mark logs as synced
        try await markLogsAsSynced(logs, threadId: threadId)

        print("✅ Successfully pushed and marked \(logs.count) changes as synced")
    }

    /// Perform bidirectional sync for a thread
    /// - Parameter threadId: The thread to sync
    func syncThread(_ threadId: UUID) async throws -> SyncSummary {
        print("🔄 Starting bidirectional sync for thread: \(threadId)")

        // Check network availability
        guard await phoenixManager.isNetworkAvailable() else {
            print("⚠️ Network unavailable, skipping sync")
            return SyncSummary(pulledCount: 0, pushedCount: 0)
        }

        // Get thread to access shard
        guard let thread = try await databaseManager.fetchThread(id: threadId) else {
            throw CDCError.threadNotFound(threadId)
        }

        // Step 1: Pull server changes
        let serverLogs = try await pullChanges(for: threadId)

        // Step 2: Apply server changes locally
        var appliedRemote = 0
        if !serverLogs.isEmpty {
            try await applyRemoteChanges(serverLogs, for: threadId)
            appliedRemote = serverLogs.count
        }

        // Step 3: Get unsynced local changes
        let localLogs = try await databaseManager.fetchUnsyncedCDCLogs(
            shardId: thread.databaseShardId
        )

        // Step 4: Push local changes to server
        var pushedLocal = 0
        if !localLogs.isEmpty {
            try await pushChanges(localLogs, for: threadId)
            pushedLocal = localLogs.count
        }

        print("✅ Bidirectional sync completed for thread: \(threadId) - Pulled: \(appliedRemote), Pushed: \(pushedLocal)")

        return SyncSummary(pulledCount: appliedRemote, pushedCount: pushedLocal)
    }

    // MARK: - Task 13.3: Conflict Resolution

    /// Apply remote changes to local database with conflict resolution
    /// - Parameters:
    ///   - remoteLogs: CDC logs from server
    ///   - threadId: The thread these changes belong to
    func applyRemoteChanges(_ remoteLogs: [CDCLog], for threadId: UUID) async throws {
        print("🔧 Applying \(remoteLogs.count) remote changes with conflict resolution")

        guard let thread = try await databaseManager.fetchThread(id: threadId) else {
            throw CDCError.threadNotFound(threadId)
        }

        for remoteLog in remoteLogs {
            do {
                // Check for local conflicts
                if let localLog = try await findLocalConflict(
                    remoteLog,
                    shardId: thread.databaseShardId
                ) {
                    // Resolve conflict using last-write-wins
                    let winner = try await resolveConflict(local: localLog, remote: remoteLog)
                    try await applyChange(winner, threadId: threadId)

                    print("⚔️ Resolved conflict for record: \(remoteLog.recordId)")
                    print("   Winner: \(winner.timestamp > localLog.timestamp ? "Remote" : "Local")")
                } else {
                    // No conflict, apply directly
                    try await applyChange(remoteLog, threadId: threadId)
                }
            } catch {
                print("❌ Failed to apply remote change: \(error)")
                // Continue with other changes
            }
        }

        print("✅ Applied remote changes successfully")
    }

    /// Resolve conflict between local and remote changes using last-write-wins
    /// - Parameters:
    ///   - local: Local CDC log
    ///   - remote: Remote CDC log
    /// - Returns: The winning CDC log (most recent)
    func resolveConflict(local: CDCLog, remote: CDCLog) async throws -> CDCLog {
        // Last-write-wins: Compare timestamps
        let winner = local.timestamp > remote.timestamp ? local : remote

        print("🏆 Conflict resolution:")
        print("   Local timestamp:  \(local.timestamp)")
        print("   Remote timestamp: \(remote.timestamp)")
        print("   Winner: \(winner.timestamp == local.timestamp ? "Local" : "Remote")")

        return winner
    }

    // MARK: - Private Helpers

    /// Find local CDC log that conflicts with remote log
    private func findLocalConflict(_ remoteLog: CDCLog, shardId: String) async throws -> CDCLog? {
        let localLogs = try await databaseManager.fetchUnsyncedCDCLogs(shardId: shardId)

        // Look for log affecting the same record
        return localLogs.first { log in
            log.tableName == remoteLog.tableName &&
            log.recordId == remoteLog.recordId
        }
    }

    /// Apply a CDC change to the local database
    private func applyChange(_ log: CDCLog, threadId: UUID) async throws {
        switch log.operation {
        case .insert:
            try await applyInsert(log, threadId: threadId)
        case .update:
            try await applyUpdate(log, threadId: threadId)
        case .delete:
            try await applyDelete(log, threadId: threadId)
        }
    }

    private func applyInsert(_ log: CDCLog, threadId: UUID) async throws {
        guard log.tableName == "messages" else {
            print("⚠️ Unsupported table for insert: \(log.tableName)")
            return
        }

        // Parse message from CDC log data
        guard let message = try? parseMessage(from: log.newData, threadId: threadId) else {
            throw CDCError.invalidMessageData(log.id)
        }

        // Check if message already exists
        let existingMessages = try await databaseManager.fetchMessages(threadId: threadId)
        if existingMessages.contains(where: { $0.id == message.id }) {
            print("⚠️ Message already exists, skipping insert: \(message.id)")
            return
        }

        try await databaseManager.createMessage(message)
    }

    private func applyUpdate(_ log: CDCLog, threadId: UUID) async throws {
        guard log.tableName == "messages" else {
            print("⚠️ Unsupported table for update: \(log.tableName)")
            return
        }

        // Parse updated message from CDC log data
        guard let message = try? parseMessage(from: log.newData, threadId: threadId) else {
            throw CDCError.invalidMessageData(log.id)
        }

        try await databaseManager.updateMessage(message)
    }

    private func applyDelete(_ log: CDCLog, threadId: UUID) async throws {
        guard log.tableName == "messages" else {
            print("⚠️ Unsupported table for delete: \(log.tableName)")
            return
        }

        try await databaseManager.deleteMessage(id: log.recordId, threadId: threadId)
    }

    /// Mark CDC logs as synced in the database
    private func markLogsAsSynced(_ logs: [CDCLog], threadId: UUID) async throws {
        guard let thread = try await databaseManager.fetchThread(id: threadId) else {
            throw CDCError.threadNotFound(threadId)
        }

        for log in logs {
            try await databaseManager.markCDCLogAsSynced(
                logId: log.id,
                shardId: thread.databaseShardId
            )
        }
    }

    /// Parse a Message from CDC log data
    private func parseMessage(from data: [String: String], threadId: UUID) throws -> Message {
        guard let idStr = data["id"],
              let id = UUID(uuidString: idStr),
              let senderId = data["sender_id"],  // Changed: now a String, not UUID
              let content = data["content"],
              let messageTypeStr = data["message_type"],
              let messageType = Message.MessageType(rawValue: messageTypeStr),
              let statusStr = data["status"],
              let status = Message.Status(rawValue: statusStr) else {
            throw CDCError.invalidMessageData("unknown")  // Pass string since we don't have ID yet
        }

        // Parse optional fields
        let replyToId = data["reply_to_id"].flatMap { UUID(uuidString: $0) }
        let editedAt = data["edited_at"].flatMap { ISO8601DateFormatter().date(from: $0) }
        let deletedAt = data["deleted_at"].flatMap { ISO8601DateFormatter().date(from: $0) }

        // Parse required date fields
        guard let createdAtStr = data["created_at"],
              let createdAt = ISO8601DateFormatter().date(from: createdAtStr) else {
            throw CDCError.invalidMessageData(idStr)  // Pass the string ID
        }

        let updatedAt = data["updated_at"]
            .flatMap { ISO8601DateFormatter().date(from: $0) } ?? createdAt

        return Message(
            id: id,
            threadId: threadId,
            senderId: senderId,
            content: content,
            messageType: messageType,
            status: status,
            metadata: nil,
            replyToId: replyToId,
            editedAt: editedAt,
            deletedAt: deletedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Protocol for Phoenix Manager

/// Protocol for Phoenix Channel Manager to enable testing
protocol PhoenixChannelManagerProtocol: Sendable {
    func pullCDCLogs(threadId: String, since: Date?) async throws -> [CDCLog]
    func pushCDCLogs(_ logs: [CDCLog], threadId: String) async throws
    func isNetworkAvailable() async -> Bool
}

// MARK: - Error Types

enum CDCError: Error, LocalizedError {
    case threadNotFound(UUID)
    case invalidMessageData(String)  // Changed to String - CDC log IDs are MD5 hashes
    case syncFailed(String)
    case conflictResolutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .threadNotFound(let id):
            return "Thread not found: \(id)"
        case .invalidMessageData(let id):
            return "Invalid message data in CDC log: \(id)"
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .conflictResolutionFailed(let reason):
            return "Conflict resolution failed: \(reason)"
        }
    }
}

// MARK: - Protocol Conformance

protocol CDCManaging: Sendable {
    func syncThread(_ threadId: UUID) async throws -> SyncSummary
}

extension CDCManager: CDCManaging {}
