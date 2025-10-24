//
//  TranslationResult.swift
//  GlobalBridge
//
//  Model for translation API responses
//  Maps to backend POST /api/v1/ai/translate response
//

import Foundation

/// Result of a translation request containing translated text and metadata
struct TranslationResult: Codable, Equatable {
    /// Original text before translation
    let originalText: String

    /// Translated text in target language
    let translatedText: String

    /// Detected or specified source language (ISO 639-1 code)
    let sourceLanguage: String

    /// Target language (ISO 639-1 code)
    let targetLanguage: String

    /// Translation confidence score (0.0 to 1.0)
    /// Higher values indicate more confident translation
    let confidence: Double?

    /// AI provider used for translation (e.g., "openai", "anthropic")
    let provider: String?

    /// Cultural context notes about the translation
    /// May include idioms, cultural references, or tone adjustments
    let culturalNotes: String?

    /// Timestamp when translation was performed
    let timestamp: Date

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case originalText = "original_text"
        case translatedText = "translated_text"
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
        case confidence
        case provider
        case culturalNotes = "cultural_notes"
        case timestamp
    }

    // MARK: - Initialization

    init(
        originalText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        confidence: Double? = nil,
        provider: String? = nil,
        culturalNotes: String? = nil,
        timestamp: Date = Date()
    ) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.confidence = confidence
        self.provider = provider
        self.culturalNotes = culturalNotes
        self.timestamp = timestamp
    }
}

// MARK: - Backend API Response DTO

/// Backend API response structure for translation endpoint
/// Maps snake_case backend JSON to camelCase Swift model
struct TranslationAPIResponse: Codable {
    let success: Bool
    let translation: String
    let sourceLanguage: String
    let targetLanguage: String
    let confidence: Double?
    let provider: String?
    let culturalNotes: String?

    enum CodingKeys: String, CodingKey {
        case success
        case translation
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
        case confidence
        case provider
        case culturalNotes = "cultural_notes"
    }

    /// Convert API response to domain model
    func toTranslationResult(originalText: String) -> TranslationResult {
        TranslationResult(
            originalText: originalText,
            translatedText: translation,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            confidence: confidence,
            provider: provider,
            culturalNotes: culturalNotes,
            timestamp: Date()
        )
    }
}

// MARK: - API Request DTO

/// Request body for translation API endpoint
struct TranslationRequest: Codable {
    let text: String
    let targetLanguage: String
    let sourceLanguage: String?

    enum CodingKeys: String, CodingKey {
        case text
        case targetLanguage = "target_language"
        case sourceLanguage = "source_language"
    }

    init(text: String, targetLanguage: String, sourceLanguage: String? = nil) {
        self.text = text
        self.targetLanguage = targetLanguage
        self.sourceLanguage = sourceLanguage
    }
}

// MARK: - Helper Extensions

extension TranslationResult {
    /// Whether the translation has high confidence (>0.8)
    var isHighConfidence: Bool {
        guard let confidence = confidence else { return false }
        return confidence > 0.8
    }

    /// Whether cultural notes are available
    var hasCulturalNotes: Bool {
        guard let notes = culturalNotes else { return false }
        return !notes.isEmpty
    }

    /// Age of the translation in seconds
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    /// Whether this translation is fresh (less than 5 minutes old)
    var isFresh: Bool {
        age < 300 // 5 minutes
    }
}

// MARK: - Caching Support

extension TranslationResult {
    /// Unique cache key for this translation
    /// Used for local caching to avoid redundant API calls
    var cacheKey: String {
        "\(sourceLanguage)_\(targetLanguage)_\(originalText.hashValue)"
    }
}

// MARK: - Display Helpers

extension TranslationResult {
    /// Human-readable source language name
    var sourceLanguageName: String {
        Locale.current.localizedString(forLanguageCode: sourceLanguage) ?? sourceLanguage
    }

    /// Human-readable target language name
    var targetLanguageName: String {
        Locale.current.localizedString(forLanguageCode: targetLanguage) ?? targetLanguage
    }

    /// Formatted confidence percentage (e.g., "95%")
    var confidencePercentage: String? {
        guard let confidence = confidence else { return nil }
        return String(format: "%.0f%%", confidence * 100)
    }
}
