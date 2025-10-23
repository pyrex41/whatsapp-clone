//
//  BootstrapModels.swift
//  GlobalBridge
//
//  Models for bootstrap data from backend
//

import Foundation

/// Response from bootstrap channel push
nonisolated public struct BootstrapResponse: Codable, Sendable {
    public let threads: [ThreadData]
    public let user: UserData
    
    public init(threads: [ThreadData], user: UserData) {
        self.threads = threads
        self.user = user
    }
}

/// Thread data from backend
nonisolated public struct ThreadData: Codable, Sendable {
    public let id: String
    public let threadType: String
    public let title: String?
    public let databaseShardId: String
    public let lastMessageAt: Date?
    public let isArchived: Bool
    public let isMuted: Bool
    public let participantIds: [String]
    public let createdAt: Date
    public let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case threadType = "thread_type"
        case title
        case databaseShardId = "database_shard_id"
        case lastMessageAt = "last_message_at"
        case isArchived = "is_archived"
        case isMuted = "is_muted"
        case participantIds = "participant_ids"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(
        id: String,
        threadType: String,
        title: String?,
        databaseShardId: String,
        lastMessageAt: Date?,
        isArchived: Bool,
        isMuted: Bool,
        participantIds: [String],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.threadType = threadType
        self.title = title
        self.databaseShardId = databaseShardId
        self.lastMessageAt = lastMessageAt
        self.isArchived = isArchived
        self.isMuted = isMuted
        self.participantIds = participantIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// User data from backend
nonisolated public struct UserData: Codable, Sendable {
    public let id: String
    public let username: String?
    public let email: String?
    public let displayName: String?
    public let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
    
    public init(
        id: String,
        username: String?,
        email: String?,
        displayName: String?,
        avatarUrl: String?
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

/// User search result from backend
nonisolated public struct UserSearchResult: Codable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let email: String?
    public let displayName: String?
    public let avatarUrl: String?
    public let isOnline: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case isOnline = "is_online"
    }
    
    public init(
        id: String,
        username: String,
        email: String?,
        displayName: String?,
        avatarUrl: String?,
        isOnline: Bool
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isOnline = isOnline
    }
    
    // Custom decoder to handle SQLite's integer boolean values (0/1)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        
        // Handle both Bool and Int for isOnline (SQLite sends 0/1)
        if let boolValue = try? container.decode(Bool.self, forKey: .isOnline) {
            isOnline = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .isOnline) {
            isOnline = intValue != 0
        } else {
            isOnline = false // Default to offline if field is missing
        }
    }
}

/// Response from search users channel push
nonisolated public struct UserSearchResponse: Codable, Sendable {
    public let users: [UserSearchResult]
    
    public init(users: [UserSearchResult]) {
        self.users = users
    }
}


