//
//  MessageCellView.swift
//  GlobalBridge
//
//  Message cell with read receipt indicator
//

import SwiftUI
import Combine

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
                // Show sender name for other's messages
                if !isOwnMessage, let displayName = message.senderDisplayName {
                    Text(displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                }

                // Message bubble
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isOwnMessage ? Color.blue : Color.gray.opacity(0.2))
                    )
                    .foregroundColor(isOwnMessage ? .white : .primary)

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

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Legacy read receipt indicator - now using ReadReceiptIndicator from GlobalBridge
struct ReadReceiptIndicatorView: View {
    let status: PhoenixMessage.MessageStatus
    let readCount: Int
    let totalParticipants: Int
    let messageId: String?

    init(status: PhoenixMessage.MessageStatus, readCount: Int, totalParticipants: Int, messageId: String? = nil) {
        self.status = status
        self.readCount = readCount
        self.totalParticipants = totalParticipants
        self.messageId = messageId
    }

    var body: some View {
        // Use the new ReadReceiptIndicator component
        ReadReceiptIndicator(
            messageId: messageId ?? "",
            status: convertStatus(status),
            readCount: readCount,
            totalParticipants: totalParticipants,
            showDetailOnTap: messageId != nil
        )
    }

    private func convertStatus(_ phoenixStatus: PhoenixMessage.MessageStatus) -> Message.MessageStatus {
        switch phoenixStatus {
        case .sending: return .pending
        case .sent: return .sent
        case .delivered: return .delivered
        case .read: return .read
        case .failed: return .failed
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
                senderDisplayName: nil,
                content: "Hello!",
                timestamp: Date(),
                status: .sent,
                metadata: nil,
                clientMessageId: nil
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
                senderDisplayName: nil,
                content: "How are you?",
                timestamp: Date().addingTimeInterval(-60),
                status: .read,
                metadata: nil,
                clientMessageId: nil
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
                senderId: "user_abc123",
                senderDisplayName: "Alice Johnson",
                content: "I'm doing great, thanks!",
                timestamp: Date().addingTimeInterval(-120),
                status: .delivered,
                metadata: nil,
                clientMessageId: nil
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
                senderDisplayName: nil,
                content: "Hello everyone!",
                timestamp: Date().addingTimeInterval(-180),
                status: .read,
                metadata: nil,
                clientMessageId: nil
            ),
            isOwnMessage: true,
            readCount: 3,
            totalParticipants: 5
        )
    }
    .padding()
}
