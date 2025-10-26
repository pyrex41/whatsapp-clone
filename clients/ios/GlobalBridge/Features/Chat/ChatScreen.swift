//
//  ChatScreen.swift
//  GlobalBridge
//

import SwiftUI

struct ChatScreen: View {
    @ObservedObject var store: Store<AppState, AppAction>
    @FocusState private var composerFocused: Bool
    @State private var hasAutoScrolled = false
    @State private var isAtBottom = true
    @State private var hasFetchedSuggestions = false // Track if we've fetched for this thread
    @State private var lastFetchTime: Date? = nil // For debouncing
    @State private var hasInteractedWithComposer = false // Track if user has focused composer
    @State private var smartReplyExpanded = false // Track if suggestions are expanded

    private var chatState: ChatState { store.state.chat }

    var body: some View {
        let _ = print("🎨 [CHAT_VIEW] Rendering ChatScreen")
        content()
            .navigationTitle(chatState.currentThread?.displayName(currentUserId: store.state.user.id, userCache: store.state.userCache) ?? "Messages")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content() -> some View {
        if let thread = chatState.currentThread {
            chatContent(thread: thread)
        } else {
            placeholderContent()
        }
    }

    @ViewBuilder
    private func placeholderContent() -> some View {
        ContentUnavailableView(
            "Select a thread",
            systemImage: "bubble.left",
            description: Text("Choose a conversation from the sidebar to get started.")
        )
    }

    @ViewBuilder
    private func chatContent(thread: Thread) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if chatState.hasMoreMessages && !chatState.messages.isEmpty {
                                loadMoreButton(thread: thread)
                            }
                            ForEach(chatState.messages, id: \.id) { message in
                                let isOwn = message.senderId == store.state.user.id
                                MessageRow(
                                    message: message,
                                    isOwnMessage: isOwn,
                                    userCache: store.state.userCache
                                )
                                .id(message.id)
                                .onAppear { if message.id == chatState.messages.last?.id { isAtBottom = true } }
                                .onDisappear { if message.id == chatState.messages.last?.id { isAtBottom = false } }
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .padding(.bottom, smartReplyExpanded ? 80 : 0) // Extra padding when suggestions expanded
                    }
                    if !isAtBottom {
                        jumpToLatestButton(proxy: proxy)
                    }
                }
                .onChange(of: chatState.messages.count) { _, _ in
                    guard let lastMessage = chatState.messages.last else { return }
                    if !hasAutoScrolled {
                        hasAutoScrolled = true
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    } else if isAtBottom {
                        withAnimation { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
                    }
                }
            }

            if !chatState.typingUsers.isEmpty {
                Text("Someone is typing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            Divider()
            // Only show smart reply suggestions after user has interacted with composer
            if hasInteractedWithComposer {
                smartReplySection(thread: thread)
            }
            composerSection
        }
        .onAppear { onAppear(thread: thread) }
        .onChange(of: chatState.currentThread?.id) { _, newId in
            InAppBannerCenter.shared.setActiveThread(newId)
            hasFetchedSuggestions = false
            lastFetchTime = nil
            hasInteractedWithComposer = false // Reset for new thread
        }
        .onDisappear { onDisappear(thread: thread) }
        .toolbar { toolbar(thread: thread) }
        .overlay {
            if chatState.isLoadingMessages { ProgressView("Loading messages…") }
        }
    }

    // Subsections
    @ViewBuilder
    private func smartReplySection(thread: Thread) -> some View {
        let threadId = thread.id.uuidString
        let suggestions = store.state.smartReplySuggestions[threadId] ?? []
        let isLoadingSuggestions = store.state.smartReplyLoading[threadId] ?? false
        SmartReplyComposerView(
            suggestions: suggestions,
            isLoading: isLoadingSuggestions,
            error: nil, // Error handling done via separate banner below for now
            translationEnabled: false,
            styleLearningEnabled: store.state.styleLearningEnabled,
            onSuggestionTap: { suggestion, timeToResponseMs in
                store.send(.acceptSuggestion(threadId: threadId, suggestion: suggestion, modifiedContent: nil))
                store.send(.recordFeedback(
                    SuggestionFeedback(
                        suggestionId: suggestion.id,
                        accepted: true,
                        modifiedContent: nil,
                        rejectionReason: nil,
                        timeToResponseMs: timeToResponseMs,
                        timestamp: Date()
                    )
                ))
            },
            onSuggestionDismiss: { dismissedSuggestion in
                // TODO: Remove dismissed suggestion from local UI state
                // This is purely UI-level dismissal - no rejection feedback is recorded
                // The suggestion may reappear in future sessions
                print("DEBUG: Suggestion dismissed (UI only): \(dismissedSuggestion.content)")
            },
            onTranslationToggle: {},
            onRetry: { refreshSmartReplies(for: thread.id) },
            onExpandToggle: { expanded in
                smartReplyExpanded = expanded
            }
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .accessibilityIdentifier("smartReplyChips")
        if let errText = store.state.smartReplyErrors[threadId], !errText.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(errText).font(.footnote).foregroundColor(.secondary).lineLimit(2).truncationMode(.tail)
                Spacer()
                Button("Retry") { refreshSmartReplies(for: thread.id) }.buttonStyle(.bordered).font(.footnote)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .accessibilityIdentifier("smartReplyErrorBanner")
        }
    }

    private var composerSection: some View {
        MessageComposerView(
            text: store.binding(
                get: { $0.chat.composer.text },
                send: AppAction.composerTextChanged
            ),
            isSending: chatState.composer.isSending,
            onSend: {
                print("📤 [COMPOSER] Send button tapped")
                store.send(.sendMessage)
                composerFocused = true
            },
            isFocused: $composerFocused
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: composerFocused) { old, new in
            print("⌨️ [COMPOSER] Focus changed: \(old) -> \(new)")
            // Mark that user has interacted with composer (show suggestions)
            if new && !hasInteractedWithComposer {
                hasInteractedWithComposer = true
                print("✨ [SMART_REPLY] User focused composer - showing preloaded suggestions")
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(thread: Thread) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text(thread.displayName(currentUserId: store.state.user.id, userCache: store.state.userCache))
                    .font(.headline)
                if let lastMessageAt = thread.lastMessageAt {
                    Text("Active \(TimestampFormatter.string(for: lastMessageAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            let isMonitored = store.state.monitoredThreads.contains(thread.id.uuidString)
            Button {
                store.send(.toggleMonitoring(threadId: thread.id.uuidString))
            } label: {
                Image(systemName: isMonitored ? "eye.fill" : "eye.slash")
                    .font(.body)
                    .foregroundColor(isMonitored ? .blue : .gray)
            }
            .accessibilityLabel(isMonitored ? "AI monitoring enabled" : "AI monitoring disabled")
            .accessibilityHint("Double tap to toggle AI monitoring for this thread")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            let isLoading = (store.state.smartReplyLoading[thread.id.uuidString] ?? false)
            Button {
                refreshSmartReplies(for: thread.id)
            } label: {
                if isLoading { ProgressView().scaleEffect(0.8) }
                else { Image(systemName: "arrow.clockwise").font(.body) }
            }
            .disabled(isLoading)
            .accessibilityLabel("Refresh smart reply suggestions")
            .accessibilityHint("Double tap to refresh AI suggestions")
        }
    }

    private func loadMoreButton(thread: Thread) -> some View {
        Button {
            store.send(.loadOlderMessages(thread.id))
        } label: {
            HStack {
                if chatState.isLoadingOlderMessages { ProgressView().scaleEffect(0.8) }
                else { Image(systemName: "arrow.up.circle") }
                Text(chatState.isLoadingOlderMessages ? "Loading..." : "Load older messages").font(.caption)
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 8)
        }
        .disabled(chatState.isLoadingOlderMessages)
    }

    private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
        Button {
            if let lastId = chatState.messages.last?.id {
                withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
            }
        } label: {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.white)
                .shadow(radius: 2)
                .padding(10)
                .background(Color.blue.opacity(0.92))
                .clipShape(Circle())
        }
        .padding(.trailing, 12)
        .padding(.bottom, 12)
    }

    // Side-effects extracted
    private func onAppear(thread: Thread) {
        print("⌨️ [COMPOSER] ChatScreen appeared")
        // Don't auto-focus composer - wait for user interaction
        // composerFocused = true  // Removed to prevent auto-showing suggestions
        InAppBannerCenter.shared.setActiveThread(thread.id)
        // Start preloading suggestions in background
        fetchSmartRepliesIfNeeded(for: thread.id)

        // Only start monitoring if enabled for this thread
        let threadIdStr = thread.id.uuidString
        if store.state.monitoredThreads.contains(threadIdStr) {
            Task {
                do {
                    try await ConversationMonitorService.shared.startMonitoring(threadId: thread.id)
                    print("✅ [AI_MONITOR] Started monitoring thread: \(thread.id)")
                } catch {
                    print("⚠️ [AI_MONITOR] Failed to start monitoring: \(error)")
                }
            }
        } else {
            print("ℹ️ [AI_MONITOR] Monitoring disabled for thread: \(thread.id)")
        }

        // Removed delayed auto-focus to prevent auto-showing suggestions
        // User must explicitly tap the composer to see suggestions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !hasAutoScrolled, let _ = chatState.messages.last?.id {
                hasAutoScrolled = true
            }
        }
    }

    private func onDisappear(thread: Thread) {
        InAppBannerCenter.shared.setActiveThread(nil)

        // Only stop monitoring if it was enabled for this thread
        let threadIdStr = thread.id.uuidString
        if store.state.monitoredThreads.contains(threadIdStr) {
            Task {
                do {
                    try await ConversationMonitorService.shared.stopMonitoring(threadId: thread.id)
                    print("✅ [AI_MONITOR] Stopped monitoring thread: \(thread.id)")
                } catch {
                    print("⚠️ [AI_MONITOR] Failed to stop monitoring: \(error)")
                }
            }
        }
    }

    // MARK: - Smart Reply Fetch Helpers

    /// Fetch smart replies if not already fetched for this thread (auto-fetch on open)
    private func fetchSmartRepliesIfNeeded(for threadId: UUID) {
        let threadIdStr = threadId.uuidString

        // Only fetch once per thread load
        guard !hasFetchedSuggestions else {
            print("🤖 [SMART_REPLY] Already fetched for this thread, skipping auto-fetch")
            return
        }

        // Don't fetch if already loading
        if let isLoading = store.state.smartReplyLoading[threadIdStr], isLoading {
            print("🤖 [SMART_REPLY] Already loading, skipping auto-fetch")
            return
        }

        print("🤖 [SMART_REPLY] Auto-fetching suggestions on thread open: \(threadId)")
        hasFetchedSuggestions = true
        lastFetchTime = Date()
        store.send(.fetchSmartReplies(threadId: threadIdStr))
    }

    /// Manually refresh smart replies with debounce (prevent spam)
    private func refreshSmartReplies(for threadId: UUID) {
        let threadIdStr = threadId.uuidString
        let now = Date()

        // Debounce: prevent refreshes within 2 seconds
        if let lastFetch = lastFetchTime, now.timeIntervalSince(lastFetch) < 2.0 {
            print("🤖 [SMART_REPLY] Debouncing refresh (too soon)")
            return
        }

        // Don't refresh if already loading
        if let isLoading = store.state.smartReplyLoading[threadIdStr], isLoading {
            print("🤖 [SMART_REPLY] Already loading, skipping manual refresh")
            return
        }

        print("🤖 [SMART_REPLY] Manual refresh triggered for thread: \(threadId)")
        lastFetchTime = now
        store.send(.fetchSmartReplies(threadId: threadIdStr))
    }
}

private struct MessageRow: View {
    let message: Message
    let isOwnMessage: Bool
    let userCache: [String: CachedUserInfo]

    var body: some View {
        HStack {
            if isOwnMessage { Spacer() }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 6) {
                // Show sender name for messages from others
                if !isOwnMessage {
                    Text(senderDisplayName)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                
                Text(message.content)
                    .padding(12)
                    .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isOwnMessage ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(TimestampFormatter.string(for: message.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 260, alignment: isOwnMessage ? .trailing : .leading)

            if !isOwnMessage { Spacer() }
        }
        .padding(.horizontal, 8)
    }
    
    private var senderDisplayName: String {
        // Look up from user cache
        if let cachedUser = userCache[message.senderId] {
            return cachedUser.effectiveDisplayName
        }
        // Fallback to sender ID prefix
        let prefix = message.senderId.prefix(8)
        return "User \(prefix)"
    }
}
