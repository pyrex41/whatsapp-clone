//
//  ReadReceiptTests.swift
//  GlobalBridgeTests
//
//  Tests for read receipt functionality
//

import XCTest
@testable import GlobalBridge

final class ReadReceiptTests: XCTestCase {
    func testReadReceiptCreation() {
        let receipt = ReadReceipt(
            userId: "user1",
            conversationId: "conv1",
            messageId: "msg1"
        )

        XCTAssertEqual(receipt.userId, "user1")
        XCTAssertEqual(receipt.conversationId, "conv1")
        XCTAssertEqual(receipt.messageId, "msg1")
    }

    func testReadReceiptStateManagement() {
        var state = ReadReceiptState()

        // Initially no receipts
        XCTAssertEqual(state.readCount(for: "msg1"), 0)
        XCTAssertFalse(state.isRead(messageId: "msg1", by: "user1"))

        // Mark as read by user1
        state.markAsRead(messageId: "msg1", userId: "user1")
        XCTAssertTrue(state.isRead(messageId: "msg1", by: "user1"))
        XCTAssertEqual(state.readCount(for: "msg1"), 1)

        // Mark as read by user2
        state.markAsRead(messageId: "msg1", userId: "user2")
        XCTAssertTrue(state.isRead(messageId: "msg1", by: "user2"))
        XCTAssertEqual(state.readCount(for: "msg1"), 2)

        // Check read by users
        let readers = state.readByUsers(for: "msg1")
        XCTAssertEqual(readers.count, 2)
        XCTAssertTrue(readers.contains("user1"))
        XCTAssertTrue(readers.contains("user2"))
    }

    func testReadReceiptStateMultipleMessages() {
        var state = ReadReceiptState()

        state.markAsRead(messageId: "msg1", userId: "user1")
        state.markAsRead(messageId: "msg2", userId: "user1")
        state.markAsRead(messageId: "msg2", userId: "user2")

        XCTAssertEqual(state.readCount(for: "msg1"), 1)
        XCTAssertEqual(state.readCount(for: "msg2"), 2)
    }

    func testReadReceiptCodable() throws {
        let receipt = ReadReceipt(
            userId: "user1",
            conversationId: "conv1",
            messageId: "msg1"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(receipt)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReadReceipt.self, from: data)

        XCTAssertEqual(decoded.userId, receipt.userId)
        XCTAssertEqual(decoded.conversationId, receipt.conversationId)
        XCTAssertEqual(decoded.messageId, receipt.messageId)
    }
}
