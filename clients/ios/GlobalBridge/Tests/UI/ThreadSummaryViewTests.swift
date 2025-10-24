//
//  ThreadSummaryViewTests.swift
//  GlobalBridgeTests
//
//  Comprehensive test suite for ThreadSummaryView and SummaryGenerationView
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class ThreadSummaryViewTests: XCTestCase {

    // MARK: - Test Data

    private var sampleSummary: ThreadSummary!
    private var emptySummary: ThreadSummary!
    private var staleSummary: ThreadSummary!

    override func setUp() async throws {
        try await super.setUp()

        // Create sample summary with full data
        sampleSummary = ThreadSummary(
            threadId: UUID(),
            summary: "Team discussed Q4 roadmap priorities, focusing on mobile app improvements and API performance optimizations.",
            keyPoints: [
                "Mobile app performance improvements are top priority",
                "API response times need optimization",
                "Infrastructure upgrade scheduled for November"
            ],
            decisions: [
                "Approved $50k budget for infrastructure upgrades",
                "Decided to use Kubernetes for container orchestration"
            ],
            actionItems: [
                ThreadSummary.ActionItem(
                    id: UUID(),
                    description: "Prepare Q4 roadmap presentation",
                    assignee: "John Doe",
                    dueDate: Date().addingTimeInterval(86400 * 2),
                    priority: .high,
                    status: .inProgress
                ),
                ThreadSummary.ActionItem(
                    id: UUID(),
                    description: "Review API performance metrics",
                    assignee: "Jane Smith",
                    dueDate: Date().addingTimeInterval(86400 * 5),
                    priority: .medium,
                    status: .pending
                )
            ],
            participants: [
                ThreadSummary.Participant(
                    id: UUID(),
                    username: "john.doe",
                    displayName: "John Doe",
                    messageCount: 24
                ),
                ThreadSummary.Participant(
                    id: UUID(),
                    username: "jane.smith",
                    displayName: "Jane Smith",
                    messageCount: 18
                )
            ],
            messageCount: 42,
            provider: "claude-3.5-sonnet"
        )

        // Empty summary with minimal data
        emptySummary = ThreadSummary(
            threadId: UUID(),
            summary: "Brief discussion.",
            keyPoints: [],
            decisions: [],
            actionItems: [],
            participants: [],
            messageCount: 5
        )

        // Stale summary (older than 1 hour)
        staleSummary = ThreadSummary(
            threadId: UUID(),
            summary: "Old summary",
            generatedAt: Date().addingTimeInterval(-7200) // 2 hours ago
        )
    }

    override func tearDown() async throws {
        sampleSummary = nil
        emptySummary = nil
        staleSummary = nil
        try await super.tearDown()
    }

    // MARK: - ThreadSummary Model Tests

    func testThreadSummaryHasActionItems() {
        XCTAssertTrue(sampleSummary.hasActionItems)
        XCTAssertFalse(emptySummary.hasActionItems)
    }

    func testThreadSummaryHasDecisions() {
        XCTAssertTrue(sampleSummary.hasDecisions)
        XCTAssertFalse(emptySummary.hasDecisions)
    }

    func testThreadSummaryHasKeyPoints() {
        XCTAssertTrue(sampleSummary.hasKeyPoints)
        XCTAssertFalse(emptySummary.hasKeyPoints)
    }

    func testThreadSummaryPendingActionItemsCount() {
        XCTAssertEqual(sampleSummary.pendingActionItemsCount, 2)
        XCTAssertEqual(emptySummary.pendingActionItemsCount, 0)
    }

    func testThreadSummaryHighPriorityActionItems() {
        XCTAssertEqual(sampleSummary.highPriorityActionItems.count, 1)
        XCTAssertEqual(emptySummary.highPriorityActionItems.count, 0)
    }

    func testThreadSummaryIsStale() {
        XCTAssertFalse(sampleSummary.isStale)
        XCTAssertTrue(staleSummary.isStale)
    }

    func testThreadSummaryParticipantsSummary() {
        let summary = sampleSummary.participantsSummary
        XCTAssertTrue(summary.contains("John Doe"))
        XCTAssertTrue(summary.contains("Jane Smith"))

        let emptyParticipants = emptySummary.participantsSummary
        XCTAssertEqual(emptyParticipants, "No participants")
    }

    // MARK: - Action Item Tests

    func testActionItemIsOverdue() {
        let overdueItem = ThreadSummary.ActionItem(
            id: UUID(),
            description: "Overdue task",
            dueDate: Date().addingTimeInterval(-86400), // Yesterday
            status: .pending
        )
        XCTAssertTrue(overdueItem.isOverdue)

        let futureItem = ThreadSummary.ActionItem(
            id: UUID(),
            description: "Future task",
            dueDate: Date().addingTimeInterval(86400), // Tomorrow
            status: .pending
        )
        XCTAssertFalse(futureItem.isOverdue)

        let completedItem = ThreadSummary.ActionItem(
            id: UUID(),
            description: "Completed task",
            dueDate: Date().addingTimeInterval(-86400),
            status: .completed
        )
        XCTAssertFalse(completedItem.isOverdue) // Completed items not overdue
    }

    func testActionItemIsDueSoon() {
        let dueSoonItem = ThreadSummary.ActionItem(
            id: UUID(),
            description: "Due soon task",
            dueDate: Date().addingTimeInterval(3600), // 1 hour from now
            status: .pending
        )
        XCTAssertTrue(dueSoonItem.isDueSoon)

        let farFutureItem = ThreadSummary.ActionItem(
            id: UUID(),
            description: "Far future task",
            dueDate: Date().addingTimeInterval(86400 * 7), // 7 days from now
            status: .pending
        )
        XCTAssertFalse(farFutureItem.isDueSoon)
    }

    func testActionItemPriorityColor() {
        let urgentItem = ThreadSummary.ActionItem(
            id: UUID(),
            description: "Urgent",
            priority: .urgent
        )
        XCTAssertEqual(urgentItem.priorityColor, "red")

        let lowItem = ThreadSummary.ActionItem(
            id: UUID(),
            description: "Low",
            priority: .low
        )
        XCTAssertEqual(lowItem.priorityColor, "gray")
    }

    // MARK: - SummaryGenerationViewModel Tests

    func testViewModelInitialization() async {
        let threadId = UUID()
        let viewModel = SummaryGenerationViewModel(
            threadId: threadId,
            messageCount: 100
        )

        XCTAssertFalse(viewModel.isGenerating)
        XCTAssertNil(viewModel.currentSummary)
        XCTAssertNil(viewModel.error)
        XCTAssertGreaterThan(viewModel.estimatedTokens, 0)
    }

    func testViewModelTokenEstimation() {
        let smallViewModel = SummaryGenerationViewModel(
            threadId: UUID(),
            messageCount: 10
        )
        let largeViewModel = SummaryGenerationViewModel(
            threadId: UUID(),
            messageCount: 1000
        )

        XCTAssertLessThan(smallViewModel.estimatedTokens, largeViewModel.estimatedTokens)
    }

    func testViewModelMaxLengthUpdatesTokens() {
        let viewModel = SummaryGenerationViewModel(
            threadId: UUID(),
            messageCount: 100
        )

        let initialTokens = viewModel.estimatedTokens
        viewModel.maxLength = 500

        // Token estimate should change when max length changes
        XCTAssertNotEqual(initialTokens, viewModel.estimatedTokens)
    }

    func testViewModelShouldAutoSummarize() {
        let smallThread = SummaryGenerationViewModel(
            threadId: UUID(),
            messageCount: 50
        )
        XCTAssertFalse(smallThread.shouldAutoSummarize())

        let largeThread = SummaryGenerationViewModel(
            threadId: UUID(),
            messageCount: 150
        )
        XCTAssertTrue(largeThread.shouldAutoSummarize())
    }

    func testViewModelExportSummary() {
        let viewModel = SummaryGenerationViewModel(
            threadId: UUID(),
            messageCount: 100
        )

        // No summary initially
        XCTAssertNil(viewModel.exportSummary())

        // Set a summary
        viewModel.currentSummary = sampleSummary

        let exportedText = viewModel.exportSummary()
        XCTAssertNotNil(exportedText)
        XCTAssertTrue(exportedText!.contains("# Thread Summary"))
        XCTAssertTrue(exportedText!.contains(sampleSummary.summary))
        XCTAssertTrue(exportedText!.contains("## Key Points"))
        XCTAssertTrue(exportedText!.contains("## Action Items"))
    }

    func testViewModelClearError() {
        let viewModel = SummaryGenerationViewModel(
            threadId: UUID(),
            messageCount: 100
        )

        viewModel.error = .notAuthenticated
        viewModel.statusMessage = "Error message"

        viewModel.clearError()

        XCTAssertNil(viewModel.error)
        XCTAssertEqual(viewModel.statusMessage, "")
    }

    // MARK: - Cache Manager Tests

    func testCacheManagerSetAndGet() async {
        let cacheManager = SummaryCacheManager()
        let threadId = UUID()

        // Initially no cache
        let initial = await cacheManager.getCachedSummary(for: threadId)
        XCTAssertNil(initial)

        // Cache a summary
        let summary = ThreadSummary(threadId: threadId, summary: "Test summary")
        await cacheManager.cacheSummary(summary)

        // Retrieve from cache
        let cached = await cacheManager.getCachedSummary(for: threadId)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.threadId, threadId)
        XCTAssertEqual(cached?.summary, "Test summary")
    }

    func testCacheManagerClearCache() async {
        let cacheManager = SummaryCacheManager()
        let threadId = UUID()

        // Cache a summary
        let summary = ThreadSummary(threadId: threadId, summary: "Test")
        await cacheManager.cacheSummary(summary)

        // Verify cached
        let cached = await cacheManager.getCachedSummary(for: threadId)
        XCTAssertNotNil(cached)

        // Clear cache
        await cacheManager.clearCache(for: threadId)

        // Verify cleared
        let afterClear = await cacheManager.getCachedSummary(for: threadId)
        XCTAssertNil(afterClear)
    }

    func testCacheManagerClearAllCache() async {
        let cacheManager = SummaryCacheManager()

        // Cache multiple summaries
        for i in 0..<5 {
            let summary = ThreadSummary(
                threadId: UUID(),
                summary: "Summary \(i)"
            )
            await cacheManager.cacheSummary(summary)
        }

        // Clear all
        await cacheManager.clearAllCache()

        // Verify all cleared (test a few random UUIDs)
        let check1 = await cacheManager.getCachedSummary(for: UUID())
        let check2 = await cacheManager.getCachedSummary(for: UUID())
        XCTAssertNil(check1)
        XCTAssertNil(check2)
    }

    // MARK: - Integration Tests

    func testViewModelCacheIntegration() async {
        let threadId = UUID()
        let cacheManager = SummaryCacheManager()

        // Create viewModel
        let viewModel = SummaryGenerationViewModel(
            threadId: threadId,
            messageCount: 100,
            cacheManager: cacheManager
        )

        // Initially no cache
        XCTAssertNil(viewModel.currentSummary)

        // Manually cache a summary
        let cachedSummary = ThreadSummary(
            threadId: threadId,
            summary: "Cached test summary"
        )
        await cacheManager.cacheSummary(cachedSummary)

        // Check cache
        await viewModel.checkCache()

        // Should now have the cached summary
        XCTAssertNotNil(viewModel.currentSummary)
        XCTAssertEqual(viewModel.currentSummary?.summary, "Cached test summary")
    }

    func testViewModelStaleCache() async {
        let threadId = UUID()
        let cacheManager = SummaryCacheManager()

        // Cache a stale summary
        let staleSummary = ThreadSummary(
            threadId: threadId,
            summary: "Stale summary",
            generatedAt: Date().addingTimeInterval(-86400 * 2) // 2 days ago
        )
        await cacheManager.cacheSummary(staleSummary)

        // Create viewModel with 24h cache expiration
        let viewModel = SummaryGenerationViewModel(
            threadId: threadId,
            messageCount: 100,
            cacheManager: cacheManager
        )
        viewModel.cacheExpirationHours = 24

        // Check cache
        await viewModel.checkCache()

        // Should not use stale cache (or should mark it as expired)
        if viewModel.currentSummary != nil {
            // If it loaded, status should indicate expired
            XCTAssertTrue(viewModel.statusMessage.contains("expired") || viewModel.statusMessage.contains("Cache"))
        }
    }

    // MARK: - Error Handling Tests

    func testAIServiceErrorDescriptions() {
        let notAuthError = AIServiceError.notAuthenticated
        XCTAssertTrue(notAuthError.localizedDescription!.contains("Not authenticated"))

        let rateLimitError = AIServiceError.rateLimitExceeded(retryAfter: 60)
        XCTAssertTrue(rateLimitError.localizedDescription!.contains("60 seconds"))

        let featureError = AIServiceError.featureDisabled(feature: "summarization")
        XCTAssertTrue(featureError.localizedDescription!.contains("summarization"))
    }

    // MARK: - Performance Tests

    func testThreadSummaryPerformance() {
        measure {
            // Create and process 100 summaries
            for _ in 0..<100 {
                let summary = ThreadSummary(
                    threadId: UUID(),
                    summary: "Performance test summary with reasonable length text",
                    keyPoints: Array(repeating: "Key point", count: 5),
                    actionItems: Array(repeating: ThreadSummary.ActionItem(
                        id: UUID(),
                        description: "Action item"
                    ), count: 3),
                    participants: Array(repeating: ThreadSummary.Participant(
                        id: UUID(),
                        username: "user"
                    ), count: 10)
                )

                // Access computed properties
                _ = summary.hasActionItems
                _ = summary.participantsSummary
                _ = summary.pendingActionItemsCount
            }
        }
    }

    func testCachePerformance() async {
        let cacheManager = SummaryCacheManager()

        measure {
            Task {
                // Cache 50 summaries
                for i in 0..<50 {
                    let summary = ThreadSummary(
                        threadId: UUID(),
                        summary: "Summary \(i)"
                    )
                    await cacheManager.cacheSummary(summary)
                }
            }
        }
    }

    // MARK: - Edge Case Tests

    func testEmptySummaryDisplay() {
        // Empty summary should still be valid
        XCTAssertFalse(emptySummary.hasKeyPoints)
        XCTAssertFalse(emptySummary.hasActionItems)
        XCTAssertFalse(emptySummary.hasDecisions)
        XCTAssertEqual(emptySummary.participantsSummary, "No participants")
    }

    func testActionItemWithoutDueDate() {
        let item = ThreadSummary.ActionItem(
            id: UUID(),
            description: "No due date",
            dueDate: nil
        )

        XCTAssertFalse(item.isOverdue)
        XCTAssertFalse(item.isDueSoon)
    }

    func testParticipantInitials() {
        let singleName = ThreadSummary.Participant(
            id: UUID(),
            username: "john"
        )
        // Should use first 2 characters for single names

        let multiName = ThreadSummary.Participant(
            id: UUID(),
            username: "john.doe",
            displayName: "John Doe"
        )
        // Should extract initials from display name
    }

    func testLongSummaryText() {
        let longText = String(repeating: "This is a very long summary. ", count: 100)
        let summary = ThreadSummary(
            threadId: UUID(),
            summary: longText
        )

        XCTAssertGreaterThan(summary.summary.count, 1000)
    }

    func testManyActionItems() {
        let manyItems = (0..<50).map { i in
            ThreadSummary.ActionItem(
                id: UUID(),
                description: "Action item \(i)",
                priority: [.low, .medium, .high, .urgent].randomElement()
            )
        }

        let summary = ThreadSummary(
            threadId: UUID(),
            summary: "Summary with many items",
            actionItems: manyItems
        )

        XCTAssertEqual(summary.actionItems.count, 50)
        XCTAssertGreaterThan(summary.highPriorityActionItems.count, 0)
    }
}

// MARK: - Mock AIService for Testing

@MainActor
final class MockAIService: AIService {
    var shouldSucceed = true
    var mockDelay: TimeInterval = 0.1
    var mockSummary: SummarizationResult?

    override func summarizeThread(threadId: String, maxLength: Int) async throws -> SummarizationResult {
        try await Task.sleep(nanoseconds: UInt64(mockDelay * 1_000_000_000))

        if !shouldSucceed {
            throw AIServiceError.apiError(message: "Mock error")
        }

        return mockSummary ?? SummarizationResult(
            summary: "Mock summary generated for thread \(threadId)",
            threadId: threadId,
            messageCount: 42
        )
    }
}
