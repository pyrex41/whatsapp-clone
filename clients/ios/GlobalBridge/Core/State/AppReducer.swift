//
//  AppReducer.swift
//  GlobalBridge
//

import Foundation

let appReducer: Store<AppState, AppAction>.Reducer = { state, action, environment in
    switch action {
    case .onAppear:
        guard state.threads.hasLoaded == false else { return .none }
        print("📱 [STARTUP] App appeared, checking authentication...")
        return .run(priority: nil) { send in
            send(.checkAuthentication)
        }
    
    case .checkAuthentication:
        print("🔐 [STARTUP] Checking if user is authenticated...")
        return .run(priority: nil) { send in
            let isAuthenticated = await AuthManager.shared.isAuthenticated
            print("🔐 [STARTUP] Auth check result: \(isAuthenticated)")
            send(.authenticationChecked(isAuthenticated: isAuthenticated))
        }
    
    case let .authenticationChecked(isAuthenticated):
        if isAuthenticated {
            print("✅ [STARTUP] User is authenticated, loading data...")
            return .run(priority: nil) { send in
                send(.loadUserAndThreads)
            }
        } else {
            print("🔐 [STARTUP] User not authenticated, triggering login...")
            return .run(priority: nil) { send in
                do {
                    _ = try await AuthManager.shared.login()
                    print("✅ [STARTUP] Login successful")
                    send(.userAuthenticated)
                } catch {
                    print("❌ [STARTUP] Login failed: \(error.localizedDescription)")
                    send(.threadsLoaded(.failure(error)))
                }
            }
        }
    
    case .userAuthenticated:
        print("✅ [STARTUP] User authenticated, loading data...")
        return .run(priority: nil) { send in
            send(.loadUserAndThreads)
        }
    
    case .loadUserAndThreads:
        state.threads.isLoading = true
        state.threads.errorMessage = nil
        
        return Command<AppAction>.run(priority: nil) { send in
            do {
                // Step 1: Connect to Phoenix with authenticated token
                print("🔌 [STARTUP] Connecting to Phoenix...")
                try await environment.realtime.ensureConnection()
                print("✅ [STARTUP] Phoenix connected")
                
                // Step 2: Load user and threads from backend
                print("📥 [STARTUP] Loading user and threads...")
                await environment.sync.initialSync()
                await environment.sync.startMonitoring()
                let result = try await environment.database.loadThreads()
                send(.threadsLoaded(.success(result)))
            } catch {
                print("❌ [STARTUP] Failed to load data: \(error.localizedDescription)")
                send(.threadsLoaded(.failure(error)))
            }
        }

    case let .threadsLoaded(result):
        state.threads.isLoading = false
        state.threads.hasLoaded = true
        switch result {
        case let .success(result):
            // Set user from bootstrap
            state.user = result.user
            print("👤 [LOADED] User set: \(result.user.id)")
            
            state.threads.items = result.threads
            if let firstThread = result.threads.first {
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
                            
                            // Now that channel is joined, trigger sync for this thread
                            print("🔄 [LOADED] Triggering sync for first thread after successful channel join")
                            await environment.sync.syncThread(threadID)
                            print("✅ [LOADED] Initial sync complete for first thread")
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
                    
                    // Sync after channel is confirmed joined
                    print("🔄 [ACTION] Syncing thread after re-connection")
                    await environment.sync.syncThread(threadID)
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
                    
                    // Sync after channel is successfully joined
                    print("🔄 [ACTION] Syncing thread after successful channel join")
                    await environment.sync.syncThread(threadID)
                    print("✅ [ACTION] Sync complete for thread: \(threadID)")
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
                let clientId = UUID()
                let localMessage = Message(
                    id: clientId,
                    threadId: threadID,
                    senderId: currentUser.id,
                    content: text,
                    messageType: .text,
                    status: .pending,  // ← Mark as pending/sending
                    createdAt: now,
                    updatedAt: now,
                    clientMessageId: clientId.uuidString  // Track original client ID for dedup
                )
                
                print("💾 [SEND] Saving locally FIRST: \(localMessage.id.uuidString) with status=pending")
                try await environment.database.storeMessage(localMessage)
                
                // 2. Show in UI immediately (optimistic update)
                send(.messageSent(.success(localMessage)))
                
                // 3. Send to backend via Phoenix (include client message ID for deduplication)
                print("📤 [SEND] Calling Phoenix.sendMessage with client ID: \(localMessage.id.uuidString)...")
                let phoenixMessage = try await environment.realtime.sendMessage(threadID, text, currentUser, localMessage.id)
                print("✅ [SEND] Phoenix confirmed - server ID: \(phoenixMessage.id.uuidString), client ID: \(localMessage.id.uuidString)")
                
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
        
        // Check for existing message by client ID (for deduplication)
        if let clientMsgId = message.clientMessageId,
           let clientUUID = UUID(uuidString: clientMsgId),
           let existingIndex = state.chat.messages.firstIndex(where: { $0.id == clientUUID }) {
            // This is our own message coming back from server - update with server ID
            print("🔄 [RECEIVE] Updating local message \(clientMsgId) with server ID: \(message.id)")
            
            // Update the existing message with the server's ID and data
            state.chat.messages[existingIndex] = message
            
            // Update in database
            return .fireAndForget {
                try? await environment.database.storeMessage(message)
            }
        }
        
        // Check if server ID already exists (shouldn't happen but safety check)
        if state.chat.messages.contains(where: { $0.id.uuidString.lowercased() == message.id.uuidString.lowercased() }) {
            print("⏭️ [RECEIVE] Skipping duplicate message by server ID: \(message.id)")
            return .none
        }
        
        // Add the message since it's not a duplicate
        state.chat.messages.append(message)
        if let index = state.threads.items.firstIndex(where: { $0.id == message.threadId }) {
            state.threads.items[index].lastMessageAt = message.createdAt
            state.threads.items[index].updatedAt = message.updatedAt
            let updatedThread = state.threads.items.remove(at: index)
            state.threads.items.insert(updatedThread, at: 0)
            state.chat.currentThread = updatedThread
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

    case let .markMessageRead(threadID, messageID):
        return .fireAndForget {
            await environment.realtime.sendReadReceipt(threadID, messageID)
        }

    case let .sendQuickReply(threadID, text):
        let currentUser = state.user
        return .run(priority: nil) { send in
            do {
                // Optimistic local insert similar to sendMessage
                let now = Date()
                let clientId = UUID()
                let localMessage = Message(
                    id: clientId,
                    threadId: threadID,
                    senderId: currentUser.id,
                    content: text,
                    messageType: .text,
                    status: .pending,
                    createdAt: now,
                    updatedAt: now,
                    clientMessageId: clientId.uuidString  // Track for deduplication
                )
                try await environment.database.storeMessage(localMessage)
                send(.messageSent(.success(localMessage)))

                let serverMessage = try await environment.realtime.sendMessage(threadID, text, currentUser, localMessage.id)
                var updated = localMessage
                updated.status = .sent
                try await environment.database.storeMessage(updated)
                send(.messageStatusUpdated(localMessage.id, .sent))
                // Also deliver the server message shape to maintain consistency
                send(.receiveRealtimeMessage(serverMessage))
            } catch {
                send(.messageSent(.failure(error)))
            }
        }

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
    
    case let .createDirectMessage(userId):
        print("💬 [DM] Creating direct message with user: \(userId)")
        return .run(priority: nil) { send in
            do {
                let threadData = try await environment.realtime.createDirectMessage(userId)
                print("✅ [DM] Backend created DM: \(threadData.id)")
                
                // Convert ThreadData to Thread
                let thread = Thread(
                    id: UUID(uuidString: threadData.id)!,
                    threadType: Thread.ThreadType(rawValue: threadData.threadType) ?? .direct,
                    title: threadData.title,
                    avatarUrl: nil,
                    lastMessageAt: threadData.lastMessageAt,
                    isArchived: threadData.isArchived,
                    isMuted: threadData.isMuted,
                    databaseShardId: threadData.databaseShardId,
                    createdAt: threadData.createdAt,
                    updatedAt: threadData.updatedAt
                )
                
                send(.directMessageCreated(.success(thread)))
            } catch {
                print("❌ [DM] Failed to create: \(error.localizedDescription)")
                send(.directMessageCreated(.failure(error)))
            }
        }
    
    case let .directMessageCreated(result):
        switch result {
        case let .success(thread):
            print("✅ [DM] DM created successfully: \(thread.id)")
            
            // Add to threads list if not already present
            if !state.threads.items.contains(where: { $0.id == thread.id }) {
                state.threads.items.insert(thread, at: 0)
            }
            
            // Select the new thread
            state.threads.selectedThreadID = thread.id
            state.chat.currentThread = thread
            state.chat.messages = []
            state.chat.isLoadingMessages = true
            
            // Join channel and load messages
            let threadID = thread.id
            return .merge(
                .run(priority: nil) { send in
                    send(.loadMessages(threadID))
                },
                .run(priority: nil) { send in
                    do {
                        try await environment.realtime.ensureConnection()
                        try await environment.realtime.connect(threadID) { message in
                            Task { @MainActor in
                                send(.receiveRealtimeMessage(message))
                            }
                        }
                        await environment.sync.syncThread(threadID)
                    } catch {
                        print("❌ [DM] Failed to connect to thread: \(error)")
                    }
                }
            )
            
        case let .failure(error):
            print("❌ [DM] Creation failed: \(error.localizedDescription)")
            state.threads.errorMessage = "Failed to create conversation: \(error.localizedDescription)"
            return .none
        }
    
    case let .createGroupThread(title, participantIds):
        print("👥 [GROUP] Creating group thread: \(title)")
        return .run(priority: nil) { send in
            do {
                let threadData = try await environment.realtime.createGroupThread(title, participantIds)
                print("✅ [GROUP] Backend created group: \(threadData.id)")
                
                // Convert ThreadData to Thread
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
                
                send(.groupThreadCreated(.success(thread)))
            } catch {
                print("❌ [GROUP] Failed to create: \(error.localizedDescription)")
                send(.groupThreadCreated(.failure(error)))
            }
        }
    
    case let .groupThreadCreated(result):
        switch result {
        case let .success(thread):
            print("✅ [GROUP] Group created successfully: \(thread.id)")
            
            // Add to threads list if not already present
            if !state.threads.items.contains(where: { $0.id == thread.id }) {
                state.threads.items.insert(thread, at: 0)
            }
            
            // Select the new thread
            state.threads.selectedThreadID = thread.id
            state.chat.currentThread = thread
            state.chat.messages = []
            state.chat.isLoadingMessages = true
            
            // Join channel and load messages
            let threadID = thread.id
            return .merge(
                .run(priority: nil) { send in
                    send(.loadMessages(threadID))
                },
                .run(priority: nil) { send in
                    do {
                        try await environment.realtime.ensureConnection()
                        try await environment.realtime.connect(threadID) { message in
                            Task { @MainActor in
                                send(.receiveRealtimeMessage(message))
                            }
                        }
                        await environment.sync.syncThread(threadID)
                    } catch {
                        print("❌ [GROUP] Failed to connect to thread: \(error)")
                    }
                }
            )
            
        case let .failure(error):
            print("❌ [GROUP] Creation failed: \(error.localizedDescription)")
            state.threads.errorMessage = "Failed to create group: \(error.localizedDescription)"
            return .none
        }
    }
}
