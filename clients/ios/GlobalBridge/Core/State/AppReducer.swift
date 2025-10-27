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
            // CRITICAL: Wait for session restoration to complete first
            print("⏳ [STARTUP] Waiting for session restoration...")
            await AuthManager.shared.ensureSessionRestored()
            print("✅ [STARTUP] Session restoration complete")

            let isAuthenticated = AuthManager.shared.isAuthenticated
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
                send(.connectionStateChanged(.connecting))
                try await environment.realtime.ensureConnection()
                print("✅ [STARTUP] Phoenix connected")
                send(.connectionStateChanged(.connected))
                
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

            // Cache users from bootstrap
            for (userId, userInfo) in result.users {
                state.userCache[userId] = userInfo
                print("👤 [CACHE] Cached user from bootstrap: \(userId) - \(userInfo.effectiveDisplayName)")
            }
            print("👥 [LOADED] Cached \(result.users.count) users from bootstrap")

            state.threads.items = result.threads
            print("📋 [LOADED] Loaded \(result.threads.count) threads - showing list (not auto-selecting)")

            // Don't auto-select any thread - let user choose from the list
            // This provides better UX similar to WhatsApp/iMessage
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

        // If selecting the same thread, ensure connection and load messages if empty
        if state.threads.selectedThreadID == threadID {
            print("ℹ️ [ACTION] Thread already selected: \(threadID)")
            
            // If we have no messages loaded, we need to load them
            if state.chat.messages.isEmpty {
                print("📥 [ACTION] Messages empty for already-selected thread, loading...")
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
                            print("❌ [ACTION] Connection failed: \(error.localizedDescription)")
                        }
                    }
                )
            } else {
                // Just ensure connection, don't reload messages
                print("ℹ️ [ACTION] Messages already loaded, just ensuring connection")
                let needsFetch = state.chat.needsHistoricalFetch  // Capture before async
                if needsFetch {
                    state.chat.needsHistoricalFetch = false  // Clear immediately
                }
                
                return .run(priority: nil) { send in
                    do {
                        try await environment.realtime.ensureConnection()
                        try await environment.realtime.connect(threadID) { message in
                            Task { @MainActor in
                                send(.receiveRealtimeMessage(message))
                            }
                        }
                        await environment.sync.syncThread(threadID)
                        
                        // Fetch historical messages if needed
                        if needsFetch {
                            send(.fetchHistoricalMessages(threadID))
                        }
                    } catch {
                        print("❌ [ACTION] Connection failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        print("✅ [ACTION] threadSelected guard passed, switching to thread: \(thread.title ?? "Untitled")")

        let previousThreadID = state.threads.selectedThreadID
        state.threads.selectedThreadID = threadID
        state.chat.currentThread = thread
        // Don't clear messages immediately if we're switching threads - let loadMessages handle it
        // This prevents the jarring empty state when messages are already loading
        if state.chat.currentThread?.id != threadID {
            state.chat.messages = []
        }
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
                    
                    // Check if we need to fetch historical messages (after channel is joined!)
                    print("📥 [ACTION] Channel joined, calling fetchHistoricalMessages...")
                    send(.fetchHistoricalMessages(threadID))
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
        guard state.chat.currentThread?.id == threadID else {
            print("⚠️ [MESSAGES] Thread mismatch! Current: \(state.chat.currentThread?.id.uuidString ?? "nil"), Loaded for: \(threadID)")
            return .none
        }
        state.chat.isLoadingMessages = false
        state.chat.isLoadingOlderMessages = false
        switch result {
        case let .success(messages):
            print("📊 [MESSAGES] Loaded \(messages.count) messages from local DB for thread: \(threadID)")
            state.chat.messages = messages.sorted(by: { $0.createdAt < $1.createdAt })
            
            // Update hasMoreMessages flag (if less than page size, we've hit the end)
            if messages.count < 50 {
                state.chat.hasMoreMessages = false
                print("📄 [MESSAGES] Reached end of history (loaded \(messages.count) < 50)")
            }
            
            // Check if we have user info for message senders
            let senderIds = Set(messages.map { $0.senderId })
            let missingUsers = senderIds.filter { state.userCache[$0] == nil }
            
            if !missingUsers.isEmpty {
                print("👥 [MESSAGES] Missing user info for \(missingUsers.count) senders, will fetch...")
                state.chat.needsHistoricalFetch = true  // Set flag to trigger user info fetch
            }
            
            // Mark if we need to fetch messages from backend
            if messages.isEmpty {
                print("⚠️ [MESSAGES] Local DB empty - SETTING needsHistoricalFetch = true")
                state.chat.needsHistoricalFetch = true
            } else if !missingUsers.isEmpty {
                print("⚠️ [MESSAGES] Have messages but missing user info - SETTING fetch flag")
            } else {
                print("✅ [MESSAGES] Messages loaded with all user info present")
            }
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

                // 6. Fire-and-forget: Trigger style learning for AI personalization
                Task {
                    await environment.phoenixManager?.triggerStyleLearning(
                        messageId: localMessage.id.uuidString,
                        threadId: threadID.uuidString
                    )
                }

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
            // This is our own message coming back from server - replace with server version
            print("🔄 [RECEIVE] Replacing local message \(clientMsgId) with server ID: \(message.id)")
            
            // Update in memory
            state.chat.messages[existingIndex] = message
            
            // CRITICAL: Delete old client message and store server message
            return .fireAndForget {
                do {
                    // Delete the old client-generated message
                    print("🗑️ [RECEIVE] Deleting client message: \(clientUUID)")
                    try await DatabaseManager.shared.deleteMessage(id: clientUUID, threadId: message.threadId)
                    
                    // Store the server message
                    print("💾 [RECEIVE] Storing server message: \(message.id)")
                    try await environment.database.storeMessage(message)
                    print("✅ [RECEIVE] Deduplication complete - old deleted, new stored")
                } catch {
                    print("⚠️ [RECEIVE] Deduplication error: \(error)")
                }
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

    case let .receiveRealtimeThread(thread):
        print("📥 [REALTIME] Received new thread: \(thread.id) - \(thread.title ?? "Untitled")")

        // Check if thread already exists
        if state.threads.items.contains(where: { $0.id == thread.id }) {
            print("⏭️ [REALTIME] Thread already exists, skipping: \(thread.id)")
            return .none
        }

        // Add thread to the beginning of the list
        state.threads.items.insert(thread, at: 0)
        print("✅ [REALTIME] Added new thread to list")

        // Persist to database
        return .fireAndForget {
            do {
                try await environment.database.saveThread(thread)
                print("💾 [REALTIME] Thread persisted to database")
            } catch {
                print("❌ [REALTIME] Failed to persist thread: \(error)")
            }
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
    
    case let .createDirectMessage(userId, displayName, username):
        print("💬 [DM] Creating direct message with user: \(userId)")
        
        // Cache user info for display name lookup
        state.userCache[userId] = CachedUserInfo(
            id: userId,
            displayName: displayName,
            username: username,
            avatarUrl: nil
        )
        return .run(priority: nil) { send in
            do {
                let threadData = try await environment.realtime.createDirectMessage(userId)
                print("✅ [DM] Backend created DM: \(threadData.id)")
                
                // Convert ThreadData to Thread
                guard let parsedId = UUID(uuidString: threadData.id) else {
                    print("❌ [DM] Invalid thread UUID from backend: \(threadData.id)")
                    throw NSError(domain: "ThreadCreation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid thread id"])
                }
                let thread = Thread(
                    id: parsedId,
                    threadType: Thread.ThreadType(rawValue: threadData.threadType) ?? .direct,
                    title: threadData.title,
                    avatarUrl: nil,
                    lastMessageAt: threadData.lastMessageAt,
                    isArchived: threadData.isArchived,
                    isMuted: threadData.isMuted,
                    databaseShardId: threadData.databaseShardId,
                    participantIds: threadData.participantIds,  // Include for DM name display
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
            
            // IMPORTANT: Save thread to database before loading messages
            // Otherwise fetchMessages will fail because thread doesn't exist locally
            let threadID = thread.id
            return .merge(
                .run(priority: nil) { send in
                    do {
                        print("💾 [DM] Saving thread to local database...")
                        try await environment.database.saveThread(thread)
                        print("✅ [DM] Thread saved locally")
                        send(.loadMessages(threadID))
                    } catch {
                        print("❌ [DM] Failed to save thread: \(error)")
                        send(.messagesLoaded(threadID, .failure(error)))
                    }
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
                guard let parsedGroupId = UUID(uuidString: threadData.id) else {
                    print("❌ [GROUP] Invalid thread UUID from backend: \(threadData.id)")
                    throw NSError(domain: "ThreadCreation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid thread id"])
                }
                let thread = Thread(
                    id: parsedGroupId,
                    threadType: Thread.ThreadType(rawValue: threadData.threadType) ?? .group,
                    title: threadData.title,
                    avatarUrl: nil,
                    lastMessageAt: threadData.lastMessageAt,
                    isArchived: threadData.isArchived,
                    isMuted: threadData.isMuted,
                    databaseShardId: threadData.databaseShardId,
                    participantIds: threadData.participantIds,  // Include participants
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
            
            // IMPORTANT: Save thread to database before loading messages
            let threadID = thread.id
            return .merge(
                .run(priority: nil) { send in
                    do {
                        print("💾 [GROUP] Saving thread to local database...")
                        try await environment.database.saveThread(thread)
                        print("✅ [GROUP] Thread saved locally")
                        send(.loadMessages(threadID))
                    } catch {
                        print("❌ [GROUP] Failed to save thread: \(error)")
                        send(.messagesLoaded(threadID, .failure(error)))
                    }
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
    
    case let .fetchHistoricalMessages(threadID):
        print("🎯 [FETCH] fetchHistoricalMessages called for thread: \(threadID)")
        print("   Current thread: \(state.chat.currentThread?.id.uuidString ?? "nil")")
        print("   Messages empty: \(state.chat.messages.isEmpty)")
        print("   Needs fetch flag: \(state.chat.needsHistoricalFetch)")
        
        // Only fetch if needed (flag must be set, thread must match)
        guard state.chat.currentThread?.id == threadID,
              state.chat.needsHistoricalFetch else {
            print("⚠️ [FETCH] Skipping - flag not set or thread mismatch")
            return .none
        }
        
        print("📥 [FETCH] ✅ Fetching from backend (for messages and/or user info)...")
        state.chat.needsHistoricalFetch = false  // Clear flag
        
        // Get participant IDs to populate user cache
        let participantIds = state.chat.currentThread?.participantIds ?? []
        
        return .run(priority: nil) { send in
            do {
                // Fetch most recent 20 messages for fast initial display (pagination loads more on scroll)
                let result = try await environment.realtime.fetchMessages(threadID, 20)
                print("✅ [FETCH] Fetched \(result.messages.count) messages + \(result.users.count) users from backend")
                
                // Convert BasicUserInfo to CachedUserInfo and cache via action
                let usersToCache = result.users.mapValues { userInfo in
                    CachedUserInfo(
                        id: userInfo.id,
                        displayName: userInfo.displayName,
                        username: userInfo.username,
                        avatarUrl: userInfo.avatarUrl
                    )
                }
                
                // Update user cache first (critical for names to show!)
                if !usersToCache.isEmpty {
                    print("👤 [FETCH] Caching \(usersToCache.count) users...")
                    send(.cacheUsers(usersToCache))
                } else {
                    print("⚠️ [FETCH] No users returned from backend!")
                }
                
                // Store messages locally (only if we fetched any)
                if !result.messages.isEmpty {
                    print("💾 [FETCH] Batch storing \(result.messages.count) messages...")

                    // Convert all Phoenix messages to Message objects
                    let messages = result.messages.compactMap { Message.fromPhoenix($0) }

                    if !messages.isEmpty {
                        // Use batch insert for much better performance (single transaction, no UI blocking)
                        try? await environment.database.batchStoreMessages(messages, threadID)
                    }

                    // Reload from local DB to show in UI with user names
                    print("🔄 [FETCH] Reloading messages to display with names...")
                    send(.loadMessages(threadID))
                } else {
                    print("ℹ️ [FETCH] No new messages, user cache updated (names should update)")
                }
            } catch {
                print("⚠️ [FETCH] Backend fetch failed: \(error.localizedDescription)")
            }
        }
    
    case let .connectionStateChanged(newState):
        state.connectionState = newState
        return .none
    
    case let .cacheUsers(users):
        for (userId, userInfo) in users {
            state.userCache[userId] = userInfo
            print("👤 [CACHE] Added user: \(userId)")
            print("   - displayName: \(userInfo.displayName ?? "nil")")
            print("   - username: \(userInfo.username)")
            print("   - effectiveDisplayName: \(userInfo.effectiveDisplayName)")
        }
        return .none
    
    case let .loadOlderMessages(threadID):
        guard state.chat.currentThread?.id == threadID,
              !state.chat.isLoadingOlderMessages,
              state.chat.hasMoreMessages else {
            print("ℹ️ [PAGINATION] Skipping - already loading or no more messages")
            return .none
        }
        
        print("📄 [PAGINATION] Loading older messages for thread: \(threadID)")
        state.chat.isLoadingOlderMessages = true
        
        // Get the oldest message timestamp to fetch before it
        let oldestTimestamp = state.chat.messages.first?.createdAt
        
        return .run(priority: nil) { send in
            do {
                // Fetch next 50 messages before oldest message
                let result = try await environment.realtime.fetchMessages(threadID, 50)
                print("✅ [PAGINATION] Fetched \(result.messages.count) older messages")
                
                // Cache any new users
                let usersToCache = result.users.mapValues { userInfo in
                    CachedUserInfo(
                        id: userInfo.id,
                        displayName: userInfo.displayName,
                        username: userInfo.username,
                        avatarUrl: userInfo.avatarUrl
                    )
                }
                if !usersToCache.isEmpty {
                    send(.cacheUsers(usersToCache))
                }
                
                // Store new messages
                if !result.messages.isEmpty {
                    print("💾 [PAGINATION] Batch storing \(result.messages.count) messages...")
                    let messages = result.messages.compactMap { Message.fromPhoenix($0) }
                    if !messages.isEmpty {
                        // Use batch insert for better performance
                        try? await environment.database.batchStoreMessages(messages, threadID)
                    }
                }

                // Reload to include new older messages
                send(.loadMessages(threadID))
            } catch {
                print("⚠️ [PAGINATION] Failed to load older messages: \(error.localizedDescription)")
                // Error state will be cleared on next messagesLoaded
            }
        }

    // MARK: - AI Features

    // MARK: Smart Reply Actions

    case let .fetchSmartReplies(threadId):
        // Set loading state for this thread
        state.smartReplyLoading[threadId] = true
        state.smartReplyErrors[threadId] = nil

        print("🤖 [SMART_REPLY] Fetching suggestions for thread: \(threadId)")

        return .run(priority: nil) { send in
            do {
                // Convert threadId String to UUID
                guard let threadUUID = UUID(uuidString: threadId) else {
                    throw AIServiceError.invalidInput(reason: "Invalid thread ID format")
                }

                let suggestions = try await SmartReplyService.shared.fetchSuggestions(
                    threadId: threadUUID,
                    limit: 3
                )
                print("✅ [SMART_REPLY] Received \(suggestions.count) suggestions")
                send(.smartRepliesReceived(threadId: threadId, .success(suggestions)))
            } catch {
                print("❌ [SMART_REPLY] Failed to fetch suggestions: \(error)")
                send(.smartRepliesReceived(threadId: threadId, .failure(error)))
            }
        }

    case let .smartRepliesReceived(threadId, result):
        // Clear loading state
        state.smartReplyLoading[threadId] = false

        switch result {
        case let .success(suggestions):
            // Update suggestions for this thread
            state.smartReplySuggestions[threadId] = suggestions
            state.smartReplyErrors[threadId] = nil
            print("✅ [SMART_REPLY] Stored \(suggestions.count) suggestions for thread: \(threadId)")

        case let .failure(error):
            // Store error for this thread
            state.smartReplyErrors[threadId] = error.localizedDescription
            print("❌ [SMART_REPLY] Error for thread \(threadId): \(error.localizedDescription)")
        }
        return .none

    case let .acceptSuggestion(threadId, suggestion, modifiedContent):
        // Insert suggestion content into composer
        let content = modifiedContent ?? suggestion.content
        state.chat.composer.text = content

        print("✅ [SMART_REPLY] Accepted suggestion: \(suggestion.id)")

        // Record feedback asynchronously
        let feedback = SuggestionFeedback(
            suggestionId: suggestion.id,
            accepted: true,
            modifiedContent: modifiedContent,
            rejectionReason: nil,
            timeToResponseMs: nil,
            timestamp: Date()
        )

        return .run(priority: nil) { send in
            send(.recordFeedback(feedback))
        }

    case let .rejectSuggestion(threadId, suggestionId, reason):
        print("❌ [SMART_REPLY] Rejected suggestion: \(suggestionId), reason: \(reason ?? "none")")

        // Remove rejected suggestion from state
        if var suggestions = state.smartReplySuggestions[threadId] {
            suggestions.removeAll { $0.id == suggestionId }
            state.smartReplySuggestions[threadId] = suggestions
        }

        // Record rejection feedback
        let feedback = SuggestionFeedback(
            suggestionId: suggestionId,
            accepted: false,
            modifiedContent: nil,
            rejectionReason: reason,
            timeToResponseMs: nil,
            timestamp: Date()
        )

        return .run(priority: nil) { send in
            send(.recordFeedback(feedback))
        }

    case let .recordFeedback(feedback):
        print("📊 [SMART_REPLY] Recording feedback for suggestion: \(feedback.suggestionId)")

        return .run(priority: nil) { _ in
            do {
                try await SmartReplyService.shared.recordFeedback(feedback)
                print("✅ [SMART_REPLY] Feedback recorded successfully")
            } catch {
                print("⚠️  [SMART_REPLY] Failed to record feedback: \(error)")
            }
        }

    // MARK: Conversation Monitoring Actions

    case let .toggleMonitoring(threadId):
        // Toggle thread in/out of monitored set
        if state.monitoredThreads.contains(threadId) {
            state.monitoredThreads.remove(threadId)
            print("👁️  [MONITORING] Disabled monitoring for thread: \(threadId)")
        } else {
            state.monitoredThreads.insert(threadId)
            print("👁️  [MONITORING] Enabled monitoring for thread: \(threadId)")
        }
        return .none

    case let .startMonitoring(threadId):
        // Add thread to monitored set
        state.monitoredThreads.insert(threadId)
        print("👁️  [MONITORING] Started monitoring thread: \(threadId)")
        return .none

    case let .stopMonitoring(threadId):
        // Remove thread from monitored set
        state.monitoredThreads.remove(threadId)
        print("👁️  [MONITORING] Stopped monitoring thread: \(threadId)")
        return .none

    case let .aiSuggestionBroadcast(threadId, suggestion):
        // Handle proactive AI suggestion from broadcast
        print("📡 [AI_BROADCAST] Received proactive suggestion for thread: \(threadId)")
        print("   - Suggestion ID: \(suggestion.id)")
        print("   - Type: \(suggestion.type)")
        print("   - Content: \(suggestion.content)")

        // Add to suggestions for this thread
        var suggestions = state.smartReplySuggestions[threadId] ?? []
        // Avoid duplicates
        if !suggestions.contains(where: { $0.id == suggestion.id }) {
            suggestions.append(suggestion)
            state.smartReplySuggestions[threadId] = suggestions
            print("✅ [AI_BROADCAST] Added proactive suggestion to state")
        } else {
            print("⚠️  [AI_BROADCAST] Suggestion already exists in state")
        }

        return .none

    // MARK: Translation Actions

    case let .translateMessage(messageId, targetLanguage):
        print("🌐 [TRANSLATION] Translating message: \(messageId) to \(targetLanguage)")

        return .run(priority: nil) { send in
            do {
                // Find message text (would need to look it up from state or database)
                // For now, this is a placeholder - actual implementation would fetch message
                let translatedText = try await AIService.shared.translate(
                    text: "Sample text", // TODO: Get actual message text
                    targetLanguage: targetLanguage
                ).translatedText

                send(.translationReceived(messageId: messageId, .success(translatedText)))
            } catch {
                print("❌ [TRANSLATION] Failed: \(error)")
                send(.translationReceived(messageId: messageId, .failure(error)))
            }
        }

    case let .translationReceived(messageId, result):
        switch result {
        case let .success(translatedText):
            state.messageTranslations[messageId] = translatedText
            print("✅ [TRANSLATION] Stored translation for message: \(messageId)")

        case let .failure(error):
            print("❌ [TRANSLATION] Error for message \(messageId): \(error.localizedDescription)")
        }
        return .none

    case let .updateTranslationPreferences(preferences):
        state.translationPreferences = preferences
        print("✅ [TRANSLATION] Updated preferences: auto-translate=\(preferences.autoTranslateEnabled)")
        return .none

    // MARK: Thread-Specific Translation Settings

    case let .updateThreadTranslationSettings(threadId, settings):
        state.threadTranslationSettings[threadId] = settings
        print("✅ [THREAD_TRANSLATION] Updated settings for thread \(threadId):")
        print("   - Target language: \(settings.targetLanguage)")
        print("   - Show suggestions: \(settings.showSuggestions)")
        print("   - Formality: \(settings.defaultFormality.displayName)")
        print("   - Auto-translate incoming: \(settings.autoTranslateIncoming)")
        print("   - Translation mode: \(settings.translationMode.displayName)")
        // TODO: Persist to UserDefaults or backend
        return .none

    case let .toggleShowSuggestions(threadId):
        var settings = state.threadTranslationSettings[threadId] ?? .default
        settings.showSuggestions.toggle()
        state.threadTranslationSettings[threadId] = settings
        print("✅ [THREAD_TRANSLATION] Toggled show suggestions for thread \(threadId): \(settings.showSuggestions)")
        return .none

    case let .setTranslationMode(threadId, mode):
        var settings = state.threadTranslationSettings[threadId] ?? .default
        settings.translationMode = mode
        state.threadTranslationSettings[threadId] = settings
        print("✅ [THREAD_TRANSLATION] Set translation mode for thread \(threadId): \(mode.displayName)")
        return .none

    case let .setFormality(threadId, level):
        var settings = state.threadTranslationSettings[threadId] ?? .default
        settings.defaultFormality = level
        state.threadTranslationSettings[threadId] = settings
        print("✅ [THREAD_TRANSLATION] Set formality for thread \(threadId): \(level.displayName)")
        return .none

    case let .toggleAutoTranslateIncoming(threadId):
        var settings = state.threadTranslationSettings[threadId] ?? .default
        settings.autoTranslateIncoming.toggle()
        state.threadTranslationSettings[threadId] = settings
        print("✅ [THREAD_TRANSLATION] Toggled auto-translate incoming for thread \(threadId): \(settings.autoTranslateIncoming)")
        return .none

    case let .setThreadTargetLanguage(threadId, language):
        var settings = state.threadTranslationSettings[threadId] ?? .default
        settings.targetLanguage = language
        state.threadTranslationSettings[threadId] = settings
        print("✅ [THREAD_TRANSLATION] Set target language for thread \(threadId): \(language)")
        return .none

    // MARK: Style Learning Actions

    case let .styleProfileUpdated(profile):
        state.userStyleProfile = profile
        print("✅ [STYLE] Updated user style profile")
        return .none

    case .fetchStyleProfile:
        print("🎨 [STYLE] Fetching user style profile")
        return .run(priority: nil) { send in
            // TODO: Implement actual style profile fetch from backend
            // For now, placeholder implementation
            print("⚠️  [STYLE] Style profile fetch not yet implemented")
        }

    case .styleProfileReceived:
        // TODO: Handle style profile received result
        print("🎨 [STYLE] Style profile received")
        return .none

    case .toggleStyleLearning:
        state.styleLearningEnabled.toggle()
        print("🎨 [STYLE] Style learning \(state.styleLearningEnabled ? "enabled" : "disabled")")
        return .none

    // MARK: AI Insights Actions

    case .toggleInsightsVisible:
        state.aiInsightsVisible.toggle()
        print("👁️  [INSIGHTS] Toggled insights visible: \(state.aiInsightsVisible)")
        return .none

    case let .setCurrentThread(threadId):
        state.currentThreadId = threadId
        print("📍 [INSIGHTS] Set current thread: \(threadId ?? "nil")")
        return .none

    // MARK: Thread Summarization Actions

    case let .fetchThreadSummary(threadId):
        state.threadSummaryLoading[threadId] = true
        state.threadSummaryErrors[threadId] = nil
        print("📝 [SUMMARY] Fetching summary for thread: \(threadId)")

        return .run(priority: nil) { send in
            do {
                let summary = try await AIService.shared.summarizeThread(threadId: threadId)
                send(.threadSummaryReceived(threadId: threadId, .success(summary)))
            } catch {
                print("❌ [SUMMARY] Failed to fetch summary: \(error.localizedDescription)")
                send(.threadSummaryReceived(threadId: threadId, .failure(error)))
            }
        }

    case let .threadSummaryReceived(threadId, result):
        state.threadSummaryLoading[threadId] = false

        switch result {
        case let .success(summary):
            state.threadSummaries[threadId] = summary
            state.threadSummaryErrors[threadId] = nil
            print("✅ [SUMMARY] Received summary for thread \(threadId): \(summary.summary.prefix(100))...")

        case let .failure(error):
            state.threadSummaryErrors[threadId] = error.localizedDescription
            print("❌ [SUMMARY] Summary error for thread \(threadId): \(error.localizedDescription)")
        }
        return .none

    case let .clearThreadSummary(threadId):
        state.threadSummaries.removeValue(forKey: threadId)
        state.threadSummaryErrors.removeValue(forKey: threadId)
        print("🗑️  [SUMMARY] Cleared summary for thread: \(threadId)")
        return .none

    // MARK: User Preferences

    case let .setUserLanguage(languageCode):
        state.userLanguage = languageCode
        print("🌐 [SETTINGS] Set user language: \(languageCode)")
        // TODO: Persist to UserDefaults or backend
        return .none

    case let .updateUserDisplayName(newName):
        state.user.displayName = newName
        print("👤 [SETTINGS] Updated user display name: \(newName)")

        // Update in user cache as well (so it shows correctly in UI immediately)
        state.userCache[state.user.id] = CachedUserInfo(
            id: state.user.id,
            displayName: newName,
            username: state.user.handle,
            avatarUrl: state.user.avatarURL?.absoluteString
        )

        return .none
    }
}
