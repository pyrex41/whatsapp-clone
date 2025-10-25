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

    private var chatState: ChatState { store.state.chat }

    var body: some View {
        let _ = print("🎨 [CHAT_VIEW] Rendering ChatScreen - currentThread: \(chatState.currentThread?.id.uuidString ?? "nil"), messages count: \(chatState.messages.count)")
        Group {
            if let thread = chatState.currentThread {
                let _ = print("✅ [CHAT_VIEW] Showing chat for thread: \(thread.id) - \(thread.title ?? "Untitled")")
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ZStack(alignment: .bottomTrailing) {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                // Load more button at top (for pagination)
                                if chatState.hasMoreMessages && !chatState.messages.isEmpty {
                                    Button {
                                        store.send(.loadOlderMessages(thread.id))
                                    } label: {
                                        HStack {
                                            if chatState.isLoadingOlderMessages {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "arrow.up.circle")
                                            }
                                            Text(chatState.isLoadingOlderMessages ? "Loading..." : "Load older messages")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 8)
                                    }
                                    .disabled(chatState.isLoadingOlderMessages)
                                }
                                
                                ForEach(chatState.messages, id: \.id) { message in
                                    let isOwn = message.senderId == store.state.user.id
                                    let _ = print("🔍 [OWNERSHIP] Message \(message.id) | senderId=\(message.senderId) | currentUserId=\(store.state.user.id) | isOwn=\(isOwn)")
                                    MessageRow(
                                        message: message,
                                        isOwnMessage: isOwn,
                                        userCache: store.state.userCache
                                    )
                                    .id(message.id)
                                    // Track bottom visibility using last item
                                    .onAppear {
                                        if message.id == chatState.messages.last?.id {
                                            isAtBottom = true
                                        }
                                    }
                                    .onDisappear {
                                        if message.id == chatState.messages.last?.id {
                                            isAtBottom = false
                                        }
                                    }
                                }
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                            }
                            // Jump-to-latest floating button when not at bottom
                            if !isAtBottom {
                                Button {
                                    if let lastId = chatState.messages.last?.id {
                                        withAnimation {
                                            proxy.scrollTo(lastId, anchor: .bottom)
                                        }
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
                        }
                        .onChange(of: chatState.messages.count) { _, _ in
                            guard let lastMessage = chatState.messages.last else { return }
                            if !hasAutoScrolled {
                                hasAutoScrolled = true
                                // Initial snap to bottom without animation
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            } else if isAtBottom {
                                // Only auto-scroll on new messages if user is already at bottom
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
                    }
                }
                .onAppear {
                    print("⌨️ [COMPOSER] ChatScreen appeared, setting focus to true")
                    composerFocused = true
                    // Notify banner center of active thread for suppression
                    InAppBannerCenter.shared.setActiveThread(thread.id)
                    // Try again after a delay to ensure view hierarchy is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("⌨️ [COMPOSER] Delayed focus attempt")
                        composerFocused = true
                        // Fallback: ensure we start at bottom when view appears
                        if !hasAutoScrolled, let last = chatState.messages.last?.id {
                            hasAutoScrolled = true
                            // We cannot access proxy here; initial scroll occurs in onChange above when messages load
                            _ = last // no-op to silence warning if optimized out
                        }
                    }
                }
                .onChange(of: chatState.currentThread?.id) { _, newId in
                    InAppBannerCenter.shared.setActiveThread(newId)
                }
                .onDisappear {
                    // Clear active thread when leaving chat
                    InAppBannerCenter.shared.setActiveThread(nil)
                }
                .toolbar {
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
                }
                .overlay {
                    if chatState.isLoadingMessages {
                        ProgressView("Loading messages…")
                    }
                }
            } else {
                let _ = print("⚠️ [CHAT_VIEW] No thread selected - showing placeholder")
                ContentUnavailableView(
                    "Select a thread",
                    systemImage: "bubble.left",
                    description: Text("Choose a conversation from the sidebar to get started.")
                )
            }
        }
        .navigationTitle(chatState.currentThread?.displayName(currentUserId: store.state.user.id, userCache: store.state.userCache) ?? "Messages")
        .navigationBarTitleDisplayMode(.inline)
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
