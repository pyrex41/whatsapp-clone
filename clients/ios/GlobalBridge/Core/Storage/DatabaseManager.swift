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

    // Contacts table
    private let contactsTable = Table("contacts")
    private let contactId = Expression<String>("id")
    private let contactUserId = Expression<String>("contact_user_id")
    private let contactDisplayNameOverride = Expression<String?>("display_name_override")
    private let contactIsFavorite = Expression<Bool>("is_favorite")
    private let contactNotes = Expression<String?>("notes")
    private let contactUserEmail = Expression<String>("user_email")
    private let contactUserUsername = Expression<String?>("user_username")
    private let contactUserDisplayName = Expression<String?>("user_display_name")
    private let contactUserAvatarUrl = Expression<String?>("user_avatar_url")
    private let contactCreatedAt = Expression<Date>("created_at")
    private let contactUpdatedAt = Expression<Date>("updated_at")
    private let contactLastSyncedAt = Expression<Date?>("last_synced_at")
    private let contactNeedsSync = Expression<Bool>("needs_sync")
    private let contactIsDeleted = Expression<Bool>("is_deleted")

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
    private let messageClientMessageId = Expression<String?>("client_message_id")  // For deduplication
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
            try await ensureMainConnection()
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

    private func ensureMainConnection() async throws {
        if mainConnection == nil {
            try await initializeMainDatabase()
        }
    }

    private func createMainTables() async throws {
        try await ensureMainConnection()
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
        try db.run(participantsTable.createIndex(participantThreadId, participantUserId, unique: true, ifNotExists: true))
        try db.run(participantsTable.createIndex(participantUserId, ifNotExists: true))
        try db.run(participantsTable.createIndex(participantIsActive, ifNotExists: true))

        // Create contacts table
        try db.run(contactsTable.create(ifNotExists: true) { t in
            t.column(contactId, primaryKey: true)
            t.column(contactUserId)
            t.column(contactDisplayNameOverride)
            t.column(contactIsFavorite, defaultValue: false)
            t.column(contactNotes)
            t.column(contactUserEmail)
            t.column(contactUserUsername)
            t.column(contactUserDisplayName)
            t.column(contactUserAvatarUrl)
            t.column(contactCreatedAt, defaultValue: Date())
            t.column(contactUpdatedAt, defaultValue: Date())
            t.column(contactLastSyncedAt)
            t.column(contactNeedsSync, defaultValue: false)
            t.column(contactIsDeleted, defaultValue: false)
        })

        // Create indexes for contacts
        try db.run(contactsTable.createIndex(contactUserId, ifNotExists: true))
        try db.run(contactsTable.createIndex(contactNeedsSync, ifNotExists: true))
        try db.run(contactsTable.createIndex(contactIsDeleted, ifNotExists: true))
        try db.run(contactsTable.createIndex(contactUpdatedAt, ifNotExists: true))

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
            t.column(messageClientMessageId)  // For deduplication tracking
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
        try connection.run(cdcLogsTable.createIndex(cdcTableName, cdcRecordId, ifNotExists: true))
        try connection.run(cdcLogsTable.createIndex(cdcTimestamp, ifNotExists: true))

        // Migration: Add client_message_id column to existing messages tables
        do {
            try connection.run(messagesTable.addColumn(messageClientMessageId))
            print("✅ [MIGRATION] Added client_message_id column to messages table")
        } catch {
            // Column already exists or other error - safe to ignore
            print("ℹ️ [MIGRATION] client_message_id column migration skipped (likely already exists)")
        }

        // Add is_synced column for CDC logs
        let cdcIsSynced = Expression<Bool>("is_synced")
        do {
            try connection.run(cdcLogsTable.addColumn(cdcIsSynced, defaultValue: false))
        } catch {
            // Column might already exist
        }
        try connection.run(cdcLogsTable.createIndex(cdcIsSynced, ifNotExists: true))

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
        try connection.run(syncStatesTable.createIndex(syncEntityType, syncEntityId, ifNotExists: true))
        try connection.run(syncStatesTable.createIndex(syncIsSynced, ifNotExists: true))

        // Task 13.1: Create SQLite triggers for automatic CDC logging
        try await createCDCTriggers(in: connection)

        print("✅ Thread-specific tables created")
    }

    // MARK: - Task 13.1: SQLite CDC Triggers

    /// Create SQLite triggers to automatically log CDC events
    private func createCDCTriggers(in connection: Connection) async throws {
        // Trigger for INSERT operations on messages
        let insertTrigger = """
        CREATE TRIGGER IF NOT EXISTS messages_insert_cdc_trigger
        AFTER INSERT ON messages
        BEGIN
            INSERT INTO cdc_logs (
                id, table_name, record_id, operation,
                old_data, new_data, changed_fields,
                timestamp, created_at, is_synced
            ) VALUES (
                lower(hex(randomblob(16))),
                'messages',
                NEW.id,
                'insert',
                NULL,
                json_object(
                    'id', NEW.id,
                    'thread_id', NEW.thread_id,
                    'sender_id', NEW.sender_id,
                    'content', NEW.content,
                    'message_type', NEW.message_type,
                    'status', NEW.status,
                    'created_at', NEW.created_at,
                    'updated_at', NEW.updated_at
                ),
                NULL,
                datetime('now'),
                datetime('now'),
                0
            );
        END;
        """

        // Trigger for UPDATE operations on messages
        let updateTrigger = """
        CREATE TRIGGER IF NOT EXISTS messages_update_cdc_trigger
        AFTER UPDATE ON messages
        BEGIN
            INSERT INTO cdc_logs (
                id, table_name, record_id, operation,
                old_data, new_data, changed_fields,
                timestamp, created_at, is_synced
            ) VALUES (
                lower(hex(randomblob(16))),
                'messages',
                NEW.id,
                'update',
                json_object(
                    'id', OLD.id,
                    'thread_id', OLD.thread_id,
                    'sender_id', OLD.sender_id,
                    'content', OLD.content,
                    'message_type', OLD.message_type,
                    'status', OLD.status,
                    'created_at', OLD.created_at,
                    'updated_at', OLD.updated_at
                ),
                json_object(
                    'id', NEW.id,
                    'thread_id', NEW.thread_id,
                    'sender_id', NEW.sender_id,
                    'content', NEW.content,
                    'message_type', NEW.message_type,
                    'status', NEW.status,
                    'created_at', NEW.created_at,
                    'updated_at', NEW.updated_at
                ),
                json_array(
                    CASE WHEN OLD.content != NEW.content THEN 'content' END,
                    CASE WHEN OLD.status != NEW.status THEN 'status' END,
                    CASE WHEN OLD.message_type != NEW.message_type THEN 'message_type' END
                ),
                datetime('now'),
                datetime('now'),
                0
            );
        END;
        """

        // Trigger for DELETE operations on messages
        let deleteTrigger = """
        CREATE TRIGGER IF NOT EXISTS messages_delete_cdc_trigger
        AFTER DELETE ON messages
        BEGIN
            INSERT INTO cdc_logs (
                id, table_name, record_id, operation,
                old_data, new_data, changed_fields,
                timestamp, created_at, is_synced
            ) VALUES (
                lower(hex(randomblob(16))),
                'messages',
                OLD.id,
                'delete',
                json_object(
                    'id', OLD.id,
                    'thread_id', OLD.thread_id,
                    'sender_id', OLD.sender_id,
                    'content', OLD.content,
                    'message_type', OLD.message_type,
                    'status', OLD.status,
                    'created_at', OLD.created_at,
                    'updated_at', OLD.updated_at
                ),
                json_object('id', OLD.id),
                NULL,
                datetime('now'),
                datetime('now'),
                0
            );
        END;
        """

        try connection.execute(insertTrigger)
        try connection.execute(updateTrigger)
        try connection.execute(deleteTrigger)

        print("✅ CDC triggers created successfully")
    }

    // MARK: - Thread Operations

    /// Create a new thread
    func createThread(_ thread: Thread) async throws {
        try await ensureMainConnection()
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
        try await ensureMainConnection()
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        do {
            var threads: [Thread] = []

            for row in try db.prepare(threadsTable.order(threadLastMessageAt.desc)) {
                // Safely parse thread data
                guard let idStr = try? row.get(threadId),
                      let id = UUID(uuidString: idStr),
                      let typeStr = try? row.get(threadType),
                      let type = Thread.ThreadType(rawValue: typeStr),
                      let shardId = try? row.get(threadDatabaseShardId),
                      let createdAt = try? row.get(threadCreatedAt),
                      let updatedAt = try? row.get(threadUpdatedAt) else {
                    print("⚠️ [DB] Skipping invalid thread row")
                    continue
                }
                
                let thread = Thread(
                    id: id,
                    threadType: type,
                    title: try? row.get(threadTitle),
                    avatarUrl: try? row.get(threadAvatarUrl),
                    lastMessageAt: try? row.get(threadLastMessageAt),
                    isArchived: (try? row.get(threadIsArchived)) ?? false,
                    isMuted: (try? row.get(threadIsMuted)) ?? false,
                    databaseShardId: shardId,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                threads.append(thread)
            }

            return threads
        } catch {
            throw DatabaseError.queryFailed("Threads: \(error.localizedDescription)")
        }
    }

    /// Fetch user data from backend without syncing threads
    func fetchUserFromBackend(phoenixManager: PhoenixChannelManager) async throws -> User {
        print("👤 [USER_SYNC] Fetching user from backend...")
        
        let bootstrap = try await phoenixManager.fetchBootstrap()
        let user = User.from(bootstrap.user)
        
        print("✅ [USER_SYNC] Received user: \(user.id) - \(user.displayName)")
        return user
    }

    /// Sync threads from backend via Phoenix channel
    func syncThreadsFromBackend(phoenixManager: PhoenixChannelManager) async throws -> ([Thread], User) {
        print("📥 Syncing threads and user from backend...")
        
        // 1. Fetch bootstrap data via Phoenix channel
        let bootstrap = try await phoenixManager.fetchBootstrap()
        
        // 2. Convert UserData to User
        let user = User.from(bootstrap.user)
        print("👤 [SYNC] Received user from backend: \(user.id) - \(user.displayName)")
        
        // 3. Clear existing local threads
        try await clearAllThreads()
        
        // 4. Insert backend threads into local database
        for threadData in bootstrap.threads {
            // Safely parse thread data from bootstrap
            guard let id = UUID(uuidString: threadData.id),
                  let threadType = Thread.ThreadType(rawValue: threadData.threadType) else {
                print("⚠️ [BOOTSTRAP] Skipping invalid thread data: id=\(threadData.id), type=\(threadData.threadType)")
                continue
            }

            let thread = Thread(
                id: id,
                threadType: threadType,
                title: threadData.title,
                avatarUrl: nil,
                lastMessageAt: threadData.lastMessageAt,
                isArchived: threadData.isArchived,
                isMuted: threadData.isMuted,
                databaseShardId: threadData.databaseShardId,
                participantIds: threadData.participantIds,
                createdAt: threadData.createdAt,
                updatedAt: threadData.updatedAt
            )
            
            // Create thread locally (without calling backend)
            try await createThreadLocally(thread)
        }
        
        let threads = try await fetchThreads()
        print("✅ Synced \(bootstrap.threads.count) threads and user from backend")
        return (threads, user)
    }

    /// Create thread locally only (used during sync)
    func createThreadLocally(_ thread: Thread) async throws {
        try await ensureMainConnection()
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }
        
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
        _ = try await getThreadDatabase(shardId: thread.databaseShardId)
    }

    /// Clear all threads from database
    private func clearAllThreads() async throws {
        try await ensureMainConnection()
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }
        
        try db.run(threadsTable.delete())
        print("🗑️ Cleared all local threads")
    }

    /// Update a thread
    func updateThread(_ thread: Thread) async throws {
        try await ensureMainConnection()
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

    /// Create or update a thread record
    func upsertThread(_ thread: Thread) async throws {
        if let existing = try await fetchThread(id: thread.id) {
            var updated = existing
            updated.title = thread.title
            updated.lastMessageAt = thread.lastMessageAt
            updated.isArchived = thread.isArchived
            updated.isMuted = thread.isMuted
            updated.updatedAt = thread.updatedAt
            try await updateThread(updated)
        } else {
            try await createThread(thread)
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

            // Use INSERT OR REPLACE to handle both creation and updates
            let upsert = messagesTable.insert(
                or: .replace,  // UPSERT: update if exists, insert if not
                messageId <- message.id.uuidString,
                messageThreadId <- message.threadId.uuidString,
                messageSenderId <- message.senderId,  // Now a String, not UUID
                messageContent <- message.content,
                messageType <- message.messageType.rawValue,
                messageStatus <- message.status.rawValue,
                messageMetadata <- metadataJson,
                messageReplyToId <- message.replyToId?.uuidString,
                messageEditedAt <- message.editedAt,
                messageDeletedAt <- message.deletedAt,
                messageClientMessageId <- message.clientMessageId,  // For deduplication
                messageCreatedAt <- message.createdAt,
                messageUpdatedAt <- message.updatedAt
            )

            try db.run(upsert)

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
                // Safely parse required UUIDs
                guard let messageIdStr = try? row.get(messageId),
                      let id = UUID(uuidString: messageIdStr),
                      let threadIdStr = try? row.get(messageThreadId),
                      let threadIdParsed = UUID(uuidString: threadIdStr),
                      let senderIdVal = try? row.get(messageSenderId),
                      let contentVal = try? row.get(messageContent),
                      let typeStr = try? row.get(messageType),
                      let messageType = Message.MessageType(rawValue: typeStr),
                      let statusStr = try? row.get(messageStatus),
                      let status = Message.Status(rawValue: statusStr),
                      let createdAtVal = try? row.get(messageCreatedAt),
                      let updatedAtVal = try? row.get(messageUpdatedAt) else {
                    print("⚠️ [DB] Skipping invalid message row")
                    continue
                }
                
                var metadata: [String: String]? = nil
                if let metadataStr = try? row.get(messageMetadata),
                   let data = metadataStr.data(using: .utf8) {
                    metadata = try? JSONDecoder().decode([String: String].self, from: data)
                }

                let message = Message(
                    id: id,
                    threadId: threadIdParsed,
                    senderId: senderIdVal,
                    content: contentVal,
                    messageType: messageType,
                    status: status,
                    metadata: metadata,
                    replyToId: (try? row.get(messageReplyToId)).flatMap { UUID(uuidString: $0) },
                    editedAt: try? row.get(messageEditedAt),
                    deletedAt: try? row.get(messageDeletedAt),
                    createdAt: createdAtVal,
                    updatedAt: updatedAtVal,
                    clientMessageId: try? row.get(messageClientMessageId)
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
            guard let newDataStr = String(data: newDataJson, encoding: .utf8) else {
                throw DatabaseError.encodingFailed("Failed to encode CDC new data as UTF-8")
            }

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
        let cdcIsSynced = Expression<Bool>("is_synced")

        do {
            var logs: [CDCLog] = []

            let query = cdcLogsTable
                .filter(cdcIsSynced == false)
                .order(cdcTimestamp.asc)
                .limit(limit)

            for row in try db.prepare(query) {
                var oldData: [String: String]? = nil
                if let oldDataStr = row[cdcOldData],
                   let data = oldDataStr.data(using: .utf8) {
                    oldData = try? JSONDecoder().decode([String: String].self, from: data)
                }

                let newDataStr = row[cdcNewData]
                guard let newDataJson = newDataStr.data(using: .utf8) else {
                    print("⚠️ [CDC] Skipping log with invalid UTF-8 data")
                    continue
                }
                let newData = try JSONDecoder().decode([String: String].self, from: newDataJson)

                var changedFields: [String]? = nil
                if let fieldsStr = row[cdcChangedFields],
                   let data = fieldsStr.data(using: .utf8) {
                    changedFields = try? JSONDecoder().decode([String].self, from: data)
                }

                // Parse CDC log (id is String, not UUID - backend uses MD5 hashes)
                guard let recordId = UUID(uuidString: row[cdcRecordId]),
                      let operation = CDCLog.CDCOperation(rawValue: row[cdcOperation]) else {
                    print("⚠️ [CDC] Skipping invalid CDC log: id=\(row[cdcId]), recordId=\(row[cdcRecordId]), operation=\(row[cdcOperation])")
                    continue
                }

                let log = CDCLog(
                    id: row[cdcId],  // Use string directly, not UUID
                    tableName: row[cdcTableName],
                    recordId: recordId,
                    operation: operation,
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

    /// Mark CDC log as synced
    func markCDCLogAsSynced(logId: String, shardId: String) async throws {
        let db = try await getThreadDatabase(shardId: shardId)
        let cdcIsSynced = Expression<Bool>("is_synced")

        do {
            let logRow = cdcLogsTable.filter(cdcId == logId)  // Already a String
            let update = logRow.update(cdcIsSynced <- true)

            let changes = try db.run(update)
            if changes == 0 {
                print("⚠️ CDC log not found for marking as synced: \(logId)")
            }
        } catch {
            throw DatabaseError.updateFailed("CDC log sync status: \(error.localizedDescription)")
        }
    }

    /// Update an existing message
    func updateMessage(_ message: Message) async throws {
        guard let thread = try await fetchThread(id: message.threadId) else {
            throw DatabaseError.notFound("Thread: \(message.threadId)")
        }

        let db = try await getThreadDatabase(shardId: thread.databaseShardId)

        do {
            let metadataJson = message.metadata.flatMap { try? JSONEncoder().encode($0) }
                .flatMap { String(data: $0, encoding: .utf8) }

            let messageRow = messagesTable.filter(messageId == message.id.uuidString)
            let update = messageRow.update(
                messageContent <- message.content,
                messageType <- message.messageType.rawValue,
                messageStatus <- message.status.rawValue,
                messageMetadata <- metadataJson,
                messageReplyToId <- message.replyToId?.uuidString,
                messageEditedAt <- message.editedAt,
                messageDeletedAt <- message.deletedAt,
                messageUpdatedAt <- Date()
            )

            let changes = try db.run(update)

            if changes == 0 {
                throw DatabaseError.notFound("Message: \(message.id)")
            }

            print("✅ Message updated: \(message.id)")
        } catch {
            throw DatabaseError.updateFailed("Message: \(error.localizedDescription)")
        }
    }

    /// Delete a message
    func deleteMessage(id: UUID, threadId: UUID) async throws {
        guard let thread = try await fetchThread(id: threadId) else {
            throw DatabaseError.notFound("Thread: \(threadId)")
        }

        let db = try await getThreadDatabase(shardId: thread.databaseShardId)

        do {
            let messageRow = messagesTable.filter(messageId == id.uuidString)
            let changes = try db.run(messageRow.delete())

            if changes == 0 {
                throw DatabaseError.notFound("Message: \(id)")
            }

            print("✅ Message deleted: \(id)")
        } catch {
            throw DatabaseError.deleteFailed("Message: \(error.localizedDescription)")
        }
    }

    /// Fetch thread by ID (public version)
    func fetchThread(id: UUID) async throws -> Thread? {
        try await ensureMainConnection()
        guard let db = mainConnection else {
            throw DatabaseError.connectionFailed("Main connection not available")
        }

        let query = threadsTable.filter(threadId == id.uuidString)

        guard let row = try db.pluck(query),
              let idStr = try? row.get(threadId),
              let id = UUID(uuidString: idStr),
              let typeStr = try? row.get(threadType),
              let threadType = Thread.ThreadType(rawValue: typeStr),
              let shardId = try? row.get(threadDatabaseShardId),
              let createdAt = try? row.get(threadCreatedAt),
              let updatedAt = try? row.get(threadUpdatedAt) else {
            return nil
        }

        return Thread(
            id: id,
            threadType: threadType,
            title: try? row.get(threadTitle),
            avatarUrl: try? row.get(threadAvatarUrl),
            lastMessageAt: try? row.get(threadLastMessageAt),
            isArchived: (try? row.get(threadIsArchived)) ?? false,
            isMuted: (try? row.get(threadIsMuted)) ?? false,
            databaseShardId: shardId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Helper Methods

    private func updateThreadLastMessage(threadId: UUID, timestamp: Date) async throws {
        try await ensureMainConnection()
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
            "sender_id": message.senderId,  // Now a String, not UUID
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

    // MARK: - Seeding Helpers

    func seedSampleDataIfNeeded(currentUser: User = .sampleCurrent) async throws {
        // Disabled: Sample data doesn't exist on backend
        // Users should create threads through the UI which will create them on both client and backend
        print("ℹ️ Sample data seeding disabled - create threads through the UI")
    }

    // MARK: - Cleanup

    /// Close all database connections
    func closeAllConnections() {
        threadConnections.removeAll()
        mainConnection = nil
        print("✅ All database connections closed")
    }

    deinit {
        MainActor.assumeIsolated {
            threadConnections.removeAll()
            mainConnection = nil
            print("✅ All database connections closed")
        }
    }
}
