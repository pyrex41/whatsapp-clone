//
//  MessageContentView.swift
//  GlobalBridge
//
//  Content view for different message types (text, image, video, audio, file)
//  Handles rendering of media content with appropriate UI
//

import SwiftUI
import AVKit

/// View for rendering different message content types
struct MessageContentView: View {
    let message: Message
    let isOwnMessage: Bool

    @State private var imageLoadingFailed = false
    @State private var showImageViewer = false

    var body: some View {
        Group {
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
    }

    // MARK: - Text Content

    private var textContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundColor(isOwnMessage ? .white : .primary)
            .textSelection(.enabled)
    }

    // MARK: - Image Content

    private var imageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = extractImageURL() {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        imageLoadingView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: 250, maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                showImageViewer = true
                            }
                    case .failure:
                        imageErrorView
                    @unknown default:
                        imageLoadingView
                    }
                }
            } else {
                imageErrorView
            }

            // Caption if present
            if let caption = extractCaption() {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.9) : .secondary)
            }
        }
    }

    private var imageLoadingView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 200, height: 200)
            .overlay(
                ProgressView()
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var imageErrorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Image unavailable")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 200, height: 200)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Video Content

    private var videoContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let videoURL = extractVideoURL() {
                VideoPlayer(player: AVPlayer(url: videoURL))
                    .frame(width: 250, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                videoErrorView
            }

            // Caption if present
            if let caption = extractCaption() {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.9) : .secondary)
            }
        }
    }

    private var videoErrorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Video unavailable")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 250, height: 200)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Audio Content

    private var audioContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundColor(isOwnMessage ? .white : .accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Message")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isOwnMessage ? .white : .primary)

                Text(extractAudioDuration() ?? "0:00")
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            Button {
                // Play audio
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(isOwnMessage ? .white : .accentColor)
            }
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    // MARK: - File Content

    private var fileContent: some View {
        HStack(spacing: 12) {
            Image(systemName: fileIcon)
                .font(.title)
                .foregroundColor(isOwnMessage ? .white : .accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(extractFileName() ?? "Document")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isOwnMessage ? .white : .primary)
                    .lineLimit(1)

                Text(extractFileSize() ?? "Unknown size")
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            Button {
                // Download/open file
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title2)
                    .foregroundColor(isOwnMessage ? .white : .accentColor)
            }
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    private var fileIcon: String {
        guard let fileName = extractFileName() else { return "doc.fill" }

        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text.fill"
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "zip", "rar": return "archivebox.fill"
        case "mp3", "wav": return "music.note"
        default: return "doc.fill"
        }
    }

    // MARK: - Location Content

    private var locationContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "map.fill")
                .font(.largeTitle)
                .foregroundColor(isOwnMessage ? .white : .accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Location shared")
                .font(.caption)
                .foregroundColor(isOwnMessage ? .white.opacity(0.9) : .secondary)
        }
        .frame(width: 200)
    }

    // MARK: - Contact Content

    private var contactContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.largeTitle)
                .foregroundColor(isOwnMessage ? .white : .accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Contact")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isOwnMessage ? .white : .primary)

                Text(message.content)
                    .font(.caption)
                    .foregroundColor(isOwnMessage ? .white.opacity(0.8) : .secondary)
            }

            Spacer()
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    // MARK: - Helper Methods

    private func extractImageURL() -> URL? {
        // Parse metadata for image URL
        guard let metadata = message.metadata,
              let urlString = metadata["image_url"],
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    private func extractVideoURL() -> URL? {
        guard let metadata = message.metadata,
              let urlString = metadata["video_url"],
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    private func extractCaption() -> String? {
        message.metadata?["caption"]
    }

    private func extractAudioDuration() -> String? {
        message.metadata?["duration"]
    }

    private func extractFileName() -> String? {
        message.metadata?["file_name"] ?? message.content
    }

    private func extractFileSize() -> String? {
        guard let sizeString = message.metadata?["file_size"],
              let bytes = Int64(sizeString) else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Preview

#Preview("All Content Types") {
    ScrollView {
        VStack(spacing: 16) {
            // Text
            MessageContentView(
                message: Message(
                    threadId: UUID(),
                    senderId: "user1",
                    content: "Hello, how are you?",
                    messageType: .text
                ),
                isOwnMessage: true
            )
            .padding()
            .background(Color.blue)
            .cornerRadius(18)

            // Audio
            MessageContentView(
                message: Message(
                    threadId: UUID(),
                    senderId: "user2",
                    content: "Audio message",
                    messageType: .audio,
                    metadata: ["duration": "0:15"]
                ),
                isOwnMessage: false
            )
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(18)

            // File
            MessageContentView(
                message: Message(
                    threadId: UUID(),
                    senderId: "user1",
                    content: "document.pdf",
                    messageType: .file,
                    metadata: [
                        "file_name": "Important Document.pdf",
                        "file_size": "2458632"
                    ]
                ),
                isOwnMessage: true
            )
            .padding()
            .background(Color.blue)
            .cornerRadius(18)
        }
        .padding()
    }
}
