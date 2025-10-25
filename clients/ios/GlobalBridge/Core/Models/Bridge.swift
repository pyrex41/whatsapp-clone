//
//  Bridge.swift
//  GlobalBridge
//
//  Created by GlobalBridge on 10/24/25.
//  Bridge models for Telegram bridge integration
//

import Foundation

/// Represents a bridge configuration and status
struct Bridge: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let bridgeType: BridgeType
    let phoneNumber: String?
    var status: BridgeStatus.Status
    var lastConnectedAt: Date?
    var errorMessage: String?
    var isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum BridgeType: String, Codable {
        case telegram = "telegram"
        case whatsapp = "whatsapp"
    }

    init(
        id: String,
        userId: String,
        bridgeType: BridgeType,
        phoneNumber: String? = nil,
        status: BridgeStatus.Status = .disconnected,
        lastConnectedAt: Date? = nil,
        errorMessage: String? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.bridgeType = bridgeType
        self.phoneNumber = phoneNumber
        self.status = status
        self.lastConnectedAt = lastConnectedAt
        self.errorMessage = errorMessage
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Bridge status update from Phoenix channel
struct BridgeStatus: Sendable {
    let bridgeId: String
    let bridgeType: String
    let status: Status
    let phoneNumber: String?
    let errorMessage: String?
    let timestamp: Date

    enum Status: String, Sendable {
        case connected = "connected"
        case disconnected = "disconnected"
        case error = "error"
        case connecting = "connecting"
    }

    var displayStatus: String {
        switch status {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        case .connecting:
            return "Connecting..."
        }
    }

    var statusColor: String {
        switch status {
        case .connected:
            return "green"
        case .disconnected:
            return "gray"
        case .error:
            return "red"
        case .connecting:
            return "yellow"
        }
    }
}

/// Request to create a new bridge
struct CreateBridgeRequest: Codable {
    let bridgeType: String
    let phoneNumber: String

    init(bridgeType: String, phoneNumber: String) {
        self.bridgeType = bridgeType
        self.phoneNumber = phoneNumber
    }
}