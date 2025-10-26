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
    let phoenixStateManager: PhoenixStateManager?

    // Translation state
    @State private var isTranslationEnabled = false
    @State private var selectedLanguage = "en"
    @State private var showLanguagePicker = false
    @State private var threadLanguage: String?
    @State private var isLoadingPreference = false

    init(
        text: Binding<String>,
        isSending: Bool,
        onSend: @escaping () -> Void,
        isFocused: FocusState<Bool>.Binding,
        threadId: String? = nil,
        phoenixStateManager: PhoenixStateManager? = nil
    ) {
        self._text = text
        self.isSending = isSending
        self.onSend = onSend
        self.isFocused = isFocused
        self.threadId = threadId
        self.phoenixStateManager = phoenixStateManager
    }

    var body: some View {
        VStack(spacing: 0) {
            // Translation toggle (if thread-specific translation is enabled)
            if threadId != nil && phoenixStateManager != nil {
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
            HStack(spacing: 12) {
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

    // MARK: - Translation Methods

    /// Load translation preference for the current thread
    private func loadTranslationPreference() async {
        guard let threadId = threadId,
              let manager = phoenixStateManager else {
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
              let manager = phoenixStateManager else {
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
            phoenixStateManager: withTranslation ? nil : nil  // Would use actual manager in real app
        )
        .padding()
    }
}
