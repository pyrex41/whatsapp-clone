//
//  Contact.swift
//  GlobalBridge
//
//  Contact model for managing user contacts with sync support
//

import Foundation

struct Contact: Identifiable, Codable, Equatable {
    let id: UUID
    let contactUserId: String  // UUID of the contact user
    var displayNameOverride: String?
    var isFavorite: Bool
    var notes: String?
    let user: ContactUser
    let createdAt: Date
    var updatedAt: Date
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var isDeleted: Bool = false

    struct ContactUser: Codable, Equatable {
        let id: String
        let email: String
        let username: String?
        let displayName: String?
        let avatarUrl: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case email
            case username
            case displayName = "display_name"
            case avatarUrl = "avatar_url"
        }
    }

    enum CodingKeys: String, CodingKey {
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

    var displayName: String {
        displayNameOverride ?? user.displayName ?? user.username ?? user.email
    }
    
    nonisolated init(
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

