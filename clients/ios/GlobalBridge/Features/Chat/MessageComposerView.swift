//
//  MessageComposerView.swift
//  GlobalBridge
//

import SwiftUI

struct MessageComposerView: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $text, prompt: Text("Message"))
                .textFieldStyle(.roundedBorder)

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(text.isEmpty || isSending ? Color.gray : Color.accentColor)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .accessibilityLabel("Send message")
        }
    }
}

#Preview {
    MessageComposerView(
        text: .constant("Hello"),
        isSending: false,
        onSend: {}
    )
}
