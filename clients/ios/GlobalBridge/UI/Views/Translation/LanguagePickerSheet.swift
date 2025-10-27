//
//  LanguagePickerSheet.swift
//  GlobalBridge
//
//  Thread-specific language picker for translation preferences
//

import SwiftUI

/// Language option for translation
struct Language: Identifiable, Equatable {
    let id = UUID()
    let code: String
    let name: String
    let nativeName: String
    let flag: String
}

/// Sheet for selecting translation language for a specific thread
struct LanguagePickerSheet: View {
    @Binding var selectedLanguage: String
    @Environment(\.dismiss) private var dismiss

    let threadId: String
    let onLanguageSelected: (String) -> Void

    @State private var searchText = ""

    private let languages: [Language] = [
        Language(code: "en", name: "English", nativeName: "English", flag: "🇺🇸"),
        Language(code: "es", name: "Spanish", nativeName: "Español", flag: "🇪🇸"),
        Language(code: "fr", name: "French", nativeName: "Français", flag: "🇫🇷"),
        Language(code: "de", name: "German", nativeName: "Deutsch", flag: "🇩🇪"),
        Language(code: "zh", name: "Chinese", nativeName: "中文", flag: "🇨🇳"),
        Language(code: "ja", name: "Japanese", nativeName: "日本語", flag: "🇯🇵"),
        Language(code: "ko", name: "Korean", nativeName: "한국어", flag: "🇰🇷"),
        Language(code: "ru", name: "Russian", nativeName: "Русский", flag: "🇷🇺"),
        Language(code: "pt", name: "Portuguese", nativeName: "Português", flag: "🇧🇷"),
        Language(code: "it", name: "Italian", nativeName: "Italiano", flag: "🇮🇹"),
        Language(code: "ar", name: "Arabic", nativeName: "العربية", flag: "🇸🇦"),
        Language(code: "hi", name: "Hindi", nativeName: "हिन्दी", flag: "🇮🇳"),
        Language(code: "nl", name: "Dutch", nativeName: "Nederlands", flag: "🇳🇱"),
        Language(code: "pl", name: "Polish", nativeName: "Polski", flag: "🇵🇱"),
        Language(code: "tr", name: "Turkish", nativeName: "Türkçe", flag: "🇹🇷"),
        Language(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt", flag: "🇻🇳"),
        Language(code: "th", name: "Thai", nativeName: "ไทย", flag: "🇹🇭"),
        Language(code: "sv", name: "Swedish", nativeName: "Svenska", flag: "🇸🇪"),
        Language(code: "da", name: "Danish", nativeName: "Dansk", flag: "🇩🇰"),
        Language(code: "no", name: "Norwegian", nativeName: "Norsk", flag: "🇳🇴"),
        Language(code: "fi", name: "Finnish", nativeName: "Suomi", flag: "🇫🇮")
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search languages", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()

                // Language list
                List(filteredLanguages) { language in
                    Button(action: {
                        selectedLanguage = language.code
                        onLanguageSelected(language.code)
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Text(language.flag)
                                .font(.largeTitle)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(language.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text(language.nativeName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if language.code == selectedLanguage {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Thread Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredLanguages: [Language] {
        if searchText.isEmpty {
            return languages
        } else {
            return languages.filter { language in
                language.name.localizedCaseInsensitiveContains(searchText) ||
                language.nativeName.localizedCaseInsensitiveContains(searchText) ||
                language.code.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

#Preview {
    LanguagePickerSheet(
        selectedLanguage: .constant("en"),
        threadId: "test-thread-id",
        onLanguageSelected: { _ in }
    )
}
