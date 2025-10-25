//
//  ThreadListView.swift
//  GlobalBridge
//
//  Thread list view with presence indicators
//

import SwiftUI
import Observation

/// Displays list of conversation threads with presence indicators
struct ThreadListView: View {
    @Bindable var phoenixState: PhoenixStateManager
    @State private var threads: [ThreadViewModel] = []
    @State private var showingNewConversation = false
    @State private var connectionState: PhoenixConnectionState = .disconnected

    init(phoenixState: PhoenixStateManager) {
        self._phoenixState = Bindable(phoenixState)
    }

    var body: some View {
        NavigationView {
            Group {
                if threads.isEmpty {
                    emptyState
                } else {
                    List(threads) { thread in
                        NavigationLink(destination: destinationView(for: thread)) {
                            ThreadRowView(
                                thread: thread,
                                presence: phoenixState.getPresence(for: thread.id).values.first,
                                bridge: bridgeForThread(thread)
                            )
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    PhoenixConnectionIndicator(state: connectionState)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewConversation = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingNewConversation) {
                NewConversationView()
            }
        }
        .task {
            // Monitor connection state
            for await _ in Timer.publish(every: 1, on: .main, in: .common).autoconnect().values {
                let newState = await phoenixState.getConnectionState()
                if connectionState != newState {
                    connectionState = newState
                }
            }
        }
        .onAppear {
            loadThreads()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No conversations yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the compose button to start a conversation")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: { showingNewConversation = true }) {
                Label("New Conversation", systemImage: "square.and.pencil")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top)
        }
    }

    private func loadThreads() {
        // Mock data for preview
        threads = [
            ThreadViewModel(
                id: "conv1",
                title: "Alice Johnson",
                avatarUrl: nil,
                lastMessage: "Hey, how are you?",
                lastMessageTime: Date().addingTimeInterval(-300),
                unreadCount: 2
            ),
            ThreadViewModel(
                id: "conv2",
                title: "Bob Smith",
                avatarUrl: nil,
                lastMessage: "See you tomorrow!",
                lastMessageTime: Date().addingTimeInterval(-3600),
                unreadCount: 0
            ),
            ThreadViewModel(
                id: "conv3",
                title: "Team Chat",
                avatarUrl: nil,
                lastMessage: "Charlie: Great idea!",
                lastMessageTime: Date().addingTimeInterval(-7200),
                unreadCount: 5
            )
        ]
    }

    private func destinationView(for thread: ThreadViewModel) -> some View {
        ChatView(
            phoenixState: phoenixState,
            conversationId: thread.id,
            currentUserId: "current_user" // TODO: Get from auth
        )
    }

    private func bridgeForThread(_ thread: ThreadViewModel) -> Bridge? {
        // For now, return nil - this would need to be implemented based on
        // thread metadata or a mapping from thread to bridge
        // TODO: Implement bridge-thread association logic
        return nil
    }
}

/// View model for thread list item
struct ThreadViewModel: Identifiable {
    let id: String
    let title: String
    let avatarUrl: String?
    let lastMessage: String?
    let lastMessageTime: Date?
    let unreadCount: Int
}

/// Row view for a single thread in the list
struct ThreadRowView: View {
    let thread: ThreadViewModel
    let presence: UserPresence?
    let bridge: Bridge?

    var body: some View {
        HStack(spacing: 12) {
            // Avatar with presence badge
            if let presence = presence {
                PresenceAvatarView(
                    avatarUrl: thread.avatarUrl,
                    status: presence.status,
                    size: 56
                )
            } else {
                defaultAvatar
            }

            // Thread info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.title)
                        .font(.headline)
                        .lineLimit(1)

                    if let bridge = bridge {
                        BridgeStatusIndicator(bridge: bridge)
                    }

                    Spacer()

                    if let time = thread.lastMessageTime {
                        Text(formatTime(time))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    if let message = thread.lastMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Circle().fill(Color.blue))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.title2)
            )
    }

    private func formatTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let calendar = Calendar.current

        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if interval < 604800 { // Within a week
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

/// Bridge status indicator
struct BridgeStatusIndicator: View {
    let bridge: Bridge?

    var body: some View {
        if let bridge = bridge {
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.caption)
                    .foregroundColor(statusColor)

                Text(displayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusIcon: String {
        guard let bridge = bridge else { return "circle.slash" }

        switch bridge.status {
        case .connected:
            return "antenna.radiowaves.left.and.right"
        case .disconnected:
            return "antenna.radiowaves.left.and.right.slash"
        case .error:
            return "exclamationmark.triangle"
        case .connecting:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private var statusColor: Color {
        guard let bridge = bridge else { return .gray }

        switch bridge.status {
        case .connected:
            return .green
        case .disconnected:
            return .gray
        case .error:
            return .red
        case .connecting:
            return .orange
        }
    }

    private var displayText: String {
        guard let bridge = bridge else { return "" }

        switch bridge.bridgeType {
        case .telegram:
            return "Telegram"
        case .whatsapp:
            return "WhatsApp"
        }
    }
}

/// Phoenix connection status indicator
struct PhoenixConnectionIndicator: View {
    let state: PhoenixConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            if case .connecting = state {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityLabel(statusText)
    }

    private var statusColor: Color {
        switch state {
        case .disconnected:
            return .red
        case .connecting, .reconnecting:
            return .orange
        case .connected:
            return .green
        case .error:
            return .red
        }
    }

    private var statusText: String {
        switch state {
        case .disconnected:
            return "Offline"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .connected:
            return "Connected"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview {
    ThreadListView(phoenixState: PhoenixStateManager.preview)
}
