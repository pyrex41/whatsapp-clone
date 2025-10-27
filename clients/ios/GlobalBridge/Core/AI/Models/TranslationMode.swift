//
//  TranslationMode.swift
//  GlobalBridge
//
//  Translation mode settings
//

import Foundation

/// Translation mode for outgoing messages
enum TranslationMode: String, Codable, CaseIterable, Identifiable {
    case automatic = "automatic"
    case onPress = "on_press"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatically"
        case .onPress:
            return "Only on press"
        }
    }

    var description: String {
        switch self {
        case .automatic:
            return "Translate all messages automatically"
        case .onPress:
            return "Show translate button to translate manually"
        }
    }

    /// Default translation mode
    static let `default`: TranslationMode = .onPress
}
