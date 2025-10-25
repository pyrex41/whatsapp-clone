//
//  PresenceIndicator.swift
//  GlobalBridge
//
//  SwiftUI components for displaying user presence and online status
//  Includes: online/offline badges, typing indicators, last seen timestamps
//

import SwiftUI
import Combine

// MARK: - Status Indicator Badge

/// Simple dot indicator for online/offline/away status
public struct PresenceIndicator: View {
    let status: UserChannelManager.PresenceStatus
    let size: CGFloat
    let showAnimation: Bool

    public init(
        status: UserChannelManager.PresenceStatus,
        size: CGFloat = 12,
        showAnimation: Bool = true
    ) {
        self.status = status
        self.size = size
        self.showAnimation = showAnimation
    }

    public var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            .scaleEffect(showAnimation && status == .online ? 1.0 : 1.0)
            .animation(
                showAnimation && status == .online
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: status
            )
    }

    private var statusColor: Color {
        switch status {
        case .online:
            return .green
        case .away:
            return .orange
        case .offline:
            return .gray
        }
    }
}

// MARK: - Inline Status Text

/// Text-based status display with optional last seen
public struct PresenceStatusText: View {
    let status: UserChannelManager.PresenceStatus
    let lastSeen: Date?
    let showLastSeen: Bool

    public init(
        status: UserChannelManager.PresenceStatus,
        lastSeen: Date? = nil,
        showLastSeen: Bool = true
    ) {
        self.status = status
        self.lastSeen = lastSeen
        self.showLastSeen = showLastSeen
    }

    public var body: some View {
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
            if showLastSeen, let lastSeen = lastSeen {
                return "Last seen \(UserChannelManager.formatLastSeen(lastSeen))"
            } else {
                return "Offline"
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .online:
            return .green
        case .away:
            return .orange
        case .offline:
            return .secondary
        }
    }
}

// MARK: - Full Presence Display

/// Complete presence display with badge, text, and last seen
public struct PresenceDisplay: View {
    let status: UserChannelManager.PresenceStatus
    let lastSeen: Date?
    let showBadge: Bool
    let showText: Bool

    public init(
        status: UserChannelManager.PresenceStatus,
        lastSeen: Date? = nil,
        showBadge: Bool = true,
        showText: Bool = true
    ) {
        self.status = status
        self.lastSeen = lastSeen
        self.showBadge = showBadge
        self.showText = showText
    }

    public var body: some View {
        HStack(spacing: 6) {
            if showBadge {
                PresenceIndicator(status: status, size: 8)
            }

            if showText {
                PresenceStatusText(status: status, lastSeen: lastSeen)
            }
        }
    }
}

// MARK: - Avatar with Presence Badge

/// User avatar with presence indicator overlay
public struct PresenceAvatar: View {
    let avatarUrl: String?
    let status: UserChannelManager.PresenceStatus
    let size: CGFloat
    let badgeSize: CGFloat?

    public init(
        avatarUrl: String? = nil,
        status: UserChannelManager.PresenceStatus,
        size: CGFloat = 48,
        badgeSize: CGFloat? = nil
    ) {
        self.avatarUrl = avatarUrl
        self.status = status
        self.size = size
        self.badgeSize = badgeSize
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar
            Group {
                if let urlString = avatarUrl,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            defaultAvatar
                        @unknown default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            // Presence badge
            if status != .offline {
                PresenceIndicator(
                    status: status,
                    size: badgeSize ?? (size * 0.28),
                    showAnimation: status == .online
                )
                .offset(x: 2, y: 2)
            }
        }
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.7), .purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: size * 0.45))
            )
    }
}

// MARK: - Typing Indicator

/// Animated typing indicator ("User is typing...")
public struct TypingUsersIndicatorView: View {
    let typingUsers: Set<String>
    let currentUserId: String
    @State private var animationPhase: Int = 0

    public init(typingUsers: Set<String>, currentUserId: String) {
        self.typingUsers = typingUsers
        self.currentUserId = currentUserId
    }

    public var body: some View {
        if !typingUsers.isEmpty {
            HStack(spacing: 4) {
                Text(typingText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 4, height: 4)
                            .opacity(animationPhase == index ? 1.0 : 0.3)
                    }
                }
            }
            .onAppear {
                startAnimation()
            }
        }
    }

    private var typingText: String {
        let otherUsers = typingUsers.filter { $0 != currentUserId }
        guard !otherUsers.isEmpty else { return "" }

        switch otherUsers.count {
        case 1:
            return "\(otherUsers.first!) is typing"
        case 2:
            let users = Array(otherUsers).sorted()
            return "\(users[0]) and \(users[1]) are typing"
        default:
            return "Multiple people are typing"
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Typing Indicator Dots Only

/// Just the animated dots for inline display
public struct TypingDotsView: View {
    @State private var animationPhase: Int = 0

    public init() {}

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .opacity(animationPhase == index ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.4),
                        value: animationPhase
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Chat List Row with Presence

/// Chat list row component with presence and typing
public struct ChatListPresenceRow: View {
    let userName: String
    let lastMessage: String?
    let timestamp: Date
    let avatarUrl: String?
    let status: UserChannelManager.PresenceStatus
    let isTyping: Bool
    let unreadCount: Int

    public init(
        userName: String,
        lastMessage: String?,
        timestamp: Date,
        avatarUrl: String? = nil,
        status: UserChannelManager.PresenceStatus,
        isTyping: Bool = false,
        unreadCount: Int = 0
    ) {
        self.userName = userName
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.avatarUrl = avatarUrl
        self.status = status
        self.isTyping = isTyping
        self.unreadCount = unreadCount
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Avatar with presence
            PresenceAvatar(
                avatarUrl: avatarUrl,
                status: status,
                size: 56
            )

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Name and timestamp
                HStack {
                    Text(userName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(formatTimestamp(timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Last message or typing indicator
                if isTyping {
                    HStack(spacing: 4) {
                        Text("typing")
                            .font(.subheadline)
                            .foregroundColor(.green)
                        TypingDotsView()
                    }
                } else if let message = lastMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Presence status
                PresenceDisplay(
                    status: status,
                    lastSeen: nil,
                    showBadge: false,
                    showText: true
                )
            }

            // Unread badge
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 8)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateComponents([.day], from: date, to: now).day ?? 0 < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Profile Header with Presence

/// Profile view header with presence info
public struct ProfilePresenceHeader: View {
    let userName: String
    let avatarUrl: String?
    let status: UserChannelManager.PresenceStatus
    let lastSeen: Date?

    public init(
        userName: String,
        avatarUrl: String? = nil,
        status: UserChannelManager.PresenceStatus,
        lastSeen: Date? = nil
    ) {
        self.userName = userName
        self.avatarUrl = avatarUrl
        self.status = status
        self.lastSeen = lastSeen
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Large avatar with presence
            PresenceAvatar(
                avatarUrl: avatarUrl,
                status: status,
                size: 100,
                badgeSize: 20
            )

            // Name
            Text(userName)
                .font(.title2.bold())

            // Status with last seen
            PresenceDisplay(
                status: status,
                lastSeen: lastSeen,
                showBadge: true,
                showText: true
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Previews

#Preview("Presence Indicators") {
    VStack(spacing: 24) {
        Text("Status Indicators")
            .font(.headline)

        HStack(spacing: 20) {
            VStack {
                PresenceIndicator(status: .online, size: 12)
                Text("Online")
                    .font(.caption)
            }

            VStack {
                PresenceIndicator(status: .away, size: 12)
                Text("Away")
                    .font(.caption)
            }

            VStack {
                PresenceIndicator(status: .offline, size: 12)
                Text("Offline")
                    .font(.caption)
            }
        }

        Divider()

        Text("Status Text")
            .font(.headline)

        VStack(spacing: 8) {
            PresenceStatusText(status: .online)
            PresenceStatusText(status: .away)
            PresenceStatusText(
                status: .offline,
                lastSeen: Date().addingTimeInterval(-3600)
            )
        }

        Divider()

        Text("Presence Avatars")
            .font(.headline)

        HStack(spacing: 20) {
            PresenceAvatar(status: .online, size: 60)
            PresenceAvatar(status: .away, size: 60)
            PresenceAvatar(status: .offline, size: 60)
        }

        Divider()

        Text("Typing Indicators")
            .font(.headline)

        TypingUsersIndicatorView(
            typingUsers: ["Alice"],
            currentUserId: "me"
        )

        TypingDotsView()
    }
    .padding()
}

#Preview("Chat List Row") {
    ChatListPresenceRow(
        userName: "Alice Johnson",
        lastMessage: "Hey, are you coming to the meeting?",
        timestamp: Date().addingTimeInterval(-300),
        status: .online,
        isTyping: true,
        unreadCount: 3
    )
    .padding()
}

#Preview("Profile Header") {
    ProfilePresenceHeader(
        userName: "Bob Smith",
        status: .online,
        lastSeen: Date()
    )
    .padding()
}
