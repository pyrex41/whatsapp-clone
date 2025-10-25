//
//  ParticipantReadReceipt.swift
//  GlobalBridge
//
//  Model for tracking participant read receipts in conversations
//

import Foundation

public struct ParticipantReadReceipt: Codable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let messageId: String
    public let conversationId: String
    public let readAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case messageId = "message_id"
        case conversationId = "conversation_id"
        case readAt = "read_at"
    }
}

extension ParticipantReadReceipt {
    static let mock = ParticipantReadReceipt(
        id: UUID().uuidString,
        userId: "user_123",
        messageId: "msg_456",
        conversationId: "conv_789",
        readAt: Date()
    )

    static func makeMock(
        userId: String = "user_123",
        messageId: String = "msg_456",
        conversationId: String = "conv_789"
    ) -> ParticipantReadReceipt {
        ParticipantReadReceipt(
            id: UUID().uuidString,
            userId: userId,
            messageId: messageId,
            conversationId: conversationId,
            readAt: Date()
        )
    }
}
