//
//  TypingIndicatorTests.swift
//  GlobalBridgeTests
//
//  Tests for typing indicator functionality
//

import XCTest
@testable import GlobalBridge

final class TypingIndicatorTests: XCTestCase {
    func testTypingIndicatorCreation() {
        let indicator = TypingIndicator(
            userId: "user1",
            conversationId: "conv1",
            isTyping: true
        )

        XCTAssertEqual(indicator.userId, "user1")
        XCTAssertEqual(indicator.conversationId, "conv1")
        XCTAssertTrue(indicator.isTyping)
    }

    func testTypingStateManagement() {
        var state = TypingState()

        // Initially no one typing
        XCTAssertFalse(state.isAnyoneTyping)
        XCTAssertNil(state.typingText(currentUserId: "me"))

        // Add typing user
        state.typingUsers.insert("user1")
        XCTAssertTrue(state.isAnyoneTyping)
        XCTAssertEqual(state.typingText(currentUserId: "me"), "user1 is typing...")

        // Add second typing user
        state.typingUsers.insert("user2")
        XCTAssertEqual(state.typingText(currentUserId: "me"), "user1 and user2 are typing...")

        // Add third typing user
        state.typingUsers.insert("user3")
        XCTAssertEqual(state.typingText(currentUserId: "me"), "Multiple people are typing...")

        // Remove all users
        state.typingUsers.removeAll()
        XCTAssertFalse(state.isAnyoneTyping)
    }

    func testTypingStateExcludesCurrentUser() {
        var state = TypingState()
        state.typingUsers.insert("me")
        state.typingUsers.insert("user1")

        let text = state.typingText(currentUserId: "me")
        XCTAssertEqual(text, "user1 is typing...")
    }

    func testTypingIndicatorCodable() throws {
        let indicator = TypingIndicator(
            userId: "user1",
            conversationId: "conv1",
            isTyping: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(indicator)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(TypingIndicator.self, from: data)

        XCTAssertEqual(decoded.userId, indicator.userId)
        XCTAssertEqual(decoded.conversationId, indicator.conversationId)
        XCTAssertEqual(decoded.isTyping, indicator.isTyping)
    }
}
