//
//  AppReducer.swift
//  GlobalBridge
//

import Foundation

let appReducer: Store<AppState, AppAction>.Reducer = { state, action, environment in
    switch action {
    case .onAppear:
        guard state.threads.hasLoaded == false else { return .none }
        state.threads.isLoading = true
        state.threads.errorMessage = nil

        let ensureRealtime = Command<AppAction>.run(priority: nil) { _ in
            do {
                try await environment.realtime.ensureConnection()
            } catch {
                print("⚠️ Realtime connection failed: \(error)")
            }
        }

        let loadThreads = Command<AppAction>.run(priority: nil) { send in
            do {
                await environment.sync.initialSync()
                await environment.sync.startMonitoring()
                let threads = try await environment.database.loadThreads()
                send(.threadsLoaded(.success(threads)))
            } catch {
                send(.threadsLoaded(.failure(error)))
            }
        }

        return .merge(ensureRealtime, loadThreads)

    case let .threadsLoaded(result):
        state.threads.isLoading = false
        state.threads.hasLoaded = true
        switch result {
        case let .success(threads):
            state.threads.items = threads
            if let firstThread = threads.first {
                print("📋 [LOADED] Auto-selecting first thread: \(firstThread.id)")
                state.threads.selectedThreadID = firstThread.id
                state.chat.currentThread = firstThread
                state.chat.messages = []
                state.chat.isLoadingMessages = true

                // Join channel and load messages for the first thread
                print("🔌 [LOADED] Connecting to realtime for first thread: \(firstThread.id)")
                let threadID = firstThread.id
                return .merge(
                    .run(priority: nil) { send in
                        send(.loadMessages(threadID))
                    },
                    .run(priority: nil) { send in
                        print("🔌 [LOADED] Executing realtime.connect for first thread: \(threadID)")
                        do {
                            try await environment.realtime.ensureConnection()
                            try await environment.realtime.connect(threadID) { message in
                                Task { @MainActor in
                                    send(.receiveRealtimeMessage(message))
                                }
                            }
                            print("✅ [LOADED] realtime.connect completed for first thread: \(threadID)")
                        } catch {
                            print("❌ [LOADED] realtime.connect failed for first thread: \(threadID): \(error.localizedDescription)")
                            if error.localizedDescription.contains("Thread not found") {
                                send(.handleOrphanedThread(threadID))
                            }
                        }
                    }
                )
            }
            return .none

        case let .failure(error):
            state.threads.errorMessage = error.localizedDescription
            return .none
        }

    case let .threadSelected(threadID):
        print("🎯 [ACTION] threadSelected fired for thread: \(threadID)")

        guard let thread = state.threads.items.first(where: { $0.id == threadID }) else {
            print("⚠️ [ACTION] threadSelected guard failed - thread not found")
            print("   - Requested thread: \(threadID)")
            print("   - Available threads: \(state.threads.items.map { $0.id })")
            return .none
        }

        // If selecting the same thread, just ensure we're connected (no-op if already connected)
        if state.threads.selectedThreadID == threadID {
            print("ℹ️ [ACTION] Thread already selected, ensuring connection: \(threadID)")
            // Don't reload messages or change state, just ensure channel is connected
            return .run(priority: nil) { send in
                print("🔌 [ACTION] Re-ensuring realtime connection for thread: \(threadID)")
                do {
                    try await environment.realtime.ensureConnection()
                    try await environment.realtime.connect(threadID) { message in
                        Task { @MainActor in
                            send(.receiveRealtimeMessage(message))
                        }
                    }
                    print("✅ [ACTION] Re-connection confirmed for thread: \(threadID)")
                } catch {
                    print("❌ [ACTION] Re-connection failed for thread: \(threadID): \(error.localizedDescription)")
                    if error.localizedDescription.contains("Thread not found") {
                        send(.handleOrphanedThread(threadID))
                    }
                }
            }
        }

        print("✅ [ACTION] threadSelected guard passed, switching to thread: \(thread.title)")

        let previousThreadID = state.threads.selectedThreadID
        state.threads.selectedThreadID = threadID
        state.chat.currentThread = thread
        state.chat.messages = []
        state.chat.isLoadingMessages = true

        var commands: [Command<AppAction>] = []

        if let previousThreadID {
            print("🔌 [ACTION] Disconnecting from previous thread: \(previousThreadID)")
            commands.append(.fireAndForget {
                await environment.realtime.disconnect(previousThreadID)
            })
        }

        print("📥 [ACTION] Adding loadMessages command for thread: \(threadID)")
        commands.append(
            .run(priority: nil) { send in
                send(.loadMessages(threadID))
            }
        )

        print("🔌 [ACTION] Adding realtime.connect command for thread: \(threadID)")
        commands.append(
            .run(priority: nil) { send in
                print("🔌 [ACTION] Executing realtime.connect for thread: \(threadID)")
                do {
                    try await environment.realtime.ensureConnection()
                    try await environment.realtime.connect(threadID) { message in
                        Task { @MainActor in
                            send(.receiveRealtimeMessage(message))
                        }
                    }
                    print("✅ [ACTION] realtime.connect completed for thread: \(threadID)")
                } catch {
                    print("❌ [ACTION] realtime.connect failed for thread: \(threadID): \(error.localizedDescription)")
                    // Handle specific error case where thread doesn't exist on backend
                    if error.localizedDescription.contains("Thread not found") {
                        print("⚠️ [ACTION] Thread exists locally but not on backend - sync issue detected")
                        send(.handleOrphanedThread(threadID))
                    }
                }
            }
        )

        print("🚀 [ACTION] Returning merged commands (count: \(commands.count))")
        return .merge(commands)

    case let .setSearchQuery(query):
        state.threads.searchQuery = query
        return .none

    case let .toggleCreationSheet(isPresented):
        state.threads.showCreationSheet = isPresented
        if !isPresented {
            state.threads.creationTitle = ""
            state.threads.isCreatingThread = false
        }
        return .none

    case let .creationTitleChanged(title):
        state.threads.creationTitle = title
        return .none

    case .createThread:
        guard state.threads.creationTitle.isEmpty == false else { return .none }
        state.threads.isCreatingThread = true
        let title = state.threads.creationTitle
        let user = state.user
        return .run(priority: nil) { send in
            do {
                let thread = try await environment.database.createThread(title, user)
                send(.threadCreated(.success(thread)))
            } catch {
                send(.threadCreated(.failure(error)))
            }
        }

    case let .threadCreated(result):
        state.threads.isCreatingThread = false
        switch result {
        case let .success(thread):
            state.threads.items.insert(thread, at: 0)
            state.threads.showCreationSheet = false
            state.threads.creationTitle = ""
            state.threads.selectedThreadID = thread.id
            state.chat.currentThread = thread
            state.chat.messages = Message.samples(for: thread.id, sender: state.user)
            return .run(priority: nil) { send in
                send(.loadMessages(thread.id))
            }

        case let .failure(error):
            state.threads.errorMessage = error.localizedDescription
            return .none
        }

    case let .loadMessages(threadID):
        state.chat.isLoadingMessages = true
        return .run(priority: nil) { send in
            do {
                let messages = try await environment.database.loadMessages(threadID)
                send(.messagesLoaded(threadID, .success(messages)))
            } catch {
                send(.messagesLoaded(threadID, .failure(error)))
            }
        }

    case let .messagesLoaded(threadID, result):
        guard state.chat.currentThread?.id == threadID else { return .none }
        state.chat.isLoadingMessages = false
        switch result {
        case let .success(messages):
            state.chat.messages = messages.sorted(by: { $0.createdAt < $1.createdAt })
        case let .failure(error):
            state.chat.messageError = error.localizedDescription
        }
        return .none

    case let .composerTextChanged(text):
        state.chat.composer.text = text
        let maybeThreadID = state.chat.currentThread?.id
        let userID = state.user.id
        let isTyping = !text.isEmpty
        return .fireAndForget {
            guard let threadID = maybeThreadID else { return }
            await environment.realtime.sendTyping(threadID, userID, isTyping)
        }

    case .sendMessage:
        guard let threadID = state.chat.currentThread?.id,
              state.chat.composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              state.chat.composer.isSending == false
        else {
            print("❌ [SEND] Guard failed - threadID: \(state.chat.currentThread?.id.uuidString ?? "nil"), text empty: \(state.chat.composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), isSending: \(state.chat.composer.isSending)")
            return .none
        }

        let text = state.chat.composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUser = state.user
        state.chat.composer.isSending = true
        state.chat.composer.text = ""

        print("📤 [SEND] OFFLINE-FIRST: Starting send for thread: \(threadID.uuidString)")

        return .run(priority: nil) { send in
            do {
                let now = Date()
                
                // 1. OFFLINE-FIRST: Create message locally FIRST with "pending" status
                let localMessage = Message(
                    threadId: threadID,
                    senderId: currentUser.id,
                    content: text,
                    messageType: .text,
                    status: .pending,  // ← Mark as pending/sending
                    createdAt: now,
                    updatedAt: now
                )
                
                print("💾 [SEND] Saving locally FIRST: \(localMessage.id.uuidString) with status=pending")
                try await environment.database.storeMessage(localMessage)
                
                // 2. Show in UI immediately (optimistic update)
                send(.messageSent(.success(localMessage)))
                
                // 3. Send to backend via Phoenix
                print("📤 [SEND] Calling Phoenix.sendMessage...")
                let phoenixMessage = try await environment.realtime.sendMessage(threadID, text, currentUser, nil)
                print("✅ [SEND] Phoenix confirmed: \(phoenixMessage.id.uuidString)")
                
                // 4. Update status to "sent" in local DB
                var updatedMessage = localMessage
                updatedMessage.status = .sent
                try await environment.database.storeMessage(updatedMessage)
                
                print("✅ [SEND] Status updated to sent: \(localMessage.id.uuidString)")
                
                // 5. Update UI with sent status
                send(.messageStatusUpdated(localMessage.id, .sent))
                
            } catch {
                print("❌ [SEND] Phoenix send failed: \(error.localizedDescription)")
                
                // Message is already saved locally with .sending status
                // Update to .failed so user knows and it can be retried
                // (In production, offline queue would retry automatically)
                send(.messageSent(.failure(error)))
            }
        }

    case let .messageStatusUpdated(messageId, newStatus):
        // Update message status in UI
        if let index = state.chat.messages.firstIndex(where: { $0.id == messageId }) {
            state.chat.messages[index].status = newStatus
            print("✅ [STATUS] Updated message \(messageId) to \(newStatus.rawValue)")
        }
        return .none

    case let .messageSent(result):
        state.chat.composer.isSending = false
        switch result {
        case let .success(message):
            if !state.chat.messages.contains(where: { $0.id == message.id }) {
                state.chat.messages.append(message)
            }
        case let .failure(error):
            state.chat.messageError = error.localizedDescription
        }
        return .none

    case let .receiveRealtimeMessage(message):
        guard state.chat.currentThread?.id == message.threadId else {
            if let index = state.threads.items.firstIndex(where: { $0.id == message.threadId }) {
                state.threads.items[index].lastMessageAt = message.createdAt
                state.threads.items[index].updatedAt = message.updatedAt
                let updatedThread = state.threads.items.remove(at: index)
                state.threads.items.insert(updatedThread, at: 0)
            }
            return .fireAndForget {
                try? await environment.database.storeMessage(message)
            }
        }
        if !state.chat.messages.contains(where: { $0.id == message.id }) {
            state.chat.messages.append(message)
            if let index = state.threads.items.firstIndex(where: { $0.id == message.threadId }) {
                state.threads.items[index].lastMessageAt = message.createdAt
                state.threads.items[index].updatedAt = message.updatedAt
                let updatedThread = state.threads.items.remove(at: index)
                state.threads.items.insert(updatedThread, at: 0)
                state.chat.currentThread = updatedThread
            }
        }
        return .fireAndForget {
            try? await environment.database.storeMessage(message)
        }

    case let .typingIndicator(threadID, userID, isTyping):
        guard state.chat.currentThread?.id == threadID,
              userID != state.user.id
        else { return .none }
        if isTyping {
            state.chat.typingUsers.insert(userID)
        } else {
            state.chat.typingUsers.remove(userID)
        }
        return .none

    case let .handleOrphanedThread(threadID):
        print("🗑️ [ORPHAN] Handling orphaned thread: \(threadID)")

        // Remove the orphaned thread from the local list
        if let index = state.threads.items.firstIndex(where: { $0.id == threadID }) {
            let orphanedThread = state.threads.items[index]
            state.threads.items.remove(at: index)
            print("🗑️ [ORPHAN] Removed thread from list: \(orphanedThread.title ?? "Untitled")")

            // If this was the selected thread, select the first available thread
            if state.threads.selectedThreadID == threadID {
                if let firstThread = state.threads.items.first {
                    print("🔄 [ORPHAN] Selecting first available thread: \(firstThread.id)")
                    state.threads.selectedThreadID = firstThread.id
                    state.chat.currentThread = firstThread
                    return .run(priority: nil) { send in
                        send(.loadMessages(firstThread.id))
                    }
                } else {
                    print("⚠️ [ORPHAN] No threads available after removal")
                    state.threads.selectedThreadID = nil
                    state.chat.currentThread = nil
                    state.chat.messages = []
                }
            }
        }

        // Show error message to user
        state.threads.errorMessage = "This conversation is no longer available on the server. It has been removed from your list."

        return .none
    }
}
