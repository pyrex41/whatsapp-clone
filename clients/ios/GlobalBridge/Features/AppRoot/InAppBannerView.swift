//
//  InAppBannerView.swift
//  GlobalBridge
//
//  Visual banner component with gestures.
//

import SwiftUI

struct InAppBannerView: View {
    let item: BannerItem
    var onTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    @State private var offsetY: CGFloat = -20
    @State private var isVisible: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    if item.count > 1 {
                        Text("\(item.count) new")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                    }
                }
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06))
                )
                .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .offset(y: offsetY)
        .opacity(isVisible ? 1 : 0)
        .gesture(dragToDismiss)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                isVisible = true
                offsetY = 0
            }
        }
        .onTapGesture { onTap?() }
    }

    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if value.translation.height < 0 { // dragging up
                    offsetY = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height < -40 { // sufficient swipe up
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        offsetY = -80
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss?()
                    }
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        offsetY = 0
                    }
                }
            }
    }

    private var avatarView: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.2))
            Text(initials(from: item.title))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.blue)
        }
        .frame(width: 36, height: 36)
    }

    private func initials(from title: String) -> String {
        let parts = title.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1))
        }
        return String(title.prefix(1))
    }
}

#Preview {
    InAppBannerView(
        item: BannerItem(
            id: UUID(),
            threadId: UUID(),
            title: "Alice Zhang",
            subtitle: "Hey! Did you see the latest update?",
            avatarURL: nil,
            count: 2,
            timestamp: .init()
        ),
        onTap: {},
        onDismiss: {}
    )
}
