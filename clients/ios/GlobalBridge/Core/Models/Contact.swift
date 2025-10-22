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
        
        public init(id: String, email: String, username: String? = nil, displayName: String? = nil, avatarUrl: String? = nil) {
            self.id = id
            self.email = email
            self.username = username
            self.displayName = displayName
            self.avatarUrl = avatarUrl
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
}

