//
//  MessageComposerView.swift
//  GlobalBridge
//

import SwiftUI

struct MessageComposerView: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void
    let isFocused: FocusState<Bool>.Binding

    // Translation support (optional)
    let threadId: String?
    let phoenixManager: PhoenixChannelManager?

    // Translation state
    @State private var isTranslationEnabled = false
    @State private var selectedLanguage = "en"
    @State private var showLanguagePicker = false
    @State private var threadLanguage: String?
    @State private var isLoadingPreference = false
    @State private var showTranslationPreview = false

    init(
        text: Binding<String>,
        isSending: Bool,
        onSend: @escaping () -> Void,
        isFocused: FocusState<Bool>.Binding,
        threadId: String? = nil,
        phoenixManager: PhoenixChannelManager? = nil
    ) {
        self._text = text
        self.isSending = isSending
        self.onSend = onSend
        self.isFocused = isFocused
        self.threadId = threadId
        self.phoenixManager = phoenixManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // Translation toggle (if thread-specific translation is enabled)
            if threadId != nil && phoenixManager != nil {
                HStack {
                    TranslationToggleButton(
                        isTranslationEnabled: $isTranslationEnabled,
                        selectedLanguage: $selectedLanguage,
                        showLanguagePicker: $showLanguagePicker,
                        threadId: threadId ?? "",
                        threadLanguage: threadLanguage
                    )

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
            }

            // Message input
            HStack(spacing: 8) {
                TextField("Message", text: $text, prompt: Text("Message"))
                    .textFieldStyle(.roundedBorder)
                    .focused(isFocused)
                    .submitLabel(.send)
                    .disabled(isSending)
                    .onSubmit(sendIfPossible)
                    .onChange(of: text) { old, new in
                        print("⌨️ [TEXT_FIELD] Text changed: '\(old)' -> '\(new)'")
                    }
                    .accessibilityIdentifier("ComposerTextField")

                // Translate & Send button (only show if translation is available)
                if threadId != nil && phoenixManager != nil {
                    Button {
                        showTranslationPreview = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                            Text("Translate")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(20)
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .accessibilityIdentifier("ComposerTranslateButton")
                    .accessibilityLabel("Translate and send")
                }

                // Regular send button
                Button {
                    sendIfPossible()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(text.isEmpty || isSending ? Color.gray : Color.blue)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityIdentifier("ComposerSendButton")
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showLanguagePicker) {
            if let tid = threadId {
                LanguagePickerSheet(
                    selectedLanguage: $selectedLanguage,
                    threadId: tid,
                    onLanguageSelected: handleLanguageSelected
                )
            }
        }
        .sheet(isPresented: $showTranslationPreview) {
            if let tid = threadId {
                TranslationPreviewSheet(
                    originalText: text,
                    targetLanguage: selectedLanguage,
                    onSend: { translatedText, formality in
                        handleTranslatedSend(translatedText: translatedText, formality: formality)
                    },
                    onCancel: {
                        showTranslationPreview = false
                    },
                    phoenixManager: phoenixManager,
                    threadId: tid
                )
            }
        }
        .task {
            await loadTranslationPreference()
        }
        .onChange(of: isTranslationEnabled) { _, newValue in
            Task {
                await saveTranslationPreference()
            }
        }
    }

    private func sendIfPossible() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending else { return }
        onSend()
    }

    private func handleTranslatedSend(translatedText: String, formality: TranslationFormality) {
        // Replace the text with the translated version
        text = translatedText

        // Close the preview sheet
        showTranslationPreview = false

        // Send the message
        onSend()

        print("📤 [TRANSLATION_SEND] Sending translated message with \(formality) formality: \(translatedText)")
    }

    // MARK: - Translation Methods

    /// Load translation preference for the current thread
    private func loadTranslationPreference() async {
        guard let threadId = threadId,
              let manager = phoenixManager else {
            return
        }

        isLoadingPreference = true
        defer { isLoadingPreference = false }

        do {
            let preference = try await manager.getTranslationPreference(threadId: threadId)

            await MainActor.run {
                self.isTranslationEnabled = preference.enabled
                if let language = preference.targetLanguage {
                    self.selectedLanguage = language
                    self.threadLanguage = language
                }

                print("✅ [COMPOSER_TRANSLATION] Loaded preference - enabled: \(preference.enabled), language: \(preference.targetLanguage ?? "nil")")
            }
        } catch {
            print("⚠️  [COMPOSER_TRANSLATION] Failed to load translation preference: \(error)")
            // Use defaults on error
        }
    }

    /// Save translation preference when enabled/disabled changes
    private func saveTranslationPreference() async {
        guard let threadId = threadId,
              let manager = phoenixManager else {
            return
        }

        do {
            try await manager.setTranslationPreference(
                threadId: threadId,
                targetLanguage: selectedLanguage,
                enabled: isTranslationEnabled
            )

            print("✅ [COMPOSER_TRANSLATION] Saved preference - enabled: \(isTranslationEnabled), language: \(selectedLanguage)")
        } catch {
            print("❌ [COMPOSER_TRANSLATION] Failed to save translation preference: \(error)")
        }
    }

    /// Handle language selection from picker sheet
    private func handleLanguageSelected(_ languageCode: String) {
        selectedLanguage = languageCode

        Task {
            await saveTranslationPreference()
        }
    }
}

#Preview("Without Translation") {
    ComposerPreview(withTranslation: false)
}

#Preview("With Translation") {
    ComposerPreview(withTranslation: true)
}

private struct ComposerPreview: View {
    let withTranslation: Bool

    @State private var text = "Hello"
    @State private var isSending = false
    @FocusState private var focused: Bool

    var body: some View {
        MessageComposerView(
            text: $text,
            isSending: isSending,
            onSend: {},
            isFocused: $focused,
            threadId: withTranslation ? "preview-thread-123" : nil,
            phoenixManager: withTranslation ? nil : nil  // Would use actual manager in real app
        )
        .padding()
    }
}
