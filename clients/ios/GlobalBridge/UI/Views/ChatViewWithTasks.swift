//
//  ChatViewWithTasks.swift
//  GlobalBridge
//
//  Example integration of TaskExtractionView with ChatView
//  Shows how to add task extraction button to chat toolbar
//

import SwiftUI
import Combine

/// Chat view with integrated task extraction button
struct ChatViewWithTasks: View {
    @Bindable var phoenixState: PhoenixStateManager
    let conversationId: String
    let currentUserId: String

    @State private var showingTaskExtraction = false
    @State private var messageText = ""
    @State private var isTyping = false
    @FocusState private var isInputFocused: Bool

    var threadUUID: UUID {
        UUID(uuidString: conversationId) ?? UUID()
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
                InlineTypingIndicatorView(typingText: typingText)
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
                        ChatPresenceTextView(
                            status: presence.status,
                            lastSeen: presence.lastSeen
                        )
                    }
                }
            }

            // ADD THIS: Task extraction button
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingTaskExtraction = true
                } label: {
                    Image(systemName: "checklist")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .sheet(isPresented: $showingTaskExtraction) {
            TaskExtractionView(threadId: threadUUID)
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
        "Chat"
    }

    private var participantCount: Int {
        presences.count + 1
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

            await phoenixState.sendTypingIndicator(
                conversationId: conversationId,
                isTyping: false
            )

            isTyping = false
        }
    }

    private func handleTypingChange(newValue: String) {
        if !newValue.isEmpty && !isTyping {
            isTyping = true
            Task {
                await phoenixState.sendTypingIndicator(
                    conversationId: conversationId,
                    isTyping: true
                )
            }
        } else if newValue.isEmpty && isTyping {
            isTyping = false
            Task {
                await phoenixState.sendTypingIndicator(
                    conversationId: conversationId,
                    isTyping: false
                )
            }
        }
    }
}

/// Presence text view component
struct ChatPresenceTextView: View {
    let status: UserPresence.PresenceStatus
    let lastSeen: Date?

    var body: some View {
        Text(statusText)
            .font(.caption)
            .foregroundColor(statusColor)
    }

    private var statusText: String {
        switch status {
        case .online:
            return "Online"
        case .away:
            return "Away"
        case .offline:
            if let lastSeen = lastSeen {
                return "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"
            }
            return "Offline"
        }
    }

    private var statusColor: Color {
        switch status {
        case .online: return .green
        case .away: return .orange
        case .offline: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChatViewWithTasks(
            phoenixState: PhoenixStateManager.preview,
            conversationId: UUID().uuidString,
            currentUserId: "user_123"
        )
    }
}
