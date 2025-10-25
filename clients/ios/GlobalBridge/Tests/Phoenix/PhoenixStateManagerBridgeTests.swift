//
//  PhoenixStateManagerBridgeTests.swift
//  GlobalBridge
//
//  Created by GlobalBridge on 10/24/25.
//  Unit tests for Phoenix state manager bridge functionality
//

import XCTest
@testable import GlobalBridge

final class PhoenixStateManagerBridgeTests: XCTestCase {
    var stateManager: PhoenixStateManager!

    override func setUp() {
        super.setUp()
        stateManager = PhoenixStateManager.preview
    }

    override func tearDown() {
        stateManager = nil
        super.tearDown()
    }

    func testBridgeStatusHandling() {
        // Given
        let bridgeStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .connected,
            phoneNumber: "+1234567890",
            errorMessage: nil,
            timestamp: Date()
        )

        // When - simulate receiving bridge status (normally done via channel handler)
        stateManager.handleBridgeStatus(bridgeStatus)

        // Then
        let bridges = stateManager.getBridges()
        XCTAssertEqual(bridges.count, 1)

        let bridge = bridges["bridge_123"]
        XCTAssertNotNil(bridge)
        XCTAssertEqual(bridge?.id, "bridge_123")
        XCTAssertEqual(bridge?.bridgeType, .telegram)
        XCTAssertEqual(bridge?.status, .connected)
        XCTAssertEqual(bridge?.phoneNumber, "+1234567890")
    }

    func testBridgeStatusUpdate() {
        // Given - initial connected status
        let initialStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .connected,
            phoneNumber: "+1234567890",
            errorMessage: nil,
            timestamp: Date()
        )

        stateManager.handleBridgeStatus(initialStatus)

        // When - update to error status
        let errorStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .error,
            phoneNumber: "+1234567890",
            errorMessage: "Connection failed",
            timestamp: Date()
        )

        stateManager.handleBridgeStatus(errorStatus)

        // Then
        let bridge = stateManager.getBridge(byId: "bridge_123")
        XCTAssertNotNil(bridge)
        XCTAssertEqual(bridge?.status, .error)
        XCTAssertEqual(bridge?.errorMessage, "Connection failed")
    }

    func testGetBridgeById() {
        // Given
        let bridgeStatus = BridgeStatus(
            bridgeId: "bridge_456",
            bridgeType: "whatsapp",
            status: .connecting,
            phoneNumber: "+0987654321",
            errorMessage: nil,
            timestamp: Date()
        )

        stateManager.handleBridgeStatus(bridgeStatus)

        // When
        let retrievedBridge = stateManager.getBridge(byId: "bridge_456")

        // Then
        XCTAssertNotNil(retrievedBridge)
        XCTAssertEqual(retrievedBridge?.bridgeType, .whatsapp)
        XCTAssertEqual(retrievedBridge?.status, .connecting)
    }

    func testGetNonExistentBridge() {
        // When
        let bridge = stateManager.getBridge(byId: "non_existent")

        // Then
        XCTAssertNil(bridge)
    }

    func testMultipleBridges() {
        // Given
        let telegramStatus = BridgeStatus(
            bridgeId: "telegram_bridge",
            bridgeType: "telegram",
            status: .connected,
            phoneNumber: "+1234567890",
            errorMessage: nil,
            timestamp: Date()
        )

        let whatsappStatus = BridgeStatus(
            bridgeId: "whatsapp_bridge",
            bridgeType: "whatsapp",
            status: .disconnected,
            phoneNumber: "+0987654321",
            errorMessage: nil,
            timestamp: Date()
        )

        // When
        stateManager.handleBridgeStatus(telegramStatus)
        stateManager.handleBridgeStatus(whatsappStatus)

        // Then
        let bridges = stateManager.getBridges()
        XCTAssertEqual(bridges.count, 2)

        let telegramBridge = bridges["telegram_bridge"]
        let whatsappBridge = bridges["whatsapp_bridge"]

        XCTAssertNotNil(telegramBridge)
        XCTAssertNotNil(whatsappBridge)
        XCTAssertEqual(telegramBridge?.bridgeType, .telegram)
        XCTAssertEqual(whatsappBridge?.bridgeType, .whatsapp)
    }

    func testBridgeStatusWithLastConnectedAt() {
        // Given
        let connectedTime = Date()
        let bridgeStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .connected,
            phoneNumber: "+1234567890",
            errorMessage: nil,
            timestamp: connectedTime
        )

        // When
        stateManager.handleBridgeStatus(bridgeStatus)

        // Then
        let bridge = stateManager.getBridge(byId: "bridge_123")
        XCTAssertNotNil(bridge)
        XCTAssertEqual(bridge?.lastConnectedAt, connectedTime)
    }

    func testBridgeStatusDisconnectedNoLastConnectedAt() {
        // Given
        let bridgeStatus = BridgeStatus(
            bridgeId: "bridge_123",
            bridgeType: "telegram",
            status: .disconnected,
            phoneNumber: "+1234567890",
            errorMessage: nil,
            timestamp: Date()
        )

        // When
        stateManager.handleBridgeStatus(bridgeStatus)

        // Then
        let bridge = stateManager.getBridge(byId: "bridge_123")
        XCTAssertNotNil(bridge)
        XCTAssertNil(bridge?.lastConnectedAt)
    }
}