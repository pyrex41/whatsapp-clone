//
//  AppEnvironment.swift
//  GlobalBridge
//

import Foundation
import SwiftUI

struct DatabaseClient {
    var loadThreads: @Sendable () async throws -> [Thread]
    var createThread: @Sendable (_ title: String, _ creator: User) async throws -> Thread
    var loadMessages: @Sendable (_ threadID: UUID) async throws -> [Message]
    var createMessage: @Sendable (_ threadID: UUID, _ content: String, _ author: User) async throws -> Message
}

struct RealtimeClient {
    var connect: @Sendable (_ threadID: UUID, _ handler: @Sendable @escaping (Message) -> Void) async -> Void
    var disconnect: @Sendable (_ threadID: UUID) async -> Void
    var sendTyping: @Sendable (_ threadID: UUID, _ userID: UUID, _ isTyping: Bool) async -> Void
}

struct AppEnvironment {
    var database: DatabaseClient
    var realtime: RealtimeClient
    var uuid: @Sendable () -> UUID = { UUID() }
    var now: @Sendable () -> Date = { Date() }
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
            }
        )

        let realtime = RealtimeClient(
            connect: { threadID, handler in
                await store.registerRealtimeHandler(threadID: threadID, handler: handler)
            },
            disconnect: { threadID in
                await store.unregisterRealtimeHandler(threadID: threadID)
            },
            sendTyping: { _, _, _ in }
        )

        return AppEnvironment(database: database, realtime: realtime)
    }()

    static let live: AppEnvironment = {
        let databaseManager = DatabaseManager.shared
        let initializationTask = Task { @MainActor in
            try await databaseManager.initialize()
            try await databaseManager.seedSampleDataIfNeeded()
        }

        let database = DatabaseClient(
            loadThreads: {
                try await initializationTask.value
                try await databaseManager.fetchThreads()
            },
            createThread: { title, creator in
                _ = try await initializationTask.value
                let now = Date()
                let thread = Thread(
                    threadType: .group,
                    title: title,
                    lastMessageAt: now,
                    unreadCount: 0,
                    createdAt: now,
                    updatedAt: now
                )
                try await databaseManager.createThread(thread)
                return thread
            },
            loadMessages: { threadID in
                _ = try await initializationTask.value
                try await databaseManager.fetchMessages(threadId: threadID, limit: 200, offset: 0)
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
            }
        )

        let realtime = RealtimeClient(
            connect: { _, _ in },
            disconnect: { _ in },
            sendTyping: { _, _, _ in }
        )

        return AppEnvironment(database: database, realtime: realtime)
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
        messages[threadID, default: []].append(message)
        if let index = threads.firstIndex(where: { $0.id == threadID }) {
            threads[index].lastMessageAt = now
            threads[index].updatedAt = now
            threads[index].unreadCount = 0
        }
        realtimeHandlers[threadID]?.forEach { handler in
            handler(message)
        }
        return message
    }

    func registerRealtimeHandler(threadID: UUID, handler: @escaping (Message) -> Void) {
        realtimeHandlers[threadID, default: []].append(handler)
    }

    func unregisterRealtimeHandler(threadID: UUID) {
        realtimeHandlers[threadID] = nil
    }
}
