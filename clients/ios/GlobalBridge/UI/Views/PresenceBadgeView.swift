//
//  PresenceBadgeView.swift
//  GlobalBridge
//
//  UI component for displaying user presence status
//

import SwiftUI
import Combine

/// Displays presence badge for online/offline status
struct PresenceBadgeView: View {
    let status: UserPresence.PresenceStatus
    let size: CGFloat
    let showBorder: Bool

    init(
        status: UserPresence.PresenceStatus,
        size: CGFloat = 12,
        showBorder: Bool = true
    ) {
        self.status = status
        self.size = size
        self.showBorder = showBorder
    }

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(Color.white, lineWidth: showBorder ? 2 : 0)
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

/// Displays presence indicator with user avatar
struct PresenceAvatarView: View {
    let avatarUrl: String?
    let status: UserPresence.PresenceStatus
    let size: CGFloat

    init(
        avatarUrl: String? = nil,
        status: UserPresence.PresenceStatus,
        size: CGFloat = 48
    ) {
        self.avatarUrl = avatarUrl
        self.status = status
        self.size = size
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Avatar
            Group {
                if let urlString = avatarUrl,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        defaultAvatar
                    }
                } else {
                    defaultAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            // Presence badge
            PresenceBadgeView(
                status: status,
                size: size * 0.25,
                showBorder: true
            )
            .offset(x: 2, y: 2)
        }
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
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: size * 0.4))
            )
    }
}

/// Text label for presence status
struct PresenceTextView: View {
    let status: UserPresence.PresenceStatus
    let lastSeen: Date?

    var body: some View {
        Text(statusText)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var statusText: String {
        switch status {
        case .online:
            return "Online"
        case .away:
            return "Away"
        case .offline:
            if let lastSeen = lastSeen {
                return "Last seen \(formatLastSeen(lastSeen))"
            } else {
                return "Offline"
            }
        }
    }

    private func formatLastSeen(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        // Badge only
        HStack(spacing: 16) {
            PresenceBadgeView(status: .online)
            PresenceBadgeView(status: .away)
            PresenceBadgeView(status: .offline)
        }

        // Avatar with badge
        HStack(spacing: 16) {
            PresenceAvatarView(status: .online, size: 48)
            PresenceAvatarView(status: .away, size: 48)
            PresenceAvatarView(status: .offline, size: 48)
        }

        // Text labels
        VStack(alignment: .leading, spacing: 8) {
            PresenceTextView(status: .online, lastSeen: nil)
            PresenceTextView(status: .away, lastSeen: nil)
            PresenceTextView(status: .offline, lastSeen: Date().addingTimeInterval(-3600))
        }
    }
    .padding()
}
