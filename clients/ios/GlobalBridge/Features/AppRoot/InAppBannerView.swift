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

    @State private var offsetY: CGFloat = -16
    @State private var isVisible: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if item.count > 1 {
                        Text("\(item.count) new")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.blue.opacity(0.18)))
                    }
                }
                Text(item.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.06))
                )
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
        )
        .padding(.horizontal, 12)
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
                .font(.headline.weight(.semibold))
                .foregroundColor(.blue)
        }
        .frame(width: 44, height: 44)
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
