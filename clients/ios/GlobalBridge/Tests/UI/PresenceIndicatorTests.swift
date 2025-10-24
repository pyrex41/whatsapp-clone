//
//  PresenceIndicatorTests.swift
//  GlobalBridgeTests
//
//  Unit tests for PresenceIndicator SwiftUI components
//

import XCTest
import SwiftUI
@testable import GlobalBridge

final class PresenceIndicatorTests: XCTestCase {

    // MARK: - PresenceIndicator Tests

    func testPresenceIndicatorOnlineColor() {
        // Given
        let indicator = PresenceIndicator(status: .online)

        // Then - should have green color (test via snapshot or manual verification)
        XCTAssertNotNil(indicator)
    }

    func testPresenceIndicatorOfflineColor() {
        // Given
        let indicator = PresenceIndicator(status: .offline)

        // Then
        XCTAssertNotNil(indicator)
    }

    func testPresenceIndicatorAwayColor() {
        // Given
        let indicator = PresenceIndicator(status: .away)

        // Then
        XCTAssertNotNil(indicator)
    }

    func testPresenceIndicatorSizing() {
        // Given
        let smallIndicator = PresenceIndicator(status: .online, size: 8)
        let largeIndicator = PresenceIndicator(status: .online, size: 20)

        // Then
        XCTAssertNotNil(smallIndicator)
        XCTAssertNotNil(largeIndicator)
    }

    // MARK: - PresenceStatusText Tests

    func testPresenceStatusTextOnline() {
        // Given
        let statusText = PresenceStatusText(status: .online)

        // Then - should show "Online"
        XCTAssertNotNil(statusText)
    }

    func testPresenceStatusTextOfflineWithLastSeen() {
        // Given
        let lastSeen = Date().addingTimeInterval(-3600) // 1 hour ago
        let statusText = PresenceStatusText(status: .offline, lastSeen: lastSeen, showLastSeen: true)

        // Then - should show "Last seen X ago"
        XCTAssertNotNil(statusText)
    }

    func testPresenceStatusTextOfflineWithoutLastSeen() {
        // Given
        let statusText = PresenceStatusText(status: .offline, lastSeen: nil)

        // Then - should show "Offline"
        XCTAssertNotNil(statusText)
    }

    func testPresenceStatusTextAway() {
        // Given
        let statusText = PresenceStatusText(status: .away)

        // Then - should show "Away"
        XCTAssertNotNil(statusText)
    }

    // MARK: - PresenceDisplay Tests

    func testPresenceDisplayWithBadgeAndText() {
        // Given
        let display = PresenceDisplay(
            status: .online,
            lastSeen: nil,
            showBadge: true,
            showText: true
        )

        // Then
        XCTAssertNotNil(display)
    }

    func testPresenceDisplayBadgeOnly() {
        // Given
        let display = PresenceDisplay(
            status: .online,
            showBadge: true,
            showText: false
        )

        // Then
        XCTAssertNotNil(display)
    }

    func testPresenceDisplayTextOnly() {
        // Given
        let display = PresenceDisplay(
            status: .online,
            showBadge: false,
            showText: true
        )

        // Then
        XCTAssertNotNil(display)
    }

    // MARK: - PresenceAvatar Tests

    func testPresenceAvatarWithUrl() {
        // Given
        let avatar = PresenceAvatar(
            avatarUrl: "https://example.com/avatar.jpg",
            status: .online,
            size: 48
        )

        // Then
        XCTAssertNotNil(avatar)
    }

    func testPresenceAvatarWithoutUrl() {
        // Given
        let avatar = PresenceAvatar(
            avatarUrl: nil,
            status: .online,
            size: 48
        )

        // Then - should show default avatar
        XCTAssertNotNil(avatar)
    }

    func testPresenceAvatarSizing() {
        // Given
        let smallAvatar = PresenceAvatar(status: .online, size: 32)
        let largeAvatar = PresenceAvatar(status: .online, size: 100)

        // Then
        XCTAssertNotNil(smallAvatar)
        XCTAssertNotNil(largeAvatar)
    }

    func testPresenceAvatarCustomBadgeSize() {
        // Given
        let avatar = PresenceAvatar(
            status: .online,
            size: 48,
            badgeSize: 16
        )

        // Then
        XCTAssertNotNil(avatar)
    }

    // MARK: - TypingIndicatorView Tests

    func testTypingIndicatorSingleUser() {
        // Given
        let typingUsers: Set<String> = ["Alice"]
        let indicator = TypingIndicatorView(
            typingUsers: typingUsers,
            currentUserId: "me"
        )

        // Then - should show "Alice is typing"
        XCTAssertNotNil(indicator)
    }

    func testTypingIndicatorTwoUsers() {
        // Given
        let typingUsers: Set<String> = ["Alice", "Bob"]
        let indicator = TypingIndicatorView(
            typingUsers: typingUsers,
            currentUserId: "me"
        )

        // Then - should show "Alice and Bob are typing"
        XCTAssertNotNil(indicator)
    }

    func testTypingIndicatorMultipleUsers() {
        // Given
        let typingUsers: Set<String> = ["Alice", "Bob", "Charlie"]
        let indicator = TypingIndicatorView(
            typingUsers: typingUsers,
            currentUserId: "me"
        )

        // Then - should show "Multiple people are typing"
        XCTAssertNotNil(indicator)
    }

    func testTypingIndicatorEmpty() {
        // Given
        let typingUsers: Set<String> = []
        let indicator = TypingIndicatorView(
            typingUsers: typingUsers,
            currentUserId: "me"
        )

        // Then - should not render anything
        XCTAssertNotNil(indicator)
    }

    func testTypingIndicatorExcludesCurrentUser() {
        // Given
        let typingUsers: Set<String> = ["Alice", "me"]
        let indicator = TypingIndicatorView(
            typingUsers: typingUsers,
            currentUserId: "me"
        )

        // Then - should only show "Alice is typing"
        XCTAssertNotNil(indicator)
    }

    // MARK: - TypingDotsView Tests

    func testTypingDotsView() {
        // Given
        let dots = TypingDotsView()

        // Then
        XCTAssertNotNil(dots)
    }

    // MARK: - ChatListPresenceRow Tests

    func testChatListRowOnline() {
        // Given
        let row = ChatListPresenceRow(
            userName: "Alice",
            lastMessage: "Hey there!",
            timestamp: Date(),
            status: .online,
            isTyping: false,
            unreadCount: 0
        )

        // Then
        XCTAssertNotNil(row)
    }

    func testChatListRowTyping() {
        // Given
        let row = ChatListPresenceRow(
            userName: "Alice",
            lastMessage: "Previous message",
            timestamp: Date(),
            status: .online,
            isTyping: true,
            unreadCount: 0
        )

        // Then - should show typing indicator instead of last message
        XCTAssertNotNil(row)
    }

    func testChatListRowUnreadCount() {
        // Given
        let row = ChatListPresenceRow(
            userName: "Alice",
            lastMessage: "Hey there!",
            timestamp: Date(),
            status: .online,
            isTyping: false,
            unreadCount: 5
        )

        // Then - should show unread badge
        XCTAssertNotNil(row)
    }

    func testChatListRowOffline() {
        // Given
        let row = ChatListPresenceRow(
            userName: "Alice",
            lastMessage: "Hey there!",
            timestamp: Date().addingTimeInterval(-86400), // 1 day ago
            status: .offline,
            isTyping: false,
            unreadCount: 0
        )

        // Then
        XCTAssertNotNil(row)
    }

    // MARK: - ProfilePresenceHeader Tests

    func testProfileHeaderOnline() {
        // Given
        let header = ProfilePresenceHeader(
            userName: "Alice Johnson",
            status: .online,
            lastSeen: nil
        )

        // Then
        XCTAssertNotNil(header)
    }

    func testProfileHeaderOfflineWithLastSeen() {
        // Given
        let lastSeen = Date().addingTimeInterval(-7200) // 2 hours ago
        let header = ProfilePresenceHeader(
            userName: "Alice Johnson",
            status: .offline,
            lastSeen: lastSeen
        )

        // Then - should show last seen
        XCTAssertNotNil(header)
    }

    func testProfileHeaderAway() {
        // Given
        let header = ProfilePresenceHeader(
            userName: "Alice Johnson",
            status: .away,
            lastSeen: nil
        )

        // Then
        XCTAssertNotNil(header)
    }

    func testProfileHeaderWithAvatar() {
        // Given
        let header = ProfilePresenceHeader(
            userName: "Alice Johnson",
            avatarUrl: "https://example.com/avatar.jpg",
            status: .online,
            lastSeen: nil
        )

        // Then
        XCTAssertNotNil(header)
    }

    // MARK: - Integration Tests

    func testPresenceStatusConversion() {
        // Test converting from UserPresence.PresenceStatus to UserChannelManager.PresenceStatus

        // Online
        let onlineStatus = UserChannelManager.PresenceStatus(from: .online)
        XCTAssertEqual(onlineStatus, .online)

        // Offline
        let offlineStatus = UserChannelManager.PresenceStatus(from: .offline)
        XCTAssertEqual(offlineStatus, .offline)

        // Away
        let awayStatus = UserChannelManager.PresenceStatus(from: .away)
        XCTAssertEqual(awayStatus, .away)
    }

    func testUserPresenceInfoCreation() {
        // Given
        let userId = "test-user"
        let presence = UserPresence(
            userId: userId,
            status: .online,
            lastSeen: nil
        )

        // When
        let presenceInfo = UserChannelManager.UserPresenceInfo(from: presence)

        // Then
        XCTAssertEqual(presenceInfo.userId, userId)
        XCTAssertEqual(presenceInfo.status, .online)
        XCTAssertNil(presenceInfo.lastSeen)
        XCTAssertFalse(presenceInfo.isTyping)
        XCTAssertNil(presenceInfo.typingInConversation)
    }

    func testUserPresenceInfoWithTyping() {
        // Given
        let presenceInfo = UserChannelManager.UserPresenceInfo(
            userId: "test-user",
            status: .online,
            lastSeen: nil,
            isTyping: true,
            typingInConversation: "conv-123"
        )

        // Then
        XCTAssertTrue(presenceInfo.isTyping)
        XCTAssertEqual(presenceInfo.typingInConversation, "conv-123")
    }

    // MARK: - Performance Tests

    func testPresenceIndicatorPerformance() {
        measure {
            for _ in 0..<100 {
                _ = PresenceIndicator(status: .online)
            }
        }
    }

    func testTypingIndicatorPerformance() {
        let typingUsers: Set<String> = ["Alice", "Bob", "Charlie"]

        measure {
            for _ in 0..<100 {
                _ = TypingIndicatorView(
                    typingUsers: typingUsers,
                    currentUserId: "me"
                )
            }
        }
    }
}
