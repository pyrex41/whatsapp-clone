//
//  ChatScreen.swift
//  GlobalBridge
//

import SwiftUI

struct ChatScreen: View {
    @ObservedObject var store: Store<AppState, AppAction>
    @FocusState private var composerFocused: Bool

    private var chatState: ChatState { store.state.chat }

    var body: some View {
        let _ = print("🎨 [CHAT_VIEW] Rendering ChatScreen - currentThread: \(chatState.currentThread?.id.uuidString ?? "nil"), messages count: \(chatState.messages.count)")
        Group {
            if let thread = chatState.currentThread {
                let _ = print("✅ [CHAT_VIEW] Showing chat for thread: \(thread.id) - \(thread.title ?? "Untitled")")
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(chatState.messages, id: \.id) { message in
                                    let isOwn = message.senderId == store.state.user.id
                                    let _ = print("💬 [MESSAGE] id=\(message.id), content=\"\(message.content)\", senderId=\(message.senderId), currentUserId=\(store.state.user.id), isOwn=\(isOwn)")
                                    MessageRow(
                                        message: message,
                                        isOwnMessage: isOwn
                                    )
                                    .id(message.id)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                        }
                        .onChange(of: chatState.messages.count) { _, _ in
                            guard let lastMessage = chatState.messages.last else { return }
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
                    // Try again after a delay to ensure view hierarchy is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("⌨️ [COMPOSER] Delayed focus attempt")
                        composerFocused = true
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(thread.title ?? "Conversation")
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
        .navigationTitle(chatState.currentThread?.title ?? "Messages")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MessageRow: View {
    let message: Message
    let isOwnMessage: Bool

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
        // TODO: Fetch from user lookup - for now show sender ID prefix
        let prefix = message.senderId.prefix(8)
        return "User \(prefix)"
    }
}
