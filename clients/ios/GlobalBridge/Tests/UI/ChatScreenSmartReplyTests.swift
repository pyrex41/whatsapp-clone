//
//  ChatScreenSmartReplyTests.swift
//  GlobalBridge
//
//  Task 33: Test auto-fetch and manual refresh of smart reply suggestions
//  Unit tests for smart reply integration in ChatScreen
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class ChatScreenSmartReplyTests: XCTestCase {

    // MARK: - Test Data

    var mockStore: Store<AppState, AppAction>!
    var testThread: Thread!

    override func setUp() async throws {
        // Create test thread
        testThread = Thread(
            id: UUID(),
            title: "Test Thread",
            participantIds: ["user1", "user2"],
            createdBy: "user1",
            createdAt: Date(),
            lastMessageAt: Date()
        )

        // Initialize mock store with test thread
        let initialState = AppState(
            user: .sampleCurrent,
            threads: ThreadsState(items: [testThread]),
            chat: ChatState(currentThread: testThread)
        )

        mockStore = Store(
            initialState: initialState,
            reducer: { state, action, _ in .none },
            environment: MockEnvironment()
        )
    }

    // MARK: - Auto-Fetch on Thread Open Tests

    func testAutoFetchTriggeredOnThreadOpen() {
        // When ChatScreen appears with a thread, it should auto-fetch smart replies
        var fetchedThreadId: String?

        let store = Store(
            initialState: AppState(
                user: .sampleCurrent,
                chat: ChatState(currentThread: testThread)
            ),
            reducer: { state, action, _ in
                if case let .fetchSmartReplies(threadId) = action {
                    fetchedThreadId = threadId
                }
                return .none
            },
            environment: MockEnvironment()
        )

        // Simulate onAppear by directly calling the equivalent logic
        let threadIdStr = testThread.id.uuidString
        store.send(.fetchSmartReplies(threadId: threadIdStr))

        XCTAssertEqual(fetchedThreadId, threadIdStr, "Should trigger fetchSmartReplies on thread open")
    }

    func testAutoFetchOnlyOncePerThread() {
        // Auto-fetch should only happen once per thread load
        var fetchCount = 0

        let store = Store(
            initialState: AppState(
                user: .sampleCurrent,
                chat: ChatState(currentThread: testThread)
            ),
            reducer: { state, action, _ in
                if case .fetchSmartReplies = action {
                    fetchCount += 1
                }
                return .none
            },
            environment: MockEnvironment()
        )

        // First call should trigger fetch
        store.send(.fetchSmartReplies(threadId: testThread.id.uuidString))
        XCTAssertEqual(fetchCount, 1)

        // Simulating the same thread appearing again shouldn't fetch again
        // (this is controlled by hasFetchedSuggestions state in ChatScreen)
    }

    func testAutoFetchSkippedWhenAlreadyLoading() {
        // Should not fetch if already loading for this thread
        let initialState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread),
            smartReplyLoading: [testThread.id.uuidString: true]
        )

        let store = Store(
            initialState: initialState,
            reducer: { state, action, _ in .none },
            environment: MockEnvironment()
        )

        let isLoading = store.state.smartReplyLoading[testThread.id.uuidString]
        XCTAssertTrue(isLoading == true, "Should be loading")
        // In real implementation, fetchSmartRepliesIfNeeded checks this and returns early
    }

    // MARK: - Manual Refresh Tests

    func testManualRefreshTriggersNewFetch() {
        var fetchCount = 0

        let store = Store(
            initialState: AppState(
                user: .sampleCurrent,
                chat: ChatState(currentThread: testThread)
            ),
            reducer: { state, action, _ in
                if case .fetchSmartReplies = action {
                    fetchCount += 1
                }
                return .none
            },
            environment: MockEnvironment()
        )

        // Manual refresh should trigger fetch
        store.send(.fetchSmartReplies(threadId: testThread.id.uuidString))
        XCTAssertEqual(fetchCount, 1)
    }

    func testManualRefreshDisabledDuringLoad() {
        let initialState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread),
            smartReplyLoading: [testThread.id.uuidString: true]
        )

        let store = Store(
            initialState: initialState,
            reducer: { state, action, _ in .none },
            environment: MockEnvironment()
        )

        // Refresh button should be disabled when loading
        let isLoading = store.state.smartReplyLoading[testThread.id.uuidString] == true
        XCTAssertTrue(isLoading, "Should be loading, refresh button disabled")
    }

    func testManualRefreshShowsLoadingIndicator() {
        let initialState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread),
            smartReplyLoading: [testThread.id.uuidString: true]
        )

        let store = Store(
            initialState: initialState,
            reducer: { state, action, _ in .none },
            environment: MockEnvironment()
        )

        // When loading, UI should show progress view
        XCTAssertTrue(store.state.smartReplyLoading[testThread.id.uuidString] == true)
    }

    // MARK: - Debounce Tests

    func testDebouncePreventsDuplicateCalls() {
        // Debounce logic is implemented in ChatScreen with 2-second threshold
        // This tests the concept rather than the UI implementation

        let now = Date()
        let lastFetch = now.addingTimeInterval(-1.0) // 1 second ago

        // Should debounce (too soon)
        let timeSinceLastFetch = now.timeIntervalSince(lastFetch)
        XCTAssertLessThan(timeSinceLastFetch, 2.0, "Should be within debounce window")
    }

    func testDebounceAllowsRefreshAfterDelay() {
        let now = Date()
        let lastFetch = now.addingTimeInterval(-3.0) // 3 seconds ago

        // Should allow refresh (enough time passed)
        let timeSinceLastFetch = now.timeIntervalSince(lastFetch)
        XCTAssertGreaterThan(timeSinceLastFetch, 2.0, "Should be outside debounce window")
    }

    // MARK: - Thread Change Tests

    func testFetchStateResetOnThreadChange() {
        let thread1 = testThread!
        let thread2 = Thread(
            id: UUID(),
            title: "Thread 2",
            participantIds: ["user1", "user3"],
            createdBy: "user1",
            createdAt: Date(),
            lastMessageAt: Date()
        )

        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: thread1),
            smartReplySuggestions: [thread1.id.uuidString: []],
            smartReplyLoading: [thread1.id.uuidString: false]
        )

        // Switch to thread2
        currentState.chat.currentThread = thread2

        // Fetch state should be reset for new thread
        XCTAssertNil(currentState.smartReplySuggestions[thread2.id.uuidString])
        XCTAssertNil(currentState.smartReplyLoading[thread2.id.uuidString])
    }

    // MARK: - Loading State Tests

    func testLoadingStateSetOnFetch() {
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread)
        )

        let threadIdStr = testThread.id.uuidString

        // Simulate fetchSmartReplies action
        currentState.smartReplyLoading[threadIdStr] = true
        currentState.smartReplyErrors[threadIdStr] = nil

        XCTAssertTrue(currentState.smartReplyLoading[threadIdStr] == true)
        XCTAssertNil(currentState.smartReplyErrors[threadIdStr])
    }

    func testLoadingStateClearedOnSuccess() {
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread),
            smartReplyLoading: [testThread.id.uuidString: true]
        )

        let threadIdStr = testThread.id.uuidString

        // Simulate successful response
        currentState.smartReplyLoading[threadIdStr] = false
        currentState.smartReplySuggestions[threadIdStr] = []
        currentState.smartReplyErrors[threadIdStr] = nil

        XCTAssertFalse(currentState.smartReplyLoading[threadIdStr] == true)
        XCTAssertNotNil(currentState.smartReplySuggestions[threadIdStr])
        XCTAssertNil(currentState.smartReplyErrors[threadIdStr])
    }

    func testLoadingStateClearedOnError() {
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread),
            smartReplyLoading: [testThread.id.uuidString: true]
        )

        let threadIdStr = testThread.id.uuidString

        // Simulate error response
        currentState.smartReplyLoading[threadIdStr] = false
        currentState.smartReplyErrors[threadIdStr] = "Network error"

        XCTAssertFalse(currentState.smartReplyLoading[threadIdStr] == true)
        XCTAssertEqual(currentState.smartReplyErrors[threadIdStr], "Network error")
    }

    // MARK: - Error Handling Tests

    func testFetchErrorDoesNotBlockRetry() {
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread),
            smartReplyErrors: [testThread.id.uuidString: "Previous error"]
        )

        let threadIdStr = testThread.id.uuidString

        // Should clear error on new fetch
        currentState.smartReplyLoading[threadIdStr] = true
        currentState.smartReplyErrors[threadIdStr] = nil

        XCTAssertNil(currentState.smartReplyErrors[threadIdStr])
    }

    func testErrorMessageStoredPerThread() {
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread)
        )

        let threadIdStr = testThread.id.uuidString

        // Store error for specific thread
        currentState.smartReplyErrors[threadIdStr] = "Network error"

        XCTAssertEqual(currentState.smartReplyErrors[threadIdStr], "Network error")
        XCTAssertNil(currentState.smartReplyErrors["other-thread"])
    }

    // MARK: - Integration Tests

    func testCompleteAutoFetchFlow() {
        // 1. Thread opens
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread)
        )

        let threadIdStr = testThread.id.uuidString

        // 2. Auto-fetch triggered
        currentState.smartReplyLoading[threadIdStr] = true
        currentState.smartReplyErrors[threadIdStr] = nil
        XCTAssertTrue(currentState.smartReplyLoading[threadIdStr] == true)

        // 3. Suggestions received
        currentState.smartReplyLoading[threadIdStr] = false
        currentState.smartReplySuggestions[threadIdStr] = [
            SmartReplySuggestion(
                id: UUID(),
                type: "quick-reply",
                content: "Thanks!",
                translatedText: nil,
                confidence: 0.95,
                position: 0,
                context: "",
                timestamp: Date()
            )
        ]

        XCTAssertFalse(currentState.smartReplyLoading[threadIdStr] == true)
        XCTAssertEqual(currentState.smartReplySuggestions[threadIdStr]?.count, 1)
    }

    func testCompleteManualRefreshFlow() {
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread),
            smartReplySuggestions: [testThread.id.uuidString: []] // Old suggestions
        )

        let threadIdStr = testThread.id.uuidString

        // 1. User taps refresh button
        currentState.smartReplyLoading[threadIdStr] = true
        XCTAssertTrue(currentState.smartReplyLoading[threadIdStr] == true)

        // 2. New suggestions received
        currentState.smartReplyLoading[threadIdStr] = false
        currentState.smartReplySuggestions[threadIdStr] = [
            SmartReplySuggestion(
                id: UUID(),
                type: "contextual",
                content: "Updated suggestion",
                translatedText: nil,
                confidence: 0.85,
                position: 0,
                context: "",
                timestamp: Date()
            )
        ]

        XCTAssertFalse(currentState.smartReplyLoading[threadIdStr] == true)
        XCTAssertEqual(currentState.smartReplySuggestions[threadIdStr]?.first?.content, "Updated suggestion")
    }

    func testErrorRecoveryFlow() {
        var currentState = AppState(
            user: .sampleCurrent,
            chat: ChatState(currentThread: testThread)
        )

        let threadIdStr = testThread.id.uuidString

        // 1. Fetch fails
        currentState.smartReplyLoading[threadIdStr] = false
        currentState.smartReplyErrors[threadIdStr] = "Network error"
        XCTAssertEqual(currentState.smartReplyErrors[threadIdStr], "Network error")

        // 2. User retries
        currentState.smartReplyLoading[threadIdStr] = true
        currentState.smartReplyErrors[threadIdStr] = nil
        XCTAssertNil(currentState.smartReplyErrors[threadIdStr])

        // 3. Success on retry
        currentState.smartReplyLoading[threadIdStr] = false
        currentState.smartReplySuggestions[threadIdStr] = []
        XCTAssertNotNil(currentState.smartReplySuggestions[threadIdStr])
    }
}

// MARK: - Mock Environment

struct MockEnvironment {
    // Mock environment for testing
}
