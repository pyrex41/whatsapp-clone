//
//  MessageBubbleViewModel.swift
//  GlobalBridge
//
//  View model for managing message bubble state and translation logic
//  Handles translation requests, caching, error handling
//

import Foundation
import Combine

/// View model managing message bubble state and translation functionality
@MainActor
final class MessageBubbleViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var translation: TranslationResult?
    @Published private(set) var isTranslating = false
    @Published private(set) var translationError: AIServiceError?

    // MARK: - Properties

    let message: Message
    private let translationService: UnifiedTranslationService
    private var cancellables = Set<AnyCancellable>()

    var hasTranslation: Bool {
        translation != nil
    }

    // MARK: - Initialization

    init(message: Message, translationService: UnifiedTranslationService) {
        self.message = message
        self.translationService = translationService

        // Check cache on init
        Task {
            await checkTranslationCache()
        }
    }

    // MARK: - Translation Methods

    /// Translate message to user's preferred language
    func translateToUserLanguage() async {
        let targetLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        await translate(to: targetLanguage)
    }

    /// Translate message to specified language
    func translate(to targetLanguage: String, from sourceLanguage: String = "auto") async {
        guard message.messageType == .text else {
            translationError = .featureDisabled(feature: "translation")
            return
        }

        // Check if already translating
        guard !isTranslating else { return }

        isTranslating = true
        translationError = nil

        do {
            let result = try await translationService.translate(
                text: message.content,
                from: sourceLanguage,
                to: targetLanguage,
                provider: .auto
            )

            translation = result
            print("✅ [BUBBLE_VM] Translation successful: \(result.provider ?? "unknown")")
        } catch let error as AIServiceError {
            translationError = error
            print("❌ [BUBBLE_VM] Translation failed: \(error.localizedDescription)")
        } catch {
            translationError = .serviceUnavailable(underlyingError: error)
            print("❌ [BUBBLE_VM] Translation failed: \(error.localizedDescription)")
        }

        isTranslating = false
    }

    /// Retry translation after error
    func retryTranslation() async {
        guard translation == nil else { return }
        await translateToUserLanguage()
    }

    /// Clear current translation
    func clearTranslation() {
        translation = nil
        translationError = nil
    }

    /// Report bad translation to analytics/backend
    func reportBadTranslation() async {
        guard let translation = translation else { return }

        print("📝 [BUBBLE_VM] Reporting bad translation:")
        print("  - Original: \(message.content)")
        print("  - Translation: \(translation.translatedText)")
        print("  - Provider: \(translation.provider ?? "unknown")")

        // TODO: Send analytics event or API call to report issue
        // Analytics.logEvent("translation_reported", parameters: [
        //     "message_id": message.id.uuidString,
        //     "provider": translation.provider ?? "unknown",
        //     "source_lang": translation.sourceLanguage,
        //     "target_lang": translation.targetLanguage
        // ])
    }

    // MARK: - Cache Management

    private func checkTranslationCache() async {
        let targetLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let cacheKey = "\(message.content)_\(targetLanguage)".hashValue

        // TODO: Implement cache lookup
        // if let cached = await translationService.cachedTranslation(for: cacheKey) {
        //     translation = cached
        // }
    }

    // MARK: - Translation Provider Selection

    /// Get available translation providers for this message
    func availableProviders() async -> [TranslationProvider] {
        var providers: [TranslationProvider] = []

        // Apple Translation (if supported)
        let targetLang = Locale.current.language.languageCode?.identifier ?? "en"
        if translationService.supportsLanguagePair(from: "auto", to: targetLang, provider: .apple) {
            providers.append(.apple)
        }

        // Backend always available (with network)
        providers.append(.backend)

        // Hybrid if both available
        if providers.count == 2 {
            providers.append(.auto)
        }

        return providers
    }
}

// MARK: - Translation Provider

enum TranslationProvider: String, CaseIterable, Identifiable {
    case apple = "apple-translation"
    case backend = "backend-ai"
    case auto = "auto"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "On-Device (Private)"
        case .backend: return "Cloud AI (More Languages)"
        case .auto: return "Automatic"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .backend: return "cloud.fill"
        case .auto: return "arrow.triangle.2.circlepath"
        }
    }

    var description: String {
        switch self {
        case .apple:
            return "Fast, private, works offline. Limited language pairs."
        case .backend:
            return "More languages, cultural notes. Requires internet."
        case .auto:
            return "Automatically choose best provider for your needs."
        }
    }
}

// MARK: - Unified Translation Service (Stub)

/// Unified translation service coordinating Apple and Backend translation
@MainActor
final class UnifiedTranslationService {
    static let shared = UnifiedTranslationService()

    private let appleService = AppleTranslationService()
    private let backendService = BackendTranslationService.shared

    private init() {}

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        provider: TranslationProvider
    ) async throws -> TranslationResult {
        switch provider {
        case .apple:
            return try await appleService.translate(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )
        case .backend:
            return try await backendService.translate(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )
        case .auto:
            // Try Apple first (faster, private), fallback to backend
            do {
                return try await appleService.translate(
                    text: text,
                    from: sourceLanguage,
                    to: targetLanguage
                )
            } catch AIServiceError.unsupportedLanguage {
                print("⚠️ [UNIFIED] Apple doesn't support this pair, using backend")
                return try await backendService.translate(
                    text: text,
                    from: sourceLanguage,
                    to: targetLanguage
                )
            }
        }
    }

    func supportsLanguagePair(from: String, to: String, provider: TranslationProvider) -> Bool {
        switch provider {
        case .apple:
            let normalizedFrom = from == "auto" ? "en" : from
            let pair = "\(normalizedFrom)_\(to)"
            return AppleTranslationService.supportedLanguagePairs.contains(pair)
        case .backend:
            return true // Backend supports all language pairs
        case .auto:
            return true // Auto will try both
        }
    }
}
