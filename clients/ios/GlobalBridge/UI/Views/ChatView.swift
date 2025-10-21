//
//  ChatView.swift
//  GlobalBridge
//
//  Main chat view with typing indicators and presence
//

import SwiftUI
import Observation

/// Main chat view displaying messages, typing indicators, and presence
struct ChatView: View {
    @Bindable var phoenixState: PhoenixStateManager
    let conversationId: String
    let currentUserId: String

    @State private var messageText = ""
    @State private var isTyping = false
    @FocusState private var isInputFocused: Bool

    init(
        phoenixState: PhoenixStateManager,
        conversationId: String,
        currentUserId: String
    ) {
        self._phoenixState = Bindable(phoenixState)
        self.conversationId = conversationId
        self.currentUserId = currentUserId
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageCellView(
                            message: message,
                            isOwnMessage: message.senderId == currentUserId,
                            readCount: readReceipts.readCount(for: message.id),
                            totalParticipants: participantCount
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }

            // Typing indicator
            if let typingText = typingState.typingText(currentUserId: currentUserId) {
                TypingIndicatorView(typingText: typingText)
                    .padding(.horizontal, 8)
            }

            // Message input
            HStack(spacing: 12) {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onChange(of: messageText) { oldValue, newValue in
                        handleTypingChange(newValue: newValue)
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(conversationTitle)
                        .font(.headline)

                    if let presence = primaryUserPresence {
                        PresenceTextView(
                            status: presence.status,
                            lastSeen: presence.lastSeen
                        )
                    }
                }
            }
        }
        .onAppear {
            Task {
                try? await phoenixState.joinConversation(conversationId)
            }
        }
        .onDisappear {
            Task {
                await phoenixState.leaveConversation(conversationId)
            }
        }
    }

    // MARK: - Computed Properties

    private var messages: [PhoenixMessage] {
        phoenixState.getMessages(for: conversationId)
    }

    private var typingState: TypingState {
        phoenixState.getTypingState(for: conversationId)
    }

    private var readReceipts: ReadReceiptState {
        phoenixState.getReadReceiptState(for: conversationId)
    }

    private var presences: [String: UserPresence] {
        phoenixState.getPresence(for: conversationId)
    }

    private var primaryUserPresence: UserPresence? {
        presences.values.first
    }

    private var conversationTitle: String {
        "Chat" // TODO: Get from conversation data
    }

    private var participantCount: Int {
        presences.count + 1 // Including current user
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let content = messageText
        messageText = ""

        Task {
            try? await phoenixState.sendMessage(
                conversationId: conversationId,
                content: content
            )

            // Stop typing indicator
            await phoenixState.sendTypingIndicator(
                conversationId: conversationId,
                isTyping: false
            )
            isTyping = false
        }
    }

    private func handleTypingChange(newValue: String) {
        let shouldBeTyping = !newValue.isEmpty

        if shouldBeTyping != isTyping {
            isTyping = shouldBeTyping

            Task {
                await phoenixState.sendTypingIndicator(
                    conversationId: conversationId,
                    isTyping: shouldBeTyping
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ChatView(
            phoenixState: PhoenixStateManager.preview,
            conversationId: "conv1",
            currentUserId: "user1"
        )
    }
}
