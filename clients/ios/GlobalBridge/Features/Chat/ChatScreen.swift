//
//  ChatScreen.swift
//  GlobalBridge
//

import SwiftUI

struct ChatScreen: View {
    @ObservedObject var store: Store<AppState, AppAction>

    private var chatState: ChatState { store.state.chat }

    var body: some View {
        Group {
            if let thread = chatState.currentThread {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(chatState.messages, id: \.id) { message in
                                    MessageRow(
                                        message: message,
                                        isOwnMessage: message.senderId == store.state.user.id
                                    )
                                    .id(message.id)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                        }
                        .onChange(of: chatState.messages.count) { _, _ in
                            if let lastMessage = chatState.messages.last {
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
                            store.send(.sendMessage)
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
                Text(message.content)
                    .padding(12)
                    .background(isOwnMessage ? Color.accentColor : Color(.secondarySystemBackground))
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
}
