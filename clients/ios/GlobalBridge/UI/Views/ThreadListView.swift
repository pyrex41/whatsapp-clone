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

    init(phoenixState: PhoenixStateManager) {
        self._phoenixState = Bindable(phoenixState)
    }

    var body: some View {
        NavigationView {
            List(threads) { thread in
                NavigationLink(destination: destinationView(for: thread)) {
                    ThreadRowView(
                        thread: thread,
                        presence: phoenixState.getPresence(for: thread.id).values.first
                    )
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .onAppear {
            loadThreads()
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

// MARK: - Preview

#Preview {
    ThreadListView(phoenixState: PhoenixStateManager.preview)
}
