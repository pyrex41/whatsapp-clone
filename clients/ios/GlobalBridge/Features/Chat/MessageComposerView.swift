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
    let translationSettings: ThreadTranslationSettings?
    let onSetOriginalText: ((String) -> Void)? // Callback to store original text before translation

    // Translation state
    @State private var showTranslationPreview = false
    @State private var isTranslating = false

    init(
        text: Binding<String>,
        isSending: Bool,
        onSend: @escaping () -> Void,
        isFocused: FocusState<Bool>.Binding,
        threadId: String? = nil,
        phoenixManager: PhoenixChannelManager? = nil,
        translationSettings: ThreadTranslationSettings? = nil,
        onSetOriginalText: ((String) -> Void)? = nil
    ) {
        self._text = text
        self.isSending = isSending
        self.onSend = onSend
        self.isFocused = isFocused
        self.threadId = threadId
        self.phoenixManager = phoenixManager
        self.translationSettings = translationSettings
        self.onSetOriginalText = onSetOriginalText
    }

    var body: some View {
        VStack(spacing: 0) {
            // Message input
            HStack(spacing: 8) {
                // Text field with inline translate button
                HStack(spacing: 4) {
                    TextField("Message", text: $text, prompt: Text("Message"))
                        .focused(isFocused)
                        .submitLabel(.send)
                        .disabled(isSending)
                        .onSubmit(sendIfPossible)
                        .onChange(of: text) { old, new in
                            print("⌨️ [TEXT_FIELD] Text changed: '\(old)' -> '\(new)'")
                        }
                        .accessibilityIdentifier("ComposerTextField")

                    // Inline translate button (only show when translationMode == .onPress)
                    if let settings = translationSettings, settings.translationMode == .onPress {
                        Button {
                            showTranslationPreview = true
                        } label: {
                            Image(systemName: "globe")
                                .font(.system(size: 16))
                                .foregroundColor(.purple)
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                        .accessibilityIdentifier("ComposerTranslateButton")
                        .accessibilityLabel("Translate message")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(20)

                // Regular send button (with translation loading indicator)
                Button {
                    sendIfPossible()
                } label: {
                    if isTranslating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(text.isEmpty || isSending ? Color.gray : Color.blue)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || isTranslating)
                .accessibilityIdentifier("ComposerSendButton")
                .accessibilityLabel(isTranslating ? "Translating message" : "Send message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showTranslationPreview) {
            if let tid = threadId, let settings = translationSettings {
                TranslationPreviewSheet(
                    originalText: text,
                    targetLanguage: settings.targetLanguage,
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
    }

    private func sendIfPossible() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending else { return }

        // Check if automatic translation is enabled
        if let settings = translationSettings, settings.translationMode == .automatic {
            // Translate first, then send
            Task {
                await translateAndSend()
            }
        } else {
            // Send directly without translation
            onSend()
        }
    }

    private func translateAndSend() async {
        guard let settings = translationSettings else {
            onSend()
            return
        }

        let originalText = text // Capture original before translation
        isTranslating = true

        do {
            let translationService = BackendTranslationService.shared
            let result = try await translationService.translate(
                text: originalText,
                targetLanguage: settings.targetLanguage,
                sourceLanguage: nil, // Auto-detect
                context: nil,
                formality: settings.defaultFormality
            )

            await MainActor.run {
                isTranslating = false

                // Store original text before replacing
                onSetOriginalText?(originalText)
                print("📝 [AUTO_TRANSLATE] Stored original text: '\(originalText)'")

                // Replace the text with translated version
                text = result.translatedText

                // Small delay to let binding update
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    await MainActor.run {
                        print("📤 [AUTO_TRANSLATE] Sending translated message: \(text)")
                        onSend()
                    }
                }
            }
        } catch {
            await MainActor.run {
                isTranslating = false
                print("❌ [AUTO_TRANSLATE] Translation failed: \(error)")
                // Send original text if translation fails
                onSend()
            }
        }
    }

    private func handleTranslatedSend(translatedText: String, formality: TranslationFormality) {
        print("📤 [TRANSLATION_SEND] Preparing to send translated message with \(formality) formality: \(translatedText)")

        // Store original text before translation
        let originalText = text
        onSetOriginalText?(originalText)
        print("📝 [MANUAL_TRANSLATE] Stored original text: '\(originalText)'")

        // Close the preview sheet first
        showTranslationPreview = false

        // Replace the text with the translated version
        text = translatedText

        // Use Task to ensure state update propagates before sending
        Task {
            // Small delay to let the binding update propagate to the store
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Send the message
            await MainActor.run {
                print("📤 [TRANSLATION_SEND] Sending message now")
                onSend()
            }
        }
    }
}

#Preview("Without Translation") {
    ComposerPreview(translationMode: nil)
}

#Preview("With Translation - On Press Mode") {
    ComposerPreview(translationMode: .onPress)
}

#Preview("With Translation - Automatic Mode") {
    ComposerPreview(translationMode: .automatic)
}

private struct ComposerPreview: View {
    let translationMode: TranslationMode?

    @State private var text = "Hello"
    @State private var isSending = false
    @FocusState private var focused: Bool

    var body: some View {
        MessageComposerView(
            text: $text,
            isSending: isSending,
            onSend: {},
            isFocused: $focused,
            threadId: translationMode != nil ? "preview-thread-123" : nil,
            phoenixManager: translationMode != nil ? nil : nil,  // Would use actual manager in real app
            translationSettings: translationMode.map { mode in
                ThreadTranslationSettings(
                    targetLanguage: "es",
                    showSuggestions: true,
                    defaultFormality: .neutral,
                    autoTranslateIncoming: false,
                    translationMode: mode
                )
            }
        )
        .padding()
    }
}
