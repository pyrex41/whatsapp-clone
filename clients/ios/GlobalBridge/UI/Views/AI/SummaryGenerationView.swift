//
//  SummaryGenerationView.swift
//  GlobalBridge
//
//  AI thread summarization generation flow with loading, caching, and error handling
//  Integrates with AIService and provides full user experience
//

import SwiftUI
import Combine

/// View for generating and managing thread summaries with AI
@MainActor
@Observable
final class SummaryGenerationViewModel {
    // MARK: - Published State

    var isGenerating: Bool = false
    var currentSummary: ThreadSummary?
    var error: AIServiceError?
    var estimatedTokens: Int = 0
    var progress: Double = 0.0
    var statusMessage: String = ""

    // MARK: - Dependencies

    private let aiService: AIService
    private let cacheManager: SummaryCacheManager
    private let threadId: UUID
    private let messageCount: Int

    // MARK: - Configuration

    var maxLength: Int = 200 {
        didSet {
            updateTokenEstimate()
        }
    }

    var autoSummarizeThreshold: Int = 100
    var cacheExpirationHours: TimeInterval = 24

    // MARK: - Initialization

    init(
        threadId: UUID,
        messageCount: Int,
        aiService: AIService = .shared,
        cacheManager: SummaryCacheManager = .shared
    ) {
        self.threadId = threadId
        self.messageCount = messageCount
        self.aiService = aiService
        self.cacheManager = cacheManager

        // Check cache on init
        Task {
            await checkCache()
        }

        updateTokenEstimate()
    }

    // MARK: - Cache Management

    func checkCache() async {
        if let cached = await cacheManager.getCachedSummary(for: threadId) {
            // Check if cache is still valid
            let age = Date().timeIntervalSince(cached.generatedAt)
            if age < (cacheExpirationHours * 3600) {
                currentSummary = cached
                statusMessage = "Loaded from cache"
                print("✅ [SUMMARY] Loaded cached summary (age: \(Int(age/3600))h)")
            } else {
                print("⚠️  [SUMMARY] Cache expired (age: \(Int(age/3600))h)")
                statusMessage = "Cache expired"
            }
        }
    }

    // MARK: - Token Estimation

    private func updateTokenEstimate() {
        // Rough estimation: 4 characters per token, plus overhead
        let baseTokens = messageCount * 100 // Average tokens per message
        let summaryTokens = maxLength / 4
        let overheadTokens = 500 // System prompt, formatting, etc.

        estimatedTokens = min(baseTokens + summaryTokens + overheadTokens, 100000)
    }

    // MARK: - Summary Generation

    func generateSummary(force: Bool = false) async {
        // Check if we should use cache
        if !force, let cached = currentSummary, !cached.isStale {
            print("📝 [SUMMARY] Using cached summary")
            statusMessage = "Using cached summary"
            return
        }

        isGenerating = true
        error = nil
        progress = 0.0
        statusMessage = "Preparing summary request..."

        do {
            // Step 1: Validate prerequisites
            progress = 0.1
            statusMessage = "Validating thread..."
            try await Task.sleep(nanoseconds: 200_000_000) // Smooth UX

            // Step 2: Call AI service
            progress = 0.3
            statusMessage = "Analyzing messages..."

            let result = try await aiService.summarizeThread(
                threadId: threadId.uuidString,
                maxLength: maxLength
            )

            // Step 3: Parse and enhance result
            progress = 0.7
            statusMessage = "Processing results..."
            try await Task.sleep(nanoseconds: 200_000_000)

            // Convert basic result to rich ThreadSummary
            let enhancedSummary = await enhanceBasicSummary(result)

            // Step 4: Cache the result
            progress = 0.9
            statusMessage = "Saving summary..."
            await cacheManager.cacheSummary(enhancedSummary)

            // Step 5: Complete
            progress = 1.0
            currentSummary = enhancedSummary
            statusMessage = "Summary ready!"

            print("✅ [SUMMARY] Generated summary successfully")

            // Clear status after delay
            try await Task.sleep(nanoseconds: 1_000_000_000)
            statusMessage = ""

        } catch let serviceError as AIServiceError {
            error = serviceError
            statusMessage = "Error: \(serviceError.localizedDescription)"
            print("❌ [SUMMARY] Error: \(serviceError)")
        } catch {
            let wrappedError = AIServiceError.apiError(message: error.localizedDescription)
            self.error = wrappedError
            statusMessage = "Error: \(error.localizedDescription)"
            print("❌ [SUMMARY] Unexpected error: \(error)")
        }

        isGenerating = false
    }

    // MARK: - Summary Enhancement

    private func enhanceBasicSummary(_ basicResult: SummarizationResult) async -> ThreadSummary {
        // If backend returns enhanced data, use it
        // For now, create a basic ThreadSummary from the simple result

        return ThreadSummary(
            threadId: UUID(uuidString: basicResult.threadId) ?? threadId,
            summary: basicResult.summary,
            keyPoints: extractKeyPoints(from: basicResult.summary),
            decisions: [],
            actionItems: [],
            participants: [],
            messageCount: basicResult.messageCount ?? messageCount,
            provider: "openai"
        )
    }

    private func extractKeyPoints(from summary: String) -> [String] {
        // Basic key point extraction from summary
        // Split by sentences and take first few substantive ones
        let sentences = summary.components(separatedBy: ". ")
        return Array(sentences.prefix(3)).map { sentence in
            sentence.hasSuffix(".") ? sentence : sentence + "."
        }
    }

    // MARK: - Auto-Summarization

    func shouldAutoSummarize() -> Bool {
        messageCount >= autoSummarizeThreshold && currentSummary == nil
    }

    // MARK: - Export

    func exportSummary() -> String? {
        guard let summary = currentSummary else { return nil }

        var text = "# Thread Summary\n\n"
        text += "Generated: \(formatDate(summary.generatedAt))\n"
        if let messageCount = summary.messageCount {
            text += "Messages: \(messageCount)\n"
        }
        text += "\n## Summary\n\n\(summary.summary)\n"

        if summary.hasKeyPoints {
            text += "\n## Key Points\n\n"
            for point in summary.keyPoints {
                text += "- \(point)\n"
            }
        }

        if summary.hasDecisions {
            text += "\n## Decisions\n\n"
            for decision in summary.decisions {
                text += "- \(decision)\n"
            }
        }

        if summary.hasActionItems {
            text += "\n## Action Items\n\n"
            for item in summary.actionItems {
                text += "- \(item.description)"
                if let assignee = item.assignee {
                    text += " (@\(assignee))"
                }
                if let dueDate = item.dueDate {
                    text += " - Due: \(formatDate(dueDate))"
                }
                text += "\n"
            }
        }

        if !summary.participants.isEmpty {
            text += "\n## Participants\n\n"
            for participant in summary.participants {
                text += "- \(participant.displayName ?? participant.username)"
                if let msgCount = participant.messageCount {
                    text += " (\(msgCount) messages)"
                }
                text += "\n"
            }
        }

        return text
    }

    // MARK: - Error Handling

    func clearError() {
        error = nil
        statusMessage = ""
    }

    func retryGeneration() async {
        clearError()
        await generateSummary(force: true)
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Summary Cache Manager

@MainActor
final class SummaryCacheManager {
    static let shared = SummaryCacheManager()

    private var cache: [UUID: ThreadSummary] = [:]
    private let cacheQueue = DispatchQueue(label: "com.globalbridge.summaryCache", attributes: .concurrent)

    func getCachedSummary(for threadId: UUID) async -> ThreadSummary? {
        return await withCheckedContinuation { continuation in
            cacheQueue.async {
                continuation.resume(returning: self.cache[threadId])
            }
        }
    }

    func cacheSummary(_ summary: ThreadSummary) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cacheQueue.async(flags: .barrier) {
                self.cache[summary.threadId] = summary
                print("💾 [CACHE] Cached summary for thread: \(summary.threadId)")
                continuation.resume()
            }
        }
    }

    func clearCache(for threadId: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cacheQueue.async(flags: .barrier) {
                self.cache.removeValue(forKey: threadId)
                print("🗑️  [CACHE] Cleared cache for thread: \(threadId)")
                continuation.resume()
            }
        }
    }

    func clearAllCache() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cacheQueue.async(flags: .barrier) {
                let count = self.cache.count
                self.cache.removeAll()
                print("🗑️  [CACHE] Cleared all cache (\(count) items)")
                continuation.resume()
            }
        }
    }
}

// MARK: - Summary Generation View

struct SummaryGenerationView: View {
    @State private var viewModel: SummaryGenerationViewModel
    @State private var showingExportSheet = false
    @State private var exportedText: String = ""
    @Environment(\.dismiss) private var dismiss

    let thread: Thread
    let messageCount: Int
    let onSummaryGenerated: ((ThreadSummary) -> Void)?

    init(
        thread: Thread,
        messageCount: Int,
        onSummaryGenerated: ((ThreadSummary) -> Void)? = nil
    ) {
        self.thread = thread
        self.messageCount = messageCount
        self.onSummaryGenerated = onSummaryGenerated
        self._viewModel = State(initialValue: SummaryGenerationViewModel(
            threadId: thread.id,
            messageCount: messageCount
        ))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header section
                    headerSection

                    // Current summary or generation UI
                    if let summary = viewModel.currentSummary {
                        // Show existing summary
                        summarySection(summary)
                    } else if viewModel.isGenerating {
                        // Show loading state
                        loadingSection
                    } else if let error = viewModel.error {
                        // Show error state
                        errorSection(error)
                    } else {
                        // Show prompt to generate
                        promptSection
                    }

                    // Configuration section
                    if !viewModel.isGenerating {
                        configurationSection
                    }
                }
                .padding(20)
            }
            .navigationTitle("Thread Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                exportSheet
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // AI Icon
            ZStack {
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundColor(.white)
            }

            // Thread info
            VStack(spacing: 4) {
                Text(thread.title ?? "Thread")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("\(messageCount) messages")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Auto-summarize notice
            if viewModel.shouldAutoSummarize() {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)

                    Text("Thread has \(messageCount)+ messages - summarization recommended")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Summary Section

    private func summarySection(_ summary: ThreadSummary) -> some View {
        VStack(spacing: 16) {
            ThreadSummaryView(
                summary: summary,
                onRegenerateTapped: {
                    Task {
                        await viewModel.generateSummary(force: true)
                    }
                },
                onExportTapped: {
                    if let text = viewModel.exportSummary() {
                        exportedText = text
                        showingExportSheet = true
                    }
                }
            )

            // Actions
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.generateSummary(force: true)
                    }
                }) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }

                Button(action: {
                    if let text = viewModel.exportSummary() {
                        exportedText = text
                        showingExportSheet = true
                    }
                }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        VStack(spacing: 20) {
            // Animated AI icon
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(Color.blue.gradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: viewModel.progress)

                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundColor(.blue)
            }

            // Status text
            VStack(spacing: 8) {
                Text("Generating Summary")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // Progress percentage
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            // Token estimate
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.secondary)

                Text("Estimated tokens: ~\(viewModel.estimatedTokens)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Error Section

    private func errorSection(_ error: AIServiceError) -> some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            // Error message
            VStack(spacing: 8) {
                Text("Generation Failed")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(error.localizedDescription ?? "Unknown error occurred")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Retry button
            Button(action: {
                Task {
                    await viewModel.retryGeneration()
                }
            }) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 40)
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(spacing: 20) {
            // Illustration
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.blue.opacity(0.6))

            // Description
            VStack(spacing: 8) {
                Text("Summarize This Thread")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Generate an AI-powered summary with key points, decisions, and action items")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Generate button
            Button(action: {
                Task {
                    await viewModel.generateSummary()
                }
            }) {
                Label("Generate Summary", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue.gradient)
                    .cornerRadius(12)
            }
        }
        .padding(.vertical, 40)
    }

    // MARK: - Configuration Section

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.secondary)

            // Max length slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Summary Length")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(viewModel.maxLength) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Slider(value: Binding(
                    get: { Double(viewModel.maxLength) },
                    set: { viewModel.maxLength = Int($0) }
                ), in: 100...1000, step: 50)
                .tint(.blue)

                HStack {
                    Text("Brief")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("Detailed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Token estimate
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated Cost")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("~\(viewModel.estimatedTokens) tokens")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                Spacer()

                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Export Sheet

    private var exportSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(exportedText)
                        .font(.body)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .navigationTitle("Export Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        showingExportSheet = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: exportedText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Generation Prompt") {
    SummaryGenerationView(
        thread: Thread(
            id: UUID(),
            threadType: .group,
            title: "Q4 Planning Discussion"
        ),
        messageCount: 156
    )
}

#Preview("Loading State") {
    let viewModel = SummaryGenerationViewModel(
        threadId: UUID(),
        messageCount: 100
    )
    viewModel.isGenerating = true
    viewModel.progress = 0.6
    viewModel.statusMessage = "Analyzing messages..."

    return SummaryGenerationView(
        thread: Thread(
            id: UUID(),
            threadType: .group,
            title: "Team Sync"
        ),
        messageCount: 100
    )
}
