//
//  InAppBannerCenter.swift
//  GlobalBridge
//
//  Lightweight in-app banner queue and presenter for foreground alerts.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class InAppBannerCenter: ObservableObject {
    static let shared = InAppBannerCenter()

    // Published state for UI container
    @Published private(set) var current: BannerItem?
    @Published private(set) var activeThreadId: UUID?

    // Queue of pending banners
    private var queue: [BannerItem] = []
    private var dismissTask: Task<Void, Never>?
    private let maxQueueLength = 5

    // Optional tap handler to delegate navigation
    var onTapThread: ((UUID) -> Void)?

    // Coalescing window (seconds) for same-thread events
    private let coalesceWindow: TimeInterval = 2.0

    private init() {}

    // MARK: - Public API

    func presentMessageBanner(threadId: UUID, title: String, subtitle: String, avatarURL: URL? = nil) {
        print("🔔 [BANNER] presentMessageBanner called: thread=\(threadId), title=\(title), subtitle=\(subtitle)")
        print("🔔 [BANNER] NotificationConfig.current = \(NotificationConfig.current.rawValue)")

        guard NotificationConfig.current != .system else {
            print("🔔 [BANNER] Skipping: NotificationConfig is .system")
            return
        }

        print("🔔 [BANNER] activeThreadId = \(activeThreadId?.uuidString ?? "nil")")

        // Suppress banners for the currently active thread
        if let active = activeThreadId, active == threadId {
            print("🔔 [BANNER] Skipping: message is for active thread")
            return
        }

        let now = Date()

        // Try to coalesce with current banner
        if var current = current, current.threadId == threadId, now.timeIntervalSince(current.timestamp) <= coalesceWindow {
            current.count += 1
            current.subtitle = subtitle
            current.timestamp = now
            self.current = current
            return
        }

        // Try to coalesce with tail of queue
        if let lastIdx = queue.indices.last, queue[lastIdx].threadId == threadId, now.timeIntervalSince(queue[lastIdx].timestamp) <= coalesceWindow {
            queue[lastIdx].count += 1
            queue[lastIdx].subtitle = subtitle
            queue[lastIdx].timestamp = now
        } else {
            let item = BannerItem(
                id: UUID(),
                threadId: threadId,
                title: title,
                subtitle: subtitle,
                avatarURL: avatarURL,
                count: 1,
                timestamp: now
            )
            queue.append(item)
            // Trim queue to avoid over-accumulation
            if queue.count > maxQueueLength {
                queue.removeFirst(queue.count - maxQueueLength)
            }
        }

        showNextIfNeeded()
    }

    /// Update the currently active (visible) thread to suppress banners for it
    func setActiveThread(_ threadId: UUID?) {
        activeThreadId = threadId
    }

    // MARK: - NotificationEvent API

    func present(event: NotificationEvent) {
        print("🔔 [BANNER] present(event:) called with event type")
        guard NotificationConfig.current != .system else {
            print("🔔 [BANNER] Skipping event: NotificationConfig is .system")
            return
        }
        switch event {
        case .messageReceived(let msg):
            print("🔔 [BANNER] Event type: messageReceived for thread \(msg.threadId)")
            presentMessageBanner(
                threadId: msg.threadId,
                title: msg.title,
                subtitle: msg.snippet,
                avatarURL: msg.avatarURL
            )

        case .threadCreated(let thread):
            print("🔔 [BANNER] Event type: threadCreated for thread \(thread.threadId)")
            presentMessageBanner(
                threadId: thread.threadId,
                title: thread.title,
                subtitle: thread.snippet,
                avatarURL: thread.avatarURL
            )
        }
    }

    func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        // Show next if available
        showNextIfNeeded()
    }

    func clearAll() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        queue.removeAll()
    }

    // MARK: - Private

    private func showNextIfNeeded() {
        guard current == nil, !queue.isEmpty else {
            print("🔔 [BANNER] showNextIfNeeded: current=\(current != nil ? "showing" : "nil"), queue.count=\(queue.count)")
            return
        }

        current = queue.removeFirst()
        print("🔔 [BANNER] ✅ Showing banner: \(current?.title ?? "unknown")")

        // Auto-dismiss after 5 seconds
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                self?.dismissCurrent()
            }
        }
    }
}

// MARK: - Model

struct BannerItem: Identifiable, Equatable {
    let id: UUID
    let threadId: UUID
    var title: String
    var subtitle: String
    var avatarURL: URL?
    var count: Int
    var timestamp: Date
}
