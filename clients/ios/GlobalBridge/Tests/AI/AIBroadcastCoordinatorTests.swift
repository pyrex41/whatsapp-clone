//
//  AIBroadcastCoordinatorTests.swift
//  GlobalBridge
//
//  Task 34.5: Test AIBroadcastCoordinator with simulated proactive suggestions
//  Unit tests for proactive suggestion handling and AppState updates
//

import XCTest
@testable import GlobalBridge

@MainActor
final class AIBroadcastCoordinatorTests: XCTestCase {

    var coordinator: AIBroadcastCoordinator!
    var mockStore: MockStore!
    var mockPhoenixManager: MockPhoenixChannelManager!

    override func setUp() async throws {
        coordinator = AIBroadcastCoordinator.shared
        mockStore = MockStore(initialState: AppState())
        mockPhoenixManager = MockPhoenixChannelManager()

        // Start coordinator with mock dependencies
        coordinator.start(with: mockStore, phoenixManager: mockPhoenixManager)
    }

    override func tearDown() async throws {
        coordinator.stop()
        coordinator = nil
        mockStore = nil
        mockPhoenixManager = nil
    }

    // MARK: - Proactive Suggestion Tests

    func testProactiveSuggestionNotificationHandling() async throws {
        // Given
        let testThreadId = "test-thread-123"
        let testSuggestion = SmartReplySuggestion(
            id: UUID(),
            type: "proactive",
            content: "Hey, how are you?",
            confidence: 0.92,
            position: 0,
            context: "proactive suggestion test",
            timestamp: Date()
        )

        // When
        NotificationCenter.default.post(
            name: NSNotification.Name("AIProactiveSuggestion"),
            object: nil,
            userInfo: [
                "threadId": testThreadId,
                "suggestion": testSuggestion
            ]
        )

        // Give time for async notification handling
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then
        XCTAssertEqual(mockStore.dispatchedActions.count, 1, "Should dispatch one action")

        guard case let .aiSuggestionBroadcast(threadId, suggestion) = mockStore.dispatchedActions.first else {
            XCTFail("Expected aiSuggestionBroadcast action")
            return
        }

        XCTAssertEqual(threadId, testThreadId)
        XCTAssertEqual(suggestion.id, testSuggestion.id)
        XCTAssertEqual(suggestion.content, "Hey, how are you?")
        XCTAssertEqual(suggestion.type, "proactive")
        XCTAssertEqual(suggestion.confidence, 0.92)
    }

    func testDebugSimulateProactiveSuggestion() async throws {
        // Given
        let testThreadId = "debug-test-thread-456"

        // When
        #if DEBUG
        coordinator.simulateProactiveSuggestion(threadId: testThreadId)
        #endif

        // Give time for async notification handling
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then
        XCTAssertEqual(mockStore.dispatchedActions.count, 1, "Should dispatch one action from DEBUG simulation")

        guard case let .aiSuggestionBroadcast(threadId, suggestion) = mockStore.dispatchedActions.first else {
            XCTFail("Expected aiSuggestionBroadcast action from DEBUG simulation")
            return
        }

        XCTAssertEqual(threadId, testThreadId)
        XCTAssertEqual(suggestion.type, "proactive")
        XCTAssertEqual(suggestion.content, "This is a test AI suggestion from DEBUG menu")
        XCTAssertEqual(suggestion.confidence, 0.95)
    }

    func testAppStateUpdateAfterProactiveSuggestion() async throws {
        // Given
        let testThreadId = "state-test-thread-789"
        let testSuggestion = SmartReplySuggestion(
            id: UUID(),
            type: "proactive",
            content: "Sounds great!",
            confidence: 0.88,
            position: 0,
            context: "state update test",
            timestamp: Date()
        )

        // When
        NotificationCenter.default.post(
            name: NSNotification.Name("AIProactiveSuggestion"),
            object: nil,
            userInfo: [
                "threadId": testThreadId,
                "suggestion": testSuggestion
            ]
        )

        // Give time for async notification handling
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Process the dispatched action through the store's reducer
        if let action = mockStore.dispatchedActions.first {
            mockStore.state = appReducer(state: mockStore.state, action: action)
        }

        // Then
        let suggestions = mockStore.state.smartReplySuggestions[testThreadId]
        XCTAssertNotNil(suggestions, "AppState should have suggestions for thread")
        XCTAssertEqual(suggestions?.count, 1, "Should have one suggestion")
        XCTAssertEqual(suggestions?.first?.content, "Sounds great!")
        XCTAssertEqual(suggestions?.first?.type, "proactive")
    }

    func testMultipleProactiveSuggestions() async throws {
        // Given
        let testThreadId = "multi-test-thread"
        let suggestions = [
            SmartReplySuggestion(id: UUID(), type: "proactive", content: "Yes!", confidence: 0.9, position: 0, context: "test", timestamp: Date()),
            SmartReplySuggestion(id: UUID(), type: "proactive", content: "No thanks", confidence: 0.85, position: 1, context: "test", timestamp: Date()),
            SmartReplySuggestion(id: UUID(), type: "proactive", content: "Maybe later", confidence: 0.8, position: 2, context: "test", timestamp: Date())
        ]

        // When
        for suggestion in suggestions {
            NotificationCenter.default.post(
                name: NSNotification.Name("AIProactiveSuggestion"),
                object: nil,
                userInfo: [
                    "threadId": testThreadId,
                    "suggestion": suggestion
                ]
            )
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds between each
        }

        // Then
        XCTAssertEqual(mockStore.dispatchedActions.count, 3, "Should dispatch three actions")
    }
}

// MARK: - Mock Store

@MainActor
class MockStore: Store<AppState, AppAction> {
    var dispatchedActions: [AppAction] = []

    init(initialState: AppState) {
        super.init(
            initialState: initialState,
            reducer: appReducer,
            middlewares: []
        )
    }

    override func send(_ action: AppAction) {
        dispatchedActions.append(action)
        super.send(action)
    }
}

// MARK: - Mock Phoenix Manager

@MainActor
class MockPhoenixChannelManager: PhoenixChannelManager {
    var subscriptionCalls: [(threadId: String, callback: (SmartReplySuggestion) -> Void)] = []
    var unsubscriptionCalls: [String] = []

    override func subscribeToAISuggestions(
        threadId: String,
        onSuggestion: @escaping (SmartReplySuggestion) -> Void
    ) async throws {
        subscriptionCalls.append((threadId, onSuggestion))
    }

    override func unsubscribeFromAISuggestions(threadId: String) async {
        unsubscriptionCalls.append(threadId)
    }
}
