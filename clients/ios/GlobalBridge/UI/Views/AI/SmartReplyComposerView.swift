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
    let error: AIServiceError?
    let translationEnabled: Bool
    let styleLearningEnabled: Bool
    let onSuggestionTap: (SmartReplySuggestion, Int) -> Void // Now includes timeToResponseMs
    let onSuggestionDismiss: ((SmartReplySuggestion) -> Void)?
    let onTranslationToggle: () -> Void
    let onRetry: (() -> Void)?

    // MARK: - State

    @State private var isExpanded: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = error {
                errorView(error)
            } else if isLoading {
                loadingView
            } else if !suggestions.isEmpty {
                suggestionsView
            }

            if !suggestions.isEmpty || isLoading {
                HStack(spacing: 8) {
                    // Compact learning indicator (just icon)
                    if styleLearningEnabled {
                        compactLearningIndicator
                    }

                    Spacer()

                    // Compact translation toggle
                    compactTranslationToggle
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("SmartReplyBar")
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
        VStack(alignment: .leading, spacing: 4) {
            // Show first suggestion always
            if let firstSuggestion = suggestions.first {
                SuggestionChip(
                    suggestion: firstSuggestion,
                    onTap: { timeToResponseMs in
                        onSuggestionTap(firstSuggestion, timeToResponseMs)
                    },
                    onDismiss: { dismissedSuggestion in
                        onSuggestionDismiss?(dismissedSuggestion)
                    },
                    isCompact: true
                )
                .accessibilityIdentifier("SmartReplyChip-\(firstSuggestion.position)")
            }

            // Show remaining suggestions when expanded
            if isExpanded {
                ForEach(suggestions.dropFirst().prefix(2)) { suggestion in
                    SuggestionChip(
                        suggestion: suggestion,
                        onTap: { timeToResponseMs in
                            onSuggestionTap(suggestion, timeToResponseMs)
                        },
                        onDismiss: { dismissedSuggestion in
                            onSuggestionDismiss?(dismissedSuggestion)
                        },
                        isCompact: true
                    )
                    .accessibilityIdentifier("SmartReplyChip-\(suggestion.position)")
                }
            }

            // Bottom row: expand/collapse button (only show if we have more than 1 suggestion)
            if suggestions.count > 1 {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Show less" : "Show \(suggestions.count - 1) more")
                                .font(.caption2)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .accessibilityLabel(isExpanded ? "Hide additional suggestions" : "Show \(suggestions.count - 1) more suggestions")
                }
                .padding(.top, 4)
            }
        }
        .accessibilityLabel("Smart reply suggestions")
    }

    // MARK: - Compact Learning Indicator

    private var compactLearningIndicator: some View {
        Image(systemName: "sparkles")
            .font(.caption)
            .foregroundColor(.purple)
            .accessibilityLabel("Style learning is active")
    }

    // MARK: - Learning Indicator (old, kept for compatibility)

    private var learningIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundColor(.purple)
            Text("Learning from your messages")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityLabel("Style learning is active")
    }

    // MARK: - Compact Translation Toggle

    private var compactTranslationToggle: some View {
        Button(action: onTranslationToggle) {
            Image(systemName: translationEnabled ? "globe" : "globe")
                .font(.caption)
                .foregroundColor(translationEnabled ? .blue : .gray)
        }
        .accessibilityLabel(translationEnabled ? "Translation enabled" : "Translation disabled")
        .accessibilityHint("Double tap to toggle translation")
    }

    // MARK: - Translation Toggle (old, kept for compatibility)

    private var translationToggleView: some View {
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

    // MARK: - Error View

    private func errorView(_ error: AIServiceError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(error.errorDescription ?? "An error occurred")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if let recoverySuggestion = error.recoverySuggestion {
                    Text(recoverySuggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let onRetry = onRetry, error.shouldRetry {
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                .accessibilityIdentifier("SmartReplyRetryButton")
                .accessibilityLabel("Retry fetching suggestions")
                .accessibilityHint("Double tap to try loading suggestions again")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.errorDescription ?? "An error occurred"). \(error.recoverySuggestion ?? "")")
    }
}

// MARK: - Suggestion Chip

private struct SuggestionChip: View {
    let suggestion: SmartReplySuggestion
    let onTap: (Int) -> Void // Now receives timeToResponseMs
    let onDismiss: (SmartReplySuggestion) -> Void
    var isCompact: Bool = false

    @State private var displayTimestamp: Date = Date()
    @State private var isDismissed: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var showDismissButton: Bool = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: isCompact ? 3 : 4) {
                if suggestion.isProactive {
                    Image(systemName: "sparkles")
                        .font(isCompact ? .caption : .caption2)
                        .foregroundColor(.purple)
                }
                Text(suggestion.content)
                    .font(isCompact ? .callout : .body)
                    .lineLimit(1)
            }
            .padding(.horizontal, isCompact ? 10 : 12)
            .padding(.vertical, isCompact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(suggestion.isProactive ? Color.purple.opacity(0.08) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(suggestion.isProactive ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    // Confidence Badge
                    ConfidenceBadge(confidence: suggestion.confidence)
                        .offset(x: showDismissButton ? -16 : -2, y: -2)

                    // Dismiss button (X)
                    if showDismissButton {
                        Button(action: handleDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .background(
                                    Circle()
                                        .fill(Color(.systemBackground))
                                        .frame(width: 14, height: 14)
                                )
                        }
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Dismiss suggestion")
                        .accessibilityHint("Double tap to remove this suggestion")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .offset(x: dragOffset)
        .opacity(isDismissed ? 0 : 1)
        .scaleEffect(isDismissed ? 0.8 : 1)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Allow horizontal dragging
                    dragOffset = value.translation.width

                    // Show dismiss button when dragging
                    if abs(dragOffset) > 10 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showDismissButton = true
                        }
                    }
                }
                .onEnded { value in
                    // Dismiss if dragged beyond threshold (50pt in either direction)
                    if abs(value.translation.width) > 50 {
                        handleDismiss()
                    } else {
                        // Snap back if not dismissed
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }

                        // Hide dismiss button after snap back
                        withAnimation(.easeOut(duration: 0.2).delay(0.3)) {
                            showDismissButton = false
                        }
                    }
                }
        )
        .onLongPressGesture(minimumDuration: 0.5) {
            // Show dismiss button on long press
            withAnimation(.easeOut(duration: 0.2)) {
                showDismissButton = true
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to insert into message. Swipe to dismiss.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Dismiss") {
            handleDismiss()
        }
        .onAppear {
            // Record the timestamp when the chip is displayed
            displayTimestamp = Date()
        }
    }

    private func handleTap() {
        // Only handle tap if not showing dismiss button
        guard !showDismissButton else {
            // Hide dismiss button on tap if it's showing
            withAnimation(.easeOut(duration: 0.2)) {
                showDismissButton = false
            }
            return
        }

        // Calculate time-to-response in milliseconds
        let timeToResponseMs = Int(Date().timeIntervalSince(displayTimestamp) * 1000)

        // Pass the time-to-response to the callback
        onTap(timeToResponseMs)
    }

    private func handleDismiss() {
        // Animate dismissal
        withAnimation(.easeOut(duration: 0.25)) {
            isDismissed = true
            dragOffset = dragOffset < 0 ? -100 : 100 // Complete the swipe animation
        }

        // Call dismiss callback after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onDismiss(suggestion)
        }
    }

    private var accessibilityLabel: String {
        let confidencePercentage = Int(suggestion.confidence * 100)
        let confidenceLevel: String

        switch suggestion.confidence {
        case 0.0..<0.6:
            confidenceLevel = "Low confidence"
        case 0.6..<0.8:
            confidenceLevel = "Medium confidence"
        default:
            confidenceLevel = "High confidence"
        }

        let suggestionType = suggestion.isProactive ? "Proactive suggestion" : "Suggestion"
        return "\(suggestionType): \(suggestion.content). \(confidenceLevel), \(confidencePercentage)%"
    }
}

// MARK: - Confidence Badge

private struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Circle()
            .fill(confidenceColor(confidence))
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 1.5)
            )
            .shadow(color: confidenceColor(confidence).opacity(0.3), radius: 2, x: 0, y: 1)
            .accessibilityLabel(confidenceAccessibilityLabel(confidence))
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.0..<0.6:
            return .orange
        case 0.6..<0.8:
            return .blue
        default:
            return .green
        }
    }

    private func confidenceAccessibilityLabel(_ confidence: Double) -> String {
        let percentage = Int(confidence * 100)
        let level: String

        switch confidence {
        case 0.0..<0.6:
            level = "Low"
        case 0.6..<0.8:
            level = "Medium"
        default:
            level = "High"
        }

        return "\(level) confidence, \(percentage)%"
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
        error: nil,
        translationEnabled: false,
        styleLearningEnabled: true,
        onSuggestionTap: { suggestion, timeMs in
            print("Tapped suggestion: \(suggestion.content) after \(timeMs)ms")
        },
        onSuggestionDismiss: { suggestion in
            print("Dismissed suggestion: \(suggestion.content)")
        },
        onTranslationToggle: {},
        onRetry: nil
    )
    .padding()
}

#Preview("Loading State") {
    SmartReplyComposerView(
        suggestions: [],
        isLoading: true,
        error: nil,
        translationEnabled: false,
        styleLearningEnabled: true,
        onSuggestionTap: { _, _ in },
        onSuggestionDismiss: nil,
        onTranslationToggle: {},
        onRetry: nil
    )
    .padding()
}

#Preview("Empty State") {
    SmartReplyComposerView(
        suggestions: [],
        isLoading: false,
        error: nil,
        translationEnabled: false,
        styleLearningEnabled: true,
        onSuggestionTap: { _, _ in },
        onSuggestionDismiss: nil,
        onTranslationToggle: {},
        onRetry: nil
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
        error: nil,
        translationEnabled: true,
        styleLearningEnabled: true,
        onSuggestionTap: { _, _ in },
        onSuggestionDismiss: nil,
        onTranslationToggle: {},
        onRetry: nil
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
            error: nil,
            translationEnabled: false,
            styleLearningEnabled: true,
            onSuggestionTap: { _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
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
            error: nil,
            translationEnabled: false,
            styleLearningEnabled: true,
            onSuggestionTap: { _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )
    }
    .padding()
}

#Preview("Network Error with Retry") {
    SmartReplyComposerView(
        suggestions: [],
        isLoading: false,
        error: .networkError(URLError(.notConnectedToInternet)),
        translationEnabled: false,
        styleLearningEnabled: true,
        onSuggestionTap: { _, _ in },
        onSuggestionDismiss: nil,
        onTranslationToggle: {},
        onRetry: {
            print("Retry tapped")
        }
    )
    .padding()
}

#Preview("Rate Limit Error") {
    SmartReplyComposerView(
        suggestions: [],
        isLoading: false,
        error: .rateLimitExceeded(
            retryAfter: Date().addingTimeInterval(300),
            remainingQuota: 0,
            tierLimit: "Premium"
        ),
        translationEnabled: false,
        styleLearningEnabled: true,
        onSuggestionTap: { _, _ in },
        onSuggestionDismiss: nil,
        onTranslationToggle: {},
        onRetry: nil
    )
    .padding()
}

#Preview("Unauthorized Error") {
    SmartReplyComposerView(
        suggestions: [],
        isLoading: false,
        error: .unauthorized,
        translationEnabled: false,
        styleLearningEnabled: true,
        onSuggestionTap: { _, _ in },
        onSuggestionDismiss: nil,
        onTranslationToggle: {},
        onRetry: nil
    )
    .padding()
}

#Preview("Confidence Levels") {
    VStack(spacing: 20) {
        Text("Confidence Score Indicators")
            .font(.headline)

        Text("High Confidence (>80%)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        SmartReplyComposerView(
            suggestions: [
                SmartReplySuggestion(
                    id: UUID(),
                    type: "quick-reply",
                    content: "Sounds great!",
                    confidence: 0.95,
                    position: 0,
                    context: "",
                    timestamp: Date()
                ),
                SmartReplySuggestion(
                    id: UUID(),
                    type: "contextual",
                    content: "Thanks for letting me know",
                    confidence: 0.87,
                    position: 1,
                    context: "",
                    timestamp: Date()
                )
            ],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            styleLearningEnabled: true,
            onSuggestionTap: { _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        Divider()

        Text("Medium Confidence (60-80%)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        SmartReplyComposerView(
            suggestions: [
                SmartReplySuggestion(
                    id: UUID(),
                    type: "contextual",
                    content: "I'll check on that",
                    confidence: 0.72,
                    position: 0,
                    context: "",
                    timestamp: Date()
                ),
                SmartReplySuggestion(
                    id: UUID(),
                    type: "proactive",
                    content: "Let me get back to you",
                    confidence: 0.65,
                    position: 1,
                    context: "",
                    timestamp: Date()
                )
            ],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            styleLearningEnabled: true,
            onSuggestionTap: { _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        Divider()

        Text("Low Confidence (<60%)")
            .font(.subheadline)
            .foregroundColor(.secondary)
        SmartReplyComposerView(
            suggestions: [
                SmartReplySuggestion(
                    id: UUID(),
                    type: "proactive",
                    content: "Maybe we should discuss this",
                    confidence: 0.48,
                    position: 0,
                    context: "",
                    timestamp: Date()
                ),
                SmartReplySuggestion(
                    id: UUID(),
                    type: "contextual",
                    content: "I'm not entirely sure",
                    confidence: 0.52,
                    position: 1,
                    context: "",
                    timestamp: Date()
                )
            ],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            styleLearningEnabled: true,
            onSuggestionTap: { _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )
    }
    .padding()
}
