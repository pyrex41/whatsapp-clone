//
//  AIStyleProfileView.swift
//  GlobalBridge
//
//  Task 18: View to display user style profile metrics
//  Shows formality level, emoji frequency, sentence length, confidence score,
//  and provides options to disable/clear the profile
//

import SwiftUI

struct AIStyleProfileView: View {
    @EnvironmentObject private var store: Store<AppState, AppAction>
    @State private var showClearConfirmation = false
    @State private var showDisableConfirmation = false

    var body: some View {
        List {
            if let profile = store.state.userStyleProfile {
                // Profile Metrics Section
                Section(header: Text("Your Messaging Style")) {
                    MetricRow(
                        title: "Formality Level",
                        value: formatFormality(profile.formalityLevel),
                        icon: "text.quote",
                        detail: String(format: "%.0f%%", profile.formalityLevel * 100)
                    )

                    MetricRow(
                        title: "Emoji Usage",
                        value: formatEmojiFrequency(profile.emojiFrequency),
                        icon: "face.smiling",
                        detail: String(format: "%.1f per message", profile.emojiFrequency)
                    )

                    MetricRow(
                        title: "Sentence Length",
                        value: formatSentenceLength(profile.avgSentenceLength),
                        icon: "text.alignleft",
                        detail: String(format: "%.0f words avg", profile.avgSentenceLength)
                    )

                    MetricRow(
                        title: "Messages Analyzed",
                        value: "\(profile.messagesAnalyzed)",
                        icon: "chart.bar.fill",
                        detail: "samples"
                    )
                }

                // Confidence Score Section
                Section(header: Text("Profile Confidence")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: confidenceIcon(profile.confidenceScore))
                                .foregroundColor(confidenceColor(profile.confidenceScore))
                            Text("Confidence Score")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.0f%%", profile.confidenceScore * 100))
                                .font(.headline)
                                .foregroundColor(confidenceColor(profile.confidenceScore))
                        }

                        // Confidence Progress Bar
                        ConfidenceProgressView(confidence: profile.confidenceScore)

                        Text(confidenceDescription(profile.confidenceScore))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                // Profile Info Section
                Section {
                    HStack {
                        Text("Last Updated")
                        Spacer()
                        Text(formatDate(profile.lastUpdatedAt))
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)

                    HStack {
                        Text("User ID")
                        Spacer()
                        Text(profile.userId.uuidString.prefix(8) + "...")
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .font(.caption)
                }

                // Actions Section
                Section {
                    Button(action: refreshProfile) {
                        Label("Refresh Profile", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive, action: { showClearConfirmation = true }) {
                        Label("Clear Profile Data", systemImage: "trash")
                    }
                }

            } else {
                // No Profile State
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Style Profile Available")
                            .font(.headline)

                        Text("Your messaging style profile will be generated as you send messages.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: fetchProfile) {
                            Label("Fetch Profile", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("AI Style Profile")
        .alert("Clear Profile Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive, action: clearProfile)
        } message: {
            Text("This will remove all analyzed messaging style data. This action cannot be undone.")
        }
    }

    // MARK: - Actions

    private func refreshProfile() {
        store.send(.fetchStyleProfile)
    }

    private func fetchProfile() {
        store.send(.fetchStyleProfile)
    }

    private func clearProfile() {
        // TODO: Add clearStyleProfile action to AppAction
        // Convert user.id (String) to UUID
        guard let userId = UUID(uuidString: store.state.user.id) else {
            print("⚠️ [AIStyleProfileView] Invalid user ID format")
            return
        }

        store.send(.styleProfileUpdated(UserStyleProfile(
            userId: userId,
            formalityLevel: 0.5,
            emojiFrequency: 0.0,
            avgSentenceLength: 0.0,
            messagesAnalyzed: 0,
            confidenceScore: 0.0
        )))
    }

    // MARK: - Formatting Helpers

    private func formatFormality(_ level: Double) -> String {
        switch level {
        case 0.0..<0.3: return "Very Casual"
        case 0.3..<0.5: return "Casual"
        case 0.5..<0.7: return "Neutral"
        case 0.7..<0.9: return "Formal"
        default: return "Very Formal"
        }
    }

    private func formatEmojiFrequency(_ frequency: Double) -> String {
        switch frequency {
        case 0.0..<0.5: return "Minimal"
        case 0.5..<1.5: return "Low"
        case 1.5..<3.0: return "Moderate"
        case 3.0..<5.0: return "High"
        default: return "Very High"
        }
    }

    private func formatSentenceLength(_ length: Double) -> String {
        switch length {
        case 0.0..<5.0: return "Very Short"
        case 5.0..<10.0: return "Short"
        case 10.0..<20.0: return "Medium"
        case 20.0..<30.0: return "Long"
        default: return "Very Long"
        }
    }

    private func confidenceIcon(_ confidence: Double) -> String {
        switch confidence {
        case 0.0..<0.3: return "exclamationmark.triangle.fill"
        case 0.3..<0.6: return "info.circle.fill"
        case 0.6..<0.8: return "checkmark.circle.fill"
        default: return "star.circle.fill"
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.0..<0.3: return .red
        case 0.3..<0.6: return .orange
        case 0.6..<0.8: return .blue
        default: return .green
        }
    }

    private func confidenceDescription(_ confidence: Double) -> String {
        switch confidence {
        case 0.0..<0.3:
            return "Low confidence - more messages needed for accurate analysis"
        case 0.3..<0.6:
            return "Moderate confidence - profile is still learning your style"
        case 0.6..<0.8:
            return "Good confidence - profile reflects your messaging patterns"
        default:
            return "High confidence - profile accurately represents your style"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Supporting Views

struct MetricRow: View {
    let title: String
    let value: String
    let icon: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}

struct ConfidenceProgressView: View {
    let confidence: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 8)

                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradientColors),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * confidence, height: 8)
            }
        }
        .frame(height: 8)
    }

    private var gradientColors: [Color] {
        switch confidence {
        case 0.0..<0.3:
            return [.red, .orange]
        case 0.3..<0.6:
            return [.orange, .yellow]
        case 0.6..<0.8:
            return [.yellow, .blue]
        default:
            return [.blue, .green]
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("With Profile") {
    NavigationView {
        AIStyleProfileView()
            .environmentObject(Store(
                initialState: AppState(
                    userStyleProfile: UserStyleProfile(
                        userId: UUID(),
                        formalityLevel: 0.65,
                        emojiFrequency: 2.3,
                        avgSentenceLength: 12.5,
                        messagesAnalyzed: 156,
                        confidenceScore: 0.87,
                        lastUpdatedAt: Date().addingTimeInterval(-3600)
                    )
                ),
                reducer: appReducer,
                environment: .preview
            ))
    }
}

#Preview("No Profile") {
    NavigationView {
        AIStyleProfileView()
            .environmentObject(Store(
                initialState: AppState(),
                reducer: appReducer,
                environment: .preview
            ))
    }
}

#Preview("Low Confidence") {
    NavigationView {
        AIStyleProfileView()
            .environmentObject(Store(
                initialState: AppState(
                    userStyleProfile: UserStyleProfile(
                        userId: UUID(),
                        formalityLevel: 0.45,
                        emojiFrequency: 1.1,
                        avgSentenceLength: 8.2,
                        messagesAnalyzed: 23,
                        confidenceScore: 0.35,
                        lastUpdatedAt: Date().addingTimeInterval(-86400)
                    )
                ),
                reducer: appReducer,
                environment: .preview
            ))
    }
}
#endif
