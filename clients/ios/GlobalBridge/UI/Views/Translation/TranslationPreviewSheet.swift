//
//  TranslationPreviewSheet.swift
//  GlobalBridge
//
//  Translation preview modal with formality adjustments
//

import SwiftUI

/// Formality level for translation
enum TranslationFormality: String, CaseIterable {
    case informal = "Informal"
    case neutral = "Neutral"
    case formal = "Formal"

    var description: String {
        switch self {
        case .informal: return "Casual, friendly tone"
        case .neutral: return "Standard, balanced tone"
        case .formal: return "Professional, polite tone"
        }
    }
}

/// Sheet showing translation preview with formality options
struct TranslationPreviewSheet: View {
    let originalText: String
    let targetLanguage: String
    let onSend: (String, TranslationFormality) -> Void
    let onCancel: () -> Void

    @State private var translatedText: String = ""
    @State private var selectedFormality: TranslationFormality = .neutral
    @State private var isTranslating: Bool = true
    @State private var error: String?

    let phoenixManager: PhoenixChannelManager?
    let threadId: String

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Original text section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Original (English)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(originalText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
                .padding()

                Divider()

                // Translated text section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Translation to \(languageName(targetLanguage))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)

                            if !translatedText.isEmpty && !isTranslating {
                                Text("Tap formality buttons below to adjust tone")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if isTranslating {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }

                    if let error = error {
                        Text(error)
                            .font(.body)
                            .foregroundColor(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemRed).opacity(0.1))
                            .cornerRadius(12)
                    } else {
                        Text(translatedText.isEmpty ? "Translating..." : translatedText)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemBlue).opacity(0.1))
                            .cornerRadius(12)
                    }
                }
                .padding()

                // Formality selector
                if !isTranslating && error == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Formality")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal)

                        HStack(spacing: 8) {
                            ForEach(TranslationFormality.allCases, id: \.self) { formality in
                                Button {
                                    selectedFormality = formality
                                    // Re-translate with new formality
                                    Task {
                                        await translateWithFormality(formality)
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(formality.rawValue)
                                            .font(.subheadline.weight(.medium))
                                        Text(formality.description)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        selectedFormality == formality
                                            ? Color.blue.opacity(0.15)
                                            : Color(.systemGray6)
                                    )
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                selectedFormality == formality
                                                    ? Color.blue
                                                    : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }

                    Button {
                        onSend(translatedText, selectedFormality)
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send Translation")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            (isTranslating || error != nil || translatedText.isEmpty)
                                ? Color.gray
                                : Color.purple
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isTranslating || error != nil || translatedText.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Preview Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .task {
            await performInitialTranslation()
        }
    }

    // MARK: - Translation Logic

    private func performInitialTranslation() async {
        isTranslating = true
        error = nil

        do {
            print("🌐 [TRANSLATION_PREVIEW] Translating to \(targetLanguage) with \(selectedFormality.rawValue) formality")

            let result = try await BackendTranslationService.shared.translate(
                text: originalText,
                targetLanguage: targetLanguage,
                sourceLanguage: "en",
                context: nil,
                formality: mapToFormalityLevel(selectedFormality)
            )

            await MainActor.run {
                translatedText = result.translatedText
                isTranslating = false
                print("✅ [TRANSLATION_PREVIEW] Translation complete: \(translatedText)")
            }
        } catch {
            await MainActor.run {
                self.error = "Translation failed: \(error.localizedDescription)"
                isTranslating = false
                print("❌ [TRANSLATION_PREVIEW] Translation failed: \(error)")
            }
        }
    }

    private func translateWithFormality(_ formality: TranslationFormality) async {
        isTranslating = true
        error = nil

        do {
            print("🌐 [TRANSLATION_PREVIEW] Re-translating with \(formality.rawValue) formality")

            let result = try await BackendTranslationService.shared.translate(
                text: originalText,
                targetLanguage: targetLanguage,
                sourceLanguage: "en",
                context: nil,
                formality: mapToFormalityLevel(formality)
            )

            await MainActor.run {
                translatedText = result.translatedText
                isTranslating = false
                print("✅ [TRANSLATION_PREVIEW] Re-translation complete: \(translatedText)")
            }
        } catch {
            await MainActor.run {
                self.error = "Translation failed: \(error.localizedDescription)"
                isTranslating = false
                print("❌ [TRANSLATION_PREVIEW] Re-translation failed: \(error)")
            }
        }
    }

    private func mapToFormalityLevel(_ formality: TranslationFormality) -> FormalityLevel {
        switch formality {
        case .informal:
            return .informal
        case .neutral:
            return .neutral
        case .formal:
            return .formal
        }
    }

    private func languageName(_ code: String) -> String {
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code)?.capitalized ?? code.uppercased()
    }
}

// MARK: - Preview

#Preview {
    TranslationPreviewSheet(
        originalText: "Hello, how are you doing today?",
        targetLanguage: "es",
        onSend: { translated, formality in
            print("Sending: \(translated) with \(formality)")
        },
        onCancel: {
            print("Cancelled")
        },
        phoenixManager: nil,
        threadId: "preview-thread"
    )
}
