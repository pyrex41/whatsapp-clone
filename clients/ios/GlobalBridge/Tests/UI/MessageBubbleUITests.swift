//
//  MessageBubbleUITests.swift
//  GlobalBridgeUITests
//
//  UI tests for MessageBubbleView translation flow
//

import XCTest

final class MessageBubbleUITests: XCTestCase {

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

    // MARK: - Translation Flow Tests

    func testTranslationButtonAppears() throws {
        // Navigate to chat with messages
        let chatView = app.otherElements["ChatView"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5))

        // Find message bubble
        let messageBubble = app.otherElements["MessageBubble-0"]
        XCTAssertTrue(messageBubble.exists)

        // Long press to show translation menu
        messageBubble.press(forDuration: 1.0)

        // Verify "Translate" button appears
        let translateButton = app.buttons["Translate"]
        XCTAssertTrue(translateButton.waitForExistence(timeout: 2))
    }

    func testTranslationToggle() throws {
        let messageBubble = app.otherElements["MessageBubble-0"]
        messageBubble.press(forDuration: 1.0)

        // Tap translate
        app.buttons["Translate"].tap()

        // Wait for translation to appear
        let translationOverlay = app.otherElements["TranslationOverlay"]
        XCTAssertTrue(translationOverlay.waitForExistence(timeout: 5))

        // Verify translation content exists
        XCTAssertTrue(app.staticTexts["Translation"].exists)

        // Toggle to hide translation
        let hideButton = app.buttons["Hide Translation"]
        hideButton.tap()

        XCTAssertFalse(translationOverlay.exists)
    }

    func testTranslationLoadingState() throws {
        let messageBubble = app.otherElements["MessageBubble-0"]
        messageBubble.press(forDuration: 1.0)
        app.buttons["Translate"].tap()

        // Verify loading indicator appears
        let loadingIndicator = app.activityIndicators.firstMatch
        XCTAssertTrue(loadingIndicator.exists)

        // Wait for translation to complete
        let translationOverlay = app.otherElements["TranslationOverlay"]
        XCTAssertTrue(translationOverlay.waitForExistence(timeout: 10))

        // Verify loading indicator disappears
        XCTAssertFalse(loadingIndicator.exists)
    }

    func testTranslationProviderBadge() throws {
        let messageBubble = app.otherElements["MessageBubble-0"]
        messageBubble.press(forDuration: 1.0)
        app.buttons["Translate"].tap()

        // Wait for translation
        let translationOverlay = app.otherElements["TranslationOverlay"]
        XCTAssertTrue(translationOverlay.waitForExistence(timeout: 5))

        // Verify provider badge exists
        let providerBadge = app.otherElements["TranslationProviderBadge"]
        XCTAssertTrue(providerBadge.exists)
    }

    func testCopyTranslation() throws {
        let messageBubble = app.otherElements["MessageBubble-0"]
        messageBubble.press(forDuration: 1.0)
        app.buttons["Translate"].tap()

        // Wait for translation
        let translationOverlay = app.otherElements["TranslationOverlay"]
        XCTAssertTrue(translationOverlay.waitForExistence(timeout: 5))

        // Tap copy button
        let copyButton = app.buttons["Copy Translation"]
        XCTAssertTrue(copyButton.exists)
        copyButton.tap()

        // Verify pasteboard (if possible in UI test)
        // Note: Pasteboard verification requires special entitlements
    }

    func testLanguageSelection() throws {
        let messageBubble = app.otherElements["MessageBubble-0"]
        messageBubble.press(forDuration: 1.0)

        // Tap "Choose Language..."
        let chooseLanguageButton = app.buttons["Choose Language..."]
        XCTAssertTrue(chooseLanguageButton.exists)
        chooseLanguageButton.tap()

        // Verify language picker appears
        let languagePicker = app.sheets.firstMatch
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 2))
    }

    func testReportBadTranslation() throws {
        let messageBubble = app.otherElements["MessageBubble-0"]

        // First translate the message
        messageBubble.press(forDuration: 1.0)
        app.buttons["Translate"].tap()

        // Wait for translation
        let translationOverlay = app.otherElements["TranslationOverlay"]
        XCTAssertTrue(translationOverlay.waitForExistence(timeout: 5))

        // Long press again to show menu with report option
        messageBubble.press(forDuration: 1.0)

        // Tap report button
        let reportButton = app.buttons["Report Bad Translation"]
        XCTAssertTrue(reportButton.exists)
        reportButton.tap()

        // Verify confirmation or feedback UI
        // (Implementation depends on actual report flow)
    }

    // MARK: - Accessibility Tests

    func testVoiceOverLabels() throws {
        let messageBubble = app.otherElements["MessageBubble-0"]

        // Verify accessibility label exists
        XCTAssertTrue(messageBubble.exists)
        XCTAssertFalse(messageBubble.label.isEmpty)

        // Long press and check translate button
        messageBubble.press(forDuration: 1.0)
        let translateButton = app.buttons["Translate"]
        XCTAssertFalse(translateButton.label.isEmpty)
    }

    func testDynamicTypeSupport() throws {
        // Test with different text sizes
        for textSize in ["XS", "S", "M", "L", "XL", "XXL", "XXXL"] {
            app.launchEnvironment["DYNAMIC_TYPE_SIZE"] = textSize
            app.launch()

            let messageBubble = app.otherElements["MessageBubble-0"]
            XCTAssertTrue(messageBubble.waitForExistence(timeout: 5))

            // Verify bubble is still visible and tappable
            XCTAssertTrue(messageBubble.isHittable)
        }
    }

    // MARK: - Error State Tests

    func testNetworkErrorState() throws {
        // Disable network
        app.launchArguments.append("DISABLE_NETWORK")
        app.launch()

        let messageBubble = app.otherElements["MessageBubble-0"]
        messageBubble.press(forDuration: 1.0)
        app.buttons["Translate"].tap()

        // Verify error message appears
        let errorAlert = app.alerts.firstMatch
        XCTAssertTrue(errorAlert.waitForExistence(timeout: 5))

        // Verify retry button exists
        let retryButton = app.buttons["Retry"]
        XCTAssertTrue(retryButton.exists)
    }

    func testQuotaExceededState() throws {
        // Mock quota exceeded
        app.launchArguments.append("QUOTA_EXCEEDED")
        app.launch()

        let messageBubble = app.otherElements["MessageBubble-0"]
        messageBubble.press(forDuration: 1.0)
        app.buttons["Translate"].tap()

        // Verify upgrade prompt appears
        let upgradeAlert = app.alerts["Quota Exceeded"]
        XCTAssertTrue(upgradeAlert.waitForExistence(timeout: 5))
    }

    // MARK: - Performance Tests

    func testScrollPerformance() throws {
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
            let chatView = app.scrollViews.firstMatch
            chatView.swipeUp(velocity: .fast)
            chatView.swipeDown(velocity: .fast)
        }
    }

    func testTranslationAnimationPerformance() throws {
        measure(metrics: [XCTOSSignpostMetric.animationMetric]) {
            let messageBubble = app.otherElements["MessageBubble-0"]
            messageBubble.press(forDuration: 1.0)
            app.buttons["Translate"].tap()

            let translationOverlay = app.otherElements["TranslationOverlay"]
            _ = translationOverlay.waitForExistence(timeout: 5)

            app.buttons["Hide Translation"].tap()
        }
    }
}
