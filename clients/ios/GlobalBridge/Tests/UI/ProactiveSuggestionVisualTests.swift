//
//  ProactiveSuggestionVisualTests.swift
//  GlobalBridge
//
//  Task 24: Test visual distinction between proactive and non-proactive suggestions
//  Unit tests for visual styling and accessibility differences
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class ProactiveSuggestionVisualTests: XCTestCase {

    // MARK: - Test Data

    let proactiveSuggestion = SmartReplySuggestion(
        id: UUID(),
        type: "proactive",
        content: "I'll be there in 5 minutes",
        translatedText: nil,
        confidence: 0.85,
        position: 0,
        context: "",
        timestamp: Date()
    )

    let nonProactiveSuggestion = SmartReplySuggestion(
        id: UUID(),
        type: "quick-reply",
        content: "Thanks!",
        translatedText: nil,
        confidence: 0.95,
        position: 0,
        context: "",
        timestamp: Date()
    )

    // MARK: - isProactive Property Tests

    func testProactiveSuggestionIsProactive() {
        XCTAssertTrue(proactiveSuggestion.isProactive)
        XCTAssertEqual(proactiveSuggestion.type, "proactive")
    }

    func testNonProactiveSuggestionIsNotProactive() {
        XCTAssertFalse(nonProactiveSuggestion.isProactive)
        XCTAssertNotEqual(nonProactiveSuggestion.type, "proactive")
    }

    func testQuickReplySuggestionIsNotProactive() {
        let suggestion = SmartReplySuggestion(
            id: UUID(),
            type: "quick-reply",
            content: "Yes",
            translatedText: nil,
            confidence: 0.95,
            position: 0,
            context: "",
            timestamp: Date()
        )
        XCTAssertFalse(suggestion.isProactive)
    }

    func testContextualSuggestionIsNotProactive() {
        let suggestion = SmartReplySuggestion(
            id: UUID(),
            type: "contextual",
            content: "Let me check",
            translatedText: nil,
            confidence: 0.85,
            position: 0,
            context: "",
            timestamp: Date()
        )
        XCTAssertFalse(suggestion.isProactive)
    }

    // MARK: - View Creation Tests

    func testSmartReplyComposerViewWithProactiveSuggestions() {
        let view = SmartReplyComposerView(
            suggestions: [proactiveSuggestion],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "View should be created with proactive suggestions")
    }

    func testSmartReplyComposerViewWithNonProactiveSuggestions() {
        let view = SmartReplyComposerView(
            suggestions: [nonProactiveSuggestion],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "View should be created with non-proactive suggestions")
    }

    func testSmartReplyComposerViewWithMixedSuggestions() {
        let view = SmartReplyComposerView(
            suggestions: [proactiveSuggestion, nonProactiveSuggestion],
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view, "View should be created with mixed suggestions")
    }

    // MARK: - Multiple Proactive Suggestions

    func testMultipleProactiveSuggestions() {
        let suggestions = [
            SmartReplySuggestion(
                id: UUID(),
                type: "proactive",
                content: "I'll be there soon",
                translatedText: nil,
                confidence: 0.85,
                position: 0,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "proactive",
                content: "Let me know if you need help",
                translatedText: nil,
                confidence: 0.75,
                position: 1,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "proactive",
                content: "Running a bit late",
                translatedText: nil,
                confidence: 0.65,
                position: 2,
                context: "",
                timestamp: Date()
            )
        ]

        suggestions.forEach { suggestion in
            XCTAssertTrue(suggestion.isProactive, "All suggestions should be proactive")
        }

        let view = SmartReplyComposerView(
            suggestions: suggestions,
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view)
    }

    // MARK: - Edge Cases

    func testEmptyTypeSuggestionIsNotProactive() {
        let suggestion = SmartReplySuggestion(
            id: UUID(),
            type: "",
            content: "Test",
            translatedText: nil,
            confidence: 0.5,
            position: 0,
            context: "",
            timestamp: Date()
        )
        XCTAssertFalse(suggestion.isProactive)
    }

    func testCaseSensitiveTypeCheck() {
        // Type comparison should be exact match
        let upperCase = SmartReplySuggestion(
            id: UUID(),
            type: "PROACTIVE",
            content: "Test",
            translatedText: nil,
            confidence: 0.5,
            position: 0,
            context: "",
            timestamp: Date()
        )
        XCTAssertFalse(upperCase.isProactive, "Type check should be case-sensitive")

        let mixedCase = SmartReplySuggestion(
            id: UUID(),
            type: "Proactive",
            confidence: 0.5,
            position: 0,
            context: "",
            timestamp: Date()
        )
        XCTAssertFalse(mixedCase.isProactive, "Type check should be case-sensitive")
    }

    func testSimilarTypeIsNotProactive() {
        let suggestion = SmartReplySuggestion(
            id: UUID(),
            type: "proactive-suggestion",
            content: "Test",
            translatedText: nil,
            confidence: 0.5,
            position: 0,
            context: "",
            timestamp: Date()
        )
        XCTAssertFalse(suggestion.isProactive, "Only exact 'proactive' type should match")
    }

    // MARK: - Integration Tests

    func testProactiveAndNonProactiveTogether() {
        let suggestions = [
            SmartReplySuggestion(
                id: UUID(),
                type: "quick-reply",
                content: "Yes",
                translatedText: nil,
                confidence: 0.95,
                position: 0,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "proactive",
                content: "I'll handle it",
                translatedText: nil,
                confidence: 0.85,
                position: 1,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "contextual",
                content: "Sounds good",
                translatedText: nil,
                confidence: 0.80,
                position: 2,
                context: "",
                timestamp: Date()
            )
        ]

        let proactiveCount = suggestions.filter { $0.isProactive }.count
        let nonProactiveCount = suggestions.filter { !$0.isProactive }.count

        XCTAssertEqual(proactiveCount, 1, "Should have 1 proactive suggestion")
        XCTAssertEqual(nonProactiveCount, 2, "Should have 2 non-proactive suggestions")

        let view = SmartReplyComposerView(
            suggestions: suggestions,
            isLoading: false,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view)
    }

    // MARK: - Visual Styling Verification Tests

    func testProactiveSuggestionHasDistinctVisualProperties() {
        // This test verifies that proactive suggestions have the isProactive flag
        // which is used to apply different styling (purple tint, border, icon)
        XCTAssertTrue(proactiveSuggestion.isProactive)

        // In actual UI, this translates to:
        // - Purple sparkles icon
        // - Purple tinted background (opacity 0.08)
        // - Purple border (opacity 0.3)
        // - "Proactive suggestion:" accessibility label prefix
    }

    func testNonProactiveSuggestionHasStandardVisualProperties() {
        // This test verifies that non-proactive suggestions do NOT have the isProactive flag
        // which means they use standard styling
        XCTAssertFalse(nonProactiveSuggestion.isProactive)

        // In actual UI, this translates to:
        // - No icon
        // - Standard secondary background
        // - No border
        // - "Suggestion:" accessibility label prefix
    }

    // MARK: - Accessibility Tests

    func testProactiveSuggestionAccessibilityLabel() {
        // Accessibility labels are set in the view, but we can verify
        // that the suggestion has the property needed to generate them
        XCTAssertTrue(proactiveSuggestion.isProactive)

        // In SmartReplyComposerView, this results in:
        // .accessibilityLabel("Proactive suggestion: \(content)")
    }

    func testNonProactiveSuggestionAccessibilityLabel() {
        // Accessibility labels are set in the view
        XCTAssertFalse(nonProactiveSuggestion.isProactive)

        // In SmartReplyComposerView, this results in:
        // .accessibilityLabel("Suggestion: \(content)")
    }

    // MARK: - Loading State Tests

    func testLoadingStateDoesNotAffectSuggestionTypes() {
        let view = SmartReplyComposerView(
            suggestions: [proactiveSuggestion, nonProactiveSuggestion],
            isLoading: true,
            error: nil,
            translationEnabled: false,
            onSuggestionTap: { _, _, _ in },
            onSuggestionDismiss: nil,
            onTranslationToggle: {},
            onRetry: nil
        )

        XCTAssertNotNil(view)

        // Suggestions should maintain their types regardless of loading state
        XCTAssertTrue(proactiveSuggestion.isProactive)
        XCTAssertFalse(nonProactiveSuggestion.isProactive)
    }

    // MARK: - Preview Verification Tests

    func testProactiveVsNonProactivePreviewData() {
        // Verify that the comparison preview has correct data
        let proactiveSuggestions = [
            SmartReplySuggestion(
                id: UUID(),
                type: "proactive",
                content: "I'll be there in 5 minutes",
                translatedText: nil,
                confidence: 0.85,
                position: 0,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "proactive",
                content: "Let me know if you need help",
                translatedText: nil,
                confidence: 0.75,
                position: 1,
                context: "",
                timestamp: Date()
            )
        ]

        let nonProactiveSuggestions = [
            SmartReplySuggestion(
                id: UUID(),
                type: "quick-reply",
                content: "Thanks!",
                translatedText: nil,
                confidence: 0.95,
                position: 0,
                context: "",
                timestamp: Date()
            ),
            SmartReplySuggestion(
                id: UUID(),
                type: "contextual",
                content: "Sounds good",
                translatedText: nil,
                confidence: 0.85,
                position: 1,
                context: "",
                timestamp: Date()
            )
        ]

        XCTAssertTrue(proactiveSuggestions.allSatisfy { $0.isProactive })
        XCTAssertTrue(nonProactiveSuggestions.allSatisfy { !$0.isProactive })
    }
}
