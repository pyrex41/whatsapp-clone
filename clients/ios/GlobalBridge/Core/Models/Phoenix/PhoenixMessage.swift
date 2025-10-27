//
//  PhoenixMessage.swift
//  GlobalBridge
//
//  Phoenix message models
//

import Foundation

/// Represents a message received from Phoenix Channels
public struct PhoenixMessage: Codable, Sendable, Identifiable {
    public let id: String
    public let conversationId: String
    public let senderId: String
    public let senderDisplayName: String? // Display name for the sender
    public let content: String
    public let timestamp: Date
    public let status: MessageStatus
    public let metadata: MessageMetadata?
    public let clientMessageId: String? // For deduplication
    public let detectedLanguage: String? // Language code detected by backend (e.g., "en", "es", "fr")

    public enum MessageStatus: String, Codable, Sendable {
        case sending
        case sent
        case delivered
        case read
        case failed
    }

    public struct MessageMetadata: Codable, Sendable {
        public let replyToId: String?
        public let edited: Bool?
        public let editedAt: Date?
        public let attachments: [Attachment]?

        public struct Attachment: Codable, Sendable {
            public let id: String
            public let type: String
            public let url: String
            public let name: String
            public let size: Int?
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case senderDisplayName = "sender_display_name"
        case content
        case timestamp
        case status
        case metadata
        case clientMessageId = "client_message_id"
        case detectedLanguage = "detected_language"
    }
}

/// Represents a conversation update from Phoenix
public struct ConversationUpdate: Codable, Sendable {
    public let conversationId: String
    public let type: UpdateType
    public let data: [String: AnyCodable]

    public enum UpdateType: String, Codable, Sendable {
        case messageReceived = "message_received"
        case messageUpdated = "message_updated"
        case messageDeleted = "message_deleted"
        case userTyping = "user_typing"
        case userPresence = "user_presence"
        case conversationRead = "conversation_read"
    }

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case type
        case data
    }
}

/// Type-erased codable wrapper for dynamic JSON
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

/// Presence state for users in a conversation
public struct UserPresence: Codable, Sendable {
    public let userId: String
    public let status: PresenceStatus
    public let lastSeen: Date?

    public enum PresenceStatus: String, Codable, Sendable {
        case online
        case offline
        case away
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case status
        case lastSeen = "last_seen"
    }
}
