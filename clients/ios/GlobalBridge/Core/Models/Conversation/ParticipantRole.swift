//
//  ParticipantRole.swift
//  GlobalBridge
//
//  Enum defining participant roles in conversations
//

import Foundation

public enum ParticipantRole: String, Codable, CaseIterable {
    case owner
    case admin
    case member
    case guest

    var displayName: String {
        switch self {
        case .owner:
            return "Owner"
        case .admin:
            return "Admin"
        case .member:
            return "Member"
        case .guest:
            return "Guest"
        }
    }

    var canEditConversation: Bool {
        switch self {
        case .owner, .admin:
            return true
        case .member, .guest:
            return false
        }
    }

    var canInviteParticipants: Bool {
        switch self {
        case .owner, .admin, .member:
            return true
        case .guest:
            return false
        }
    }

    var canRemoveParticipants: Bool {
        switch self {
        case .owner, .admin:
            return true
        case .member, .guest:
            return false
        }
    }
}
