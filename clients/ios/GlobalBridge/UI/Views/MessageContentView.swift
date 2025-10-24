//
//  MessageContentView.swift
//  GlobalBridge
//
//  Renders message content based on message type
//

import SwiftUI

/// Renders different message content types
struct MessageContentView: View {
    let message: Message
    let isOwnMessage: Bool

    var body: some View {
        switch message.messageType {
        case .text:
            textContent
        case .image:
            imageContent
        case .video:
            videoContent
        case .audio:
            audioContent
        case .file:
            fileContent
        case .location:
            locationContent
        case .contact:
            contactContent
        }
    }

    // MARK: - Content Types

    private var textContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundColor(isOwnMessage ? .white : .primary)
            .textSelection(.enabled)
    }

    private var imageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Placeholder for image
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 150)
                .overlay(
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                )
                .cornerRadius(8)

            if !message.content.isEmpty {
                Text(message.content)
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white : .secondary)
            }
        }
    }

    private var videoContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Placeholder for video
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 150)
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                )
                .cornerRadius(8)

            if !message.content.isEmpty {
                Text(message.content)
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white : .secondary)
            }
        }
    }

    private var audioContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(isOwnMessage ? .white : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Message")
                    .font(.subheadline)
                    .foregroundColor(isOwnMessage ? .white : .primary)

                Text("0:15")
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            Button {
                // Play audio
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(isOwnMessage ? .white : .blue)
            }
        }
        .padding(.horizontal, 8)
    }

    private var fileContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.largeTitle)
                .foregroundColor(isOwnMessage ? .white : .blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(isOwnMessage ? .white : .primary)
                    .lineLimit(1)

                Text("PDF • 1.2 MB")
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.8) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var locationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Placeholder for map
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 120)
                .overlay(
                    Image(systemName: "map")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                )
                .cornerRadius(8)

            Text(message.content)
                .font(.caption)
                .foregroundColor(isOwnMessage ? .white : .secondary)
        }
    }

    private var contactContent: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isOwnMessage ? Color.white.opacity(0.3) : Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: "person.fill")
                    .foregroundColor(isOwnMessage ? .white : .blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(message.content)
                    .font(.body)
                    .foregroundColor(isOwnMessage ? .white : .primary)

                Text("Contact")
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.8) : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        MessageContentView(
            message: Message(
                threadId: UUID(),
                senderId: "user1",
                content: "Hello, this is a text message!",
                messageType: .text,
                status: .read
            ),
            isOwnMessage: true
        )
        .padding()
        .background(Color.blue)
        .cornerRadius(16)

        MessageContentView(
            message: Message(
                threadId: UUID(),
                senderId: "user2",
                content: "Image.jpg",
                messageType: .image,
                status: .delivered
            ),
            isOwnMessage: false
        )
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(16)
    }
    .padding()
}
