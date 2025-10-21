//
//  Thread+Samples.swift
//  GlobalBridge
//
//  Created by AI Assistant on 10/21/25.
//

import Foundation

extension Thread {
    static let sampleThreads: [Thread] = [
        Thread(
            threadType: .direct,
            title: "Product Strategy",
            avatarUrl: nil,
            lastMessageAt: Date().addingTimeInterval(-60),
            databaseShardId: "thread_product_strategy",
            unreadCount: 2
        ),
        Thread(
            threadType: .group,
            title: "Bridge Integrations",
            avatarUrl: nil,
            lastMessageAt: Date().addingTimeInterval(-3600),
            databaseShardId: "thread_bridge_integrations",
            unreadCount: 0
        ),
        Thread(
            threadType: .channel,
            title: "QA Sync",
            avatarUrl: nil,
            lastMessageAt: Date().addingTimeInterval(-10800),
            databaseShardId: "thread_qa_sync",
            unreadCount: 5
        )
    ]
}

extension Message {
    static func samples(for threadId: UUID, sender: User = .sampleCurrent) -> [Message] {
        [
            Message(
                threadId: threadId,
                senderId: sender.id,
                content: "Welcome to GlobalBridge! This is a seeded conversation.",
                messageType: .text,
                status: .delivered,
                createdAt: Date().addingTimeInterval(-600)
            ),
            Message(
                threadId: threadId,
                senderId: UUID(),
                content: "Great to be here. Let's connect Slack and Telegram next.",
                messageType: .text,
                status: .read,
                createdAt: Date().addingTimeInterval(-420)
            ),
            Message(
                threadId: threadId,
                senderId: sender.id,
                content: "Sounds good! I'll prep the bridge configs.",
                messageType: .text,
                status: .sent,
                createdAt: Date().addingTimeInterval(-120)
            )
        ]
    }
}
