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
        var locale: Locale.Identifier
        var enableReadReceipts: Bool
        var enableTypingIndicators: Bool
        var theme: Theme

        enum Theme: String, Codable {
            case system
            case light
            case dark
        }

        static let `default` = Preferences(
            locale: Locale.current.identifier,
            enableReadReceipts: true,
            enableTypingIndicators: true,
            theme: .system
        )
    }

    init(
        id: UUID = UUID(),
        handle: String,
        displayName: String,
        avatarURL: URL? = nil,
        email: String,
        phoneNumber: String? = nil,
        status: UserStatus = .active,
        publicKey: String? = nil,
        devicePublicKeys: [UUID: String] = [:],
        preferences: Preferences = .default,
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
        self.preferences = preferences
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension User {
    static let sampleCurrent = User(
        handle: "reuben",
        displayName: "Reuben Brooks",
        avatarURL: nil,
        email: "reuben@example.com",
        devicePublicKeys: [UUID(): "DEVICE_PUBLIC_KEY_SAMPLE"]
    )
}
