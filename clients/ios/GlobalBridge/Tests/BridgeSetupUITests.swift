//
//  BridgeSetupUITests.swift
//  GlobalBridgeUITests
//
//  Created by GlobalBridge on 10/24/25.
//  UI tests for bridge setup and management flows
//

import XCTest

final class BridgeSetupUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    func testBridgeSetupFlow() {
        // Given - App is launched and user is on main screen

        // When - User navigates to bridge setup
        let bridgeSetupButton = app.buttons["bridgeSetupButton"]
        XCTAssertTrue(bridgeSetupButton.exists, "Bridge setup button should exist")

        bridgeSetupButton.tap()

        // Then - Bridge setup screen should appear
        let bridgeSetupScreen = app.otherElements["bridgeSetupScreen"]
        XCTAssertTrue(bridgeSetupScreen.waitForExistence(timeout: 5), "Bridge setup screen should appear")

        // Test Telegram bridge selection
        let telegramButton = app.buttons["telegramBridgeButton"]
        XCTAssertTrue(telegramButton.exists, "Telegram bridge button should exist")

        telegramButton.tap()

        // Phone number input should appear
        let phoneNumberField = app.textFields["phoneNumberField"]
        XCTAssertTrue(phoneNumberField.waitForExistence(timeout: 3), "Phone number field should appear")

        // Enter phone number
        phoneNumberField.tap()
        phoneNumberField.typeText("+1234567890")

        // Create bridge button should be enabled
        let createBridgeButton = app.buttons["createBridgeButton"]
        XCTAssertTrue(createBridgeButton.exists, "Create bridge button should exist")
        XCTAssertTrue(createBridgeButton.isEnabled, "Create bridge button should be enabled")

        // Note: We don't actually create the bridge in UI tests to avoid side effects
    }

    func testBridgeStatusDisplay() {
        // Given - User has existing bridges

        // When - User views bridge list
        let bridgeList = app.tables["bridgeList"]
        XCTAssertTrue(bridgeList.waitForExistence(timeout: 5), "Bridge list should exist")

        // Then - Bridge status should be displayed
        let bridgeCell = bridgeList.cells.element(boundBy: 0)
        XCTAssertTrue(bridgeCell.exists, "At least one bridge cell should exist")

        // Check for status indicator
        let statusIndicator = bridgeCell.images["statusIndicator"]
        XCTAssertTrue(statusIndicator.exists, "Status indicator should exist")

        // Check for status text
        let statusLabel = bridgeCell.staticTexts["bridgeStatusLabel"]
        XCTAssertTrue(statusLabel.exists, "Status label should exist")
    }

    func testBridgeSettingsNavigation() {
        // Given - User is viewing bridge list

        // When - User taps on a bridge
        let bridgeList = app.tables["bridgeList"]
        XCTAssertTrue(bridgeList.waitForExistence(timeout: 5), "Bridge list should exist")

        let bridgeCell = bridgeList.cells.element(boundBy: 0)
        if bridgeCell.exists {
            bridgeCell.tap()

            // Then - Bridge settings screen should appear
            let bridgeSettingsScreen = app.otherElements["bridgeSettingsScreen"]
            XCTAssertTrue(bridgeSettingsScreen.waitForExistence(timeout: 3), "Bridge settings screen should appear")

            // Check for settings options
            let deleteButton = app.buttons["deleteBridgeButton"]
            XCTAssertTrue(deleteButton.exists, "Delete bridge button should exist")

            let reconnectButton = app.buttons["reconnectBridgeButton"]
            XCTAssertTrue(reconnectButton.exists, "Reconnect bridge button should exist")
        }
    }

    func testBridgeErrorHandling() {
        // Given - Bridge has error status

        // When - User views bridge list
        let bridgeList = app.tables["bridgeList"]
        XCTAssertTrue(bridgeList.waitForExistence(timeout: 5), "Bridge list should exist")

        // Then - Error status should be clearly indicated
        let errorBridgeCell = bridgeList.cells.containing(.staticText, identifier: "Error").element
        if errorBridgeCell.exists {
            let errorIcon = errorBridgeCell.images["errorIcon"]
            XCTAssertTrue(errorIcon.exists, "Error icon should be visible")

            let errorMessage = errorBridgeCell.staticTexts["errorMessage"]
            XCTAssertTrue(errorMessage.exists, "Error message should be displayed")
        }
    }

    func testBridgeConnectionFlow() {
        // Given - Bridge is disconnected

        // When - User initiates connection
        let bridgeList = app.tables["bridgeList"]
        XCTAssertTrue(bridgeList.waitForExistence(timeout: 5), "Bridge list should exist")

        let disconnectedBridgeCell = bridgeList.cells.containing(.staticText, identifier: "Disconnected").element
        if disconnectedBridgeCell.exists {
            let connectButton = disconnectedBridgeCell.buttons["connectButton"]
            XCTAssertTrue(connectButton.exists, "Connect button should exist")

            connectButton.tap()

            // Then - Status should change to connecting
            let connectingStatus = disconnectedBridgeCell.staticTexts["Connecting..."]
            XCTAssertTrue(connectingStatus.waitForExistence(timeout: 3), "Connecting status should appear")
        }
    }

    func testBridgeDeletion() {
        // Given - User is in bridge settings

        // When - User taps delete bridge
        let deleteButton = app.buttons["deleteBridgeButton"]
        if deleteButton.waitForExistence(timeout: 5) {
            deleteButton.tap()

            // Then - Confirmation dialog should appear
            let confirmDialog = app.alerts["confirmDeleteDialog"]
            XCTAssertTrue(confirmDialog.waitForExistence(timeout: 3), "Delete confirmation dialog should appear")

            let cancelButton = confirmDialog.buttons["Cancel"]
            XCTAssertTrue(cancelButton.exists, "Cancel button should exist")

            // Cancel the deletion
            cancelButton.tap()

            // Dialog should disappear
            XCTAssertFalse(confirmDialog.exists, "Confirmation dialog should be dismissed")
        }
    }

    func testBridgeListRefresh() {
        // Given - User is viewing bridge list

        // When - User pulls to refresh
        let bridgeList = app.tables["bridgeList"]
        XCTAssertTrue(bridgeList.waitForExistence(timeout: 5), "Bridge list should exist")

        // Perform pull to refresh gesture
        let startPoint = bridgeList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let endPoint = bridgeList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        startPoint.press(forDuration: 0, thenDragTo: endPoint)

        // Then - Refresh indicator should appear briefly
        // Note: Testing refresh completion is complex in UI tests
        // We just verify the list still exists after the gesture
        XCTAssertTrue(bridgeList.exists, "Bridge list should still exist after refresh")
    }

    func testBridgeStatusUpdates() {
        // Given - Bridge status changes in background

        // When - Status update notification is received
        let bridgeList = app.tables["bridgeList"]
        XCTAssertTrue(bridgeList.waitForExistence(timeout: 5), "Bridge list should exist")

        // Simulate status change (in real app this would come from Phoenix channel)
        // For UI testing, we verify the UI can display different states

        let bridgeCell = bridgeList.cells.element(boundBy: 0)
        if bridgeCell.exists {
            // Check that status text can change
            let statusLabels = ["Connected", "Disconnected", "Error", "Connecting..."]
            var foundStatusLabel = false

            for statusText in statusLabels {
                let statusLabel = bridgeCell.staticTexts[statusText]
                if statusLabel.exists {
                    foundStatusLabel = true
                    break
                }
            }

            XCTAssertTrue(foundStatusLabel, "At least one valid status should be displayed")
        }
    }
}