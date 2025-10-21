//
//  User.swift
//  GlobalBridge
//
//  Created by AI Assistant on 10/21/25.
//

import Foundation

/// Primary user model mirroring the backend schema.
struct User: Identifiable, Codable, Equatable {
    let id: UUID
    var handle: String
    var displayName: String
    var avatarURL: URL?
    var email: String
    var phoneNumber: String?
    var status: UserStatus
    var publicKey: String?
    var devicePublicKeys: [UUID: String]
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
        id: UUID = UUID(),
        handle: String,
        displayName: String,
        avatarURL: URL? = nil,
        email: String,
        phoneNumber: String? = nil,
        status: UserStatus = .active,
        publicKey: String? = nil,
        devicePublicKeys: [UUID: String] = [:],
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
    nonisolated static var sampleCurrent: User {
        User(
            handle: "reuben",
            displayName: "Reuben Brooks",
            avatarURL: nil,
            email: "reuben@example.com",
            devicePublicKeys: [UUID(): "DEVICE_PUBLIC_KEY_SAMPLE"]
        )
    }
}
