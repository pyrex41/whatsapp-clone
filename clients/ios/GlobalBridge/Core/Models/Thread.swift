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
    var participantIds: [String]?  // For displaying DM names
    var unreadCount: Int
    var lastReadMessageId: UUID?
    var encryptionVersion: Int
    var encryptionSalt: String?
    let createdAt: Date
    var updatedAt: Date

    enum ThreadType: String, Codable {
        case direct = "direct"
        case group = "group"
        case channel = "channel"
    }

    nonisolated init(
        id: UUID = UUID(),
        threadType: ThreadType,
        title: String? = nil,
        avatarUrl: String? = nil,
        lastMessageAt: Date? = nil,
        isArchived: Bool = false,
        isMuted: Bool = false,
        databaseShardId: String? = nil,
        participantIds: [String]? = nil,
        unreadCount: Int = 0,
        lastReadMessageId: UUID? = nil,
        encryptionVersion: Int = 1,
        encryptionSalt: String? = nil,
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
        self.participantIds = participantIds
        self.unreadCount = unreadCount
        self.lastReadMessageId = lastReadMessageId
        self.encryptionVersion = encryptionVersion
        self.encryptionSalt = encryptionSalt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Display name for the thread.
    /// - Groups: prefer title; fallback to "Group Chat".
    /// - Direct messages: ALWAYS use userCache for proper name formatting,
    ///   fallback to backend title only if user not in cache yet.
    func displayName(currentUserId: String, userCache: [String: CachedUserInfo] = [:]) -> String {
        // Groups: use title
        if threadType != .direct {
            return title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Group Chat"
        }

        // DMs: ALWAYS prioritize userCache for proper display name formatting
        if let participants = participantIds,
           let otherParticipant = participants.first(where: { $0 != currentUserId }) {
            print("🔍 [DISPLAY_NAME] Looking up user: \(otherParticipant) in cache (size: \(userCache.count))")

            // Look up from cache first - this formats usernames properly
            if let cachedUser = userCache[otherParticipant] {
                print("✅ [DISPLAY_NAME] Found in cache: \(cachedUser.effectiveDisplayName)")
                return cachedUser.effectiveDisplayName
            }

            print("⚠️ [DISPLAY_NAME] Not in cache, using fallback")
            print("   Cache keys: \(userCache.keys)")

            // Fallback 1: Use backend title if available (during initial load)
            if let provided = title?.trimmingCharacters(in: .whitespacesAndNewlines), !provided.isEmpty {
                // Format the backend title using the same logic as CachedUserInfo
                return formatUsername(provided)
            }

            // Fallback 2: Use ID prefix
            let prefix = otherParticipant.prefix(8)
            return "User \(prefix)"
        }
        // Last resort
        return "Direct Message"
    }

    /// Format username into a readable display name (same logic as CachedUserInfo)
    private func formatUsername(_ username: String) -> String {
        // Check if username looks like an email
        if username.contains("@") {
            let localPart = username.components(separatedBy: "@").first ?? username
            let cleanName = localPart.components(separatedBy: "+").first ?? localPart
            let formatted = cleanName
                .replacingOccurrences(of: ".", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            return formatted
        }

        // Check if username has timestamp suffix (e.g., "john_1702345678901" or "user_1702345678901")
        let parts = username.components(separatedBy: "_")
        if parts.count >= 2, let lastPart = parts.last, lastPart.count >= 10, lastPart.allSatisfy({ $0.isNumber }) {
            let namePart = parts.dropLast().joined(separator: " ")

            // Special case: if the name part is just "user", show "User <id prefix>"
            if namePart.lowercased() == "user" {
                let idPrefix = String(lastPart.prefix(8))
                return "User \(idPrefix)"
            }

            // Otherwise format the name nicely
            let formatted = namePart.capitalized
            return formatted.isEmpty ? username : formatted
        }

        // Otherwise use username as-is with some formatting
        let formatted = username
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return formatted.isEmpty ? username : formatted
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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
