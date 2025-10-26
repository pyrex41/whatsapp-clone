//
//  ChatView.swift
//  GlobalBridge
//
//  Main chat view with typing indicators and presence
//

import SwiftUI
import Combine
import Observation

/// Main chat view displaying messages, typing indicators, and presence
struct ChatView: View {
    @Bindable var phoenixState: PhoenixStateManager
    let conversationId: String
    let currentUserId: String
    let conversationTitle: String? // Optional title override

    @State private var messageText = ""
    @State private var isTyping = false
    @FocusState private var isInputFocused: Bool

    init(
        phoenixState: PhoenixStateManager,
        conversationId: String,
        currentUserId: String,
        conversationTitle: String? = nil
    ) {
        self._phoenixState = Bindable(phoenixState)
        self.conversationId = conversationId
        self.currentUserId = currentUserId
        self.conversationTitle = conversationTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { scrollProxy in
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
                .onAppear {
                    // Scroll to bottom when view appears
                    if let lastMessage = messages.last {
                        scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
                .onChange(of: messages.count) { oldCount, newCount in
                    // Scroll to bottom when new messages arrive
                    if newCount > oldCount, let lastMessage = messages.last {
                        withAnimation {
                            scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Typing indicator
            if let typingText = typingState.typingText(currentUserId: currentUserId) {
                InlineTypingIndicatorView(typingText: typingText)
                    .padding(.horizontal, 8)
            }

            // Message composer with translation support
            MessageComposerView(
                text: $messageText,
                isSending: false,  // TODO: Add sending state tracking
                onSend: sendMessage,
                isFocused: $isInputFocused,
                threadId: conversationId,
                phoenixStateManager: phoenixState
            )
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(displayTitle)
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

    private var displayTitle: String {
        // Use provided title if available, otherwise try to determine from presence
        if let title = conversationTitle {
            return title
        }

        // For DMs, try to get other user's display name from presence
        let otherUsers = presences.values.filter { $0.userId != currentUserId }
        if otherUsers.count == 1, let otherUser = otherUsers.first {
            // Extract display name from userId (format: user_abc123 or full name)
            let userId = otherUser.userId
            if userId.hasPrefix("user_") {
                return "User \(userId.dropFirst(5).prefix(8))"
            }
            return userId
        }

        return "Chat"
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
