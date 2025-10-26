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

    var body: some View {
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
    }

    private func sendIfPossible() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSending else { return }
        onSend()
    }
}

#Preview {
    ComposerPreview()
}

private struct ComposerPreview: View {
    @State private var text = "Hello"
    @State private var isSending = false
    @FocusState private var focused: Bool

    var body: some View {
        MessageComposerView(
            text: $text,
            isSending: isSending,
            onSend: {},
            isFocused: $focused
        )
        .padding()
    }
}
