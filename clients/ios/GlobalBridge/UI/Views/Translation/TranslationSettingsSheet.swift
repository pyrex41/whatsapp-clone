//
//  TranslationSettingsSheet.swift
//  GlobalBridge
//
//  Thread-specific translation settings modal
//

import SwiftUI

struct TranslationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: ThreadTranslationSettings

    let threadId: String
    let onSave: (ThreadTranslationSettings) -> Void

    @State private var localSettings: ThreadTranslationSettings

    init(settings: Binding<ThreadTranslationSettings>, threadId: String, onSave: @escaping (ThreadTranslationSettings) -> Void) {
        self._settings = settings
        self.threadId = threadId
        self.onSave = onSave
        self._localSettings = State(initialValue: settings.wrappedValue)
    }

    var body: some View {
        NavigationView {
            Form {
                // Show Suggestions Section
                Section {
                    Toggle("Show Suggestions", isOn: $localSettings.showSuggestions)
                } header: {
                    Text("Smart Reply")
                } footer: {
                    Text("Display AI-powered quick reply suggestions above the message composer")
                }

                // Formality Section
                Section {
                    Picker("Default Formality", selection: $localSettings.defaultFormality) {
                        ForEach(FormalityLevel.allCases) { level in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.displayName)
                                    .font(.body)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Translation Tone")
                } footer: {
                    Text("Choose the default formality level for translations in this conversation")
                }

                // Auto-translate Incoming Section
                Section {
                    Toggle("Auto-translate incoming messages", isOn: $localSettings.autoTranslateIncoming)
                } header: {
                    Text("Incoming Messages")
                } footer: {
                    Text("Automatically translate received messages to your base language. Tap translated messages to see the original.")
                }

                // Translation Mode Section
                Section {
                    Picker("Translation Mode", selection: $localSettings.translationMode) {
                        ForEach(TranslationMode.allCases) { mode in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    if mode == .onPress {
                                        Image(systemName: "globe")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                    }
                                    Text(mode.displayName)
                                        .font(.body)
                                }
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("Outgoing Messages")
                } footer: {
                    if localSettings.translationMode == .onPress {
                        Text("A globe button will appear in the message field to translate messages before sending")
                    } else {
                        Text("All messages will be automatically translated to \(languageName(for: localSettings.targetLanguage)) before sending")
                    }
                }
            }
            .navigationTitle("Translation Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings = localSettings
                        onSave(localSettings)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func languageName(for code: String) -> String {
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}

#Preview {
    TranslationSettingsSheet(
        settings: .constant(.default),
        threadId: "test-thread",
        onSave: { _ in }
    )
}
