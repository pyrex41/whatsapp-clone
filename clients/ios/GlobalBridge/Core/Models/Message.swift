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
    let senderId: UUID
    var content: String
    var messageType: MessageType
    var status: MessageStatus
    var metadata: [String: String]?
    var replyToId: UUID?
    var editedAt: Date?
    var deletedAt: Date?
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

    init(
        id: UUID = UUID(),
        threadId: UUID,
        senderId: UUID,
        content: String,
        messageType: MessageType = .text,
        status: MessageStatus = .pending,
        metadata: [String: String]? = nil,
        replyToId: UUID? = nil,
        editedAt: Date? = nil,
        deletedAt: Date? = nil,
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
