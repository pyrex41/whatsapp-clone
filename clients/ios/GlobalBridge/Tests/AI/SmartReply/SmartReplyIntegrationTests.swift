//
//  SmartReplyIntegrationTests.swift
//  GlobalBridgeTests
//
//  Task 31.1: Integration tests for SmartReplyService
//  Tests caching TTL, feedback recording flow, and complete E2E scenarios
//

import XCTest
@testable import GlobalBridge

@MainActor
final class SmartReplyIntegrationTests: XCTestCase {

    var sut: SmartReplyService!
    var mockSession: URLSession!
    var mockAuthManager: MockAuthManager!
    var mockClock: MockClock!
    var networkCallCount: Int = 0

    override func setUp() {
        super.setUp()

        // Configure mock URLSession
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        // Create mock dependencies
        mockAuthManager = MockAuthManager()
        mockAuthManager.mockToken = "valid_token"

        mockClock = MockClock(startTime: Date(timeIntervalSince1970: 1000000))

        // Create service with mocks
        sut = SmartReplyService(
            session: mockSession,
            authManager: mockAuthManager,
            baseURL: URL(string: "http://localhost:4000")!,
            clock: mockClock
        )

        networkCallCount = 0
    }

    override func tearDown() {
        sut = nil
        mockSession = nil
        mockAuthManager = nil
        mockClock = nil
        networkCallCount = 0
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Cache TTL Tests

    func testCachingFirstCallHitsNetwork() async throws {
        // Given
        let testThreadId = UUID()
        setupSuccessfulSuggestionResponse()

        // When
        let result = try await sut.fetchSuggestions(threadId: testThreadId)

        // Then
        XCTAssertEqual(networkCallCount, 1, "First call should hit network")
        XCTAssertEqual(result.count, 3)
    }

    func testCachingSecondCallWithin60sUsesCache() async throws {
        // Given
        let testThreadId = UUID()
        setupSuccessfulSuggestionResponse()

        // First call
        let firstResult = try await sut.fetchSuggestions(threadId: testThreadId)
        XCTAssertEqual(networkCallCount, 1)

        // Advance clock by 30 seconds (within TTL)
        mockClock.advance(by: 30)

        // When - second call
        let secondResult = try await sut.fetchSuggestions(threadId: testThreadId)

        // Then
        XCTAssertEqual(networkCallCount, 1, "Second call within 60s should use cache, no additional network call")
        XCTAssertEqual(secondResult.count, 3)
        XCTAssertEqual(firstResult[0].id, secondResult[0].id, "Should return same cached data")
    }

    func testCachingAfter60sHitsNetworkAgain() async throws {
        // Given
        let testThreadId = UUID()
        setupSuccessfulSuggestionResponse()

        // First call
        _ = try await sut.fetchSuggestions(threadId: testThreadId)
        XCTAssertEqual(networkCallCount, 1)

        // Advance clock by 61 seconds (past TTL)
        mockClock.advance(by: 61)

        // When - second call after TTL expired
        _ = try await sut.fetchSuggestions(threadId: testThreadId)

        // Then
        XCTAssertEqual(networkCallCount, 2, "Call after 60s should hit network again")
    }

    func testCachingExactly60sUsesCache() async throws {
        // Given
        let testThreadId = UUID()
        setupSuccessfulSuggestionResponse()

        // First call
        _ = try await sut.fetchSuggestions(threadId: testThreadId)
        XCTAssertEqual(networkCallCount, 1)

        // Advance clock by exactly 60 seconds (at TTL boundary)
        mockClock.advance(by: 60)

        // When - second call at exactly 60s
        _ = try await sut.fetchSuggestions(threadId: testThreadId)

        // Then - cache should still be valid (< TTL, not <=)
        XCTAssertEqual(networkCallCount, 1, "Call at exactly 60s should still use cache (boundary condition)")
    }

    func testCachingDifferentThreadsIndependent() async throws {
        // Given
        let thread1 = UUID()
        let thread2 = UUID()
        setupSuccessfulSuggestionResponse()

        // When
        _ = try await sut.fetchSuggestions(threadId: thread1)
        XCTAssertEqual(networkCallCount, 1)

        _ = try await sut.fetchSuggestions(threadId: thread2)

        // Then
        XCTAssertEqual(networkCallCount, 2, "Different threads should have independent caches")
    }

    func testCachingClearForThreadInvalidatesCache() async throws {
        // Given
        let testThreadId = UUID()
        setupSuccessfulSuggestionResponse()

        // First call
        _ = try await sut.fetchSuggestions(threadId: testThreadId)
        XCTAssertEqual(networkCallCount, 1)

        // Clear cache for this thread
        sut.clearCache(for: testThreadId)

        // When - fetch again immediately
        _ = try await sut.fetchSuggestions(threadId: testThreadId)

        // Then
        XCTAssertEqual(networkCallCount, 2, "After cache clear, should hit network again")
    }

    func testCachingClearAllInvalidatesAllCaches() async throws {
        // Given
        let thread1 = UUID()
        let thread2 = UUID()
        setupSuccessfulSuggestionResponse()

        _ = try await sut.fetchSuggestions(threadId: thread1)
        _ = try await sut.fetchSuggestions(threadId: thread2)
        XCTAssertEqual(networkCallCount, 2)

        // Clear all caches
        sut.clearAllCache()

        // When - fetch both again
        _ = try await sut.fetchSuggestions(threadId: thread1)
        _ = try await sut.fetchSuggestions(threadId: thread2)

        // Then
        XCTAssertEqual(networkCallCount, 4, "After clearAllCache, both threads should hit network")
    }

    // MARK: - Complete Feedback Flow Tests

    func testCompleteFeedbackFlowAccepted() async throws {
        // Given
        let testThreadId = UUID()
        let suggestionId = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        setupSuccessfulSuggestionResponse()

        // Fetch suggestions
        let suggestions = try await sut.fetchSuggestions(threadId: testThreadId)
        XCTAssertEqual(suggestions[0].id, suggestionId)

        // Setup feedback response
        MockURLProtocol.requestHandler = { [weak self] request in
            if request.url?.path == "/api/v1/ai/record_feedback" {
                self?.networkCallCount += 1

                // Verify feedback payload
                if let bodyData = request.httpBody,
                   let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    XCTAssertEqual(bodyJSON["suggestion_id"] as? String, suggestionId.uuidString)
                    XCTAssertEqual(bodyJSON["accepted"] as? Bool, true)
                    XCTAssertNil(bodyJSON["modified_content"])
                }

                let responseJSON = """
                {
                    "success": true
                }
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, responseJSON.data(using: .utf8))
            }
            throw NSError(domain: "TestError", code: -1, userInfo: nil)
        }

        // When - record feedback
        let feedback = SuggestionFeedback(suggestionId: suggestionId, accepted: true, timeToResponseMs: 1500)
        try await sut.recordFeedback(feedback)

        // Then
        XCTAssertEqual(networkCallCount, 2, "One fetch + one feedback = 2 network calls")
    }

    func testCompleteFeedbackFlowModified() async throws {
        // Given
        let testThreadId = UUID()
        let suggestionId = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        setupSuccessfulSuggestionResponse()
        let suggestions = try await sut.fetchSuggestions(threadId: testThreadId)

        // Setup feedback response
        MockURLProtocol.requestHandler = { [weak self] request in
            if request.url?.path == "/api/v1/ai/record_feedback" {
                self?.networkCallCount += 1

                // Verify modified content is present
                if let bodyData = request.httpBody,
                   let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    XCTAssertEqual(bodyJSON["accepted"] as? Bool, true)
                    XCTAssertEqual(bodyJSON["modified_content"] as? String, "Thanks, I'll check it out!")
                }

                let responseJSON = """
                {
                    "success": true
                }
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, responseJSON.data(using: .utf8))
            }
            throw NSError(domain: "TestError", code: -1, userInfo: nil)
        }

        // When - record modified feedback
        let feedback = SuggestionFeedback(
            suggestionId: suggestionId,
            accepted: true,
            modifiedContent: "Thanks, I'll check it out!",
            timeToResponseMs: 2000
        )
        try await sut.recordFeedback(feedback)

        // Then - should succeed
        XCTAssertEqual(networkCallCount, 2)
    }

    func testCompleteFeedbackFlowRejected() async throws {
        // Given
        let testThreadId = UUID()
        let suggestionId = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

        setupSuccessfulSuggestionResponse()
        let suggestions = try await sut.fetchSuggestions(threadId: testThreadId)

        // Setup feedback response
        MockURLProtocol.requestHandler = { [weak self] request in
            if request.url?.path == "/api/v1/ai/record_feedback" {
                self?.networkCallCount += 1

                // Verify rejection reason is present
                if let bodyData = request.httpBody,
                   let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    XCTAssertEqual(bodyJSON["accepted"] as? Bool, false)
                    XCTAssertEqual(bodyJSON["rejection_reason"] as? String, "not_relevant")
                }

                let responseJSON = """
                {
                    "success": true
                }
                """
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, responseJSON.data(using: .utf8))
            }
            throw NSError(domain: "TestError", code: -1, userInfo: nil)
        }

        // When - record rejected feedback
        let feedback = SuggestionFeedback(
            suggestionId: suggestionId,
            accepted: false,
            rejectionReason: "not_relevant",
            timeToResponseMs: 500
        )
        try await sut.recordFeedback(feedback)

        // Then - should succeed
        XCTAssertEqual(networkCallCount, 2)
    }

    // MARK: - Helper Methods

    private func setupSuccessfulSuggestionResponse() {
        MockURLProtocol.requestHandler = { [weak self] request in
            if request.url?.path == "/api/v1/ai/suggest_replies" {
                self?.networkCallCount += 1

                let responseJSON = """
                {
                    "success": true,
                    "suggestions": [
                        {
                            "id": "550e8400-e29b-41d4-a716-446655440000",
                            "type": "quick-reply",
                            "content": "Thanks!",
                            "confidence": 0.95,
                            "position": 0,
                            "context": "",
                            "timestamp": "2025-10-25T12:00:00Z"
                        },
                        {
                            "id": "550e8400-e29b-41d4-a716-446655440001",
                            "type": "contextual",
                            "content": "Let me check",
                            "confidence": 0.85,
                            "position": 1,
                            "context": "",
                            "timestamp": "2025-10-25T12:00:00Z"
                        },
                        {
                            "id": "550e8400-e29b-41d4-a716-446655440002",
                            "type": "proactive",
                            "content": "I'll be there",
                            "confidence": 0.75,
                            "position": 2,
                            "context": "",
                            "timestamp": "2025-10-25T12:00:00Z"
                        }
                    ]
                }
                """

                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, responseJSON.data(using: .utf8))
            }

            throw NSError(domain: "TestError", code: -1, userInfo: nil)
        }
    }
}
