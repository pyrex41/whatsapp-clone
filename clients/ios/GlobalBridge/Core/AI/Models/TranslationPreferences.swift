//
//  TranslationPreferences.swift
//  GlobalBridge
//
//  Created on 2025-10-25.
//

import Foundation

/// Represents user preferences for message translation
struct TranslationPreferences: Codable, Equatable {
    let preferredLanguage: String // ISO 639-1 code (e.g., "en", "es", "fr")
    let autoTranslateEnabled: Bool
    let contactOverrides: [String: Bool] // contactId -> enabled
    let threadOverrides: [String: Bool] // threadId -> enabled

    /// Default translation preferences with English and auto-translate enabled
    static let `default` = TranslationPreferences(
        preferredLanguage: "en",
        autoTranslateEnabled: true,
        contactOverrides: [:],
        threadOverrides: [:]
    )
}
