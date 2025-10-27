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
    @State private var smartReplyExpanded = false // Track if suggestions are expanded
    @State private var showTranslationSettings = false // Translation settings sheet
    @State private var showSummary = false // Summary sheet visibility

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
                                let threadId = thread.id.uuidString
                                let threadSettings = store.state.threadTranslationSettings[threadId] ?? .default
                                MessageRow(
                                    message: message,
                                    isOwnMessage: isOwn,
                                    userCache: store.state.userCache,
                                    translationSettings: threadSettings,
                                    phoenixManager: store.environment.phoenixManager,
                                    threadId: threadId,
                                    userBaseLanguage: store.state.userLanguage
                                )
                                .id(message.id)
                                .onAppear { if message.id == chatState.messages.last?.id { isAtBottom = true } }
                                .onDisappear { if message.id == chatState.messages.last?.id { isAtBottom = false } }
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
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
                .onChange(of: smartReplyExpanded) { _, expanded in
                    // Auto-scroll to bottom when suggestions expand to keep them visible
                    if expanded, let lastMessage = chatState.messages.last {
                        // Delay to ensure layout has updated before scrolling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: store.state.smartReplySuggestions[thread.id.uuidString]?.count ?? 0) { oldCount, newCount in
                    // Auto-scroll when suggestions appear or disappear
                    if let lastMessage = chatState.messages.last {
                        let suggestionsAppeared = oldCount == 0 && newCount > 0
                        let suggestionsDisappeared = oldCount > 0 && newCount == 0

                        if suggestionsAppeared || suggestionsDisappeared {
                            // Delay to ensure layout has updated before scrolling
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
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

            // Show smart reply suggestions if enabled in thread settings
            let threadId = thread.id.uuidString
            let threadSettings = store.state.threadTranslationSettings[threadId] ?? .default
            if threadSettings.showSuggestions {
                let hasSuggestions = !(store.state.smartReplySuggestions[threadId] ?? []).isEmpty
                let isLoading = store.state.smartReplyLoading[threadId] ?? false
                let errorText = store.state.smartReplyErrors[threadId] ?? ""
                // Ignore "no messages" error - it's expected for empty threads
                let hasRelevantError = !errorText.isEmpty && !errorText.contains("No messages in thread")

                if hasSuggestions || isLoading || hasRelevantError {
                    smartReplySection(thread: thread)
                } else {
                    // Show standalone translation settings button when no suggestions
                    standaloneTranslationSettingsButton(thread: thread)
                }
            }

            composerSection
        }
        .onAppear { onAppear(thread: thread) }
        .onChange(of: chatState.currentThread?.id) { _, newId in
            InAppBannerCenter.shared.setActiveThread(newId)
            hasFetchedSuggestions = false
            lastFetchTime = nil
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
        let threadSettings = store.state.threadTranslationSettings[threadId] ?? .default

        // Only render if we have suggestions or are loading (performance optimization)
        if !suggestions.isEmpty || isLoadingSuggestions {
            SmartReplyComposerView(
                suggestions: suggestions,
                isLoading: isLoadingSuggestions,
                error: nil, // Error handling done via separate banner below for now
                styleLearningEnabled: store.state.styleLearningEnabled,
                translationMode: threadSettings.translationMode,
                onSuggestionTap: { suggestion, textToInsert, timeToResponseMs in
                    // Pass the text to insert (could be English or Spanish depending on translation mode)
                    let modifiedContent = textToInsert != suggestion.content ? textToInsert : nil
                    store.send(.acceptSuggestion(threadId: threadId, suggestion: suggestion, modifiedContent: modifiedContent))
                    store.send(.recordFeedback(
                        SuggestionFeedback(
                            suggestionId: suggestion.id,
                            accepted: true,
                            modifiedContent: modifiedContent,
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
                onRetry: { refreshSmartReplies(for: thread.id) },
                onExpandToggle: { expanded in
                    smartReplyExpanded = expanded
                },
                onTranslationSettings: {
                    showTranslationSettings = true
                }
            )
            .sheet(isPresented: $showTranslationSettings) {
                TranslationSettingsSheet(
                    settings: .constant(threadSettings),
                    threadId: threadId,
                    onSave: { newSettings in
                        store.send(.updateThreadTranslationSettings(threadId: threadId, settings: newSettings))
                    }
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
            .accessibilityIdentifier("smartReplyChips")
        }
        // Only show error banner for relevant errors (not "no messages" error)
        if let errText = store.state.smartReplyErrors[threadId],
           !errText.isEmpty,
           !errText.contains("No messages in thread") {
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

    /// Standalone translation settings button (shown when suggestions are hidden)
    @ViewBuilder
    private func standaloneTranslationSettingsButton(thread: Thread) -> some View {
        let threadId = thread.id.uuidString
        let threadSettings = store.state.threadTranslationSettings[threadId] ?? .default

        HStack {
            Spacer()
            Button(action: {
                showTranslationSettings = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.caption)
                    Text("Translation Settings")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Translation settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .sheet(isPresented: $showTranslationSettings) {
            TranslationSettingsSheet(
                settings: .constant(threadSettings),
                threadId: threadId,
                onSave: { newSettings in
                    store.send(.updateThreadTranslationSettings(threadId: threadId, settings: newSettings))
                }
            )
        }
    }


    private var composerSection: some View {
        let threadId = chatState.currentThread?.id.uuidString
        let threadSettings = threadId.map { store.state.threadTranslationSettings[$0] ?? .default }

        return MessageComposerView(
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
            isFocused: $composerFocused,
            threadId: threadId,
            phoenixManager: store.environment.phoenixManager,
            translationSettings: threadSettings
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .onChange(of: composerFocused) { old, new in
            print("⌨️ [COMPOSER] Focus changed: \(old) -> \(new)")
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
        // Only show summary button if there are messages in the chat
        if !chatState.messages.isEmpty {
            ToolbarItem(placement: .navigationBarTrailing) {
                let threadIdStr = thread.id.uuidString
                let isLoadingSummary = store.state.threadSummaryLoading[threadIdStr] ?? false
                Button {
                    showSummary = true
                    // Fetch summary if not already loaded or if stale
                    if store.state.threadSummaries[threadIdStr] == nil ||
                       (store.state.threadSummaries[threadIdStr]?.isStale ?? false) {
                        store.send(.fetchThreadSummary(threadId: threadIdStr))
                    }
                } label: {
                    if isLoadingSummary {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "text.bubble")
                            .font(.body)
                    }
                }
                .disabled(isLoadingSummary)
                .accessibilityLabel("View conversation summary")
                .accessibilityHint("Double tap to view AI-generated summary of this conversation")
                .sheet(isPresented: $showSummary) {
                    summarySheet(thread: thread)
                }
            }
        }
    }

    // MARK: - Summary Sheet

    @ViewBuilder
    private func summarySheet(thread: Thread) -> some View {
        let threadIdStr = thread.id.uuidString
        let summary = store.state.threadSummaries[threadIdStr]
        let isLoading = store.state.threadSummaryLoading[threadIdStr] ?? false
        let error = store.state.threadSummaryErrors[threadIdStr]

        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Generating summary...")
                        .padding()
                } else if let error = error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("Failed to generate summary")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            store.send(.fetchThreadSummary(threadId: threadIdStr))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let summary = summary {
                    ThreadSummaryView(
                        summary: summary,
                        onRegenerateTapped: {
                            store.send(.fetchThreadSummary(threadId: threadIdStr))
                        },
                        onExportTapped: {
                            // TODO: Implement export functionality
                            print("📤 [SUMMARY] Export tapped")
                        },
                        onDismissTapped: {
                            showSummary = false
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "No Summary Available",
                        systemImage: "text.bubble",
                        description: Text("Tap the button below to generate a summary")
                    )
                    .overlay(alignment: .bottom) {
                        Button("Generate Summary") {
                            store.send(.fetchThreadSummary(threadId: threadIdStr))
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                    }
                }
            }
            .navigationTitle("Conversation Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSummary = false
                    }
                }
            }
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

        // Fetch suggestions immediately (no artificial delay)
        Task {
            await MainActor.run {
                fetchSmartRepliesIfNeeded(for: thread.id)
            }
        }

        // Always start monitoring for all threads
        Task {
            do {
                try await ConversationMonitorService.shared.startMonitoring(threadId: thread.id)
                print("✅ [AI_MONITOR] Started monitoring thread: \(thread.id)")
            } catch {
                print("⚠️ [AI_MONITOR] Failed to start monitoring: \(error)")
            }
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

        // Always stop monitoring when leaving thread
        Task {
            do {
                try await ConversationMonitorService.shared.stopMonitoring(threadId: thread.id)
                print("✅ [AI_MONITOR] Stopped monitoring thread: \(thread.id)")
            } catch {
                print("⚠️ [AI_MONITOR] Failed to stop monitoring: \(error)")
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
    let translationSettings: ThreadTranslationSettings?
    let phoenixManager: PhoenixChannelManager?
    let threadId: String?
    let userBaseLanguage: String

    @State private var translatedText: String?
    @State private var isTranslating = false
    @State private var showingTranslation = false

    private let translationService = BackendTranslationService.shared

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

                // Message bubble with tap gesture
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayText)
                        .padding(12)
                        .background(isOwnMessage ? Color.blue : Color(.systemGray5))
                        .foregroundColor(isOwnMessage ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture {
                            handleMessageTap()
                        }

                    // Translation indicator
                    if showingTranslation {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.caption2)
                            Text("Tap to see original")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    }

                    // Loading indicator
                    if isTranslating {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Translating...")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                    }
                }

                Text(TimestampFormatter.string(for: message.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 260, alignment: isOwnMessage ? .trailing : .leading)

            if !isOwnMessage { Spacer() }
        }
        .padding(.horizontal, 8)
        .task {
            await autoTranslateIfNeeded()
        }
    }

    private var displayText: String {
        if showingTranslation, let translated = translatedText {
            return translated
        }
        return message.content
    }

    private func handleMessageTap() {
        if translatedText != nil {
            // Toggle between original and translated
            withAnimation(.spring(response: 0.3)) {
                showingTranslation.toggle()
            }
        } else if !isOwnMessage {
            // Translate on demand for incoming messages
            Task {
                await translateMessage()
            }
        }
    }

    private func autoTranslateIfNeeded() async {
        // Only auto-translate incoming messages if setting is enabled
        guard let settings = translationSettings,
              !isOwnMessage,
              settings.autoTranslateIncoming else {
            return
        }

        await translateMessage()

        // Show translation by default if auto-translate is enabled
        if translatedText != nil {
            await MainActor.run {
                showingTranslation = true
            }
        }
    }

    private func translateMessage() async {
        guard let settings = translationSettings else {
            return
        }

        isTranslating = true

        do {
            // Use user's base language preference from global settings
            let targetLanguage = userBaseLanguage
            print("🌐 [MESSAGE_TRANSLATION] Translating to user's base language: \(targetLanguage)")

            let result = try await translationService.translate(
                text: message.content,
                targetLanguage: targetLanguage,
                sourceLanguage: nil, // Auto-detect
                context: nil,
                formality: settings.defaultFormality
            )

            // Skip translation if detected source language matches target language
            if result.sourceLanguage == targetLanguage {
                print("⏭️ [MESSAGE_TRANSLATION] Skipping translation: message already in target language (\(targetLanguage))")
                isTranslating = false
                return
            }

            translatedText = result.translatedText
            isTranslating = false
        } catch {
            print("❌ [MESSAGE_TRANSLATION] Failed to translate: \(error)")
            isTranslating = false
        }
    }

    private var senderDisplayName: String {
        // Look up from user cache
        if let cachedUser = userCache[message.senderId] {
            // If we have a display name, use it
            if let displayName = cachedUser.displayName, !displayName.isEmpty {
                return displayName
            }

            // Try to extract a readable name from username
            let username = cachedUser.username

            // Check if username looks like an email
            if username.contains("@") {
                // Extract the part before @ and format it nicely
                let localPart = username.components(separatedBy: "@").first ?? username
                // Remove + aliases (e.g., "name+alias" -> "name")
                let cleanName = localPart.components(separatedBy: "+").first ?? localPart
                // Replace dots and underscores with spaces and capitalize
                let formatted = cleanName
                    .replacingOccurrences(of: ".", with: " ")
                    .replacingOccurrences(of: "_", with: " ")
                    .capitalized
                return formatted
            }

            // Check if username looks like a system ID (e.g., "user_abc123")
            if username.starts(with: "user_") {
                // Extract the part after "user_" and capitalize
                let idPart = String(username.dropFirst(5)) // Remove "user_"
                return "User \(idPart.prefix(8).capitalized)"
            }

            // Otherwise use username as-is
            return username
        }

        // Fallback to sender ID prefix
        let prefix = message.senderId.prefix(8)
        return "User \(prefix)"
    }
}
