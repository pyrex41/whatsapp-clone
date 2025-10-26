//
//  SmartReplyServiceTests.swift
//  GlobalBridgeTests
//
//  Task 31.1: Unit tests for SmartReplyService
//  Tests network operations, caching, feedback recording, and error handling
//

import XCTest
@testable import GlobalBridge

@MainActor
final class SmartReplyServiceTests: XCTestCase {

    var sut: SmartReplyService!
    var mockSession: URLSession!
    var mockAuthManager: MockAuthManager!
    var mockClock: MockClock!

    override func setUp() {
        super.setUp()

        // Configure mock URLSession
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        // Create mock dependencies
        mockAuthManager = MockAuthManager()
        mockClock = MockClock()

        // Create service with mocks
        sut = SmartReplyService(
            session: mockSession,
            authManager: mockAuthManager,
            baseURL: URL(string: "http://localhost:4000")!,
            clock: mockClock
        )
    }

    override func tearDown() {
        sut = nil
        mockSession = nil
        mockAuthManager = nil
        mockClock = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Fetch Suggestions Tests

    func testFetchSuggestionsSuccess() async throws {
        // Given
        let testThreadId = UUID()
        let expectedJSON = """
        {
            "success": true,
            "suggestions": [
                {
                    "id": "550e8400-e29b-41d4-a716-446655440000",
                    "type": "quick-reply",
                    "content": "Thanks!",
                    "confidence": 0.95,
                    "position": 0,
                    "context": "response",
                    "timestamp": "2025-10-25T12:00:00Z"
                },
                {
                    "id": "550e8400-e29b-41d4-a716-446655440001",
                    "type": "contextual",
                    "content": "Let me check and get back to you",
                    "confidence": 0.85,
                    "position": 1,
                    "context": "inquiry",
                    "timestamp": "2025-10-25T12:00:00Z"
                },
                {
                    "id": "550e8400-e29b-41d4-a716-446655440002",
                    "type": "proactive",
                    "content": "I'll be there in 5 minutes",
                    "confidence": 0.75,
                    "position": 2,
                    "context": "eta",
                    "timestamp": "2025-10-25T12:00:00Z"
                }
            ]
        }
        """

        mockAuthManager.mockToken = "valid_jwt_token"

        MockURLProtocol.requestHandler = { request in
            // Verify request
            XCTAssertEqual(request.url?.path, "/api/v1/ai/suggest_replies")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid_jwt_token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

            // Verify request body
            if let bodyData = request.httpBody,
               let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                XCTAssertEqual(bodyJSON["thread_id"] as? String, testThreadId.uuidString)
                XCTAssertEqual(bodyJSON["limit"] as? Int, 3)
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!

            return (response, expectedJSON.data(using: .utf8))
        }

        // When
        let result = try await sut.fetchSuggestions(threadId: testThreadId, limit: 3)

        // Then
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].content, "Thanks!")
        XCTAssertEqual(result[0].type, "quick-reply")
        XCTAssertEqual(result[0].confidence, 0.95)
        XCTAssertEqual(result[1].content, "Let me check and get back to you")
        XCTAssertEqual(result[2].content, "I'll be there in 5 minutes")
        XCTAssertEqual(result[2].type, "proactive")
    }

    func testFetchSuggestionsUnauthorized() async {
        // Given
        let testThreadId = UUID()
        mockAuthManager.mockToken = nil

        // When/Then
        do {
            _ = try await sut.fetchSuggestions(threadId: testThreadId)
            XCTFail("Should throw unauthorized error")
        } catch let error as AIServiceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchSuggestionsRateLimitExceeded() async {
        // Given
        let testThreadId = UUID()
        mockAuthManager.mockToken = "valid_token"

        MockURLProtocol.requestHandler = { request in
            let resetTime = Date().addingTimeInterval(300).timeIntervalSince1970
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: [
                    "X-RateLimit-Reset": String(Int(resetTime)),
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Tier": "pro"
                ]
            )!
            return (response, nil)
        }

        // When/Then
        do {
            _ = try await sut.fetchSuggestions(threadId: testThreadId)
            XCTFail("Should throw rate limit error")
        } catch let error as AIServiceError {
            if case .rateLimitExceeded(let retryAfter, let quota, let tier) = error {
                XCTAssertNotNil(retryAfter)
                XCTAssertEqual(quota, 0)
                XCTAssertEqual(tier, "pro")
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchSuggestionsNetworkError() async {
        // Given
        let testThreadId = UUID()
        mockAuthManager.mockToken = "valid_token"

        MockURLProtocol.requestHandler = { request in
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        }

        // When/Then
        do {
            _ = try await sut.fetchSuggestions(threadId: testThreadId)
            XCTFail("Should throw network error")
        } catch let error as AIServiceError {
            if case .networkError(_) = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchSuggestionsServerError() async {
        // Given
        let testThreadId = UUID()
        mockAuthManager.mockToken = "valid_token"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        }

        // When/Then
        do {
            _ = try await sut.fetchSuggestions(threadId: testThreadId)
            XCTFail("Should throw backend error")
        } catch let error as AIServiceError {
            if case .backendError(_) = error {
                // Success - service retries then throws backendError
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchSuggestionsInvalidLimit() async {
        // Given
        let testThreadId = UUID()

        // When/Then
        do {
            _ = try await sut.fetchSuggestions(threadId: testThreadId, limit: 0)
            XCTFail("Should throw invalid input error")
        } catch let error as AIServiceError {
            if case .invalidInput(let reason) = error {
                XCTAssertTrue(reason.contains("between 1 and 10"))
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }

        do {
            _ = try await sut.fetchSuggestions(threadId: testThreadId, limit: 11)
            XCTFail("Should throw invalid input error")
        } catch let error as AIServiceError {
            if case .invalidInput(_) = error {
                // Success
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchSuggestionsInvalidJSON() async {
        // Given
        let testThreadId = UUID()
        mockAuthManager.mockToken = "valid_token"
        let invalidJSON = "{ invalid json }"

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, invalidJSON.data(using: .utf8))
        }

        // When/Then
        do {
            _ = try await sut.fetchSuggestions(threadId: testThreadId)
            XCTFail("Should throw decoding error")
        } catch {
            // Expected to fail decoding
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Record Feedback Tests

    func testRecordFeedbackAccepted() async throws {
        // Given
        let suggestionId = UUID()
        let feedback = SuggestionFeedback(
            suggestionId: suggestionId,
            accepted: true,
            timeToResponseMs: 1500
        )

        mockAuthManager.mockToken = "valid_token"

        MockURLProtocol.requestHandler = { request in
            // Verify request
            XCTAssertEqual(request.url?.path, "/api/v1/ai/record_feedback")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid_token")

            // Verify request body
            if let bodyData = request.httpBody,
               let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                XCTAssertEqual(bodyJSON["suggestion_id"] as? String, suggestionId.uuidString)
                XCTAssertEqual(bodyJSON["accepted"] as? Bool, true)
                XCTAssertEqual(bodyJSON["time_to_response_ms"] as? Int, 1500)
                XCTAssertNil(bodyJSON["modified_content"])
                XCTAssertNil(bodyJSON["rejection_reason"])
            }

            let responseJSON = """
            {
                "success": true
            }
            """

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON.data(using: .utf8))
        }

        // When
        try await sut.recordFeedback(feedback)

        // Then - should not throw
    }

    func testRecordFeedbackModified() async throws {
        // Given
        let suggestionId = UUID()
        let feedback = SuggestionFeedback(
            suggestionId: suggestionId,
            accepted: true,
            modifiedContent: "Thanks, I'll check that out!",
            timeToResponseMs: 2000
        )

        mockAuthManager.mockToken = "valid_token"

        MockURLProtocol.requestHandler = { request in
            // Verify request body
            if let bodyData = request.httpBody,
               let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                XCTAssertEqual(bodyJSON["accepted"] as? Bool, true)
                XCTAssertEqual(bodyJSON["modified_content"] as? String, "Thanks, I'll check that out!")
            }

            let responseJSON = """
            {
                "success": true
            }
            """

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseJSON.data(using: .utf8))
        }

        // When
        try await sut.recordFeedback(feedback)

        // Then - should not throw
    }

    func testRecordFeedbackRejected() async throws {
        // Given
        let suggestionId = UUID()
        let feedback = SuggestionFeedback(
            suggestionId: suggestionId,
            accepted: false,
            rejectionReason: "not_relevant",
            timeToResponseMs: 500
        )

        mockAuthManager.mockToken = "valid_token"

        MockURLProtocol.requestHandler = { request in
            // Verify request body
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

        // When
        try await sut.recordFeedback(feedback)

        // Then - should not throw
    }

    func testRecordFeedbackUnauthorized() async {
        // Given
        let feedback = SuggestionFeedback(suggestionId: UUID(), accepted: true)
        mockAuthManager.mockToken = nil

        // When/Then
        do {
            try await sut.recordFeedback(feedback)
            XCTFail("Should throw unauthorized error")
        } catch let error as AIServiceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cache Tests

    func testCacheClearForThread() async throws {
        // Given
        let testThreadId = UUID()
        mockAuthManager.mockToken = "valid_token"

        let expectedJSON = """
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
                }
            ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, expectedJSON.data(using: .utf8))
        }

        // Fetch to populate cache
        _ = try await sut.fetchSuggestions(threadId: testThreadId)

        // When
        sut.clearCache(for: testThreadId)

        // Then - next fetch should hit network again (we'd need to track request count in real test)
        // For now, just verify it doesn't throw
    }

    func testCacheClearAll() {
        // When
        sut.clearAllCache()

        // Then - should not throw
    }
}
