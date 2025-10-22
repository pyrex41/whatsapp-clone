//
//  Message.swift
//  GlobalBridge
//
//  Created by DatabaseManager on 10/20/25.
//

import Foundation

/// Message model for per-thread sharded database
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let threadId: UUID
    let senderId: String  // Changed from UUID to String to match backend
    var content: String
    var messageType: MessageType
    var status: MessageStatus
    var metadata: [String: String]?
    var replyToId: UUID?
    var editedAt: Date?
    var deletedAt: Date?
    var isEncrypted: Bool
    var encryptionKeyId: String?
    var ciphertext: Data?
    let createdAt: Date
    let updatedAt: Date

    enum MessageType: String, Codable {
        case text = "text"
        case image = "image"
        case video = "video"
        case audio = "audio"
        case file = "file"
        case location = "location"
        case contact = "contact"
    }

    enum MessageStatus: String, Codable {
        case pending = "pending"
        case sent = "sent"
        case delivered = "delivered"
        case read = "read"
        case failed = "failed"
    }

    // Alias for backward compatibility
    typealias Status = MessageStatus

    nonisolated init(
        id: UUID = UUID(),
        threadId: UUID,
        senderId: String,  // Changed from UUID to String
        content: String,
        messageType: MessageType = .text,
        status: MessageStatus = .pending,
        metadata: [String: String]? = nil,
        replyToId: UUID? = nil,
        editedAt: Date? = nil,
        deletedAt: Date? = nil,
        isEncrypted: Bool = false,
        encryptionKeyId: String? = nil,
        ciphertext: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.senderId = senderId
        self.content = content
        self.messageType = messageType
        self.status = status
        self.metadata = metadata
        self.replyToId = replyToId
        self.editedAt = editedAt
        self.deletedAt = deletedAt
        self.isEncrypted = isEncrypted
        self.encryptionKeyId = encryptionKeyId
        self.ciphertext = ciphertext
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Message {
    nonisolated static func fromPhoenix(_ phoenixMessage: PhoenixMessage) -> Message? {
        guard
            let messageId = UUID(uuidString: phoenixMessage.id),
            let threadId = UUID(uuidString: phoenixMessage.conversationId)
        else {
            return nil
        }

        let status: MessageStatus
        switch phoenixMessage.status {
        case .sending:
            status = .pending
        case .sent:
            status = .sent
        case .delivered:
            status = .delivered
        case .read:
            status = .read
        case .failed:
            status = .failed
        }

        var replyTo: UUID?
        if let reply = phoenixMessage.metadata?.replyToId {
            replyTo = UUID(uuidString: reply)
        }

        return Message(
            id: messageId,
            threadId: threadId,
            senderId: phoenixMessage.senderId,  // Now a String
            content: phoenixMessage.content,
            messageType: .text,
            status: status,
            metadata: nil,
            replyToId: replyTo,
            editedAt: phoenixMessage.metadata?.editedAt,
            deletedAt: nil,
            isEncrypted: false,
            encryptionKeyId: nil,
            ciphertext: nil,
            createdAt: phoenixMessage.timestamp,
            updatedAt: phoenixMessage.timestamp
        )
    }
}
