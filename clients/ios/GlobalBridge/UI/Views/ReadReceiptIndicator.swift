//
//  ReadReceiptIndicator.swift
//  GlobalBridge
//
//  Real-time read receipt indicator with smooth animations
//  Supports single/double checkmarks and group chat participant counts
//

import SwiftUI

/// Visual indicator for message delivery and read status
/// Shows: sent (single ✓), delivered (double ✓✓), read (blue ✓✓)
public struct ReadReceiptIndicator: View {
    // MARK: - Properties

    let messageId: String
    let status: Message.MessageStatus
    let readCount: Int
    let totalParticipants: Int
    let showDetailOnTap: Bool

    @State private var showDetail = false
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Initialization

    public init(
        messageId: String = "",
        status: Message.MessageStatus,
        readCount: Int = 0,
        totalParticipants: Int = 2,
        showDetailOnTap: Bool = true
    ) {
        self.messageId = messageId
        self.status = status
        self.readCount = readCount
        self.totalParticipants = totalParticipants
        self.showDetailOnTap = showDetailOnTap
    }

    // MARK: - Body

    public var body: some View {
        Button {
            if showDetailOnTap && isGroupChat {
                showDetail = true
            }
        } label: {
            HStack(spacing: 2) {
                checkmarkIcon
                    .foregroundColor(iconColor)
                    .font(.caption2)

                // Show read count for group chats
                if isGroupChat && readCount > 0 {
                    Text("\(readCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .sheet(isPresented: $showDetail) {
            if !messageId.isEmpty {
                ReadReceiptDetailView(messageId: messageId)
            }
        }
        .onAppear {
            animateIfNeeded()
        }
        .onChange(of: status) { oldValue, newValue in
            if oldValue != newValue {
                animateStatusChange()
            }
        }
    }

    // MARK: - Checkmark Icon

    @ViewBuilder
    private var checkmarkIcon: some View {
        ZStack {
            switch status {
            case .pending:
                // Clock icon for pending/sending
                Image(systemName: "clock.fill")
                    .symbolRenderingMode(.monochrome)
                    .transition(.opacity.combined(with: .scale))

            case .sent:
                // Single checkmark
                Image(systemName: "checkmark")
                    .symbolRenderingMode(.monochrome)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .opacity
                    ))

            case .delivered:
                // Double checkmark (gray)
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark")
                }
                .symbolRenderingMode(.monochrome)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))

            case .read:
                // Double checkmark (blue)
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                    Image(systemName: "checkmark")
                }
                .symbolRenderingMode(.monochrome)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))

            case .failed:
                // Exclamation mark for failed
                Image(systemName: "exclamationmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.6),
            value: isAnimating
        )
        .animation(
            reduceMotion ? .none : .easeInOut(duration: 0.2),
            value: status
        )
    }

    // MARK: - Colors

    private var iconColor: Color {
        switch status {
        case .pending:
            return .secondary
        case .sent:
            return .secondary
        case .delivered:
            return .secondary
        case .read:
            return .blue
        case .failed:
            return .red
        }
    }

    // MARK: - Helpers

    private var isGroupChat: Bool {
        totalParticipants > 2
    }

    private func animateIfNeeded() {
        guard !reduceMotion else { return }

        // Animate on appearance for sent/delivered/read states
        if status == .sent || status == .delivered || status == .read {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.1)) {
                isAnimating = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation {
                    isAnimating = false
                }
            }
        }
    }

    private func animateStatusChange() {
        guard !reduceMotion else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isAnimating = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation {
                isAnimating = false
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch status {
        case .pending:
            return "Message sending"
        case .sent:
            return "Message sent"
        case .delivered:
            return isGroupChat ? "Message delivered to \(readCount) of \(totalParticipants - 1) people" : "Message delivered"
        case .read:
            return isGroupChat ? "Message read by \(readCount) of \(totalParticipants - 1) people" : "Message read"
        case .failed:
            return "Message failed to send"
        }
    }

    private var accessibilityHint: String {
        if showDetailOnTap && isGroupChat && (status == .delivered || status == .read) {
            return "Tap to see who has read this message"
        }
        return ""
    }
}

// MARK: - Compact Variant

/// Compact read receipt indicator without tap interaction
public struct CompactReadReceiptIndicator: View {
    let status: Message.MessageStatus
    let readCount: Int?

    public init(status: Message.MessageStatus, readCount: Int? = nil) {
        self.status = status
        self.readCount = readCount
    }

    public var body: some View {
        HStack(spacing: 2) {
            ReadReceiptIndicator(
                status: status,
                readCount: readCount ?? 0,
                totalParticipants: 2,
                showDetailOnTap: false
            )
        }
    }
}

// MARK: - Animated Transition Helper

/// Helper view for smooth status transitions
struct ReadReceiptStatusTransition: ViewModifier {
    let status: Message.MessageStatus
    @State private var previousStatus: Message.MessageStatus?

    func body(content: Content) -> some View {
        content
            .id(status)
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))
            .onAppear {
                previousStatus = status
            }
            .onChange(of: status) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    previousStatus = newValue
                }
            }
    }
}

extension View {
    func readReceiptStatusTransition(_ status: Message.MessageStatus) -> some View {
        modifier(ReadReceiptStatusTransition(status: status))
    }
}

// MARK: - Preview

#Preview("All States") {
    VStack(spacing: 20) {
        Group {
            HStack {
                Text("Pending:")
                Spacer()
                ReadReceiptIndicator(status: .pending, showDetailOnTap: false)
            }

            HStack {
                Text("Sent:")
                Spacer()
                ReadReceiptIndicator(status: .sent, showDetailOnTap: false)
            }

            HStack {
                Text("Delivered:")
                Spacer()
                ReadReceiptIndicator(status: .delivered, showDetailOnTap: false)
            }

            HStack {
                Text("Read:")
                Spacer()
                ReadReceiptIndicator(status: .read, showDetailOnTap: false)
            }

            HStack {
                Text("Failed:")
                Spacer()
                ReadReceiptIndicator(status: .failed, showDetailOnTap: false)
            }
        }

        Divider()

        Text("Group Chat").font(.headline)

        Group {
            HStack {
                Text("Delivered (2/5):")
                Spacer()
                ReadReceiptIndicator(
                    messageId: "msg1",
                    status: .delivered,
                    readCount: 2,
                    totalParticipants: 6
                )
            }

            HStack {
                Text("Read (4/5):")
                Spacer()
                ReadReceiptIndicator(
                    messageId: "msg2",
                    status: .read,
                    readCount: 4,
                    totalParticipants: 6
                )
            }
        }
    }
    .padding()
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        HStack {
            Text("Sent:")
            Spacer()
            ReadReceiptIndicator(status: .sent, showDetailOnTap: false)
        }

        HStack {
            Text("Read:")
            Spacer()
            ReadReceiptIndicator(status: .read, showDetailOnTap: false)
        }

        HStack {
            Text("Group Read (3/5):")
            Spacer()
            ReadReceiptIndicator(
                messageId: "msg1",
                status: .read,
                readCount: 3,
                totalParticipants: 6
            )
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Animated Transition") {
    struct AnimatedPreview: View {
        @State private var status: Message.MessageStatus = .pending

        var body: some View {
            VStack(spacing: 30) {
                ReadReceiptIndicator(status: status, showDetailOnTap: false)
                    .font(.largeTitle)

                Button("Next State") {
                    withAnimation {
                        switch status {
                        case .pending: status = .sent
                        case .sent: status = .delivered
                        case .delivered: status = .read
                        case .read: status = .pending
                        case .failed: status = .pending
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    return AnimatedPreview()
}
