//
//  TranslationOverlayView.swift
//  GlobalBridge
//
//  Dedicated view for displaying translation results with rich metadata
//  Shows original text, translated text, provider info, confidence, cultural notes
//

import SwiftUI

/// Translation overlay view displaying translation results with metadata
struct TranslationOverlayView: View {
    // MARK: - Properties

    let originalText: String
    let translation: TranslationResult
    let onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingCulturalNotes = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Header with provider badge
            header

            // Original text section
            originalTextSection

            // Translation separator
            Divider()

            // Translated text section
            translatedTextSection

            // Cultural notes (if available)
            if let notes = translation.culturalNotes, !notes.isEmpty {
                culturalNotesSection(notes)
            }

            // Action buttons
            actionButtons
        }
        .padding(16)
        .background(backgroundColor)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            TranslationProviderBadge(provider: translation.provider ?? "unknown")

            if let confidence = translation.confidence {
                confidenceBadge(confidence)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Close translation")
        }
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: confidenceIcon(confidence))
                .font(.caption)
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(confidenceColor(confidence))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(confidenceColor(confidence).opacity(0.15))
        )
    }

    private func confidenceIcon(_ confidence: Double) -> String {
        switch confidence {
        case 0.9...1.0: return "checkmark.seal.fill"
        case 0.7..<0.9: return "checkmark.circle.fill"
        case 0.5..<0.7: return "checkmark.circle"
        default: return "exclamationmark.circle"
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.9...1.0: return .green
        case 0.7..<0.9: return .blue
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }

    // MARK: - Original Text Section

    private var originalTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Original")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(translation.sourceLanguageName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                    )
            }

            Text(originalText)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Translated Text Section

    private var translatedTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Translation")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Text(translation.targetLanguageName)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.15))
                    )
            }

            Text(translation.translatedText)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cultural Notes Section

    private func culturalNotesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    showingCulturalNotes.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .font(.caption)
                    Text("Cultural Context")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: showingCulturalNotes ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.accentColor)
            }

            if showingCulturalNotes {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.05))
                    )
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                UIPasteboard.general.string = originalText
            } label: {
                Label("Copy Original", systemImage: "doc.on.doc")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)

            Button {
                UIPasteboard.general.string = translation.translatedText
            } label: {
                Label("Copy Translation", systemImage: "doc.on.doc.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        if colorScheme == .dark {
            return Color(.systemGray6)
        } else {
            return Color.white
        }
    }
}

// MARK: - Preview

#Preview("High Confidence") {
    TranslationOverlayView(
        originalText: "Hello, how are you doing today?",
        translation: TranslationResult(
            originalText: "Hello, how are you doing today?",
            translatedText: "Hola, ¿cómo estás hoy?",
            sourceLanguage: "en",
            targetLanguage: "es",
            confidence: 0.95,
            provider: "backend-ai",
            culturalNotes: "This is an informal greeting. Use 'usted' for formal situations."
        ),
        onClose: {}
    )
    .padding()
    .previewLayout(.sizeThatFits)
}

#Preview("Medium Confidence") {
    TranslationOverlayView(
        originalText: "I'm feeling under the weather.",
        translation: TranslationResult(
            originalText: "I'm feeling under the weather.",
            translatedText: "Me siento un poco mal.",
            sourceLanguage: "en",
            targetLanguage: "es",
            confidence: 0.75,
            provider: "apple-translation",
            culturalNotes: "Idiomatic expression meaning 'feeling sick'. Direct translation may not capture full meaning."
        ),
        onClose: {}
    )
    .padding()
    .previewLayout(.sizeThatFits)
}

#Preview("Dark Mode") {
    TranslationOverlayView(
        originalText: "Good night!",
        translation: TranslationResult(
            originalText: "Good night!",
            translatedText: "おやすみなさい！",
            sourceLanguage: "en",
            targetLanguage: "ja",
            confidence: 0.92,
            provider: "hybrid"
        ),
        onClose: {}
    )
    .padding()
    .previewLayout(.sizeThatFits)
    .preferredColorScheme(.dark)
}
