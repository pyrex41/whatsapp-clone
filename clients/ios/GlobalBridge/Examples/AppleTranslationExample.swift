//
//  AppleTranslationExample.swift
//  GlobalBridge
//
//  Example implementations showing how to use AppleTranslationService
//  in real-world scenarios
//

import SwiftUI
import Combine

// MARK: - Example 1: Message Translation in Chat View

struct MessageRowWithTranslation: View {
    @StateObject private var translationService = AppleTranslationService()
    @State private var translatedText: String?
    @State private var isTranslating = false
    @State private var showOriginal = false

    let message: Message
    let userLanguage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Original message or translated text
            Text(showOriginal ? message.text : (translatedText ?? message.text))
                .font(.body)
                .foregroundColor(.primary)

            // Translation controls
            HStack {
                // Show original button (if translated)
                if translatedText != nil {
                    Button {
                        showOriginal.toggle()
                    } label: {
                        Label(
                            showOriginal ? "Show Translation" : "Show Original",
                            systemImage: "arrow.2.squarepath"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                // Translate button
                if !isTranslating {
                    Button {
                        Task {
                            await translateMessage()
                        }
                    } label: {
                        Label("Translate", systemImage: "globe")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private func translateMessage() async {
        isTranslating = true
        defer { isTranslating = false }

        do {
            let result = try await translationService.translate(
                text: message.text,
                from: "auto",
                to: userLanguage
            )

            withAnimation {
                translatedText = result.translatedText
            }

            // Log analytics
            print("✅ Translated message \(message.id) with confidence: \(result.confidence ?? 0)")

        } catch AIServiceError.unsupportedLanguage(let code) {
            print("⚠️ Unsupported language: \(code)")
            // Show alert to user

        } catch {
            print("❌ Translation failed: \(error)")
            // Show error to user
        }
    }
}

// MARK: - Example 2: Batch Translation for Thread

class ThreadTranslationViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var translatedMessages: [UUID: String] = [:]
    @Published var isTranslatingAll = false
    @Published var translationProgress: Double = 0

    private let translationService = AppleTranslationService()
    private let targetLanguage: String

    init(targetLanguage: String) {
        self.targetLanguage = targetLanguage
    }

    /// Translate all messages in the thread
    func translateAllMessages() async {
        isTranslatingAll = true
        translationProgress = 0
        defer { isTranslatingAll = false }

        let texts = messages.map { $0.text }

        do {
            let results = try await translationService.batchTranslate(
                texts: texts,
                from: "auto",
                to: targetLanguage
            )

            // Update UI with translations
            await MainActor.run {
                for (index, result) in results.enumerated() {
                    let messageId = messages[index].id
                    translatedMessages[messageId] = result.translatedText

                    // Update progress
                    translationProgress = Double(index + 1) / Double(messages.count)
                }
            }

            print("✅ Translated \(results.count) messages")

        } catch {
            print("❌ Batch translation failed: \(error)")
        }
    }

    /// Translate a single message
    func translateMessage(_ message: Message) async {
        do {
            let result = try await translationService.translate(
                text: message.text,
                from: "auto",
                to: targetLanguage
            )

            await MainActor.run {
                translatedMessages[message.id] = result.translatedText
            }

        } catch {
            print("❌ Translation failed for message \(message.id): \(error)")
        }
    }
}

// MARK: - Example 3: Language Model Management View

struct LanguageModelManagerView: View {
    @StateObject private var service = AppleTranslationService()
    @State private var selectedSourceLanguage = "en"
    @State private var selectedTargetLanguage = "es"
    @State private var isDownloading = false
    @State private var showError = false
    @State private var errorMessage = ""

    let supportedLanguages = [
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ar", "Arabic"),
        ("ru", "Russian"),
        ("hi", "Hindi")
    ]

    var body: some View {
        NavigationView {
            List {
                // Language pair selector
                Section("Download Translation Model") {
                    Picker("From", selection: $selectedSourceLanguage) {
                        ForEach(supportedLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }

                    Picker("To", selection: $selectedTargetLanguage) {
                        ForEach(supportedLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }

                    if isPairSupported {
                        if isPairAvailable {
                            HStack {
                                Label("Model Available", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)

                                Spacer()

                                Button("Delete") {
                                    Task {
                                        await deleteModel()
                                    }
                                }
                                .foregroundColor(.red)
                            }
                        } else {
                            Button {
                                Task {
                                    await downloadModel()
                                }
                            } label: {
                                if isDownloading {
                                    HStack {
                                        ProgressView()
                                        Text("Downloading...")
                                    }
                                } else {
                                    Label("Download Model (~50MB)", systemImage: "arrow.down.circle")
                                }
                            }
                            .disabled(isDownloading)

                            // Show progress
                            if let progress = service.downloadProgress[languagePairKey] {
                                ProgressView(value: progress)
                                    .padding(.top, 4)
                                Text("\(Int(progress * 100))% complete")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Label("Language pair not supported", systemImage: "xmark.circle")
                            .foregroundColor(.orange)
                    }
                }

                // Available models list
                Section("Downloaded Models") {
                    if service.availableLanguagePairs.isEmpty {
                        Text("No models downloaded")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(service.availableLanguagePairs).sorted(), id: \.self) { pair in
                            LanguageModelRow(languagePair: pair)
                        }
                    }
                }

                // Storage info
                Section("Storage") {
                    HStack {
                        Text("Models")
                        Spacer()
                        Text("\(service.availableLanguagePairs.count) downloaded")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Estimated Size")
                        Spacer()
                        Text("~\(service.availableLanguagePairs.count * 100)MB")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Translation Models")
            .task {
                await service.checkAvailableLanguagePairs()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var languagePairKey: String {
        "\(selectedSourceLanguage)_\(selectedTargetLanguage)"
    }

    private var isPairSupported: Bool {
        AppleTranslationService.supportedLanguagePairs.contains(languagePairKey)
    }

    private var isPairAvailable: Bool {
        service.availableLanguagePairs.contains(languagePairKey)
    }

    private func downloadModel() async {
        isDownloading = true
        defer { isDownloading = false }

        do {
            let success = try await service.downloadModel(
                from: selectedSourceLanguage,
                to: selectedTargetLanguage
            )

            if !success {
                errorMessage = "Model download failed"
                showError = true
            }

        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteModel() async {
        await service.deleteModel(
            from: selectedSourceLanguage,
            to: selectedTargetLanguage
        )
    }
}

struct LanguageModelRow: View {
    let languagePair: String

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(languageName(languagePair))
                        .font(.body)
                    Text(languagePair)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "globe")
                    .foregroundColor(.blue)
            }

            Spacer()

            Text("~100MB")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func languageName(_ pair: String) -> String {
        let components = pair.components(separatedBy: "_")
        guard components.count == 2 else { return pair }

        let source = Locale.current.localizedString(forLanguageCode: components[0]) ?? components[0]
        let target = Locale.current.localizedString(forLanguageCode: components[1]) ?? components[1]

        return "\(source) → \(target)"
    }
}

// MARK: - Example 4: Auto-Translation Toggle

struct ChatSettingsView: View {
    @AppStorage("autoTranslateEnabled") private var autoTranslateEnabled = false
    @AppStorage("translationLanguage") private var translationLanguage = "en"

    var body: some View {
        Form {
            Section("Translation") {
                Toggle("Auto-Translate Messages", isOn: $autoTranslateEnabled)

                if autoTranslateEnabled {
                    Picker("Translate to", selection: $translationLanguage) {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Italian").tag("it")
                        Text("Portuguese").tag("pt")
                    }
                }
            }

            Section {
                Text("Messages will be automatically translated to your selected language.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Example 5: Translation with Fallback to Backend

class HybridTranslationService {
    private let appleService = AppleTranslationService()
    private let backendService = AIService() // Assuming AIService exists

    /// Translate using Apple Translation, fall back to backend if needed
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult {

        // Try Apple Translation first
        do {
            let result = try await appleService.translate(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )

            print("✅ Used Apple Translation (on-device)")
            return result

        } catch AIServiceError.unsupportedLanguage {
            // Fall back to backend for unsupported languages
            print("⚠️ Language pair unsupported by Apple, using backend...")

            let result = try await backendService.translate(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )

            print("✅ Used Backend Translation (cloud)")
            return result

        } catch {
            // For other errors, also try backend
            print("⚠️ Apple Translation failed: \(error), trying backend...")

            let result = try await backendService.translate(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )

            return result
        }
    }
}

// MARK: - Example 6: Language Detection Demo

struct LanguageDetectionDemoView: View {
    @StateObject private var service = AppleTranslationService()
    @State private var inputText = ""
    @State private var detectedLanguage: String?
    @State private var isDetecting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Language Detection Demo")
                .font(.headline)

            TextEditor(text: $inputText)
                .frame(height: 100)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Button {
                Task {
                    await detectLanguage()
                }
            } label: {
                if isDetecting {
                    ProgressView()
                } else {
                    Label("Detect Language", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.isEmpty || isDetecting)

            if let language = detectedLanguage {
                VStack {
                    Label(
                        "Detected: \(languageName(language))",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundColor(.green)
                    .font(.headline)

                    Text("Language code: \(language)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func detectLanguage() async {
        isDetecting = true
        defer { isDetecting = false }

        detectedLanguage = await service.detectLanguage(of: inputText)
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

// MARK: - Example 7: Performance Monitoring

class TranslationPerformanceMonitor: ObservableObject {
    @Published var averageTranslationTime: TimeInterval = 0
    @Published var totalTranslations: Int = 0
    @Published var cacheHitRate: Double = 0

    private let service = AppleTranslationService()
    private let cache = AIServiceCache.shared
    private var translationTimes: [TimeInterval] = []

    func trackTranslation(text: String, targetLanguage: String) async throws -> TranslationResult {
        let startTime = Date()

        let result = try await service.translate(
            text: text,
            from: "auto",
            to: targetLanguage
        )

        let duration = Date().timeIntervalSince(startTime)

        await MainActor.run {
            translationTimes.append(duration)
            totalTranslations += 1
            averageTranslationTime = translationTimes.reduce(0, +) / Double(translationTimes.count)

            // Update cache hit rate
            let metrics = cache.getMetrics()
            cacheHitRate = metrics.hitRate
        }

        return result
    }

    func getPerformanceReport() -> String {
        """
        Translation Performance Report:
        - Total Translations: \(totalTranslations)
        - Average Time: \(String(format: "%.0f", averageTranslationTime * 1000))ms
        - Cache Hit Rate: \(String(format: "%.1f", cacheHitRate * 100))%
        - Fastest: \(String(format: "%.0f", (translationTimes.min() ?? 0) * 1000))ms
        - Slowest: \(String(format: "%.0f", (translationTimes.max() ?? 0) * 1000))ms
        """
    }
}

// MARK: - Supporting Types (Mocks for Examples)

struct Message: Identifiable {
    let id: UUID
    let text: String
    let language: String?
}
