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

            translation = result.toTranslationResult()
            print("✅ [BUBBLE_VM] Translation successful: \(result.provider)")
        } catch let error as AIServiceError {
            translationError = error
            print("❌ [BUBBLE_VM] Translation failed: \(error.localizedDescription)")
        } catch {
            translationError = .unknown(error)
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
        let pair = "\("en")_\(targetLang)" // when source is auto, assume 'en' for support check
        if AppleTranslationService.supportedLanguagePairs.contains(pair) {
            providers.append(.apple)
        }

        // Backend always available (with network)
        providers.append(.backend)

        // Add auto (smart) if we have at least one concrete provider to choose between
        if !providers.isEmpty {
            providers.append(.auto)
        }

        return providers
    }
}

// MARK: - TranslationProvider UI helpers

extension TranslationProvider: CaseIterable, Identifiable {
    public var id: String { rawValue }

    public static var allCases: [TranslationProvider] {
        // UI selection uses these; 'hybrid' is internal/debug only
        return [.apple, .backend, .auto]
    }

    var displayName: String {
        switch self {
        case .apple: return "On-Device (Private)"
        case .backend: return "Cloud AI (More Languages)"
        case .auto: return "Automatic"
        case .hybrid: return "Hybrid (Compare)"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .backend: return "cloud.fill"
        case .auto: return "arrow.triangle.2.circlepath"
        case .hybrid: return "rectangle.split.2x1"
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
        case .hybrid:
            return "Run both providers and compare results."
        }
    }
}
