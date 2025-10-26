//
//  SmartReplyComposerView.swift
//  GlobalBridge
//
//  Task 12: Smart Reply Composer UI
//  Displays AI suggestion chips inline above the message composer with loading states,
//  tap-to-insert interaction, and translation toggle.
//

import SwiftUI

/// Smart reply composer view with suggestion chips
struct SmartReplyComposerView: View {

    // MARK: - Properties

    let suggestions: [SmartReplySuggestion]
    let isLoading: Bool
    let translationEnabled: Bool
    let onSuggestionTap: (SmartReplySuggestion, Int) -> Void // Now includes timeToResponseMs
    let onTranslationToggle: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                loadingView
            } else if !suggestions.isEmpty {
                suggestionsView
            }

            if !suggestions.isEmpty || isLoading {
                translationToggleView
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Loading View

    private var loadingView: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                ShimmerChip()
                    .frame(height: 36)
            }
            Spacer()
        }
        .accessibilityLabel("Loading smart reply suggestions")
    }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions.prefix(3)) { suggestion in
                    SuggestionChip(
                        suggestion: suggestion,
                        onTap: { timeToResponseMs in
                            onSuggestionTap(suggestion, timeToResponseMs)
                        }
                    )
                }
            }
        }
        .accessibilityLabel("Smart reply suggestions")
    }

    // MARK: - Translation Toggle

    private var translationToggleView: some View {
        HStack {
            Spacer()
            Button(action: onTranslationToggle) {
                HStack(spacing: 4) {
                    Image(systemName: translationEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                    Text("Translate")
                        .font(.caption)
                }
                .foregroundColor(translationEnabled ? .blue : .gray)
            }
            .accessibilityLabel(translationEnabled ? "Translation enabled" : "Translation disabled")
            .accessibilityHint("Double tap to toggle translation")
        }
    }
}

// MARK: - Suggestion Chip

private struct SuggestionChip: View {
    let suggestion: SmartReplySuggestion
    let onTap: (Int) -> Void // Now receives timeToResponseMs

    @State private var displayTimestamp: Date = Date()

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 4) {
                if suggestion.isProactive {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
                Text(suggestion.content)
                    .font(.body)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(suggestion.isProactive ? Color.purple.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(suggestion.isProactive ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(suggestion.isProactive ? "Proactive suggestion: \(suggestion.content)" : "Suggestion: \(suggestion.content)")
        .accessibilityHint("Double tap to insert into message")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            // Record the timestamp when the chip is displayed
            displayTimestamp = Date()
        }
    }

    private func handleTap() {
        // Calculate time-to-response in milliseconds
        let timeToResponseMs = Int(Date().timeIntervalSince(displayTimestamp) * 1000)

        // Pass the time-to-response to the callback
        onTap(timeToResponseMs)
    }
}

// MARK: - Shimmer Chip

private struct ShimmerChip: View {
    @State private var isAnimating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemGray5),
                        Color(.systemGray6),
                        Color(.systemGray5)
                    ]),
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                )
            )
            .onAppear {
                withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating.toggle()
                }
            }
    }
}

// MARK: - Previews

#Preview("With Suggestions") {
    SmartReplyComposerView(
        suggestions: [
            SmartReplySuggestion(
                id: UUID(),
                type: "quick-reply",
                content: "Thanks!",
                confidence: 0.95,
                position: 0,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "contextual",
                content: "Let me check and get back to you",
                confidence: 0.85,
                position: 1,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "proactive",
                content: "I'll be there in 5 minutes",
                confidence: 0.75,
                position: 2,
                context: "",
                timestamp: Date()
            )
        ],
        isLoading: false,
        translationEnabled: false,
        onSuggestionTap: { suggestion, timeMs in
            print("Tapped suggestion: \(suggestion.content) after \(timeMs)ms")
        },
        onTranslationToggle: {}
    )
    .padding()
}

#Preview("Loading State") {
    SmartReplyComposerView(
        suggestions: [],
        isLoading: true,
        translationEnabled: false,
        onSuggestionTap: { _, _ in },
        onTranslationToggle: {}
    )
    .padding()
}

#Preview("Empty State") {
    SmartReplyComposerView(
        suggestions: [],
        isLoading: false,
        translationEnabled: false,
        onSuggestionTap: { _, _ in },
        onTranslationToggle: {}
    )
    .padding()
}

#Preview("Translation Enabled") {
    SmartReplyComposerView(
        suggestions: [
            SmartReplySuggestion(
                id: UUID(),
                type: "quick-reply",
                content: "Yes, absolutely!",
                confidence: 0.95,
                position: 0,
                context: "",
                timestamp: Date()
            )
        ],
        isLoading: false,
        translationEnabled: true,
        onSuggestionTap: { _, _ in },
        onTranslationToggle: {}
    )
    .padding()
}

#Preview("Proactive vs Non-Proactive") {
    VStack(spacing: 20) {
        Text("Visual Distinction Demo")
            .font(.headline)

        Text("Proactive Suggestions (Purple Theme)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        SmartReplyComposerView(
            suggestions: [
                SmartReplySuggestion(
                    id: UUID(),
                    type: "proactive",
                    content: "I'll be there in 5 minutes",
                    confidence: 0.85,
                    position: 0,
                    context: "",
                    timestamp: Date()
                ),
                SmartReplySuggestion(
                    id: UUID(),
                    type: "proactive",
                    content: "Let me know if you need help",
                    confidence: 0.75,
                    position: 1,
                    context: "",
                    timestamp: Date()
                )
            ],
            isLoading: false,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {}
        )

        Divider()

        Text("Non-Proactive Suggestions (Standard Theme)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        SmartReplyComposerView(
            suggestions: [
                SmartReplySuggestion(
                    id: UUID(),
                    type: "quick-reply",
                    content: "Thanks!",
                    confidence: 0.95,
                    position: 0,
                    context: "",
                    timestamp: Date()
                ),
                SmartReplySuggestion(
                    id: UUID(),
                    type: "contextual",
                    content: "Sounds good",
                    confidence: 0.85,
                    position: 1,
                    context: "",
                    timestamp: Date()
                )
            ],
            isLoading: false,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {}
        )
    }
    .padding()
}
