//
//  TypingIndicator.swift
//  GlobalBridge
//
//  Typing indicator models for real-time typing status
//

import Foundation

/// Represents a typing indicator event
public struct TypingIndicator: Codable, Sendable, Equatable {
    public let userId: String
    public let conversationId: String
    public let isTyping: Bool
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case conversationId = "conversation_id"
        case isTyping = "is_typing"
        case timestamp
    }

    public nonisolated init(
        userId: String,
        conversationId: String,
        isTyping: Bool,
        timestamp: Date = Date()
    ) {
        self.userId = userId
        self.conversationId = conversationId
        self.isTyping = isTyping
        self.timestamp = timestamp
    }
}

/// Represents a read receipt event
public struct ReadReceipt: Codable, Sendable, Equatable {
    public let userId: String
    public let conversationId: String
    public let messageId: String
    public let readAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case conversationId = "conversation_id"
        case messageId = "message_id"
        case readAt = "read_at"
    }

    public nonisolated init(
        userId: String,
        conversationId: String,
        messageId: String,
        readAt: Date = Date()
    ) {
        self.userId = userId
        self.conversationId = conversationId
        self.messageId = messageId
        self.readAt = readAt
    }
}

/// Stores typing state for a conversation
public struct TypingState: Equatable, Sendable {
    public var typingUsers: Set<String>
    public var lastUpdate: Date

    public nonisolated init(typingUsers: Set<String> = [], lastUpdate: Date = Date()) {
        self.typingUsers = typingUsers
        self.lastUpdate = lastUpdate
    }

    public var isAnyoneTyping: Bool {
        !typingUsers.isEmpty
    }

    public func typingText(currentUserId: String) -> String? {
        let otherUsers = typingUsers.filter { $0 != currentUserId }
        guard !otherUsers.isEmpty else { return nil }

        switch otherUsers.count {
        case 1:
            return "\(otherUsers.first!) is typing..."
        case 2:
            return "\(otherUsers.sorted().joined(separator: " and ")) are typing..."
        default:
            return "Multiple people are typing..."
        }
    }
}

/// Stores read receipt state for messages
public struct ReadReceiptState: Equatable {
    public var receipts: [String: [String: Date]] // messageId -> userId -> readAt

    public init(receipts: [String: [String: Date]] = [:]) {
        self.receipts = receipts
    }

    public func readByUsers(for messageId: String) -> [String] {
        if let readerMap = receipts[messageId] {
            return Array(readerMap.keys)
        }
        return []
    }

    public func readCount(for messageId: String) -> Int {
        receipts[messageId]?.count ?? 0
    }

    public func isRead(messageId: String, by userId: String) -> Bool {
        receipts[messageId]?[userId] != nil
    }

    public mutating func markAsRead(messageId: String, userId: String, at date: Date = Date()) {
        if receipts[messageId] == nil {
            receipts[messageId] = [:]
        }
        receipts[messageId]?[userId] = date
    }
}
