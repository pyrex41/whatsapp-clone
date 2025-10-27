//
//  InAppBannerContainer.swift
//  GlobalBridge
//
//  Root overlay that presents the current banner from InAppBannerCenter.
//

import SwiftUI

struct InAppBannerContainer: View {
    @ObservedObject private var center = InAppBannerCenter.shared

    var body: some View {
        let notificationMode = NotificationConfig.current
        print("🔔 [BANNER_CONTAINER] Rendering - mode: \(notificationMode.rawValue), current banner: \(center.current?.title ?? "none")")

        if notificationMode == .system {
            print("🔔 [BANNER_CONTAINER] Notification mode is .system - not showing banners")
            return AnyView(EmptyView())
        } else {
            print("🔔 [BANNER_CONTAINER] Notification mode is \(notificationMode.rawValue) - banners enabled")
            return AnyView(
                VStack(spacing: 0) {
                    if let item = center.current {
                        print("🔔 [BANNER_CONTAINER] Showing banner: \(item.title)")
                        InAppBannerView(
                            item: item,
                            onTap: { handleTap(item) },
                            onDismiss: { center.dismissCurrent() }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        print("🔔 [BANNER_CONTAINER] No banner to show")
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .animation(.easeInOut(duration: 0.25), value: center.current)
                .onAppear {
                    print("🔔 [BANNER_CONTAINER] Container appeared - observing InAppBannerCenter.shared")
                }
            )
        }
    }

    private func handleTap(_ item: BannerItem) {
        center.onTapThread?(item.threadId)
        center.dismissCurrent()
    }
}

