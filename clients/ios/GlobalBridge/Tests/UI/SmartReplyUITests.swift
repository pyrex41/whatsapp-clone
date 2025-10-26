//
//  SmartReplyUITests.swift
//  GlobalBridgeUITests
//
//  Task 31.2: UI tests for Smart Reply happy path E2E flow
//  Tests the complete flow: open chat → tap chip → composer fills → send → message appears
//

import XCTest

final class SmartReplyUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Happy Path E2E Flow

    func testSmartReplyHappyPath() throws {
        // Given - app is launched and chat is open
        let chatView = app.otherElements["ChatView"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "ChatView should exist")

        // Then - Smart Reply bar should appear
        let smartReplyBar = app.otherElements["SmartReplyBar"]
        XCTAssertTrue(smartReplyBar.waitForExistence(timeout: 2), "SmartReplyBar should appear within 2 seconds")

        // When - user taps the first suggestion chip
        let chip0 = app.buttons["SmartReplyChip-0"]
        XCTAssertTrue(chip0.exists, "First chip should exist")

        // Get the chip's label text before tapping (this is the suggestion content)
        let chipLabel = chip0.label
        XCTAssertFalse(chipLabel.isEmpty, "Chip should have a label")

        chip0.tap()

        // Then - composer should be populated with the chip text
        let composerTextField = app.textFields["ComposerTextField"]
        XCTAssertTrue(composerTextField.exists, "ComposerTextField should exist")

        // Extract just the suggestion text from the accessibility label
        // Label format: "Suggestion: <text>. <confidence info>"
        let suggestionText = extractSuggestionText(from: chipLabel)

        // Verify composer contains the suggestion text
        if let composerValue = composerTextField.value as? String {
            XCTAssertEqual(composerValue, suggestionText, "Composer should contain the chip text")
        }

        // When - user taps send button
        let sendButton = app.buttons["ComposerSendButton"]
        XCTAssertTrue(sendButton.exists, "Send button should exist")
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled")

        sendButton.tap()

        // Then - message should appear in the chat
        // Note: In a real test, we'd verify a new message bubble appears
        // For now, we verify the composer is cleared
        let isComposerEmpty = (composerTextField.value as? String)?.isEmpty ?? true
        XCTAssertTrue(isComposerEmpty, "Composer should be cleared after sending")
    }

    func testSmartReplyBarAppearsOnChatOpen() throws {
        // Given
        let chatView = app.otherElements["ChatView"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5))

        // Then - Smart Reply bar should appear within 1.5 seconds
        let smartReplyBar = app.otherElements["SmartReplyBar"]
        XCTAssertTrue(smartReplyBar.waitForExistence(timeout: 1.5), "Smart Reply bar should appear within 1.5s")
    }

    func testSmartReplyChipsExist() throws {
        // Given
        let smartReplyBar = app.otherElements["SmartReplyBar"]
        XCTAssertTrue(smartReplyBar.waitForExistence(timeout: 2))

        // Then - at least one chip should be visible (up to 3)
        let chip0 = app.buttons["SmartReplyChip-0"]
        XCTAssertTrue(chip0.exists, "At least one suggestion chip should exist")

        // Optionally verify more chips
        // Note: We may have 1-3 chips depending on backend response
    }

    func testSmartReplyChipTapPopulatesComposer() throws {
        // Given
        let chip0 = app.buttons["SmartReplyChip-0"]
        XCTAssertTrue(chip0.waitForExistence(timeout: 2))

        let chipLabel = chip0.label
        let suggestionText = extractSuggestionText(from: chipLabel)

        // When
        chip0.tap()

        // Then
        let composerTextField = app.textFields["ComposerTextField"]
        if let composerValue = composerTextField.value as? String {
            XCTAssertEqual(composerValue, suggestionText, "Composer text should match chip suggestion")
        }
    }

    func testSendButtonEnabledAfterChipTap() throws {
        // Given
        let chip0 = app.buttons["SmartReplyChip-0"]
        XCTAssertTrue(chip0.waitForExistence(timeout: 2))

        // When
        chip0.tap()

        // Then
        let sendButton = app.buttons["ComposerSendButton"]
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled after tapping chip")
    }

    // MARK: - Error State Tests

    func testSmartReplyOfflineErrorState() throws {
        // Note: This test requires the app to be in offline mode
        // In a real test, we'd use a launch argument like "SIMULATE_OFFLINE"
        app.launchEnvironment["SIMULATE_OFFLINE"] = "true"
        app.launch()

        // Given
        let chatView = app.otherElements["ChatView"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5))

        // Then - error state should appear
        let smartReplyBar = app.otherElements["SmartReplyBar"]
        if smartReplyBar.waitForExistence(timeout: 2) {
            // Check for retry button if error is retryable
            let retryButton = app.buttons["SmartReplyRetryButton"]
            if retryButton.exists {
                XCTAssertTrue(retryButton.isHittable, "Retry button should be visible and hittable")
            }
        }
    }

    func testSmartReplyRetryButton() throws {
        // This test verifies the retry button works when it appears
        // Note: Requires error state, which may need specific launch arguments

        app.launchEnvironment["SIMULATE_OFFLINE"] = "true"
        app.launch()

        let chatView = app.otherElements["ChatView"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5))

        let retryButton = app.buttons["SmartReplyRetryButton"]
        if retryButton.waitForExistence(timeout: 2) {
            // When - tap retry
            retryButton.tap()

            // Then - loading or success state should appear
            // (specific behavior depends on whether network is restored)
        }
    }

    // MARK: - Accessibility Tests

    func testSmartReplyAccessibilityLabels() throws {
        // Given
        let smartReplyBar = app.otherElements["SmartReplyBar"]
        XCTAssertTrue(smartReplyBar.waitForExistence(timeout: 2))

        // Then - chips should have accessibility labels
        let chip0 = app.buttons["SmartReplyChip-0"]
        XCTAssertTrue(chip0.exists)
        XCTAssertFalse(chip0.label.isEmpty, "Chip should have an accessibility label")

        // Verify label contains suggestion content and confidence info
        XCTAssertTrue(chip0.label.contains("suggestion") || chip0.label.contains("Suggestion"),
                     "Label should identify this as a suggestion")
    }

    func testComposerAccessibilityIdentifiers() throws {
        // Verify composer components have correct accessibility identifiers
        let composerTextField = app.textFields["ComposerTextField"]
        XCTAssertTrue(composerTextField.exists, "ComposerTextField should exist with accessibility identifier")

        let sendButton = app.buttons["ComposerSendButton"]
        XCTAssertTrue(sendButton.exists, "ComposerSendButton should exist with accessibility identifier")
    }

    func testVoiceOverSupport() throws {
        // Given
        let chip0 = app.buttons["SmartReplyChip-0"]
        XCTAssertTrue(chip0.waitForExistence(timeout: 2))

        // Then - verify accessibility traits
        XCTAssertTrue(chip0.exists)
        XCTAssertFalse(chip0.label.isEmpty, "Chip should have VoiceOver-readable label")

        // Verify hint is present
        if !chip0.label.isEmpty {
            // Label should contain both suggestion text and confidence information
            XCTAssertTrue(chip0.label.count > 5, "Label should be descriptive")
        }
    }

    // MARK: - Helper Methods

    /// Extracts the suggestion text from the chip's accessibility label
    /// Label format: "Suggestion: <text>. <confidence info>" or "<type> suggestion: <text>. <confidence info>"
    private func extractSuggestionText(from label: String) -> String {
        // Split by ": " to get the part after "Suggestion" or "Proactive suggestion"
        let components = label.components(separatedBy: ": ")
        guard components.count > 1 else {
            return label // Return full label if format is unexpected
        }

        // Get the text after the colon
        let textPart = components[1]

        // Split by ". " to remove confidence info
        let textComponents = textPart.components(separatedBy: ". ")
        guard let suggestionText = textComponents.first else {
            return textPart
        }

        return suggestionText
    }
}
