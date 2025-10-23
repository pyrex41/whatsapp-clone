//
//  User.swift
//  GlobalBridge
//
//  Created by AI Assistant on 10/21/25.
//

import Foundation

/// Primary user model mirroring the backend schema.
struct User: Identifiable, Codable, Equatable {
    let id: String  // Changed from UUID to String to match backend
    var handle: String
    var displayName: String
    var avatarURL: URL?
    var email: String
    var phoneNumber: String?
    var status: UserStatus
    var publicKey: String?
    var devicePublicKeys: [String: String]  // Changed from [UUID: String] to match
    var preferences: Preferences
    let createdAt: Date
    var updatedAt: Date

    enum UserStatus: String, Codable {
        case active
        case disabled
        case pending
    }

    struct Preferences: Codable, Equatable {
        var locale: String
        var enableReadReceipts: Bool
        var enableTypingIndicators: Bool
        var theme: Theme

        enum Theme: String, Codable {
            case system
            case light
            case dark
        }

        nonisolated static let defaultLocaleIdentifier = "en_US"

        nonisolated static func defaultPreferences() -> Preferences {
            Preferences(
                locale: defaultLocaleIdentifier,
                enableReadReceipts: true,
                enableTypingIndicators: true,
                theme: .system
            )
        }
    }

    nonisolated init(
        id: String,  // Changed from UUID to String
        handle: String,
        displayName: String,
        avatarURL: URL? = nil,
        email: String,
        phoneNumber: String? = nil,
        status: UserStatus = .active,
        publicKey: String? = nil,
        devicePublicKeys: [String: String] = [:],  // Changed from [UUID: String]
        preferences: Preferences? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.email = email
        self.phoneNumber = phoneNumber
        self.status = status
        self.publicKey = publicKey
        self.devicePublicKeys = devicePublicKeys
        self.preferences = preferences ?? Preferences.defaultPreferences()
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension User {
    /// Initialize from UserData received from backend
    nonisolated static func from(_ userData: UserData) -> User {
        User(
            id: userData.id,
            handle: userData.username ?? "Unknown",
            displayName: userData.displayName ?? userData.username ?? "User",
            email: userData.email ?? "",
            preferences: .defaultPreferences()
        )
    }
    
    nonisolated static var sampleCurrent: User {
        User(
            id: "6abe02c6-92e1-4012-8e2c-f30ea22e71c1",
            handle: "reuben",
            displayName: "Reuben Brooks",
            avatarURL: nil,
            email: "reuben@example.com",
            devicePublicKeys: [:]
        )
    }
}
