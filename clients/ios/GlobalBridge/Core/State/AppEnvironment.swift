//
//  AppEnvironment.swift
//  GlobalBridge
//

import Foundation
import SwiftUI

// Actor to safely guard one-time registration for global message handler
actor GlobalBannerHandlerRegistry {
    static let shared = GlobalBannerHandlerRegistry()
    private var registered = false
    func markIfNeeded() -> Bool {
        if registered { return false }
        registered = true
        return true
    }
}

struct DatabaseClient {
    var loadThreads: @Sendable () async throws -> [Thread]
    var createThread: @Sendable (_ title: String, _ creator: User) async throws -> Thread
    var loadMessages: @Sendable (_ threadID: UUID) async throws -> [Message]
    var createMessage: @Sendable (_ threadID: UUID, _ content: String, _ author: User) async throws -> Message
    var storeMessage: @Sendable (_ message: Message) async throws -> Void
}

struct RealtimeClient {
    var ensureConnection: @Sendable () async throws -> Void
    var connect: @Sendable (_ threadID: UUID, _ handler: @Sendable @escaping (Message) -> Void) async throws -> Void
    var disconnect: @Sendable (_ threadID: UUID) async -> Void
    var sendTyping: @Sendable (_ threadID: UUID, _ userID: String, _ isTyping: Bool) async -> Void  // Changed userID from UUID to String
    var sendMessage: @Sendable (_ threadID: UUID, _ content: String, _ author: User, _ clientMessageId: UUID?) async throws -> Message
    var sendReadReceipt: @Sendable (_ threadID: UUID, _ messageId: String) async -> Void
}

struct SyncClient {
    var initialSync: @Sendable () async -> Void
    var startMonitoring: @Sendable () async -> Void
    var stopMonitoring: @Sendable () async -> Void
    var syncThread: @Sendable (_ threadID: UUID) async -> Void
}

struct AppEnvironment {
    var database: DatabaseClient
    var realtime: RealtimeClient
    var sync: SyncClient
    var uuid: @Sendable () -> UUID = { UUID() }
    var now: @Sendable () -> Date = { Date() }
    var deviceId: UUID = UUID() // Unique device identifier for deduplication
}

extension AppEnvironment {
    static let preview: AppEnvironment = {
        let store = InMemoryDataStore.shared

        let database = DatabaseClient(
            loadThreads: {
                await store.loadThreads()
            },
            createThread: { title, creator in
                await store.createThread(title: title, creator: creator)
            },
            loadMessages: { threadID in
                await store.loadMessages(threadID: threadID)
            },
            createMessage: { threadID, content, author in
                await store.createMessage(threadID: threadID, content: content, author: author)
            },
            storeMessage: { message in
                await store.saveMessage(message)
            }
        )

        let realtime = RealtimeClient(
            ensureConnection: { },
            connect: { threadID, handler in
                await store.registerRealtimeHandler(threadID: threadID, handler: handler)
            },
            disconnect: { threadID in
                await store.unregisterRealtimeHandler(threadID: threadID)
            },
            sendTyping: { _, _, _ in },
            sendMessage: { threadID, content, author, _ in
                await store.createMessage(threadID: threadID, content: content, author: author)
            },
            sendReadReceipt: { _, _ in }
        )

        let sync = SyncClient(
            initialSync: { },
            startMonitoring: { },
            stopMonitoring: { },
            syncThread: { _ in }
        )

        return AppEnvironment(database: database, realtime: realtime, sync: sync)
    }()

    static let live: AppEnvironment = {
        let databaseManager = DatabaseManager.shared
        let initializationTask = Task { @MainActor in
            try await databaseManager.initialize()
            try await databaseManager.seedSampleDataIfNeeded()
        }

        let phoenixConfig = PhoenixConfig.current  // Auto-selects dev/prod based on build config
        let phoenixManager = PhoenixChannelManager(config: phoenixConfig)

        let threadService = ThreadService()

        let syncActorTask = Task { () -> SyncActor in
            let cdcManager = await MainActor.run {
                CDCManager(
                    databaseManager: databaseManager,
                    phoenixManager: phoenixManager,
                    deviceId: UUID()
                )
            }

            return SyncActor(
                phoenixManager: phoenixManager,
                databaseManager: databaseManager,
                cdcManager: cdcManager
            )
        }

        let database = DatabaseClient(
            loadThreads: {
                _ = try await initializationTask.value
                
                print("📥 [LOAD_THREADS] Starting thread load...")
                
                // ALWAYS fetch user identity from backend
                print("👤 [LOAD_THREADS] Fetching current user identity...")
                let user = try await databaseManager.fetchUserFromBackend(phoenixManager: phoenixManager)
                print("✅ [LOAD_THREADS] User identity confirmed: \(user.id)")
                await AuthManager.shared.setBootstrappedUser(user)
                
                // Check if we should sync threads from backend
                let localThreads = try await databaseManager.fetchThreads()
                
                if localThreads.isEmpty {
                    print("📥 [LOAD_THREADS] No local threads, syncing from backend...")
                    
                    do {
                        // Sync threads from backend via Phoenix bootstrap
                        let (syncedThreads, _) = try await databaseManager.syncThreadsFromBackend(phoenixManager: phoenixManager)
                        print("✅ [LOAD_THREADS] Synced \(syncedThreads.count) threads from backend")
                        return syncedThreads
                    } catch {
                        print("❌ [LOAD_THREADS] Bootstrap sync failed: \(error)")
                        print("❌ [LOAD_THREADS] Error details: \(error.localizedDescription)")
                        throw error
                    }
                } else {
                    print("✅ [LOAD_THREADS] Loaded \(localThreads.count) threads from local DB")
                    return localThreads
                }
            },
            createThread: { title, creator in
                _ = try await initializationTask.value
                
                print("🆕 [CREATE_THREAD] Creating thread '\(title)' via backend...")
                print("🆕 [CREATE_THREAD] Using creator ID from backend: \(creator.id)")
                
                // 1. Create thread on backend first via Phoenix
                // Use the backend-provided user ID (which comes from UserData.id from bootstrap)
                let threadData = try await phoenixManager.createThread(
                    threadType: "group",
                    title: title,
                    participantIds: [creator.id]  // creator.id is already a String
                )
                
                print("✅ [CREATE_THREAD] Backend created thread: \(threadData.id)")
                
                // 2. Convert to local Thread model and create locally
                let thread = Thread(
                    id: UUID(uuidString: threadData.id)!,
                    threadType: Thread.ThreadType(rawValue: threadData.threadType) ?? .group,
                    title: threadData.title,
                    avatarUrl: nil,
                    lastMessageAt: threadData.lastMessageAt,
                    isArchived: threadData.isArchived,
                    isMuted: threadData.isMuted,
                    databaseShardId: threadData.databaseShardId,
                    createdAt: threadData.createdAt,
                    updatedAt: threadData.updatedAt
                )
                
                // 3. Create in local database (using the backend's ID and shard ID)
                try await databaseManager.createThreadLocally(thread)
                
                print("✅ [CREATE_THREAD] Thread created locally with backend ID: \(thread.id)")
                
                return thread
            },
            loadMessages: { threadID in
                _ = try await initializationTask.value
                return try await databaseManager.fetchMessages(threadId: threadID, limit: 200, offset: 0)
            },
            createMessage: { threadID, content, author in
                _ = try await initializationTask.value
                let now = Date()
                let message = Message(
                    threadId: threadID,
                    senderId: author.id,
                    content: content,
                    messageType: .text,
                    status: .sent,
                    createdAt: now,
                    updatedAt: now
                )
                try await databaseManager.createMessage(message)
                return message
            },
            storeMessage: { message in
                _ = try await initializationTask.value
                do {
                    try await databaseManager.createMessage(message)
                } catch {
                    print("⚠️ Failed to store message \(message.id): \(error)")
                }
            }
        )

        let realtime = RealtimeClient(
            ensureConnection: {
                // Get Auth0 token
                let token = await AuthManager.shared.getAccessToken()
                
                if token == nil {
                    print("🔐 [REALTIME] No auth token, attempting Auth0 login...")
                    _ = try await AuthManager.shared.login()
                }
                
                let authToken = await AuthManager.shared.getAccessToken()
                print("🔌 [REALTIME] Connecting with Auth0 token...")
                
                // Retry connection up to 3 times with delay
                var lastError: Error?
                for attempt in 1...3 {
                    do {
                        try await phoenixManager.connect(authToken: authToken)
                        print("✅ [REALTIME] Phoenix connected on attempt \(attempt)")
                        break
                    } catch {
                        lastError = error
                        if attempt < 3 {
                            print("⚠️ [REALTIME] Connection attempt \(attempt) failed, retrying in 1s...")
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                    }
                }
                
                // If all retries failed, throw the last error
                if let error = lastError {
                    let state = await phoenixManager.getConnectionState()
                    if case .connected = state {
                        print("✅ [REALTIME] Connected despite error")
                    } else {
                        print("❌ [REALTIME] All connection attempts failed")
                        throw error
                    }
                }
                
                // Join user channel for bootstrap
                if let userId = await AuthManager.shared.getUserId() {
                    print("👤 [REALTIME] Joining user channel for: \(userId)")
                    try await phoenixManager.joinUserChannel(userId: userId)
                    print("✅ [REALTIME] User channel joined")

                    // Register global new_message handler once (user-wide feed)
                    if await GlobalBannerHandlerRegistry.shared.markIfNeeded() {
                        await phoenixManager.onAnyMessage { phoenixMessage in
                            guard let message = Message.fromPhoenix(phoenixMessage) else { return }
                            // Present banner in banner mode only
                            Task { @Sendable in
                                guard NotificationConfig.current != .system else { return }
                                // Skip self messages
                                let currentUserId = await AuthManager.shared.getUserId()
                                if let currentUserId, currentUserId == message.senderId { return }
                                // Respect mute
                                let thread = try? await databaseManager.fetchThread(id: message.threadId)
                                if thread?.isMuted == true { return }
                                // Build event
                                let raw = message.content.replacingOccurrences(of: "\n", with: " ")
                                let snippet = String(raw.prefix(120))
                                let title = thread?.title ?? "New message"
                                let event = NotificationEvent.messageReceived(
                                    .init(threadId: message.threadId, title: title, snippet: snippet, avatarURL: nil)
                                )
                                await MainActor.run {
                                    InAppBannerCenter.shared.present(event: event)
                                }
                            }
                        }
                    }
                }
            },
            connect: { threadID, handler in
                print("🔌 [CONNECT] Realtime connect called for thread: \(threadID)")

                // Get Auth0 token
                let token = await AuthManager.shared.getAccessToken()
                
                print("🔌 [CONNECT] Connecting to Phoenix...")
                try await phoenixManager.connect(authToken: token)
                print("✅ [CONNECT] Phoenix connected")

                let conversationId = threadID.uuidString
                print("🔌 [CONNECT] Joining channel: thread:\(conversationId)")
                try await phoenixManager.joinConversation(conversationId)
                print("✅ [CONNECT] Channel joined successfully!")

                await phoenixManager.onMessage(conversationId: conversationId) { phoenixMessage in
                    guard let message = Message.fromPhoenix(phoenixMessage) else { return }
                    Task { @MainActor in
                        handler(message)
                    }
                }
                print("✅ [CONNECT] Message handler registered for thread: \(threadID)")
            },
            disconnect: { threadID in
                await phoenixManager.leaveConversation(threadID.uuidString)
            },
            sendTyping: { threadID, _, isTyping in
                await phoenixManager.sendTypingIndicator(conversationId: threadID.uuidString, isTyping: isTyping)
            },
            sendMessage: { threadID, content, _, clientMessageId in
                print("📤 [ENV] sendMessage called - thread: \(threadID.uuidString), content: \"\(content)\", clientMessageId: \(clientMessageId?.uuidString ?? "nil")")

                // Get Auth0 token
                let token = await AuthManager.shared.getAccessToken()
                
                print("📤 [ENV] Ensuring Phoenix connection with Auth0 token...")
                try await phoenixManager.connect(authToken: token)
                print("✅ [ENV] Phoenix connected")

                print("📤 [ENV] Calling phoenixManager.sendMessage...")
                let phoenixMessage = try await phoenixManager.sendMessage(
                    conversationId: threadID.uuidString,
                    content: content,
                    clientMessageId: clientMessageId?.uuidString,
                    replyToId: nil
                )
                print("✅ [ENV] Phoenix response: id=\(phoenixMessage.id), conversationId=\(phoenixMessage.conversationId), senderId=\(phoenixMessage.senderId), content=\"\(phoenixMessage.content)\", status=\(phoenixMessage.status.rawValue)")

                print("📤 [ENV] Converting PhoenixMessage to Message...")
                guard let message = Message.fromPhoenix(phoenixMessage) else {
                    print("❌ [ENV] Failed to convert PhoenixMessage to Message")
                    throw DatabaseError.insertFailed("Failed to convert Phoenix message")
                }
                print("✅ [ENV] Message converted successfully: id=\(message.id.uuidString)")

                return message
            },
            sendReadReceipt: { threadID, messageId in
                await phoenixManager.sendReadReceipt(conversationId: threadID.uuidString, messageId: messageId)
            }
        )

        let sync = SyncClient(
            initialSync: {
                _ = try? await initializationTask.value
                do {
                    let remoteThreads = try await threadService.fetchThreads()
                    for thread in remoteThreads {
                        try await databaseManager.upsertThread(thread)
                    }
                } catch {
                    print("⚠️ Failed to fetch remote threads: \\(error.localizedDescription)")
                }
                // Note: syncAllThreads() is NOT called here because thread channels aren't joined yet
                // Sync will be triggered automatically when:
                // 1. User taps on a thread → channel joins → sync happens
                // 2. Connectivity monitoring detects connection → syncs all threads
                print("✅ Initial sync preparation complete (channels will sync when joined)")
            },
            startMonitoring: {
                let actor = await syncActorTask.value
                await actor.startMonitoring()
            },
            stopMonitoring: {
                let actor = await syncActorTask.value
                await actor.stopMonitoring()
            },
            syncThread: { threadID in
                _ = try? await initializationTask.value
                let actor = await syncActorTask.value
                _ = await actor.triggerSync(threadId: threadID)
            }
        )

        return AppEnvironment(database: database, realtime: realtime, sync: sync)
    }()
}

// MARK: - In-memory preview data store

actor InMemoryDataStore {
    static let shared = InMemoryDataStore()

    private var threads: [Thread]
    private var messages: [UUID: [Message]]
    private var realtimeHandlers: [UUID: [(Message) -> Void]] = [:]

    init(
        threads: [Thread]? = nil,
        messages: [UUID: [Message]] = [:]
    ) {
        let initialThreads = threads ?? Thread.sampleThreads

        var messageMap: [UUID: [Message]] = messages
        if messageMap.isEmpty {
            for thread in initialThreads {
                messageMap[thread.id] = Message.samples(for: thread.id, sender: User.sampleCurrent)
            }
        }
        self.threads = initialThreads
        self.messages = messageMap
    }

    func loadThreads() -> [Thread] {
        threads
    }

    func createThread(title: String, creator: User) -> Thread {
        var thread = Thread(
            threadType: .group,
            title: title,
            lastMessageAt: Date(),
            databaseShardId: "thread_\(UUID().uuidString)",
            unreadCount: 0
        )
        threads.insert(thread, at: 0)
        let seededMessages = Message.samples(for: thread.id, sender: creator)
        messages[thread.id] = seededMessages
        thread.lastMessageAt = seededMessages.last?.createdAt
        thread.updatedAt = Date()
        threads[0] = thread
        return thread
    }

    func loadMessages(threadID: UUID) -> [Message] {
        messages[threadID] ?? []
    }

    func createMessage(threadID: UUID, content: String, author: User) -> Message {
        let now = Date()
        let message = Message(
            threadId: threadID,
            senderId: author.id,
            content: content,
            messageType: .text,
            status: .sent,
            createdAt: now,
            updatedAt: now
        )
        saveMessage(message)
        return message
    }

    func saveMessage(_ message: Message) {
        messages[message.threadId, default: []].append(message)
        if let index = threads.firstIndex(where: { $0.id == message.threadId }) {
            threads[index].lastMessageAt = message.createdAt
            threads[index].updatedAt = message.updatedAt
            threads[index].unreadCount = 0
        }
        realtimeHandlers[message.threadId]?.forEach { handler in
            handler(message)
        }
    }

    func registerRealtimeHandler(threadID: UUID, handler: @escaping (Message) -> Void) {
        realtimeHandlers[threadID, default: []].append(handler)
    }

    func unregisterRealtimeHandler(threadID: UUID) {
        realtimeHandlers[threadID] = nil
    }
}
