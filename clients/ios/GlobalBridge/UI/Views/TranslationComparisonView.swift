//
//  TranslationComparisonView.swift
//  GlobalBridge
//
//  Side-by-side translation comparison UI for hybrid mode.
//  Displays Apple Translation vs Backend Translation with visual quality indicators,
//  performance metrics, user voting, and copy functionality.
//
//  Features:
//  - Real-time comparison (both providers run concurrently)
//  - Visual quality indicators (color-coded confidence)
//  - Performance metrics (latency display)
//  - User voting on better translation
//  - Cultural notes comparison
//  - Copy either translation to clipboard
//  - Smooth animations and SwiftUI polish
//  - Accessibility support
//  - Dark mode support
//

import SwiftUI

// MARK: - Translation Comparison Result

/// Extended translation result for comparison UI
struct TranslationComparison: Identifiable, Equatable {
    let id = UUID()
    let originalText: String
    let sourceLanguage: String
    let targetLanguage: String

    // Primary translation (usually backend)
    let primaryTranslation: String
    let primaryProvider: String
    let primaryConfidence: Double
    let primaryCulturalNotes: String?

    // Alternate translation (usually apple)
    let alternateTranslation: String?
    let alternateProvider: String?
    let alternateConfidence: Double?
    let alternateCulturalNotes: String?

    // Performance metrics
    let latencyMs: Int
    let timestamp: Date

    // User feedback
    var userPreference: TranslationPreference?
    var userFeedback: String?

    /// Create from UnifiedTranslationResult
    init(from result: UnifiedTranslationResult) {
        self.originalText = result.originalText
        self.sourceLanguage = result.sourceLanguage
        self.targetLanguage = result.targetLanguage
        self.primaryTranslation = result.translatedText
        self.primaryProvider = result.provider
        self.primaryConfidence = result.confidence
        self.primaryCulturalNotes = result.culturalNotes
        self.alternateTranslation = result.alternateTranslation
        self.alternateProvider = result.alternateProvider
        self.alternateConfidence = result.alternateConfidence
        self.alternateCulturalNotes = nil // Not available in current result
        self.latencyMs = result.latencyMs
        self.timestamp = result.timestamp
        self.userPreference = nil
        self.userFeedback = nil
    }

    /// Has alternate translation for comparison
    var hasComparison: Bool {
        alternateTranslation != nil && alternateProvider != nil
    }

    /// Are translations identical
    var isIdentical: Bool {
        guard let alternate = alternateTranslation else { return false }
        return primaryTranslation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
               alternate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// User preference for translation quality
enum TranslationPreference: String, Codable {
    case primary = "primary"
    case alternate = "alternate"
    case both = "both"        // Both are good
    case neither = "neither"  // Both are poor
}

// MARK: - Translation Comparison View

/// Side-by-side translation comparison UI
struct TranslationComparisonView: View {

    // MARK: - Properties

    let comparison: TranslationComparison
    let onVote: ((TranslationPreference) -> Void)?
    let onFeedback: ((String) -> Void)?

    @State private var selectedPreference: TranslationPreference?
    @State private var showFeedbackSheet = false
    @State private var feedbackText = ""
    @State private var copiedProvider: String?
    @State private var showCopyConfirmation = false
    @State private var expandedNotes: String?

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Initialization

    init(
        comparison: TranslationComparison,
        onVote: ((TranslationPreference) -> Void)? = nil,
        onFeedback: ((String) -> Void)? = nil
    ) {
        self.comparison = comparison
        self.onVote = onVote
        self.onFeedback = onFeedback
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with original text
                originalTextSection

                // Performance metrics
                performanceSection

                if comparison.hasComparison {
                    // Side-by-side comparison
                    comparisonSection

                    // Voting section
                    votingSection
                } else {
                    // Single translation (no comparison)
                    singleTranslationSection
                }

                // Cultural notes (if available)
                if comparison.primaryCulturalNotes != nil || comparison.alternateCulturalNotes != nil {
                    culturalNotesSection
                }

                // Feedback button
                feedbackButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showFeedbackSheet) {
            feedbackSheetContent
        }
        .overlay {
            if showCopyConfirmation {
                copyConfirmationOverlay
            }
        }
    }

    // MARK: - Original Text Section

    private var originalTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Original Text")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(languageLabel(comparison.sourceLanguage))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }

            Text(comparison.originalText)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        HStack(spacing: 20) {
            // Latency
            VStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("\(comparison.latencyMs)ms")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Latency")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Translation count
            VStack(spacing: 4) {
                Image(systemName: comparison.hasComparison ? "arrow.left.arrow.right" : "arrow.right")
                    .font(.title3)
                    .foregroundColor(.green)
                Text(comparison.hasComparison ? "2" : "1")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Providers")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            if comparison.isIdentical {
                Divider()

                // Identical indicator
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                    Text("Identical")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Results")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Comparison Section

    private var comparisonSection: some View {
        VStack(spacing: 16) {
            Text("Side-by-Side Comparison")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 12) {
                // Primary translation
                translationCard(
                    text: comparison.primaryTranslation,
                    provider: comparison.primaryProvider,
                    confidence: comparison.primaryConfidence,
                    isPrimary: true
                )

                // Alternate translation
                if let alternateText = comparison.alternateTranslation,
                   let alternateProvider = comparison.alternateProvider,
                   let alternateConfidence = comparison.alternateConfidence {
                    translationCard(
                        text: alternateText,
                        provider: alternateProvider,
                        confidence: alternateConfidence,
                        isPrimary: false
                    )
                }
            }
        }
    }

    // MARK: - Translation Card

    private func translationCard(
        text: String,
        provider: String,
        confidence: Double,
        isPrimary: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider header
            HStack {
                Image(systemName: providerIcon(provider))
                    .font(.caption)
                    .foregroundColor(providerColor(provider))

                Text(providerLabel(provider))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(providerColor(provider))

                Spacer()

                if isPrimary {
                    Text("Primary")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
            }

            // Confidence indicator
            confidenceIndicator(confidence)

            // Translation text
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Copy button
            Button(action: {
                copyTranslation(text, provider: provider)
            }) {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                    Text("Copy")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedPreference == (isPrimary ? .primary : .alternate) ? Color.green : Color.clear, lineWidth: 2)
                )
        )
    }

    // MARK: - Confidence Indicator

    private func confidenceIndicator(_ confidence: Double) -> some View {
        HStack(spacing: 8) {
            // Color-coded quality indicator
            Circle()
                .fill(confidenceColor(confidence))
                .frame(width: 8, height: 8)

            Text("Confidence: \(Int(confidence * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Quality badge
            Text(qualityLabel(confidence))
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(confidenceColor(confidence))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(confidenceColor(confidence).opacity(0.2))
                .cornerRadius(4)
        }
    }

    // MARK: - Voting Section

    private var votingSection: some View {
        VStack(spacing: 12) {
            Text("Which translation is better?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                // Primary vote
                voteButton(
                    title: providerLabel(comparison.primaryProvider),
                    preference: .primary,
                    icon: "hand.thumbsup.fill"
                )

                // Alternate vote
                voteButton(
                    title: providerLabel(comparison.alternateProvider ?? ""),
                    preference: .alternate,
                    icon: "hand.thumbsup.fill"
                )
            }

            HStack(spacing: 12) {
                // Both good
                voteButton(
                    title: "Both Good",
                    preference: .both,
                    icon: "checkmark.circle.fill"
                )

                // Neither good
                voteButton(
                    title: "Neither",
                    preference: .neither,
                    icon: "xmark.circle.fill"
                )
            }

            if selectedPreference != nil {
                Text("Thank you for your feedback!")
                    .font(.caption)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // MARK: - Vote Button

    private func voteButton(
        title: String,
        preference: TranslationPreference,
        icon: String
    ) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedPreference = preference
                onVote?(preference)
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(selectedPreference == preference ? .white : .blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedPreference == preference ? Color.blue : Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Single Translation Section

    private var singleTranslationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Translation")
                    .font(.headline)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: providerIcon(comparison.primaryProvider))
                        .font(.caption)
                        .foregroundColor(providerColor(comparison.primaryProvider))
                    Text(providerLabel(comparison.primaryProvider))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(providerColor(comparison.primaryProvider))
                }
            }

            confidenceIndicator(comparison.primaryConfidence)

            Text(comparison.primaryTranslation)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)

            Button(action: {
                copyTranslation(comparison.primaryTranslation, provider: comparison.primaryProvider)
            }) {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                    Text("Copy Translation")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
        }
    }

    // MARK: - Cultural Notes Section

    private var culturalNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cultural Notes")
                .font(.headline)

            if let primaryNotes = comparison.primaryCulturalNotes {
                culturalNoteCard(
                    notes: primaryNotes,
                    provider: comparison.primaryProvider,
                    isExpanded: expandedNotes == comparison.primaryProvider
                )
            }

            if let alternateNotes = comparison.alternateCulturalNotes,
               let alternateProvider = comparison.alternateProvider {
                culturalNoteCard(
                    notes: alternateNotes,
                    provider: alternateProvider,
                    isExpanded: expandedNotes == alternateProvider
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func culturalNoteCard(notes: String, provider: String, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation {
                    expandedNotes = isExpanded ? nil : provider
                }
            }) {
                HStack {
                    Image(systemName: providerIcon(provider))
                        .font(.caption)
                        .foregroundColor(providerColor(provider))

                    Text(providerLabel(provider))
                        .font(.caption)
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(.primary)

            if isExpanded {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .padding()
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }

    // MARK: - Feedback Button

    private var feedbackButton: some View {
        Button(action: {
            showFeedbackSheet = true
        }) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                Text("Provide Additional Feedback")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Feedback Sheet

    private var feedbackSheetContent: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Help us improve translations")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $feedbackText)
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(8)

                Spacer()
            }
            .padding()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showFeedbackSheet = false
                        feedbackText = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        onFeedback?(feedbackText)
                        showFeedbackSheet = false
                        feedbackText = ""
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Copy Confirmation Overlay

    private var copyConfirmationOverlay: some View {
        VStack {
            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                Text("Copied to clipboard!")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .padding(.bottom, 50)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showCopyConfirmation = false
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func copyTranslation(_ text: String, provider: String) {
        UIPasteboard.general.string = text
        copiedProvider = provider
        withAnimation {
            showCopyConfirmation = true
        }
    }

    private func providerIcon(_ provider: String) -> String {
        switch provider.lowercased() {
        case "apple":
            return "apple.logo"
        case "backend", "openai", "anthropic":
            return "cloud.fill"
        default:
            return "globe"
        }
    }

    private func providerLabel(_ provider: String) -> String {
        switch provider.lowercased() {
        case "apple":
            return "Apple Translation"
        case "backend":
            return "Backend Translation"
        case "openai":
            return "OpenAI"
        case "anthropic":
            return "Claude"
        default:
            return provider.capitalized
        }
    }

    private func providerColor(_ provider: String) -> Color {
        switch provider.lowercased() {
        case "apple":
            return .blue
        case "backend", "openai", "anthropic":
            return .purple
        default:
            return .gray
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.9 {
            return .green
        } else if confidence >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    private func qualityLabel(_ confidence: Double) -> String {
        if confidence >= 0.9 {
            return "Excellent"
        } else if confidence >= 0.7 {
            return "Good"
        } else {
            return "Fair"
        }
    }

    private func languageLabel(_ code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code) ?? code.uppercased()
    }
}

// MARK: - SwiftUI Previews

#Preview("Hybrid Comparison") {
    let comparison = TranslationComparison(
        from: UnifiedTranslationResult(
            originalText: "Hello, how are you today?",
            translatedText: "Hola, ¿cómo estás hoy?",
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceLanguageCode: "en",
            targetLanguageCode: "es",
            confidence: 0.95,
            provider: "backend",
            culturalNotes: "In Spanish, formal 'usted' form could be used for more respectful greetings",
            timestamp: Date(),
            alternateTranslation: "Hola, ¿cómo está usted hoy?",
            alternateProvider: "apple",
            alternateConfidence: 0.88,
            latencyMs: 245,
            cacheHit: false,
            fallbackUsed: false
        )
    )

    TranslationComparisonView(
        comparison: comparison,
        onVote: { preference in
            print("User voted: \(preference.rawValue)")
        },
        onFeedback: { feedback in
            print("User feedback: \(feedback)")
        }
    )
}

#Preview("Single Translation") {
    let comparison = TranslationComparison(
        from: UnifiedTranslationResult(
            originalText: "Good morning!",
            translatedText: "Buenos días!",
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceLanguageCode: "en",
            targetLanguageCode: "es",
            confidence: 0.92,
            provider: "apple",
            culturalNotes: "Common morning greeting in Spanish-speaking countries",
            timestamp: Date(),
            alternateTranslation: nil,
            alternateProvider: nil,
            alternateConfidence: nil,
            latencyMs: 120,
            cacheHit: false,
            fallbackUsed: false
        )
    )

    TranslationComparisonView(
        comparison: comparison
    )
}

#Preview("Identical Results") {
    let comparison = TranslationComparison(
        from: UnifiedTranslationResult(
            originalText: "Thank you",
            translatedText: "Gracias",
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceLanguageCode: "en",
            targetLanguageCode: "es",
            confidence: 0.98,
            provider: "backend",
            culturalNotes: nil,
            timestamp: Date(),
            alternateTranslation: "Gracias",
            alternateProvider: "apple",
            alternateConfidence: 0.97,
            latencyMs: 180,
            cacheHit: false,
            fallbackUsed: false
        )
    )

    TranslationComparisonView(comparison: comparison)
}

#Preview("Dark Mode") {
    let comparison = TranslationComparison(
        from: UnifiedTranslationResult(
            originalText: "Where is the nearest restaurant?",
            translatedText: "¿Dónde está el restaurante más cercano?",
            sourceLanguage: "en",
            targetLanguage: "es",
            sourceLanguageCode: "en",
            targetLanguageCode: "es",
            confidence: 0.91,
            provider: "backend",
            culturalNotes: "Use 'más cercano' for nearest in distance",
            timestamp: Date(),
            alternateTranslation: "¿Dónde queda el restaurante más próximo?",
            alternateProvider: "apple",
            alternateConfidence: 0.86,
            latencyMs: 210,
            cacheHit: false,
            fallbackUsed: false
        )
    )

    TranslationComparisonView(comparison: comparison)
        .preferredColorScheme(.dark)
}
