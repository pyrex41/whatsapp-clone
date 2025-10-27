//
//  ThreadTranslationSettings.swift
//  GlobalBridge
//
//  Thread-specific translation settings
//

import Foundation

/// Translation settings for a specific thread
struct ThreadTranslationSettings: Codable, Equatable {
    /// Target language for translations (ISO 639-1 code, e.g., "es", "fr")
    /// This is the language we translate TO for this thread
    var targetLanguage: String

    /// Whether to show smart reply suggestions
    var showSuggestions: Bool

    /// Default formality level for translations
    var defaultFormality: FormalityLevel

    /// Whether to auto-translate incoming messages to user's base language
    var autoTranslateIncoming: Bool

    /// Translation mode for outgoing messages
    var translationMode: TranslationMode

    /// Default settings for a new thread
    static let `default` = ThreadTranslationSettings(
        targetLanguage: "es", // Default to Spanish for US users
        showSuggestions: true,
        defaultFormality: FormalityLevel.neutral,
        autoTranslateIncoming: false,
        translationMode: TranslationMode.onPress
    )

    /// Create default settings with specific target language
    static func defaultSettings(targetLanguage: String) -> ThreadTranslationSettings {
        ThreadTranslationSettings(
            targetLanguage: targetLanguage,
            showSuggestions: true,
            defaultFormality: FormalityLevel.neutral,
            autoTranslateIncoming: false,
            translationMode: TranslationMode.onPress
        )
    }
}
