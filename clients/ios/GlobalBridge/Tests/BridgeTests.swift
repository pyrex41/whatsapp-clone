//
//  BridgeTests.swift
//  GlobalBridge
//
//  Created by GlobalBridge on 10/24/25.
//  Unit tests for Bridge models
//

import XCTest
@testable import GlobalBridge

final class BridgeTests: XCTestCase {
    func testBridgeInitialization() {
        // Given
        let id = "bridge_123"
        let userId = "user_456"
        let bridgeType = Bridge.BridgeType.telegram
        let phoneNumber = "+1234567890"
        let status = BridgeStatus.Status.connected
        let lastConnectedAt = Date()
        let errorMessage = "Test error"
        let isActive = true
        let createdAt = Date()
        let updatedAt = Date()

        // When
        let bridge = Bridge(
            id: id,
            userId: userId,
            bridgeType: bridgeType,
            phoneNumber: phoneNumber,
            status: status,
            lastConnectedAt: lastConnectedAt,
            errorMessage: errorMessage,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        // Then
        XCTAssertEqual(bridge.id, id)
        XCTAssertEqual(bridge.userId, userId)
        XCTAssertEqual(bridge.bridgeType, bridgeType)
        XCTAssertEqual(bridge.phoneNumber, phoneNumber)
        XCTAssertEqual(bridge.status, status)
        XCTAssertEqual(bridge.lastConnectedAt, lastConnectedAt)
        XCTAssertEqual(bridge.errorMessage, errorMessage)
        XCTAssertEqual(bridge.isActive, isActive)
        XCTAssertEqual(bridge.createdAt, createdAt)
        XCTAssertEqual(bridge.updatedAt, updatedAt)
    }

    func testBridgeDefaultValues() {
        // When
        let bridge = Bridge(
            id: "bridge_123",
            userId: "user_456",
            bridgeType: .telegram
        )

        // Then
        XCTAssertEqual(bridge.status, .disconnected)
        XCTAssertNil(bridge.phoneNumber)
        XCTAssertNil(bridge.lastConnectedAt)
        XCTAssertNil(bridge.errorMessage)
        XCTAssertTrue(bridge.isActive)
        XCTAssertNotNil(bridge.createdAt)
        XCTAssertNotNil(bridge.updatedAt)
    }

    func testBridgeEquatable() {
        // Given
        let bridge1 = Bridge(
            id: "bridge_123",
            userId: "user_456",
            bridgeType: .telegram,
            phoneNumber: "+1234567890"
        )

        let bridge2 = Bridge(
            id: "bridge_123",
            userId: "user_456",
            bridgeType: .telegram,
            phoneNumber: "+1234567890"
        )

        let bridge3 = Bridge(
            id: "bridge_456",
            userId: "user_456",
            bridgeType: .telegram,
            phoneNumber: "+1234567890"
        )

        // Then
        XCTAssertEqual(bridge1, bridge2)
        XCTAssertNotEqual(bridge1, bridge3)
    }

    func testBridgeTypeCodable() {
        // Given
        let telegram: Bridge.BridgeType = .telegram
        let whatsapp: Bridge.BridgeType = .whatsapp

        // When/Then
        XCTAssertEqual(telegram.rawValue, "telegram")
        XCTAssertEqual(whatsapp.rawValue, "whatsapp")

        // Test decoding
        XCTAssertEqual(Bridge.BridgeType(rawValue: "telegram"), .telegram)
        XCTAssertEqual(Bridge.BridgeType(rawValue: "whatsapp"), .whatsapp)
        XCTAssertNil(Bridge.BridgeType(rawValue: "invalid"))
    }

    func testBridgeStatusInitialization() {
        // Given
        let bridgeId = "bridge_123"
        let bridgeType = "telegram"
        let status = BridgeStatus.Status.connected
        let phoneNumber = "+1234567890"
        let errorMessage = "Connection failed"
        let timestamp = Date()

        // When
        let bridgeStatus = BridgeStatus(
            bridgeId: bridgeId,
            bridgeType: bridgeType,
            status: status,
            phoneNumber: phoneNumber,
            errorMessage: errorMessage,
            timestamp: timestamp
        )

        // Then
        XCTAssertEqual(bridgeStatus.bridgeId, bridgeId)
        XCTAssertEqual(bridgeStatus.bridgeType, bridgeType)
        XCTAssertEqual(bridgeStatus.status, status)
        XCTAssertEqual(bridgeStatus.phoneNumber, phoneNumber)
        XCTAssertEqual(bridgeStatus.errorMessage, errorMessage)
        XCTAssertEqual(bridgeStatus.timestamp, timestamp)
    }

    func testBridgeStatusDisplayStatus() {
        // Test connected status
        let connectedStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .connected,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(connectedStatus.displayStatus, "Connected")

        // Test disconnected status
        let disconnectedStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .disconnected,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(disconnectedStatus.displayStatus, "Disconnected")

        // Test error status
        let errorStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .error,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(errorStatus.displayStatus, "Error")

        // Test connecting status
        let connectingStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .connecting,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(connectingStatus.displayStatus, "Connecting...")
    }

    func testBridgeStatusStatusColor() {
        // Test connected color
        let connectedStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .connected,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(connectedStatus.statusColor, "green")

        // Test disconnected color
        let disconnectedStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .disconnected,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(disconnectedStatus.statusColor, "gray")

        // Test error color
        let errorStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .error,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(errorStatus.statusColor, "red")

        // Test connecting color
        let connectingStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .connecting,
            phoneNumber: nil,
            errorMessage: nil,
            timestamp: Date()
        )
        XCTAssertEqual(connectingStatus.statusColor, "yellow")
    }

    func testBridgeStatusStatusEnum() {
        // Test raw values
        XCTAssertEqual(BridgeStatus.Status.connected.rawValue, "connected")
        XCTAssertEqual(BridgeStatus.Status.disconnected.rawValue, "disconnected")
        XCTAssertEqual(BridgeStatus.Status.error.rawValue, "error")
        XCTAssertEqual(BridgeStatus.Status.connecting.rawValue, "connecting")

        // Test decoding
        XCTAssertEqual(BridgeStatus.Status(rawValue: "connected"), .connected)
        XCTAssertEqual(BridgeStatus.Status(rawValue: "disconnected"), .disconnected)
        XCTAssertEqual(BridgeStatus.Status(rawValue: "error"), .error)
        XCTAssertEqual(BridgeStatus.Status(rawValue: "connecting"), .connecting)
        XCTAssertNil(BridgeStatus.Status(rawValue: "invalid"))
    }

    func testCreateBridgeRequestInitialization() {
        // Given
        let bridgeType = "telegram"
        let phoneNumber = "+1234567890"

        // When
        let request = CreateBridgeRequest(bridgeType: bridgeType, phoneNumber: phoneNumber)

        // Then
        XCTAssertEqual(request.bridgeType, bridgeType)
        XCTAssertEqual(request.phoneNumber, phoneNumber)
    }

    func testCreateBridgeRequestCodable() {
        // Given
        let request = CreateBridgeRequest(bridgeType: "telegram", phoneNumber: "+1234567890")

        // When/Then - Test encoding/decoding
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(request)

            let decoder = JSONDecoder()
            let decodedRequest = try decoder.decode(CreateBridgeRequest.self, from: data)

            XCTAssertEqual(decodedRequest.bridgeType, request.bridgeType)
            XCTAssertEqual(decodedRequest.phoneNumber, request.phoneNumber)
        } catch {
            XCTFail("Encoding/decoding failed: \(error)")
        }
    }

    func testBridgeCodable() {
        // Given
        let bridge = Bridge(
            id: "bridge_123",
            userId: "user_456",
            bridgeType: .telegram,
            phoneNumber: "+1234567890",
            status: .connected,
            lastConnectedAt: Date(),
            errorMessage: "Test error",
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        // When/Then - Test encoding/decoding
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(bridge)

            let decoder = JSONDecoder()
            let decodedBridge = try decoder.decode(Bridge.self, from: data)

            XCTAssertEqual(decodedBridge.id, bridge.id)
            XCTAssertEqual(decodedBridge.userId, bridge.userId)
            XCTAssertEqual(decodedBridge.bridgeType, bridge.bridgeType)
            XCTAssertEqual(decodedBridge.phoneNumber, bridge.phoneNumber)
            XCTAssertEqual(decodedBridge.status, bridge.status)
            XCTAssertEqual(decodedBridge.isActive, bridge.isActive)
        } catch {
            XCTFail("Encoding/decoding failed: \(error)")
        }
    }
}