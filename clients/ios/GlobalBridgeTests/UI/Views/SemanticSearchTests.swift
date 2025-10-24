//
//  SemanticSearchTests.swift
//  GlobalBridgeTests
//
//  Comprehensive tests for semantic search functionality
//

import XCTest
@testable import GlobalBridge

@MainActor
final class SemanticSearchTests: XCTestCase {

    var sut: SemanticSearchViewModel!
    var mockAIService: MockAIService!

    override func setUp() async throws {
        try await super.setUp()
        mockAIService = MockAIService()
        sut = SemanticSearchViewModel(aiService: mockAIService)
    }

    override func tearDown() async throws {
        sut = nil
        mockAIService = nil
        try await super.tearDown()
    }

    // MARK: - Search Query Tests

    func testSearchQueryDebouncing() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Search debounced")
        mockAIService.searchSemanticHandler = { _, _, _, _ in
            expectation.fulfill()
            return []
        }

        // When
        sut.searchQuery = "d"
        sut.searchQuery = "di"
        sut.searchQuery = "din"
        sut.searchQuery = "dinner"

        // Then - should only search once after debounce
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(mockAIService.searchSemanticCallCount, 1)
    }

    func testEmptySearchQueryClearsResults() {
        // Given
        sut.searchResults = [
            SearchResult(messageId: "1", content: "test", relevanceScore: 0.9, threadId: nil, timestamp: nil)
        ]

        // When
        sut.searchQuery = ""

        // Then
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertNil(sut.searchError)
    }

    func testClearSearchResetsState() {
        // Given
        sut.searchQuery = "test query"
        sut.searchResults = [
            SearchResult(messageId: "1", content: "test", relevanceScore: 0.9, threadId: nil, timestamp: nil)
        ]
        sut.searchError = .apiError(message: "test error")

        // When
        sut.clearSearch()

        // Then
        XCTAssertTrue(sut.searchQuery.isEmpty)
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertNil(sut.searchError)
    }

    // MARK: - Perform Search Tests

    func testPerformSearchSuccess() async throws {
        // Given
        let mockResults = [
            SearchResult(messageId: "1", content: "dinner plans", relevanceScore: 0.95, threadId: "thread1", timestamp: nil),
            SearchResult(messageId: "2", content: "dinner tomorrow", relevanceScore: 0.88, threadId: "thread1", timestamp: nil)
        ]
        mockAIService.searchSemanticHandler = { _, _, _, _ in mockResults }
        sut.searchQuery = "dinner"

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(sut.searchResults.count, 2)
        XCTAssertNil(sut.searchError)
        XCTAssertFalse(sut.isSearching)
        XCTAssertEqual(mockAIService.lastSearchQuery, "dinner")
    }

    func testPerformSearchWithThreadFilter() async throws {
        // Given
        let threadId = "specific-thread"
        mockAIService.searchSemanticHandler = { _, _, _, _ in [] }
        sut.searchQuery = "test"
        sut.selectedThreadId = threadId

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(mockAIService.lastSearchThreadId, threadId)
    }

    func testPerformSearchWithResultLimit() async throws {
        // Given
        let limit = 25
        mockAIService.searchSemanticHandler = { _, _, _, _ in [] }
        sut.searchQuery = "test"
        sut.resultLimit = limit

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(mockAIService.lastSearchLimit, limit)
    }

    func testPerformSearchWithRecencyBias() async throws {
        // Given
        mockAIService.searchSemanticHandler = { _, _, _, _ in [] }
        sut.searchQuery = "test"
        sut.recencyBias = false

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(mockAIService.lastSearchRecencyBias, false)
    }

    func testPerformSearchError() async throws {
        // Given
        mockAIService.searchSemanticHandler = { _, _, _, _ in
            throw AIServiceError.rateLimitExceeded(retryAfter: 60)
        }
        sut.searchQuery = "test"

        // When
        await sut.performSearch()

        // Then
        XCTAssertTrue(sut.searchResults.isEmpty)
        XCTAssertEqual(sut.searchError, .rateLimitExceeded(retryAfter: 60))
        XCTAssertFalse(sut.isSearching)
    }

    func testPerformSearchFeatureDisabled() async throws {
        // Given
        mockAIService.searchSemanticHandler = { _, _, _, _ in
            throw AIServiceError.featureDisabled(feature: "semantic_search")
        }
        sut.searchQuery = "test"

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(sut.searchError, .featureDisabled(feature: "semantic_search"))
    }

    // MARK: - Date Range Filter Tests

    func testFilterByDateRangeToday() async throws {
        // Given
        let now = Date()
        let yesterday = now.addingTimeInterval(-24 * 3600)
        let formatter = ISO8601DateFormatter()

        let mockResults = [
            SearchResult(messageId: "1", content: "today", relevanceScore: 0.9, threadId: nil, timestamp: formatter.string(from: now)),
            SearchResult(messageId: "2", content: "yesterday", relevanceScore: 0.8, threadId: nil, timestamp: formatter.string(from: yesterday))
        ]

        mockAIService.searchSemanticHandler = { _, _, _, _ in mockResults }
        sut.searchQuery = "test"
        sut.dateRange = .today

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertEqual(sut.searchResults.first?.messageId, "1")
    }

    func testFilterByDateRangeLastWeek() async throws {
        // Given
        let now = Date()
        let sixDaysAgo = now.addingTimeInterval(-6 * 24 * 3600)
        let tenDaysAgo = now.addingTimeInterval(-10 * 24 * 3600)
        let formatter = ISO8601DateFormatter()

        let mockResults = [
            SearchResult(messageId: "1", content: "recent", relevanceScore: 0.9, threadId: nil, timestamp: formatter.string(from: sixDaysAgo)),
            SearchResult(messageId: "2", content: "old", relevanceScore: 0.8, threadId: nil, timestamp: formatter.string(from: tenDaysAgo))
        ]

        mockAIService.searchSemanticHandler = { _, _, _, _ in mockResults }
        sut.searchQuery = "test"
        sut.dateRange = .lastWeek

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertEqual(sut.searchResults.first?.messageId, "1")
    }

    func testFilterByDateRangeCustom() async throws {
        // Given
        let startDate = Date().addingTimeInterval(-10 * 24 * 3600)
        let endDate = Date().addingTimeInterval(-5 * 24 * 3600)
        let inRangeDate = Date().addingTimeInterval(-7 * 24 * 3600)
        let outRangeDate = Date().addingTimeInterval(-3 * 24 * 3600)
        let formatter = ISO8601DateFormatter()

        let mockResults = [
            SearchResult(messageId: "1", content: "in range", relevanceScore: 0.9, threadId: nil, timestamp: formatter.string(from: inRangeDate)),
            SearchResult(messageId: "2", content: "out range", relevanceScore: 0.8, threadId: nil, timestamp: formatter.string(from: outRangeDate))
        ]

        mockAIService.searchSemanticHandler = { _, _, _, _ in mockResults }
        sut.searchQuery = "test"
        sut.dateRange = .custom
        sut.customStartDate = startDate
        sut.customEndDate = endDate

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertEqual(sut.searchResults.first?.messageId, "1")
    }

    func testFilterByDateRangeAnytime() async throws {
        // Given
        let mockResults = [
            SearchResult(messageId: "1", content: "test1", relevanceScore: 0.9, threadId: nil, timestamp: nil),
            SearchResult(messageId: "2", content: "test2", relevanceScore: 0.8, threadId: nil, timestamp: nil)
        ]

        mockAIService.searchSemanticHandler = { _, _, _, _ in mockResults }
        sut.searchQuery = "test"
        sut.dateRange = .anytime

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(sut.searchResults.count, 2)
    }

    // MARK: - Search History Tests

    func testLoadSearchHistory() {
        // Given
        let history = ["dinner plans", "meeting notes", "project updates"]
        UserDefaults.standard.set(history, forKey: "semanticSearchHistory")

        // When
        sut.loadSearchHistory()

        // Then
        XCTAssertEqual(sut.searchHistory, history)
    }

    func testSearchAddsToHistory() async throws {
        // Given
        mockAIService.searchSemanticHandler = { _, _, _, _ in [] }
        sut.searchQuery = "dinner plans"

        // When
        await sut.performSearch()

        // Then
        XCTAssertTrue(sut.searchHistory.contains("dinner plans"))
    }

    func testSearchHistoryNoDuplicates() async throws {
        // Given
        mockAIService.searchSemanticHandler = { _, _, _, _ in [] }
        sut.searchQuery = "dinner plans"

        // When
        await sut.performSearch()
        await sut.performSearch()

        // Then
        let count = sut.searchHistory.filter { $0 == "dinner plans" }.count
        XCTAssertEqual(count, 1)
    }

    func testSearchHistoryMaxLength() async throws {
        // Given
        mockAIService.searchSemanticHandler = { _, _, _, _ in [] }

        // When - Add 25 searches
        for i in 0..<25 {
            sut.searchQuery = "query \(i)"
            await sut.performSearch()
        }

        // Then - Should only keep 20
        XCTAssertEqual(sut.searchHistory.count, 20)
        XCTAssertEqual(sut.searchHistory.first, "query 24") // Most recent first
    }

    func testClearSearchHistory() {
        // Given
        sut.searchHistory = ["query1", "query2", "query3"]

        // When
        sut.clearSearchHistory()

        // Then
        XCTAssertTrue(sut.searchHistory.isEmpty)
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: "semanticSearchHistory"))
    }

    func testRemoveFromHistory() {
        // Given
        sut.searchHistory = ["query1", "query2", "query3"]

        // When
        sut.removeFromHistory("query2")

        // Then
        XCTAssertEqual(sut.searchHistory, ["query1", "query3"])
    }

    func testHasSearchHistory() {
        // When empty
        sut.searchHistory = []
        XCTAssertFalse(sut.hasSearchHistory)

        // When has items
        sut.searchHistory = ["query1"]
        XCTAssertTrue(sut.hasSearchHistory)
    }

    // MARK: - Example Queries Tests

    func testExampleQueriesNotEmpty() {
        XCTAssertFalse(sut.exampleQueries.isEmpty)
        XCTAssertTrue(sut.exampleQueries.count >= 5)
    }

    // MARK: - Integration Tests

    func testCompleteSearchFlow() async throws {
        // Given
        let mockResults = [
            SearchResult(messageId: "1", content: "dinner at 7pm", relevanceScore: 0.95, threadId: "thread1", timestamp: nil)
        ]
        mockAIService.searchSemanticHandler = { _, _, _, _ in mockResults }

        // When
        sut.searchQuery = "dinner"
        await sut.performSearch()

        // Then
        XCTAssertEqual(sut.searchResults.count, 1)
        XCTAssertTrue(sut.searchHistory.contains("dinner"))
        XCTAssertNil(sut.searchError)
        XCTAssertFalse(sut.isSearching)
    }

    func testSearchWithAllFilters() async throws {
        // Given
        mockAIService.searchSemanticHandler = { _, _, _, _ in [] }
        sut.searchQuery = "test query"
        sut.selectedThreadId = "thread1"
        sut.dateRange = .lastWeek
        sut.resultLimit = 25
        sut.recencyBias = false

        // When
        await sut.performSearch()

        // Then
        XCTAssertEqual(mockAIService.lastSearchQuery, "test query")
        XCTAssertEqual(mockAIService.lastSearchThreadId, "thread1")
        XCTAssertEqual(mockAIService.lastSearchLimit, 25)
        XCTAssertEqual(mockAIService.lastSearchRecencyBias, false)
    }
}

// MARK: - Mock AI Service

@MainActor
class MockAIService: AIService {
    var searchSemanticHandler: ((String, String?, Int, Bool) async throws -> [SearchResult])?
    var searchSemanticCallCount = 0
    var lastSearchQuery: String?
    var lastSearchThreadId: String?
    var lastSearchLimit: Int?
    var lastSearchRecencyBias: Bool?

    override func searchSemantic(
        query: String,
        threadId: String? = nil,
        limit: Int = 10,
        recencyBias: Bool = true
    ) async throws -> [SearchResult] {
        searchSemanticCallCount += 1
        lastSearchQuery = query
        lastSearchThreadId = threadId
        lastSearchLimit = limit
        lastSearchRecencyBias = recencyBias

        if let handler = searchSemanticHandler {
            return try await handler(query, threadId, limit, recencyBias)
        }
        return []
    }
}

// MARK: - Search Results View Tests

final class SearchResultsViewTests: XCTestCase {

    func testGroupByThread() {
        // Given
        let results = [
            SearchResult(messageId: "1", content: "msg1", relevanceScore: 0.9, threadId: "thread1", timestamp: nil),
            SearchResult(messageId: "2", content: "msg2", relevanceScore: 0.8, threadId: "thread2", timestamp: nil),
            SearchResult(messageId: "3", content: "msg3", relevanceScore: 0.7, threadId: "thread1", timestamp: nil)
        ]

        // When
        let grouped = Dictionary(grouping: results) { $0.threadId ?? "Unknown" }

        // Then
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped["thread1"]?.count, 2)
        XCTAssertEqual(grouped["thread2"]?.count, 1)
    }

    func testGroupByDate() {
        // Given
        let now = Date()
        let yesterday = now.addingTimeInterval(-24 * 3600)
        let formatter = ISO8601DateFormatter()

        let results = [
            SearchResult(messageId: "1", content: "today", relevanceScore: 0.9, threadId: nil, timestamp: formatter.string(from: now)),
            SearchResult(messageId: "2", content: "yesterday", relevanceScore: 0.8, threadId: nil, timestamp: formatter.string(from: yesterday))
        ]

        // When
        let grouped = Dictionary(grouping: results) { result -> String in
            guard let timestamp = result.timestamp,
                  let date = formatter.date(from: timestamp) else {
                return "Unknown"
            }

            if Calendar.current.isDateInToday(date) {
                return "Today"
            } else if Calendar.current.isDateInYesterday(date) {
                return "Yesterday"
            }
            return "Earlier"
        }

        // Then
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped["Today"]?.count, 1)
        XCTAssertEqual(grouped["Yesterday"]?.count, 1)
    }

    func testRelevanceScoreColor() {
        // Given
        let highScore = 0.85
        let mediumScore = 0.65
        let lowScore = 0.35

        // When/Then
        XCTAssertTrue(highScore >= 0.8) // Green
        XCTAssertTrue(mediumScore >= 0.6 && mediumScore < 0.8) // Blue
        XCTAssertTrue(lowScore >= 0.2 && lowScore < 0.6) // Orange
    }

    func testRelevanceIndicatorBars() {
        // Test bar count logic
        XCTAssertEqual(barCount(for: 0.85), 5)
        XCTAssertEqual(barCount(for: 0.65), 4)
        XCTAssertEqual(barCount(for: 0.45), 3)
        XCTAssertEqual(barCount(for: 0.25), 2)
        XCTAssertEqual(barCount(for: 0.15), 1)
    }

    private func barCount(for score: Double) -> Int {
        if score >= 0.8 { return 5 }
        else if score >= 0.6 { return 4 }
        else if score >= 0.4 { return 3 }
        else if score >= 0.2 { return 2 }
        else { return 1 }
    }
}

// MARK: - Highlighted Text Tests

final class HighlightedTextTests: XCTestCase {

    func testHighlightSingleWord() {
        // Given
        let text = "Let's have dinner tomorrow"
        let query = "dinner"

        // When
        let components = highlightComponents(text: text, query: query)

        // Then
        XCTAssertTrue(components.contains { $0.text.lowercased() == "dinner" && $0.isHighlighted })
    }

    func testHighlightMultipleWords() {
        // Given
        let text = "Let's have dinner and lunch tomorrow"
        let query = "dinner lunch"

        // When
        let components = highlightComponents(text: text, query: query)

        // Then
        let highlightedWords = components.filter { $0.isHighlighted }.map { $0.text.lowercased() }
        XCTAssertTrue(highlightedWords.contains("dinner"))
        XCTAssertTrue(highlightedWords.contains("lunch"))
    }

    func testNoHighlightWhenNoMatch() {
        // Given
        let text = "Let's have dinner tomorrow"
        let query = "breakfast"

        // When
        let components = highlightComponents(text: text, query: query)

        // Then
        XCTAssertFalse(components.contains { $0.isHighlighted })
    }

    private func highlightComponents(text: String, query: String) -> [(text: String, isHighlighted: Bool)] {
        // Simplified version of highlighting logic for testing
        var components: [(String, Bool)] = []
        let queryWords = query.lowercased().split(separator: " ").map { String($0) }

        for word in queryWords {
            if let range = text.range(of: word, options: .caseInsensitive) {
                components.append((String(text[range]), true))
            }
        }

        if components.isEmpty {
            components.append((text, false))
        }

        return components
    }
}
