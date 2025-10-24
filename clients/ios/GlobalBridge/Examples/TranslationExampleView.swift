//
//  TranslationExampleView.swift
//  GlobalBridge
//
//  Example SwiftUI view demonstrating UnifiedTranslationService usage
//  Shows provider selection, hybrid mode, metrics, and error handling
//

import SwiftUI

struct TranslationExampleView: View {

    // MARK: - State

    @StateObject private var translationService = UnifiedTranslationService.shared
    @StateObject private var networkMonitor = NetworkMonitor.shared

    @State private var inputText = ""
    @State private var translatedText = ""
    @State private var sourceLanguage = "en"
    @State private var targetLanguage = "es"
    @State private var selectedProvider: TranslationProvider = .auto

    @State private var isTranslating = false
    @State private var showError = false
    @State private var errorMessage = ""

    @State private var lastResult: UnifiedTranslationResult?
    @State private var showMetrics = false

    // MARK: - Body

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Network Status
                    networkStatusBanner

                    // Input Section
                    inputSection

                    // Language Selection
                    languageSection

                    // Provider Selection
                    providerSection

                    // Translate Button
                    translateButton

                    // Result Section
                    if let result = lastResult {
                        resultSection(result: result)
                    }

                    // Metrics Button
                    metricsButton
                }
                .padding()
            }
            .navigationTitle("Translation Service")
            .alert("Translation Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showMetrics) {
                metricsView
            }
        }
    }

    // MARK: - Subviews

    private var networkStatusBanner: some View {
        HStack {
            Image(systemName: networkMonitor.isConnected ? "wifi" : "wifi.slash")
                .foregroundColor(networkMonitor.isConnected ? .green : .red)

            Text(networkMonitor.isConnected ? "Online" : "Offline")
                .font(.subheadline)
                .foregroundColor(networkMonitor.isConnected ? .green : .red)

            Spacer()

            Text(networkMonitor.connectionType.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text to Translate")
                .font(.headline)

            TextEditor(text: $inputText)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var languageSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("From")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Source", selection: $sourceLanguage) {
                    Text("Auto").tag("auto")
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Chinese").tag("zh")
                    Text("Japanese").tag("ja")
                }
                .pickerStyle(.menu)
            }

            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)

            VStack(alignment: .leading) {
                Text("To")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Target", selection: $targetLanguage) {
                    Text("Spanish").tag("es")
                    Text("English").tag("en")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Chinese").tag("zh")
                    Text("Japanese").tag("ja")
                    Text("Korean").tag("ko")
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Translation Provider")
                .font(.headline)

            Picker("Provider", selection: $selectedProvider) {
                Label("Auto (Smart)", systemImage: "wand.and.stars")
                    .tag(TranslationProvider.auto)

                Label("Apple (On-device)", systemImage: "applelogo")
                    .tag(TranslationProvider.apple)

                Label("Backend (Cloud)", systemImage: "cloud")
                    .tag(TranslationProvider.backend)

                Label("Hybrid (Both)", systemImage: "square.split.2x1")
                    .tag(TranslationProvider.hybrid)
            }
            .pickerStyle(.segmented)

            // Provider description
            Text(providerDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }

    private var providerDescription: String {
        switch selectedProvider {
        case .auto:
            return "Automatically selects the best provider based on network, language support, and quotas"
        case .apple:
            return "On-device translation using Apple's ML models. Privacy-first, works offline"
        case .backend:
            return "Cloud-based translation with advanced features. Requires internet connection"
        case .hybrid:
            return "Translates with both providers for quality comparison"
        }
    }

    private var translateButton: some View {
        Button(action: performTranslation) {
            HStack {
                if isTranslating {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }

                Text(isTranslating ? "Translating..." : "Translate")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(inputText.isEmpty ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(inputText.isEmpty || isTranslating)
    }

    private func resultSection(result: UnifiedTranslationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            // Primary Translation
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Translation")
                        .font(.headline)

                    Spacer()

                    providerBadge(result.provider)
                }

                Text(result.translatedText)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                // Metadata
                HStack {
                    Label("\(Int(result.confidence * 100))%", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)

                    Label("\(result.latencyMs)ms", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if result.cacheHit {
                        Label("Cached", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if result.fallbackUsed {
                        Label("Fallback", systemImage: "arrow.uturn.left")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }

            // Alternate Translation (Hybrid Mode)
            if let alternate = result.alternateTranslation,
               let altProvider = result.alternateProvider,
               let altConfidence = result.alternateConfidence {

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Alternate Translation")
                            .font(.headline)

                        Spacer()

                        providerBadge(altProvider)
                    }

                    Text(alternate)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                    Label("\(Int(altConfidence * 100))% confidence", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Cultural Notes
            if let notes = result.culturalNotes {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Cultural Notes", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundColor(.blue)

                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }

    private func providerBadge(_ provider: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: provider == "apple" ? "applelogo" : "cloud")
                .font(.caption)

            Text(provider.capitalized)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(provider == "apple" ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
        .foregroundColor(provider == "apple" ? .blue : .green)
        .cornerRadius(4)
    }

    private var metricsButton: some View {
        Button(action: { showMetrics = true }) {
            HStack {
                Image(systemName: "chart.bar")
                Text("View Metrics")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .foregroundColor(.primary)
            .cornerRadius(10)
        }
    }

    private var metricsView: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let metrics = translationService.getMetrics()

                    // Overview
                    metricCard(
                        title: "Total Translations",
                        value: "\(metrics.totalTranslations)",
                        icon: "arrow.triangle.2.circlepath",
                        color: .blue
                    )

                    // Provider Breakdown
                    GroupBox(label: Label("Provider Usage", systemImage: "square.split.2x1")) {
                        VStack(alignment: .leading, spacing: 12) {
                            metricRow(
                                label: "Apple (On-device)",
                                value: "\(metrics.appleTranslations)",
                                color: .blue
                            )

                            metricRow(
                                label: "Backend (Cloud)",
                                value: "\(metrics.backendTranslations)",
                                color: .green
                            )

                            metricRow(
                                label: "Hybrid (Both)",
                                value: "\(metrics.hybridTranslations)",
                                color: .purple
                            )
                        }
                    }

                    // Performance
                    GroupBox(label: Label("Performance", systemImage: "speedometer")) {
                        VStack(alignment: .leading, spacing: 12) {
                            metricRow(
                                label: "Avg Latency",
                                value: String(format: "%.0fms", metrics.averageLatencyMs),
                                color: .orange
                            )

                            metricRow(
                                label: "Cache Hit Rate",
                                value: String(format: "%.1f%%", metrics.cacheHitRate * 100),
                                color: .green
                            )

                            metricRow(
                                label: "Fallback Rate",
                                value: String(format: "%.1f%%", metrics.fallbackRate * 100),
                                color: .yellow
                            )
                        }
                    }

                    // Reliability
                    GroupBox(label: Label("Reliability", systemImage: "shield.checkered")) {
                        VStack(alignment: .leading, spacing: 12) {
                            metricRow(
                                label: "Offline Translations",
                                value: "\(metrics.offlineTranslations)",
                                color: .red
                            )

                            metricRow(
                                label: "Errors",
                                value: "\(metrics.errorCount)",
                                color: .red
                            )

                            metricRow(
                                label: "Fallback Events",
                                value: "\(metrics.fallbackEvents)",
                                color: .yellow
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Translation Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showMetrics = false
                    }
                }
            }
        }
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.2))
                .cornerRadius(10)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func metricRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }

    // MARK: - Actions

    private func performTranslation() {
        Task {
            isTranslating = true
            defer { isTranslating = false }

            do {
                let result = try await translationService.translate(
                    text: inputText,
                    from: sourceLanguage,
                    to: targetLanguage,
                    provider: selectedProvider
                )

                lastResult = result
                translatedText = result.translatedText

            } catch let error as AIServiceError {
                errorMessage = error.localizedDescription
                showError = true
                print("Translation error: \(error)")

            } catch {
                errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                showError = true
                print("Unexpected error: \(error)")
            }
        }
    }
}

// MARK: - Preview

struct TranslationExampleView_Previews: PreviewProvider {
    static var previews: some View {
        TranslationExampleView()
    }
}
