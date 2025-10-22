//
//  Contact.swift
//  GlobalBridge
//
//  Contact model for managing user contacts with sync support
//

import Foundation

public struct Contact: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let contactUserId: String  // UUID of the contact user
    public var displayNameOverride: String?
    public var isFavorite: Bool
    public var notes: String?
    public let user: ContactUser
    public let createdAt: Date
    public var updatedAt: Date
    public var lastSyncedAt: Date?
    public var needsSync: Bool = false
    public var isDeleted: Bool = false

    public struct ContactUser: Codable, Equatable, Sendable {
        public let id: String
        public let email: String
        public let username: String?
        public let displayName: String?
        public let avatarUrl: String?
        
        public enum CodingKeys: String, CodingKey {
            case id
            case email
            case username
            case displayName = "display_name"
            case avatarUrl = "avatar_url"
        }
        
        public nonisolated init(id: String, email: String, username: String? = nil, displayName: String? = nil, avatarUrl: String? = nil) {
            self.id = id
            self.email = email
            self.username = username
            self.displayName = displayName
            self.avatarUrl = avatarUrl
        }
        
        // Explicit nonisolated Codable implementation for Swift 6 concurrency
        public nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
            self.email = try container.decode(String.self, forKey: .email)
            self.username = try container.decodeIfPresent(String.self, forKey: .username)
            self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            self.avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        }
        
        public nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(email, forKey: .email)
            try container.encodeIfPresent(username, forKey: .username)
            try container.encodeIfPresent(displayName, forKey: .displayName)
            try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        }
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case contactUserId = "contact_user_id"
        case displayNameOverride = "display_name_override"
        case isFavorite = "is_favorite"
        case notes
        case user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSyncedAt = "last_synced_at"
        case needsSync = "needs_sync"
        case isDeleted = "is_deleted"
    }

    public var displayName: String {
        displayNameOverride ?? user.displayName ?? user.username ?? user.email
    }
    
    public nonisolated init(
        id: UUID = UUID(),
        contactUserId: String,
        displayNameOverride: String? = nil,
        isFavorite: Bool = false,
        notes: String? = nil,
        user: ContactUser,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        needsSync: Bool = false,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.contactUserId = contactUserId
        self.displayNameOverride = displayNameOverride
        self.isFavorite = isFavorite
        self.notes = notes
        self.user = user
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSyncedAt = lastSyncedAt
        self.needsSync = needsSync
        self.isDeleted = isDeleted
    }
    
    // Explicit nonisolated Codable implementation for Swift 6 concurrency
    public nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.contactUserId = try container.decode(String.self, forKey: .contactUserId)
        self.displayNameOverride = try container.decodeIfPresent(String.self, forKey: .displayNameOverride)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.user = try container.decode(ContactUser.self, forKey: .user)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        self.needsSync = try container.decodeIfPresent(Bool.self, forKey: .needsSync) ?? false
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
    }
    
    public nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(contactUserId, forKey: .contactUserId)
        try container.encodeIfPresent(displayNameOverride, forKey: .displayNameOverride)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(user, forKey: .user)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try container.encode(needsSync, forKey: .needsSync)
        try container.encode(isDeleted, forKey: .isDeleted)
    }
}

