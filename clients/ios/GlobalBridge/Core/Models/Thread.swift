//
//  Thread.swift
//  GlobalBridge
//
//  Created by DatabaseManager on 10/20/25.
//

import Foundation

/// Represents a conversation thread matching backend schema
struct Thread: Identifiable, Codable, Equatable {
    let id: UUID
    let threadType: ThreadType
    var title: String?
    var avatarUrl: String?
    var lastMessageAt: Date?
    var isArchived: Bool
    var isMuted: Bool
    let databaseShardId: String
    let createdAt: Date
    let updatedAt: Date

    enum ThreadType: String, Codable {
        case direct = "direct"
        case group = "group"
        case channel = "channel"
    }

    init(
        id: UUID = UUID(),
        threadType: ThreadType,
        title: String? = nil,
        avatarUrl: String? = nil,
        lastMessageAt: Date? = nil,
        isArchived: Bool = false,
        isMuted: Bool = false,
        databaseShardId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.threadType = threadType
        self.title = title
        self.avatarUrl = avatarUrl
        self.lastMessageAt = lastMessageAt
        self.isArchived = isArchived
        self.isMuted = isMuted
        self.databaseShardId = databaseShardId ?? "thread_\(id.uuidString)"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Thread participant matching backend schema
struct ThreadParticipant: Identifiable, Codable, Equatable {
    let id: UUID
    let threadId: UUID
    let userId: UUID
    var role: ParticipantRole
    let joinedAt: Date
    var leftAt: Date?
    var isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum ParticipantRole: String, Codable {
        case member = "member"
        case admin = "admin"
        case owner = "owner"
    }

    init(
        id: UUID = UUID(),
        threadId: UUID,
        userId: UUID,
        role: ParticipantRole = .member,
        joinedAt: Date = Date(),
        leftAt: Date? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.userId = userId
        self.role = role
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
