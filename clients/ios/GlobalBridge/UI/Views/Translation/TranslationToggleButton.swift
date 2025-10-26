//
//  TranslationToggleButton.swift
//  GlobalBridge
//
//  Translation toggle button for message composer
//

import SwiftUI

/// Compact translation toggle button for message composer toolbar
struct TranslationToggleButton: View {
    @Binding var isTranslationEnabled: Bool
    @Binding var selectedLanguage: String
    @Binding var showLanguagePicker: Bool

    let threadId: String
    let threadLanguage: String?

    var body: some View {
        HStack(spacing: 8) {
            // Translation toggle with label
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isTranslationEnabled.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isTranslationEnabled ? "globe.americas.fill" : "globe")
                        .font(.body)
                        .foregroundColor(isTranslationEnabled ? .blue : .secondary)

                    Text(isTranslationEnabled ? "Auto-translate" : "Auto-translate")
                        .font(.caption)
                        .foregroundColor(isTranslationEnabled ? .blue : .secondary)
                }
            }
            .accessibilityLabel(isTranslationEnabled ? "Translation enabled" : "Translation disabled")

            if isTranslationEnabled {
                // Clarified language selector
                Button(action: {
                    showLanguagePicker = true
                }) {
                    HStack(spacing: 4) {
                        Text("to")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(languageName(selectedLanguage))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)

                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.15))
                    )
                }
                .accessibilityLabel("Translate to \(languageName(selectedLanguage))")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTranslationEnabled)
    }

    private func languageName(_ code: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}

/// Translation settings indicator with badge
struct TranslationStatusBadge: View {
    let enabled: Bool
    let targetLanguage: String

    var body: some View {
        if enabled {
            HStack(spacing: 4) {
                Image(systemName: "globe.americas.fill")
                    .font(.caption)

                Text(targetLanguage.uppercased())
                    .font(.caption2.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}

#Preview("Toggle Button") {
    VStack(spacing: 20) {
        TranslationToggleButton(
            isTranslationEnabled: .constant(false),
            selectedLanguage: .constant("en"),
            showLanguagePicker: .constant(false),
            threadId: "test-thread",
            threadLanguage: "es"
        )

        TranslationToggleButton(
            isTranslationEnabled: .constant(true),
            selectedLanguage: .constant("en"),
            showLanguagePicker: .constant(false),
            threadId: "test-thread",
            threadLanguage: "es"
        )
    }
    .padding()
}

#Preview("Status Badge") {
    VStack(spacing: 20) {
        TranslationStatusBadge(enabled: false, targetLanguage: "es")
        TranslationStatusBadge(enabled: true, targetLanguage: "es")
    }
    .padding()
}
