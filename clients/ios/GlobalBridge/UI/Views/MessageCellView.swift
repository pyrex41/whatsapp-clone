//
//  MessageCellView.swift
//  GlobalBridge
//
//  Message cell with read receipt indicator
//

import SwiftUI

/// Displays a single message with read receipt status
struct MessageCellView: View {
    let message: PhoenixMessage
    let isOwnMessage: Bool
    let readCount: Int
    let totalParticipants: Int

    var body: some View {
        HStack {
            if isOwnMessage {
                Spacer()
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                // Message bubble
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isOwnMessage ? Color.blue : Color.gray.opacity(0.2))
                    )
                    .foregroundColor(isOwnMessage ? .white : .primary)

                // Bridge attribution label (only for bridged messages)
                if let bridgeLabel = bridgeAttributionLabel {
                    Text(bridgeLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }

                // Message status and time
                HStack(spacing: 4) {
                    // Timestamp
                    Text(formatTimestamp(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Read receipt indicator (only for own messages)
                    if isOwnMessage {
                        ReadReceiptIndicatorView(
                            status: message.status,
                            readCount: readCount,
                            totalParticipants: totalParticipants
                        )
                    }
                }
            }

            if !isOwnMessage {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var bridgeAttributionLabel: String? {
        guard let metadata = message.metadata else { return nil }

        // Check if this is a bridged message
        if let platform = metadata.bridgePlatform {
            switch platform {
            case "telegram":
                return "via Telegram"
            default:
                return "via \(platform.capitalized)"
            }
        }

        return nil
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Read receipt indicator showing message delivery status
struct ReadReceiptIndicatorView: View {
    let status: PhoenixMessage.MessageStatus
    let readCount: Int
    let totalParticipants: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundColor(iconColor)

            // Show read count for group chats
            if totalParticipants > 2 && readCount > 0 {
                Text("\(readCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var iconName: String {
        switch status {
        case .sending:
            return "clock"
        case .sent:
            return "checkmark"
        case .delivered:
            return "checkmark.circle"
        case .read:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        switch status {
        case .sending:
            return .secondary
        case .sent:
            return .secondary
        case .delivered:
            return .secondary
        case .read:
            return .blue
        case .failed:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // Own message - sent
        MessageCellView(
            message: PhoenixMessage(
                id: "1",
                conversationId: "conv1",
                senderId: "me",
                content: "Hello!",
                timestamp: Date(),
                status: .sent,
                metadata: nil
            ),
            isOwnMessage: true,
            readCount: 0,
            totalParticipants: 2
        )

        // Own message - read
        MessageCellView(
            message: PhoenixMessage(
                id: "2",
                conversationId: "conv1",
                senderId: "me",
                content: "How are you?",
                timestamp: Date().addingTimeInterval(-60),
                status: .read,
                metadata: nil
            ),
            isOwnMessage: true,
            readCount: 1,
            totalParticipants: 2
        )

        // Other's message
        MessageCellView(
            message: PhoenixMessage(
                id: "3",
                conversationId: "conv1",
                senderId: "other",
                content: "I'm doing great, thanks!",
                timestamp: Date().addingTimeInterval(-120),
                status: .delivered,
                metadata: nil
            ),
            isOwnMessage: false,
            readCount: 0,
            totalParticipants: 2
        )

        // Group chat message
        MessageCellView(
            message: PhoenixMessage(
                id: "4",
                conversationId: "conv1",
                senderId: "me",
                content: "Hello everyone!",
                timestamp: Date().addingTimeInterval(-180),
                status: .read,
                metadata: nil
            ),
            isOwnMessage: true,
            readCount: 3,
            totalParticipants: 5
        )
    }
    .padding()
}
