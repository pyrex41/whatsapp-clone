//
//  InAppBannerContainer.swift
//  GlobalBridge
//
//  Root overlay that presents the current banner from InAppBannerCenter.
//

import SwiftUI

struct InAppBannerContainer: View {
    @StateObject private var center = InAppBannerCenter.shared

    var body: some View {
        if NotificationConfig.current == .system { EmptyView() } else {
            VStack(spacing: 0) {
                if let item = center.current {
                    InAppBannerView(
                        item: item,
                        onTap: { handleTap(item) },
                        onDismiss: { center.dismissCurrent() }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.25), value: center.current)
        }
    }

    private func handleTap(_ item: BannerItem) {
        center.onTapThread?(item.threadId)
        center.dismissCurrent()
    }
}

