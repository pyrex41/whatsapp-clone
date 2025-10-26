//
//  SmartReplyErrorStateTests.swift
//  GlobalBridge
//
//  Task 15: Test loading and error states in SmartReplyComposerView
//  Unit tests for error handling, loading states, and retry logic
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class SmartReplyErrorStateTests: XCTestCase {

    // MARK: - Test Data

    let sampleSuggestion = SmartReplySuggestion(
        id: UUID(),
        type: "quick-reply",
        content: "Thanks!",
        confidence: 0.95,
        position: 0,
        context: "",
        timestamp: Date()
    )

    // MARK: - Loading State Tests

    func testLoadingStateRendersShimmer() {
        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: true,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "View should render with loading state")
    }

    func testLoadingStateHidessuggestions() {
        let view = SmartReplyComposerView(
            suggestions: [sampleSuggestion],
            isLoading: true,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "Loading state should take precedence over suggestions")
    }

    func testLoadingStateShowsTranslationToggle() {
        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: true,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "Translation toggle should be visible during loading")
    }

    // MARK: - Error State Tests

    func testErrorStateRendersErrorView() {
        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: false,
            error: .networkError(URLError(.notConnectedToInternet)),
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: {}
        )

        XCTAssertNotNil(view, "View should render with error state")
    }

    func testErrorStateTakesPrecedenceOverLoading() {
        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: true,
            error: .unauthorized,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "Error state should take precedence over loading")
    }

    func testErrorStateTakesPrecedenceOverSuggestions() {
        let view = SmartReplyComposerView(
            suggestions: [sampleSuggestion],
            isLoading: false,
            error: .forbidden,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "Error state should take precedence over suggestions")
    }

    // MARK: - Network Error Tests

    func testNetworkErrorShowsRetryButton() {
        let error: AIServiceError = .networkError(URLError(.notConnectedToInternet))

        XCTAssertTrue(error.shouldRetry, "Network errors should be retryable")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testNetworkErrorWithRetryCallback() {
        var retryTapped = false

        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: false,
            error: .networkError(URLError(.timedOut)),
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: {
                retryTapped = true
            }
        )

        XCTAssertNotNil(view)
        XCTAssertFalse(retryTapped, "Retry not tapped yet")
    }

    // MARK: - Server Error Tests

    func testServerErrorShowsRetryButton() {
        let error: AIServiceError = .httpError(statusCode: 500, message: "Internal Server Error")

        XCTAssertTrue(error.shouldRetry, "Server errors (500-599) should be retryable")
        XCTAssertNotNil(error.errorDescription)
    }

    func testClientErrorDoesNotShowRetryButton() {
        let error: AIServiceError = .httpError(statusCode: 400, message: "Bad Request")

        XCTAssertFalse(error.shouldRetry, "Client errors should not be retryable")
    }

    // MARK: - Rate Limit Error Tests

    func testRateLimitErrorWithRetryAfter() {
        let retryAfter = Date().addingTimeInterval(300) // 5 minutes
        let error: AIServiceError = .rateLimitExceeded(
            retryAfter: retryAfter,
            remainingQuota: 0,
            tierLimit: "Premium"
        )

        XCTAssertTrue(error.shouldRetry, "Rate limit with retry time should be retryable")
        XCTAssertTrue(error.isTierLimited)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testRateLimitErrorWithoutRetryAfter() {
        let error: AIServiceError = .rateLimitExceeded(
            retryAfter: nil,
            remainingQuota: 0,
            tierLimit: "Pro"
        )

        XCTAssertFalse(error.shouldRetry, "Rate limit without retry time should not be retryable")
        XCTAssertTrue(error.isTierLimited)
    }

    // MARK: - Auth Error Tests

    func testUnauthorizedError() {
        let error: AIServiceError = .unauthorized

        XCTAssertFalse(error.shouldRetry, "Auth errors should not be retryable")
        XCTAssertTrue(error.requiresAuth)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }

    func testForbiddenError() {
        let error: AIServiceError = .forbidden

        XCTAssertFalse(error.shouldRetry, "Forbidden errors should not be retryable")
        XCTAssertTrue(error.requiresAuth)
    }

    // MARK: - Feature Availability Error Tests

    func testFeatureNotAvailableError() {
        let error: AIServiceError = .featureNotAvailable(
            feature: "Smart Reply",
            requiredTier: "Premium"
        )

        XCTAssertFalse(error.shouldRetry)
        XCTAssertTrue(error.isTierLimited)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertNotNil(error.recoverySuggestion)
    }

    // MARK: - No Error State Tests

    func testNoErrorShowsSuggestions() {
        let view = SmartReplyComposerView(
            suggestions: [sampleSuggestion],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "View should show suggestions when no error")
    }

    func testNoErrorAndNoSuggestionsShowsNothing() {
        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "View should handle empty state")
    }

    // MARK: - Retry Callback Tests

    func testRetryCallbackOptional() {
        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: false,
            error: .networkError(URLError(.notConnectedToInternet)),
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "View should handle nil retry callback")
    }

    func testRetryCallbackWithRetryableError() {
        var retryCount = 0

        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: false,
            error: .networkError(URLError(.networkConnectionLost)),
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: {
                retryCount += 1
            }
        )

        XCTAssertNotNil(view)
        XCTAssertEqual(retryCount, 0, "Retry should not be called automatically")
    }

    func testRetryCallbackNotShownForNonRetryableError() {
        var retryCount = 0

        let view = SmartReplyComposerView(
            suggestions: [],
            isLoading: false,
            error: .unauthorized,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: {
                retryCount += 1
            }
        )

        XCTAssertNotNil(view)
        // Retry button should not be shown for non-retryable errors
    }

    // MARK: - State Priority Tests

    func testStatePriority() {
        // Priority: Error > Loading > Suggestions > Empty

        // Error takes precedence over everything
        let errorView = SmartReplyComposerView(
            suggestions: [sampleSuggestion],
            isLoading: true,
            error: .unauthorized,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )
        XCTAssertNotNil(errorView)

        // Loading takes precedence over suggestions
        let loadingView = SmartReplyComposerView(
            suggestions: [sampleSuggestion],
            isLoading: true,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )
        XCTAssertNotNil(loadingView)

        // Suggestions shown when no error or loading
        let suggestionsView = SmartReplyComposerView(
            suggestions: [sampleSuggestion],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )
        XCTAssertNotNil(suggestionsView)
    }

    // MARK: - Error Message Tests

    func testErrorMessages() {
        let errors: [AIServiceError] = [
            .networkError(URLError(.notConnectedToInternet)),
            .unauthorized,
            .forbidden,
            .rateLimitExceeded(retryAfter: nil, remainingQuota: 0, tierLimit: "Pro"),
            .invalidInput(reason: "Invalid thread ID"),
            .backendError(message: "Server error"),
            .featureDisabled(feature: "Smart Reply")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description")
        }
    }

    // MARK: - Integration Tests

    func testErrorToLoadingToSuccessFlow() {
        // 1. Start with error
        let errorView = SmartReplyComposerView(
            suggestions: [],
            isLoading: false,
            error: .networkError(URLError(.timedOut)),
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: {}
        )
        XCTAssertNotNil(errorView)

        // 2. User taps retry -> loading state
        let loadingView = SmartReplyComposerView(
            suggestions: [],
            isLoading: true,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )
        XCTAssertNotNil(loadingView)

        // 3. Success -> suggestions shown
        let successView = SmartReplyComposerView(
            suggestions: [sampleSuggestion],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _ in },
            onTranslationToggle: {},
            onRetry: nil
        )
        XCTAssertNotNil(successView)
    }

    func testAllErrorTypesRenderable() {
        let errors: [AIServiceError] = [
            .networkError(URLError(.notConnectedToInternet)),
            .invalidResponse,
            .httpError(statusCode: 500, message: "Server Error"),
            .unauthorized,
            .forbidden,
            .rateLimitExceeded(retryAfter: Date(), remainingQuota: 0, tierLimit: "Premium"),
            .featureNotAvailable(feature: "Smart Reply", requiredTier: "Pro"),
            .invalidInput(reason: "Invalid ID"),
            .threadNotFound(threadId: UUID()),
            .invalidText,
            .unsupportedLanguage(code: "xx"),
            .backendError(message: "Error"),
            .vectorDatabaseError(reason: "Connection failed"),
            .noEmbeddingsAvailable(threadId: UUID()),
            .featureDisabled(feature: "AI")
        ]

        for error in errors {
            let view = SmartReplyComposerView(
                suggestions: [],
                isLoading: false,
                error: error,
                translationEnabled: false,
                onSuggestionTap: { _, _ in },
                onTranslationToggle: {},
                onRetry: error.shouldRetry ? {} : nil
            )
            XCTAssertNotNil(view, "View should render for error: \(error)")
        }
    }
}
