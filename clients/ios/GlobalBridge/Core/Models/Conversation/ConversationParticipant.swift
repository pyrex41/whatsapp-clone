//
//  ConversationParticipant.swift
//  GlobalBridge
//
//  Model for conversation participants with roles and status
//

import Foundation

public struct ConversationParticipant: Codable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let conversationId: String
    public let role: ParticipantRole
    public let joinedAt: Date
    public let lastReadMessageId: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let isTyping: Bool
    public let lastSeenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case conversationId = "conversation_id"
        case role
        case joinedAt = "joined_at"
        case lastReadMessageId = "last_read_message_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isTyping = "is_typing"
        case lastSeenAt = "last_seen_at"
    }

    public var isOnline: Bool {
        guard let lastSeen = lastSeenAt else { return false }
        return Date().timeIntervalSince(lastSeen) < 300 // 5 minutes
    }

    public var presenceStatus: String {
        if isOnline {
            return "Online"
        } else if let lastSeen = lastSeenAt {
            let interval = Date().timeIntervalSince(lastSeen)
            if interval < 3600 { // Less than 1 hour
                return "Active recently"
            } else if interval < 86400 { // Less than 24 hours
                return "Last seen today"
            } else {
                return "Offline"
            }
        } else {
            return "Offline"
        }
    }
}

extension ConversationParticipant {
    static let mock = ConversationParticipant(
        id: UUID().uuidString,
        userId: "user_123",
        conversationId: "conv_789",
        role: .member,
        joinedAt: Date(),
        lastReadMessageId: "msg_456",
        displayName: "Test User",
        avatarUrl: nil,
        isTyping: false,
        lastSeenAt: Date()
    )

    static func makeMock(
        userId: String = "user_123",
        conversationId: String = "conv_789",
        role: ParticipantRole = .member,
        displayName: String = "Test User",
        isOnline: Bool = true
    ) -> ConversationParticipant {
        ConversationParticipant(
            id: UUID().uuidString,
            userId: userId,
            conversationId: conversationId,
            role: role,
            joinedAt: Date(),
            lastReadMessageId: nil,
            displayName: displayName,
            avatarUrl: nil,
            isTyping: false,
            lastSeenAt: isOnline ? Date() : Date().addingTimeInterval(-7200)
        )
    }
}
