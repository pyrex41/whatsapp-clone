//
//  TranslationComparisonExamples.swift
//  GlobalBridge
//
//  Usage examples for TranslationComparisonView
//

import SwiftUI

// MARK: - Example 1: Basic Usage with Hybrid Translation

struct BasicComparisonExample: View {
    @StateObject private var translationService = UnifiedTranslationService.shared
    @State private var comparison: TranslationComparison?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Basic Translation Comparison")
                .font(.title)
                .fontWeight(.bold)

            Button("Translate with Hybrid Mode") {
                Task {
                    await performHybridTranslation()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            if isLoading {
                ProgressView("Translating...")
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if let comparison = comparison {
                TranslationComparisonView(
                    comparison: comparison,
                    onVote: { preference in
                        print("✅ User voted: \(preference.rawValue)")
                    },
                    onFeedback: { feedback in
                        print("💬 User feedback: \(feedback)")
                    }
                )
            }
        }
        .padding()
    }

    private func performHybridTranslation() async {
        isLoading = true
        errorMessage = nil

        do {
            // Request hybrid translation (runs both providers concurrently)
            let result = try await translationService.translate(
                text: "Hello, how are you today?",
                from: "en",
                to: "es",
                provider: .hybrid
            )

            comparison = TranslationComparison(from: result)
        } catch {
            errorMessage = "Translation failed: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// MARK: - Example 2: Chat Integration with Comparison

struct ChatTranslationComparisonExample: View {
    @State private var message = "Good morning! How can I help you?"
    @State private var targetLanguage = "es"
    @State private var comparison: TranslationComparison?
    @State private var showComparison = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Original message
                Text(message)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)

                // Language selector
                HStack {
                    Text("Translate to:")
                    Picker("Language", selection: $targetLanguage) {
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Japanese").tag("ja")
                    }
                    .pickerStyle(.segmented)
                }

                // Compare button
                Button("Compare Translations") {
                    Task {
                        await compareTranslations()
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Chat Translation")
            .sheet(isPresented: $showComparison) {
                if let comparison = comparison {
                    NavigationView {
                        TranslationComparisonView(
                            comparison: comparison,
                            onVote: { preference in
                                saveUserPreference(preference)
                            },
                            onFeedback: { feedback in
                                submitFeedback(feedback)
                            }
                        )
                        .navigationTitle("Translation Quality")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showComparison = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func compareTranslations() async {
        do {
            let result = try await UnifiedTranslationService.shared.translate(
                text: message,
                from: "en",
                to: targetLanguage,
                provider: .hybrid
            )

            comparison = TranslationComparison(from: result)
            showComparison = true
        } catch {
            print("❌ Translation error: \(error)")
        }
    }

    private func saveUserPreference(_ preference: TranslationPreference) {
        print("💾 Saving user preference: \(preference.rawValue)")
        // Save to analytics or user preferences
    }

    private func submitFeedback(_ feedback: String) {
        print("📝 Submitting feedback: \(feedback)")
        // Send to backend analytics
    }
}

// MARK: - Example 3: Batch Translation Comparison

struct BatchTranslationComparisonExample: View {
    @State private var messages = [
        "Hello",
        "How are you?",
        "Thank you",
        "Goodbye"
    ]

    @State private var comparisons: [TranslationComparison] = []
    @State private var isProcessing = false
    @State private var selectedIndex: Int?

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Batch Translation Comparison")
                    .font(.title2)
                    .fontWeight(.bold)

                Button("Compare All") {
                    Task {
                        await compareAll()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

                if isProcessing {
                    ProgressView("Processing \(comparisons.count)/\(messages.count)...")
                }

                List {
                    ForEach(Array(comparisons.enumerated()), id: \.offset) { index, comparison in
                        Button(action: {
                            selectedIndex = index
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comparison.originalText)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                HStack {
                                    Text("\(comparison.primaryProvider) vs \(comparison.alternateProvider ?? "N/A")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    if comparison.isIdentical {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Batch Comparison")
            .sheet(item: $selectedIndex.map { Binding.constant(comparisons[$0]) }) { comparison in
                TranslationComparisonView(comparison: comparison)
            }
        }
    }

    private func compareAll() async {
        isProcessing = true
        comparisons = []

        for message in messages {
            do {
                let result = try await UnifiedTranslationService.shared.translate(
                    text: message,
                    from: "en",
                    to: "es",
                    provider: .hybrid
                )

                let comparison = TranslationComparison(from: result)
                comparisons.append(comparison)
            } catch {
                print("❌ Failed to translate '\(message)': \(error)")
            }
        }

        isProcessing = false
    }
}

// MARK: - Example 4: Quality Monitoring Dashboard

struct QualityMonitoringExample: View {
    @State private var votes: [TranslationPreference: Int] = [
        .primary: 0,
        .alternate: 0,
        .both: 0,
        .neither: 0
    ]

    @State private var comparison: TranslationComparison?
    @State private var feedbackHistory: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Translation Quality Monitor")
                    .font(.title2)
                    .fontWeight(.bold)

                // Voting statistics
                GroupBox("User Votes") {
                    VStack(spacing: 12) {
                        voteRow(preference: .primary, count: votes[.primary] ?? 0)
                        voteRow(preference: .alternate, count: votes[.alternate] ?? 0)
                        voteRow(preference: .both, count: votes[.both] ?? 0)
                        voteRow(preference: .neither, count: votes[.neither] ?? 0)
                    }
                }

                // Latest comparison
                if let comparison = comparison {
                    GroupBox("Latest Comparison") {
                        TranslationComparisonView(
                            comparison: comparison,
                            onVote: { preference in
                                recordVote(preference)
                            },
                            onFeedback: { feedback in
                                recordFeedback(feedback)
                            }
                        )
                    }
                }

                // Test button
                Button("Test New Translation") {
                    Task {
                        await testTranslation()
                    }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Quality Dashboard")
        }
    }

    private func voteRow(preference: TranslationPreference, count: Int) -> some View {
        HStack {
            Text(preference.rawValue.capitalized)
                .font(.body)

            Spacer()

            Text("\(count)")
                .font(.body)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
    }

    private func recordVote(_ preference: TranslationPreference) {
        votes[preference, default: 0] += 1
    }

    private func recordFeedback(_ feedback: String) {
        feedbackHistory.append(feedback)
        print("💬 Total feedback received: \(feedbackHistory.count)")
    }

    private func testTranslation() async {
        let testPhrases = [
            "Hello, world!",
            "How are you?",
            "Thank you very much",
            "I need help"
        ]

        if let randomPhrase = testPhrases.randomElement() {
            do {
                let result = try await UnifiedTranslationService.shared.translate(
                    text: randomPhrase,
                    from: "en",
                    to: "es",
                    provider: .hybrid
                )

                comparison = TranslationComparison(from: result)
            } catch {
                print("❌ Test translation failed: \(error)")
            }
        }
    }
}

// MARK: - Example 5: Offline vs Online Comparison

struct OfflineOnlineComparisonExample: View {
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var comparison: TranslationComparison?
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Offline vs Online Quality")
                .font(.title2)
                .fontWeight(.bold)

            // Network status
            HStack {
                Circle()
                    .fill(networkMonitor.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                Text(networkMonitor.isConnected ? "Online" : "Offline")
                    .font(.caption)
            }

            Button("Compare Translation Quality") {
                Task {
                    await compareQuality()
                }
            }
            .buttonStyle(.borderedProminent)

            if let comparison = comparison {
                TranslationComparisonView(
                    comparison: comparison,
                    onVote: { preference in
                        logQualityMetric(preference)
                    }
                )
            }
        }
        .padding()
        .alert("Network Required", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Backend comparison requires internet connection")
        }
    }

    private func compareQuality() async {
        if !networkMonitor.isConnected {
            showAlert = true
            return
        }

        do {
            let result = try await UnifiedTranslationService.shared.translate(
                text: "Good morning, how can I help you today?",
                from: "en",
                to: "es",
                provider: .hybrid
            )

            comparison = TranslationComparison(from: result)
        } catch {
            print("❌ Quality comparison failed: \(error)")
        }
    }

    private func logQualityMetric(_ preference: TranslationPreference) {
        print("📊 Quality metric: \(preference.rawValue) (Network: \(networkMonitor.isConnected ? "online" : "offline"))")
        // Log to analytics
    }
}

// MARK: - Previews

#Preview("Basic Example") {
    BasicComparisonExample()
}

#Preview("Chat Integration") {
    ChatTranslationComparisonExample()
}

#Preview("Batch Comparison") {
    BatchTranslationComparisonExample()
}

#Preview("Quality Monitoring") {
    QualityMonitoringExample()
}

#Preview("Offline vs Online") {
    OfflineOnlineComparisonExample()
}
