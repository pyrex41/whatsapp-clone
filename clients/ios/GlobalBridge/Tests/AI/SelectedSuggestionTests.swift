//
//  SelectedSuggestionTests.swift
//  GlobalBridge
//
//  Task 21: Test suggestion modification detection
//  Unit tests for modification tracking and feedback creation
//

import XCTest
@testable import GlobalBridge

final class SelectedSuggestionTests: XCTestCase {

    // MARK: - Test Data

    let sampleSuggestion = SmartReplySuggestion(
        id: UUID(),
        type: "quick-reply",
        content: "Thanks for the update!",
        confidence: 0.95,
        position: 0,
        context: "",
        timestamp: Date()
    )

    // MARK: - Initialization Tests

    func testSelectedSuggestionInitialization() {
        let timeMs = 1234
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: timeMs)

        XCTAssertEqual(selected.suggestion.id, sampleSuggestion.id)
        XCTAssertEqual(selected.originalContent, sampleSuggestion.content)
        XCTAssertEqual(selected.timeToResponseMs, timeMs)
        XCTAssertNotNil(selected.selectionTime)
    }

    func testOriginalContentCaptured() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)

        XCTAssertEqual(selected.originalContent, "Thanks for the update!")
    }

    // MARK: - Modification Detection Tests

    func testNoModification() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "Thanks for the update!")

        XCTAssertFalse(wasModified)
        XCTAssertNil(modifiedContent)
    }

    func testNoModificationWithWhitespace() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)

        // Test with leading/trailing whitespace
        let (wasModified1, modifiedContent1) = selected.detectModification(in: "  Thanks for the update!  ")
        XCTAssertFalse(wasModified1)
        XCTAssertNil(modifiedContent1)

        // Test with extra spaces
        let (wasModified2, modifiedContent2) = selected.detectModification(in: "Thanks for the update!   ")
        XCTAssertFalse(wasModified2)
        XCTAssertNil(modifiedContent2)
    }

    func testModificationDetected() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "Thanks for the great update!")

        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "Thanks for the great update!")
    }

    func testMinorModification() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)

        // Single character change
        let (wasModified, modifiedContent) = selected.detectModification(in: "Thanks for the update")
        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "Thanks for the update")
    }

    func testMajorModification() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "Completely different message")

        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "Completely different message")
    }

    func testCaseSensitiveModification() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "THANKS FOR THE UPDATE!")

        // Should detect case change as modification
        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "THANKS FOR THE UPDATE!")
    }

    func testEmojiAddition() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "Thanks for the update! 😊")

        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "Thanks for the update! 😊")
    }

    func testPunctuationChange() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "Thanks for the update?")

        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "Thanks for the update?")
    }

    // MARK: - Feedback Creation Tests

    func testCreateFeedbackUnmodified() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 1234)
        let feedback = selected.createFeedback(finalContent: "Thanks for the update!", accepted: true)

        XCTAssertEqual(feedback.suggestionId, sampleSuggestion.id)
        XCTAssertTrue(feedback.accepted)
        XCTAssertNil(feedback.modifiedContent)
        XCTAssertEqual(feedback.timeToResponseMs, 1234)
    }

    func testCreateFeedbackModified() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 1234)
        let feedback = selected.createFeedback(finalContent: "Thanks for the great update!", accepted: true)

        XCTAssertEqual(feedback.suggestionId, sampleSuggestion.id)
        XCTAssertTrue(feedback.accepted)
        XCTAssertEqual(feedback.modifiedContent, "Thanks for the great update!")
        XCTAssertEqual(feedback.timeToResponseMs, 1234)
    }

    func testCreateFeedbackRejected() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 1234)
        let feedback = selected.createFeedback(finalContent: "Different message", accepted: false)

        XCTAssertEqual(feedback.suggestionId, sampleSuggestion.id)
        XCTAssertFalse(feedback.accepted)
        XCTAssertEqual(feedback.modifiedContent, "Different message")
        XCTAssertEqual(feedback.timeToResponseMs, 1234)
    }

    func testFeedbackIncludesTimeToResponse() {
        let timeMs = 5678
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: timeMs)
        let feedback = selected.createFeedback(finalContent: "Thanks for the update!", accepted: true)

        XCTAssertEqual(feedback.timeToResponseMs, timeMs)
    }

    // MARK: - Edge Cases

    func testEmptyContentModification() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "")

        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "")
    }

    func testWhitespaceOnlyContent() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "   ")

        // Whitespace-only should be considered different from original
        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "   ")
    }

    func testNewlineInContent() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: "Thanks for the\nupdate!")

        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, "Thanks for the\nupdate!")
    }

    func testVeryLongModification() {
        let selected = SelectedSuggestion(suggestion: sampleSuggestion, timeToResponseMs: 100)
        let longText = String(repeating: "Thanks for the update! ", count: 100)
        let (wasModified, modifiedContent) = selected.detectModification(in: longText)

        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, longText)
    }

    func testMultipleSuggestions() {
        let suggestion1 = SmartReplySuggestion(
            id: UUID(),
            type: "quick-reply",
            content: "Yes",
            confidence: 0.95,
            position: 0,
            context: "",
            timestamp: Date()
        )

        let suggestion2 = SmartReplySuggestion(
            id: UUID(),
            type: "quick-reply",
            content: "No",
            confidence: 0.85,
            position: 1,
            context: "",
            timestamp: Date()
        )

        let selected1 = SelectedSuggestion(suggestion: suggestion1, timeToResponseMs: 100)
        let selected2 = SelectedSuggestion(suggestion: suggestion2, timeToResponseMs: 200)

        XCTAssertEqual(selected1.originalContent, "Yes")
        XCTAssertEqual(selected2.originalContent, "No")
        XCTAssertNotEqual(selected1.suggestion.id, selected2.suggestion.id)
    }

    // MARK: - Integration Tests

    func testEndToEndModificationFlow() {
        // 1. User selects suggestion
        let suggestion = SmartReplySuggestion(
            id: UUID(),
            type: "contextual",
            content: "I'll check and get back to you",
            confidence: 0.9,
            position: 0,
            context: "",
            timestamp: Date()
        )

        let selected = SelectedSuggestion(suggestion: suggestion, timeToResponseMs: 2500)

        // 2. User modifies the content
        let modifiedText = "I'll check and get back to you tomorrow"

        // 3. Detect modification
        let (wasModified, modifiedContent) = selected.detectModification(in: modifiedText)
        XCTAssertTrue(wasModified)
        XCTAssertEqual(modifiedContent, modifiedText)

        // 4. Create feedback
        let feedback = selected.createFeedback(finalContent: modifiedText, accepted: true)

        // 5. Verify feedback
        XCTAssertEqual(feedback.suggestionId, suggestion.id)
        XCTAssertTrue(feedback.accepted)
        XCTAssertEqual(feedback.modifiedContent, modifiedText)
        XCTAssertEqual(feedback.timeToResponseMs, 2500)
    }

    func testEndToEndUnmodifiedFlow() {
        // 1. User selects suggestion
        let suggestion = SmartReplySuggestion(
            id: UUID(),
            type: "quick-reply",
            content: "Sounds good!",
            confidence: 0.95,
            position: 0,
            context: "",
            timestamp: Date()
        )

        let selected = SelectedSuggestion(suggestion: suggestion, timeToResponseMs: 500)

        // 2. User sends without modification
        let finalText = "Sounds good!"

        // 3. Detect modification
        let (wasModified, modifiedContent) = selected.detectModification(in: finalText)
        XCTAssertFalse(wasModified)
        XCTAssertNil(modifiedContent)

        // 4. Create feedback
        let feedback = selected.createFeedback(finalContent: finalText, accepted: true)

        // 5. Verify feedback
        XCTAssertEqual(feedback.suggestionId, suggestion.id)
        XCTAssertTrue(feedback.accepted)
        XCTAssertNil(feedback.modifiedContent)
        XCTAssertEqual(feedback.timeToResponseMs, 500)
    }
}
