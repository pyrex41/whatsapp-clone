//
//  TypingIndicatorView.swift
//  GlobalBridge
//
//  UI component for displaying typing indicators
//

import SwiftUI

/// Displays typing indicator for users currently typing
struct TypingIndicatorView: View {
    let typingText: String?

    var body: some View {
        if let text = typingText {
            HStack(spacing: 4) {
                TypingDots()
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
    }
}

/// Animated typing dots indicator
private struct TypingDots: View {
    @State private var animatingDots = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(animatingDots ? 0.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animatingDots
                    )
            }
        }
        .onAppear {
            animatingDots = true
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        TypingIndicatorView(typingText: "Alice is typing...")
        TypingIndicatorView(typingText: "Bob and Charlie are typing...")
        TypingIndicatorView(typingText: "Multiple people are typing...")
        TypingIndicatorView(typingText: nil)
    }
    .padding()
}
