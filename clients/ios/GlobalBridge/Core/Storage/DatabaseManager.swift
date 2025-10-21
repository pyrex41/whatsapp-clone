//
//  DatabaseManager.swift
//  GlobalBridge
//
//  Created by DatabaseManager on 10/20/25.
//  Task 9: Implement DatabaseManager for local SQLite operations
//

import Foundation
import SQLite

/// Main database manager with per-thread sharding support
@MainActor
final class DatabaseManager {

    // MARK: - Singleton
    static let shared = DatabaseManager()

    // MARK: - Properties
    private var mainConnection: Connection?
    private var threadConnections: [String: Connection] = [:]
    private let fileManager = FileManager.default
    private let databaseQueue = DispatchQueue(label: "com.globalbridge.database", qos: .userInitiated)

    // Database paths
    private lazy var documentsDirectory: URL = {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    private lazy var databasesDirectory: URL = {
        let url = documentsDirectory.appendingPathComponent("Databases", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private lazy var mainDatabasePath: String = {
        databasesDirectory.appendingPathComponent("globalbridge_main.db").path
    }()

    // MARK: - Table Definitions (Main Database)

    // Threads table
    private let threadsTable = Table("threads")
    private let threadId = Expression<String>("id")
    private let threadType = Expression<String>("thread_type")
    private let threadTitle = Expression<String?>("title")
    private let threadAvatarUrl = Expression<String?>("avatar_url")
    private let threadLastMessageAt = Expression<Date?>("last_message_at")
    private let threadIsArchived = Expression<Bool>("is_archived")
    private let threadIsMuted = Expression<Bool>("is_muted")
    private let threadDatabaseShardId = Expression<String>("database_shard_id")
    private let threadCreatedAt = Expression<Date>("created_at")
    private let threadUpdatedAt = Expression<Date>("updated_at")

    // Thread participants table
    private let participantsTable = Table("thread_participants")
    private let participantId = Expression<String>("id")
    private let participantThreadId = Expression<String>("thread_id")
    private let participantUserId = Expression<String>("user_id")
    private let participantRole = Expression<String>("role")
    private let participantJoinedAt = Expression<Date>("joined_at")
    private let participantLeftAt = Expression<Date?>("left_at")
    private let participantIsActive = Expression<Bool>("is_active")
    private let participantCreatedAt = Expression<Date>("created_at")
    private let participantUpdatedAt = Expression<Date>("updated_at")

    // MARK: - Per-Thread Table Definitions

    // Messages table (per-thread shard)
    private let messagesTable = Table("messages")
    private let messageId = Expression<String>("id")
    private let messageThreadId = Expression<String>("thread_id")
    private let messageSenderId = Expression<String>("sender_id")
    private let messageContent = Expression<String>("content")
    private let messageType = Expression<String>("message_type")
    private let messageStatus = Expression<String>("status")
    private let messageMetadata = Expression<String?>("metadata")
    private let messageReplyToId = Expression<String?>("reply_to_id")
    private let messageEditedAt = Expression<Date?>("edited_at")
    private let messageDeletedAt = Expression<Date?>("deleted_at")
    private let messageCreatedAt = Expression<Date>("created_at")
    private let messageUpdatedAt = Expression<Date>("updated_at")

    // CDC logs table (per-thread shard)
    private let cdcLogsTable = Table("cdc_logs")
    private let cdcId = Expression<String>("id")
    private let cdcTableName = Expression<String>("table_name")
    private let cdcRecordId = Expression<String>("record_id")
    private let cdcOperation = Expression<String>("operation")
    private let cdcOldData = Expression<String?>("old_data")
    private let cdcNewData = Expression<String>("new_data")
    private let cdcChangedFields = Expression<String?>("changed_fields")
    private let cdcUserId = Expression<String?>("user_id")
    private let cdcDeviceId = Expression<String?>("device_id")
    private let cdcTimestamp = Expression<Date>("timestamp")
    private let cdcCreatedAt = Expression<Date>("created_at")

    // Sync states table (per-thread shard)
    private let syncStatesTable = Table("sync_states")
    private let syncId = Expression<String>("id")
    private let syncDeviceId = Expression<String>("device_id")
    private let syncThreadId = Expression<String?>("thread_id")
    private let syncEntityType = Expression<String>("entity_type")
    private let syncEntityId = Expression<String>("entity_id")
    private let syncOperation = Expression<String>("operation")
    private let syncLastSyncAt = Expression<Date?>("last_sync_at")
    private let syncCursor = Expression<Int?>("sync_cursor")
    private let syncIsSynced = Expression<Bool>("is_synced")
    private let syncCreatedAt = Expression<Date>("created_at")
    private let syncUpdatedAt = Expression<Date>("updated_at")

    // MARK: - Initialization

    private init() {}

    /// Initialize the database system
    func initialize() async throws {
        print("🗄️ Initializing DatabaseManager...")

        do {
            // Initialize main database
            try await initializeMainDatabase()
            print("✅ DatabaseManager initialized successfully")
        } catch {
            print("❌ DatabaseManager initialization failed: \(error)")
            throw DatabaseError.initializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Main Database Setup

    private func initializeMainDatabase() async throws {
        do {
            mainConnection = try Connection(mainDatabasePath)
            mainConnection?.busyTimeout = 5.0

            // Enable WAL mode for better concurrency
            try mainConnection?.execute("PRAGMA journal_mode=WAL")
            try mainConnection?.execute("PRAGMA foreign_keys=ON")

            // Create main tables
            try await createMainTables()

            print("✅ Main database initialized at: \(mainDatabasePath)")
        } catch {
            throw DatabaseError.connectionFailed("Main database: \(error.localizedDescription)")
        }
    }

    private func createMainTables() async throws {
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        // Create threads table
        try db.run(threadsTable.create(ifNotExists: true) { t in
            t.column(threadId, primaryKey: true)
            t.column(threadType)
            t.column(threadTitle)
            t.column(threadAvatarUrl)
            t.column(threadLastMessageAt)
            t.column(threadIsArchived, defaultValue: false)
            t.column(threadIsMuted, defaultValue: false)
            t.column(threadDatabaseShardId, unique: true)
            t.column(threadCreatedAt, defaultValue: Date())
            t.column(threadUpdatedAt, defaultValue: Date())
        })

        // Create indexes for threads
        try db.run(threadsTable.createIndex(threadType, ifNotExists: true))
        try db.run(threadsTable.createIndex(threadLastMessageAt, ifNotExists: true))
        try db.run(threadsTable.createIndex(threadDatabaseShardId, unique: true, ifNotExists: true))

        // Create thread_participants table
        try db.run(participantsTable.create(ifNotExists: true) { t in
            t.column(participantId, primaryKey: true)
            t.column(participantThreadId)
            t.column(participantUserId)
            t.column(participantRole, defaultValue: "member")
            t.column(participantJoinedAt, defaultValue: Date())
            t.column(participantLeftAt)
            t.column(participantIsActive, defaultValue: true)
            t.column(participantCreatedAt, defaultValue: Date())
            t.column(participantUpdatedAt, defaultValue: Date())
        })

        // Create indexes for participants
        try db.run(participantsTable.createIndex([participantThreadId, participantUserId], unique: true, ifNotExists: true))
        try db.run(participantsTable.createIndex(participantUserId, ifNotExists: true))
        try db.run(participantsTable.createIndex(participantIsActive, ifNotExists: true))

        print("✅ Main tables created successfully")
    }

    // MARK: - Per-Thread Database Sharding

    /// Get or create a per-thread database connection
    private func getThreadDatabase(shardId: String) async throws -> Connection {
        // Check if connection already exists
        if let existing = threadConnections[shardId] {
            return existing
        }

        // Create new thread-specific database
        let threadDbPath = databasesDirectory
            .appendingPathComponent("thread_\(shardId).db")
            .path

        do {
            let connection = try Connection(threadDbPath)
            connection.busyTimeout = 5.0

            // Enable WAL mode for better concurrency
            try connection.execute("PRAGMA journal_mode=WAL")
            try connection.execute("PRAGMA foreign_keys=ON")

            // Create per-thread tables
            try await createThreadTables(in: connection)

            // Cache the connection
            threadConnections[shardId] = connection

            print("✅ Thread database created for shard: \(shardId)")
            return connection
        } catch {
            throw DatabaseError.shardingFailed("Failed to create thread database: \(error.localizedDescription)")
        }
    }

    private func createThreadTables(in connection: Connection) async throws {
        // Create messages table
        try connection.run(messagesTable.create(ifNotExists: true) { t in
            t.column(messageId, primaryKey: true)
            t.column(messageThreadId)
            t.column(messageSenderId)
            t.column(messageContent)
            t.column(messageType, defaultValue: "text")
            t.column(messageStatus, defaultValue: "pending")
            t.column(messageMetadata)
            t.column(messageReplyToId)
            t.column(messageEditedAt)
            t.column(messageDeletedAt)
            t.column(messageCreatedAt, defaultValue: Date())
            t.column(messageUpdatedAt, defaultValue: Date())
        })

        // Create indexes for messages
        try connection.run(messagesTable.createIndex(messageThreadId, ifNotExists: true))
        try connection.run(messagesTable.createIndex(messageSenderId, ifNotExists: true))
        try connection.run(messagesTable.createIndex(messageCreatedAt, ifNotExists: true))
        try connection.run(messagesTable.createIndex(messageStatus, ifNotExists: true))

        // Create CDC logs table
        try connection.run(cdcLogsTable.create(ifNotExists: true) { t in
            t.column(cdcId, primaryKey: true)
            t.column(cdcTableName)
            t.column(cdcRecordId)
            t.column(cdcOperation)
            t.column(cdcOldData)
            t.column(cdcNewData)
            t.column(cdcChangedFields)
            t.column(cdcUserId)
            t.column(cdcDeviceId)
            t.column(cdcTimestamp, defaultValue: Date())
            t.column(cdcCreatedAt, defaultValue: Date())
        })

        // Create indexes for CDC logs
        try connection.run(cdcLogsTable.createIndex([cdcTableName, cdcRecordId], ifNotExists: true))
        try connection.run(cdcLogsTable.createIndex(cdcTimestamp, ifNotExists: true))

        // Create sync_states table
        try connection.run(syncStatesTable.create(ifNotExists: true) { t in
            t.column(syncId, primaryKey: true)
            t.column(syncDeviceId)
            t.column(syncThreadId)
            t.column(syncEntityType)
            t.column(syncEntityId)
            t.column(syncOperation)
            t.column(syncLastSyncAt)
            t.column(syncCursor)
            t.column(syncIsSynced, defaultValue: false)
            t.column(syncCreatedAt, defaultValue: Date())
            t.column(syncUpdatedAt, defaultValue: Date())
        })

        // Create indexes for sync states
        try connection.run(syncStatesTable.createIndex(syncDeviceId, ifNotExists: true))
        try connection.run(syncStatesTable.createIndex(syncThreadId, ifNotExists: true))
        try connection.run(syncStatesTable.createIndex([syncEntityType, syncEntityId], ifNotExists: true))
        try connection.run(syncStatesTable.createIndex(syncIsSynced, ifNotExists: true))

        print("✅ Thread-specific tables created")
    }

    // MARK: - Thread Operations

    /// Create a new thread
    func createThread(_ thread: Thread) async throws {
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        do {
            let insert = threadsTable.insert(
                threadId <- thread.id.uuidString,
                threadType <- thread.threadType.rawValue,
                threadTitle <- thread.title,
                threadAvatarUrl <- thread.avatarUrl,
                threadLastMessageAt <- thread.lastMessageAt,
                threadIsArchived <- thread.isArchived,
                threadIsMuted <- thread.isMuted,
                threadDatabaseShardId <- thread.databaseShardId,
                threadCreatedAt <- thread.createdAt,
                threadUpdatedAt <- thread.updatedAt
            )

            try db.run(insert)

            // Initialize thread-specific database
            _ = try await getThreadDatabase(shardId: thread.databaseShardId)

            // Log CDC event
            try await logCDCEvent(
                shardId: thread.databaseShardId,
                tableName: "threads",
                recordId: thread.id,
                operation: .insert,
                newData: threadToDictionary(thread)
            )

            print("✅ Thread created: \(thread.id)")
        } catch {
            throw DatabaseError.insertFailed("Thread: \(error.localizedDescription)")
        }
    }

    /// Fetch all threads
    func fetchThreads() async throws -> [Thread] {
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        do {
            var threads: [Thread] = []

            for row in try db.prepare(threadsTable.order(threadLastMessageAt.desc)) {
                let thread = Thread(
                    id: UUID(uuidString: row[threadId])!,
                    threadType: Thread.ThreadType(rawValue: row[threadType])!,
                    title: row[threadTitle],
                    avatarUrl: row[threadAvatarUrl],
                    lastMessageAt: row[threadLastMessageAt],
                    isArchived: row[threadIsArchived],
                    isMuted: row[threadIsMuted],
                    databaseShardId: row[threadDatabaseShardId],
                    createdAt: row[threadCreatedAt],
                    updatedAt: row[threadUpdatedAt]
                )
                threads.append(thread)
            }

            return threads
        } catch {
            throw DatabaseError.queryFailed("Threads: \(error.localizedDescription)")
        }
    }

    /// Update a thread
    func updateThread(_ thread: Thread) async throws {
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        do {
            let threadRow = threadsTable.filter(threadId == thread.id.uuidString)
            let update = threadRow.update(
                threadTitle <- thread.title,
                threadAvatarUrl <- thread.avatarUrl,
                threadLastMessageAt <- thread.lastMessageAt,
                threadIsArchived <- thread.isArchived,
                threadIsMuted <- thread.isMuted,
                threadUpdatedAt <- Date()
            )

            let changes = try db.run(update)

            if changes == 0 {
                throw DatabaseError.notFound("Thread: \(thread.id)")
            }

            // Log CDC event
            try await logCDCEvent(
                shardId: thread.databaseShardId,
                tableName: "threads",
                recordId: thread.id,
                operation: .update,
                newData: threadToDictionary(thread)
            )

            print("✅ Thread updated: \(thread.id)")
        } catch {
            throw DatabaseError.updateFailed("Thread: \(error.localizedDescription)")
        }
    }

    /// Delete a thread
    func deleteThread(id: UUID) async throws {
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        do {
            // Fetch thread to get shard ID
            let threadRow = threadsTable.filter(threadId == id.uuidString)
            guard let row = try db.pluck(threadRow) else {
                throw DatabaseError.notFound("Thread: \(id)")
            }

            let shardId = row[threadDatabaseShardId]

            // Delete thread record
            try db.run(threadRow.delete())

            // Clean up thread-specific database
            threadConnections.removeValue(forKey: shardId)

            let threadDbPath = databasesDirectory
                .appendingPathComponent("thread_\(shardId).db")
                .path
            try? fileManager.removeItem(atPath: threadDbPath)
            try? fileManager.removeItem(atPath: "\(threadDbPath)-shm")
            try? fileManager.removeItem(atPath: "\(threadDbPath)-wal")

            print("✅ Thread deleted: \(id)")
        } catch {
            throw DatabaseError.deleteFailed("Thread: \(error.localizedDescription)")
        }
    }

    // MARK: - Message Operations (Per-Thread Sharded)

    /// Create a message in thread-specific database
    func createMessage(_ message: Message) async throws {
        // Get thread to determine shard
        guard let thread = try await fetchThread(id: message.threadId) else {
            throw DatabaseError.notFound("Thread: \(message.threadId)")
        }

        let db = try await getThreadDatabase(shardId: thread.databaseShardId)

        do {
            let metadataJson = message.metadata.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }

            let insert = messagesTable.insert(
                messageId <- message.id.uuidString,
                messageThreadId <- message.threadId.uuidString,
                messageSenderId <- message.senderId.uuidString,
                messageContent <- message.content,
                messageType <- message.messageType.rawValue,
                messageStatus <- message.status.rawValue,
                messageMetadata <- metadataJson,
                messageReplyToId <- message.replyToId?.uuidString,
                messageEditedAt <- message.editedAt,
                messageDeletedAt <- message.deletedAt,
                messageCreatedAt <- message.createdAt,
                messageUpdatedAt <- message.updatedAt
            )

            try db.run(insert)

            // Update thread's last_message_at
            try await updateThreadLastMessage(threadId: message.threadId, timestamp: message.createdAt)

            // Log CDC event
            try await logCDCEvent(
                shardId: thread.databaseShardId,
                tableName: "messages",
                recordId: message.id,
                operation: .insert,
                newData: messageToDictionary(message)
            )

            print("✅ Message created: \(message.id) in thread: \(message.threadId)")
        } catch {
            throw DatabaseError.insertFailed("Message: \(error.localizedDescription)")
        }
    }

    /// Fetch messages for a thread
    func fetchMessages(threadId: UUID, limit: Int = 50, offset: Int = 0) async throws -> [Message] {
        guard let thread = try await fetchThread(id: threadId) else {
            throw DatabaseError.notFound("Thread: \(threadId)")
        }

        let db = try await getThreadDatabase(shardId: thread.databaseShardId)

        do {
            var messages: [Message] = []

            let query = messagesTable
                .filter(messageThreadId == threadId.uuidString)
                .order(messageCreatedAt.desc)
                .limit(limit, offset: offset)

            for row in try db.prepare(query) {
                var metadata: [String: String]? = nil
                if let metadataStr = row[messageMetadata],
                   let data = metadataStr.data(using: .utf8) {
                    metadata = try? JSONDecoder().decode([String: String].self, from: data)
                }

                let message = Message(
                    id: UUID(uuidString: row[messageId])!,
                    threadId: UUID(uuidString: row[messageThreadId])!,
                    senderId: UUID(uuidString: row[messageSenderId])!,
                    content: row[messageContent],
                    messageType: Message.MessageType(rawValue: row[messageType])!,
                    status: Message.Status(rawValue: row[messageStatus])!,
                    metadata: metadata,
                    replyToId: row[messageReplyToId].flatMap { UUID(uuidString: $0) },
                    editedAt: row[messageEditedAt],
                    deletedAt: row[messageDeletedAt],
                    createdAt: row[messageCreatedAt],
                    updatedAt: row[messageUpdatedAt]
                )
                messages.append(message)
            }

            return messages
        } catch {
            throw DatabaseError.queryFailed("Messages: \(error.localizedDescription)")
        }
    }

    // MARK: - CDC Operations

    /// Log a change data capture event
    private func logCDCEvent(
        shardId: String,
        tableName: String,
        recordId: UUID,
        operation: CDCLog.CDCOperation,
        oldData: [String: String]? = nil,
        newData: [String: String],
        userId: UUID? = nil,
        deviceId: UUID? = nil
    ) async throws {
        let db = try await getThreadDatabase(shardId: shardId)

        do {
            let oldDataJson = oldData.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }

            let newDataJson = try JSONEncoder().encode(newData)
            let newDataStr = String(data: newDataJson, encoding: .utf8)!

            let changedFields = oldData != nil ? Array(newData.keys.filter { newData[$0] != oldData?[$0] }) : nil
            let changedFieldsJson = changedFields.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }

            let insert = cdcLogsTable.insert(
                cdcId <- UUID().uuidString,
                cdcTableName <- tableName,
                cdcRecordId <- recordId.uuidString,
                cdcOperation <- operation.rawValue,
                cdcOldData <- oldDataJson,
                cdcNewData <- newDataStr,
                cdcChangedFields <- changedFieldsJson,
                cdcUserId <- userId?.uuidString,
                cdcDeviceId <- deviceId?.uuidString,
                cdcTimestamp <- Date(),
                cdcCreatedAt <- Date()
            )

            try db.run(insert)
            print("✅ CDC event logged: \(operation.rawValue) on \(tableName)")
        } catch {
            print("⚠️ Failed to log CDC event: \(error)")
            // Don't throw - CDC logging is non-critical
        }
    }

    /// Fetch unsynced CDC logs
    func fetchUnsyncedCDCLogs(shardId: String, limit: Int = 100) async throws -> [CDCLog] {
        let db = try await getThreadDatabase(shardId: shardId)

        do {
            var logs: [CDCLog] = []

            let query = cdcLogsTable
                .order(cdcTimestamp.asc)
                .limit(limit)

            for row in try db.prepare(query) {
                var oldData: [String: String]? = nil
                if let oldDataStr = row[cdcOldData],
                   let data = oldDataStr.data(using: .utf8) {
                    oldData = try? JSONDecoder().decode([String: String].self, from: data)
                }

                let newDataStr = row[cdcNewData]
                let newData = try JSONDecoder().decode(
                    [String: String].self,
                    from: newDataStr.data(using: .utf8)!
                )

                var changedFields: [String]? = nil
                if let fieldsStr = row[cdcChangedFields],
                   let data = fieldsStr.data(using: .utf8) {
                    changedFields = try? JSONDecoder().decode([String].self, from: data)
                }

                let log = CDCLog(
                    id: UUID(uuidString: row[cdcId])!,
                    tableName: row[cdcTableName],
                    recordId: UUID(uuidString: row[cdcRecordId])!,
                    operation: CDCLog.CDCOperation(rawValue: row[cdcOperation])!,
                    oldData: oldData,
                    newData: newData,
                    changedFields: changedFields,
                    userId: row[cdcUserId].flatMap { UUID(uuidString: $0) },
                    deviceId: row[cdcDeviceId].flatMap { UUID(uuidString: $0) },
                    timestamp: row[cdcTimestamp],
                    createdAt: row[cdcCreatedAt]
                )
                logs.append(log)
            }

            return logs
        } catch {
            throw DatabaseError.queryFailed("CDC logs: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    private func fetchThread(id: UUID) async throws -> Thread? {
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        let query = threadsTable.filter(threadId == id.uuidString)

        guard let row = try db.pluck(query) else {
            return nil
        }

        return Thread(
            id: UUID(uuidString: row[threadId])!,
            threadType: Thread.ThreadType(rawValue: row[threadType])!,
            title: row[threadTitle],
            avatarUrl: row[threadAvatarUrl],
            lastMessageAt: row[threadLastMessageAt],
            isArchived: row[threadIsArchived],
            isMuted: row[threadIsMuted],
            databaseShardId: row[threadDatabaseShardId],
            createdAt: row[threadCreatedAt],
            updatedAt: row[threadUpdatedAt]
        )
    }

    private func updateThreadLastMessage(threadId: UUID, timestamp: Date) async throws {
        guard let db = mainConnection else { return }

        let threadRow = threadsTable.filter(self.threadId == threadId.uuidString)
        try db.run(threadRow.update(
            threadLastMessageAt <- timestamp,
            threadUpdatedAt <- Date()
        ))
    }

    // MARK: - Serialization Helpers

    private func threadToDictionary(_ thread: Thread) -> [String: String] {
        var dict: [String: String] = [
            "id": thread.id.uuidString,
            "thread_type": thread.threadType.rawValue,
            "is_archived": String(thread.isArchived),
            "is_muted": String(thread.isMuted),
            "database_shard_id": thread.databaseShardId,
            "created_at": ISO8601DateFormatter().string(from: thread.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: thread.updatedAt)
        ]

        if let title = thread.title { dict["title"] = title }
        if let avatarUrl = thread.avatarUrl { dict["avatar_url"] = avatarUrl }
        if let lastMessageAt = thread.lastMessageAt {
            dict["last_message_at"] = ISO8601DateFormatter().string(from: lastMessageAt)
        }

        return dict
    }

    private func messageToDictionary(_ message: Message) -> [String: String] {
        var dict: [String: String] = [
            "id": message.id.uuidString,
            "thread_id": message.threadId.uuidString,
            "sender_id": message.senderId.uuidString,
            "content": message.content,
            "message_type": message.messageType.rawValue,
            "status": message.status.rawValue,
            "created_at": ISO8601DateFormatter().string(from: message.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: message.updatedAt)
        ]

        if let replyToId = message.replyToId { dict["reply_to_id"] = replyToId.uuidString }
        if let editedAt = message.editedAt {
            dict["edited_at"] = ISO8601DateFormatter().string(from: editedAt)
        }
        if let deletedAt = message.deletedAt {
            dict["deleted_at"] = ISO8601DateFormatter().string(from: deletedAt)
        }

        return dict
    }

    // MARK: - Cleanup

    /// Close all database connections
    func closeAllConnections() {
        threadConnections.removeAll()
        mainConnection = nil
        print("✅ All database connections closed")
    }

    deinit {
        closeAllConnections()
    }
}
