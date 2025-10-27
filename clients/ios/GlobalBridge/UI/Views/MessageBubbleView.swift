//
//  MessageBubbleView.swift
//  GlobalBridge
//
//  Comprehensive message bubble UI with integrated translation features
//  Supports text, image, video, audio, and file content types
//  Includes translation toggle, provider badges, loading/error states
//

import SwiftUI
import Combine

/// Comprehensive message bubble view with translation support
struct MessageBubbleView: View {
    // MARK: - Properties

    let message: Message
    let isOwnMessage: Bool
    let readCount: Int
    let totalParticipants: Int

    @StateObject private var viewModel: MessageBubbleViewModel
    @State private var showTranslation = false
    @State private var showTranslationMenu = false
    @State private var showCulturalNotes = false
    @State private var showLanguageSelection = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Initialization

    init(
        message: Message,
        isOwnMessage: Bool,
        readCount: Int = 0,
        totalParticipants: Int = 2,
        translationService: UnifiedTranslationService? = nil
    ) {
        self.message = message
        self.isOwnMessage = isOwnMessage
        self.readCount = readCount
        self.totalParticipants = totalParticipants
        self._viewModel = StateObject(
            wrappedValue: MessageBubbleViewModel(
                message: message,
                translationService: translationService ?? UnifiedTranslationService.shared
            )
        )
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwnMessage {
                Spacer(minLength: 50)
            }

            VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 4) {
                // Main message content
                messageBubble

                // Translation overlay if shown
                if showTranslation, let translation = viewModel.translation {
                    translationOverlay(translation)
                }

                // Message metadata
                messageMetadata
            }

            if !isOwnMessage {
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contextMenu {
            contextMenuContent
        }
    }

    // MARK: - Message Bubble

    private var messageBubble: some View {
        MessageContentView(
            message: message,
            isOwnMessage: isOwnMessage
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(bubbleBackground)
        .overlay(editedIndicator, alignment: .topTrailing)
        .onLongPressGesture {
            showTranslationMenu = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(bubbleColor)
            .shadow(
                color: Color.black.opacity(0.05),
                radius: 2,
                x: 0,
                y: 1
            )
    }

    private var bubbleColor: Color {
        if isOwnMessage {
            return Color.blue
        } else {
            return colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)
        }
    }

    private var editedIndicator: some View {
        Group {
            if message.editedAt != nil {
                Text("edited")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(4)
            }
        }
    }

    // MARK: - Translation Overlay

    private func translationOverlay(_ result: TranslationResult) -> some View {
        VStack(alignment: isOwnMessage ? .trailing : .leading, spacing: 6) {
            // Provider badge
            HStack(spacing: 4) {
                TranslationProviderBadge(provider: result.provider ?? "unknown")

                if let confidence = result.confidence {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // Translated text
            Text(result.translatedText)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(translationBackgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                )

            // Cultural notes if available (collapsible for clean UX)
            if let notes = result.culturalNotes, !notes.isEmpty {
                culturalNotesView(notes: notes)
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = result.translatedText
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }

                Button {
                    withAnimation {
                        showTranslation = false
                    }
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .transition(.opacity.combined(with: .scale))
    }

    private var translationBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(.systemGray6)
        } else {
            return Color.white
        }
    }

    /// Cultural notes view with collapsible design
    @ViewBuilder
    private func culturalNotesView(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tap to expand/collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showCulturalNotes.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Cultural Context")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: showCulturalNotes ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expanded notes
            if showCulturalNotes {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 8)
    }

    // MARK: - Message Metadata

    private var messageMetadata: some View {
        HStack(spacing: 6) {
            // Timestamp
            Text(formatTimestamp(message.createdAt))
                .font(.caption2)
                .foregroundColor(.secondary)

            // Translation status icon
            if viewModel.hasTranslation {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showTranslation.toggle()
                    }
                } label: {
                    Image(systemName: showTranslation ? "globe.badge.chevron.backward" : "globe")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel(showTranslation ? "Hide translation" : "Show translation")
            }

            // Loading indicator for translation in progress
            if viewModel.isTranslating {
                ProgressView()
                    .scaleEffect(0.7)
            }

            // Read receipt indicator (only for own messages)
            if isOwnMessage {
                ReadReceiptIndicator(
                    messageId: message.id.uuidString,
                    status: message.status,
                    readCount: readCount,
                    totalParticipants: totalParticipants,
                    showDetailOnTap: totalParticipants > 2
                )
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // Translation actions
        if message.messageType == .text {
            Section("Translation") {
                if !viewModel.hasTranslation {
                    Button {
                        Task {
                            await viewModel.translateToUserLanguage()
                            withAnimation {
                                showTranslation = true
                            }
                        }
                    } label: {
                        Label("Translate", systemImage: "globe")
                    }
                } else {
                    Button {
                        withAnimation {
                            showTranslation.toggle()
                        }
                    } label: {
                        Label(
                            showTranslation ? "Hide Translation" : "Show Translation",
                            systemImage: showTranslation ? "eye.slash" : "eye"
                        )
                    }
                }

                Button {
                    showLanguageSelection = true
                } label: {
                    Label("Choose Language...", systemImage: "text.bubble")
                }
            }
        }

        // Standard message actions
        Section {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if let translation = viewModel.translation {
                Button {
                    UIPasteboard.general.string = translation.translatedText
                } label: {
                    Label("Copy Translation", systemImage: "doc.on.doc.fill")
                }
            }
        }

        // Reply action
        Button {
            // Handle reply
        } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }

        // Report bad translation
        if viewModel.hasTranslation {
            Button(role: .destructive) {
                Task {
                    await viewModel.reportBadTranslation()
                }
            } label: {
                Label("Report Bad Translation", systemImage: "exclamationmark.triangle")
            }
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()

        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
        } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEE h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }

        return formatter.string(from: date)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = isOwnMessage ? "You: " : "Message: "
        label += message.content

        if let translation = viewModel.translation, showTranslation {
            label += ". Translation: \(translation.translatedText)"
        }

        if message.editedAt != nil {
            label += ". Edited"
        }

        return label
    }

    private var accessibilityHint: String {
        if message.messageType == .text && !viewModel.hasTranslation {
            return "Long press to translate"
        } else if viewModel.hasTranslation {
            return "Tap translation icon to \(showTranslation ? "hide" : "show") translation"
        }
        return ""
    }
}

// MARK: - Preview

#Preview("Text Messages") {
    ScrollView {
        VStack(spacing: 12) {
            // Own message
            MessageBubbleView(
                message: Message(
                    threadId: UUID(),
                    senderId: "me",
                    content: "Hello, how are you?",
                    messageType: .text,
                    status: .read
                ),
                isOwnMessage: true,
                readCount: 1,
                totalParticipants: 2
            )

            // Other's message
            MessageBubbleView(
                message: Message(
                    threadId: UUID(),
                    senderId: "other",
                    content: "I'm doing great, thanks!",
                    messageType: .text,
                    status: .delivered
                ),
                isOwnMessage: false
            )

            // Edited message
            MessageBubbleView(
                message: Message(
                    threadId: UUID(),
                    senderId: "me",
                    content: "Fixed my typo!",
                    messageType: .text,
                    status: .read,
                    editedAt: Date()
                ),
                isOwnMessage: true,
                readCount: 1,
                totalParticipants: 2
            )
        }
        .padding()
    }
}

#Preview("Dark Mode") {
    ScrollView {
        VStack(spacing: 12) {
            MessageBubbleView(
                message: Message(
                    threadId: UUID(),
                    senderId: "me",
                    content: "Dark mode looks great!",
                    messageType: .text,
                    status: .read
                ),
                isOwnMessage: true
            )

            MessageBubbleView(
                message: Message(
                    threadId: UUID(),
                    senderId: "other",
                    content: "Yes, it does!",
                    messageType: .text,
                    status: .delivered
                ),
                isOwnMessage: false
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
