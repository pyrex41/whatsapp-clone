//
//  NotificationEvent.swift
//  GlobalBridge
//
//  Unified notification event model to drive in-app banners and routing.
//

import Foundation

enum NotificationEvent {
    case messageReceived(MessageNotification)
    case threadCreated(ThreadNotification)

    struct MessageNotification {
        let threadId: UUID
        let title: String
        let snippet: String
        let avatarURL: URL?
    }

    struct ThreadNotification {
        let threadId: UUID
        let title: String
        let snippet: String
        let avatarURL: URL?
    }
}

