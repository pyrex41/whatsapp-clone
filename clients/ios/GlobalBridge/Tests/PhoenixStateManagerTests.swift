//
//  PhoenixStateManagerTests.swift
//  GlobalBridgeTests
//
//  Tests for enhanced PhoenixStateManager with typing, receipts, and presence
//

import XCTest
@testable import GlobalBridge

@MainActor
final class PhoenixStateManagerIntegrationTests: XCTestCase {
    var stateManager: PhoenixStateManager!

    override func setUp() async throws {
        stateManager = PhoenixStateManager(config: .development)
    }

    override func tearDown() async throws {
        await stateManager.disconnect()
        stateManager = nil
    }

    func testTypingStateInitialization() {
        let typingState = stateManager.getTypingState(for: "conv1")

        XCTAssertFalse(typingState.isAnyoneTyping)
        XCTAssertNil(typingState.typingText(currentUserId: "me"))
    }

    func testReadReceiptStateInitialization() {
        let receiptState = stateManager.getReadReceiptState(for: "conv1")

        XCTAssertEqual(receiptState.readCount(for: "msg1"), 0)
    }

    func testPresenceStateInitialization() {
        let presences = stateManager.getPresence(for: "conv1")

        XCTAssertTrue(presences.isEmpty)
    }

    func testMessagesRetrieval() {
        let messages = stateManager.getMessages(for: "conv1")

        XCTAssertTrue(messages.isEmpty)
    }

    func testConnectionState() {
        XCTAssertEqual(stateManager.connectionState, .disconnected)
    }
}
