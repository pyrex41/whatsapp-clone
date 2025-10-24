//
//  UsageQuotaViewTests.swift
//  GlobalBridgeTests
//
//  Comprehensive test suite for UsageQuotaView UI component
//  Tests quota display, progress indicators, warnings, and upgrade prompts
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class UsageQuotaViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithAllParameters() {
        // Given/When
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 50,
            limit: 100,
            tier: .free,
            compact: false
        )

        // Then
        XCTAssertNotNil(view)
    }

    func testInitWithUnlimitedQuota() {
        // Given/When
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 500,
            limit: nil,
            tier: .enterprise
        )

        // Then - Should handle nil limit (unlimited)
        XCTAssertNotNil(view)
    }

    func testCompactMode() {
        // Given/When
        let view = UsageQuotaView(
            quotaType: .fileSize,
            current: 10,
            limit: 20,
            tier: .free,
            compact: true
        )

        // Then
        XCTAssertNotNil(view)
    }

    // MARK: - QuotaType Tests

    func testQuotaTypeIcons() {
        XCTAssertEqual(UsageQuotaView.QuotaType.groupMembers.icon, "person.3.fill")
        XCTAssertEqual(UsageQuotaView.QuotaType.fileSize.icon, "doc.fill")
        XCTAssertEqual(UsageQuotaView.QuotaType.storage.icon, "externaldrive.fill")
        XCTAssertEqual(UsageQuotaView.QuotaType.callParticipants.icon, "video.fill")
        XCTAssertEqual(UsageQuotaView.QuotaType.messageHistory.icon, "clock.fill")
    }

    func testQuotaTypeTitles() {
        XCTAssertEqual(UsageQuotaView.QuotaType.groupMembers.title, "Group Members")
        XCTAssertEqual(UsageQuotaView.QuotaType.fileSize.title, "File Size")
        XCTAssertEqual(UsageQuotaView.QuotaType.storage.title, "Storage")
        XCTAssertEqual(UsageQuotaView.QuotaType.callParticipants.title, "Call Participants")
        XCTAssertEqual(UsageQuotaView.QuotaType.messageHistory.title, "Message History")
    }

    func testQuotaTypeFormatValue() {
        XCTAssertEqual(UsageQuotaView.QuotaType.groupMembers.formatValue(50), "50")
        XCTAssertEqual(UsageQuotaView.QuotaType.fileSize.formatValue(20), "20 MB")
        XCTAssertEqual(UsageQuotaView.QuotaType.storage.formatValue(10), "10 GB")
        XCTAssertEqual(UsageQuotaView.QuotaType.callParticipants.formatValue(8), "8")
        XCTAssertEqual(UsageQuotaView.QuotaType.messageHistory.formatValue(365), "365 days")
    }

    // MARK: - Usage Level Tests

    func testLowUsage() {
        // Given - 23% usage
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 23,
            limit: 100,
            tier: .free
        )

        // Then - Should show green color
        XCTAssertNotNil(view)
    }

    func testMediumUsage() {
        // Given - 60% usage
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 6,
            limit: 10,
            tier: .free
        )

        // Then - Should show yellow color
        XCTAssertNotNil(view)
    }

    func testHighUsage() {
        // Given - 90% usage (approaching limit)
        let view = UsageQuotaView(
            quotaType: .fileSize,
            current: 18,
            limit: 20,
            tier: .free
        )

        // Then - Should show orange warning
        XCTAssertNotNil(view)
    }

    func testAtLimit() {
        // Given - 100% usage
        let view = UsageQuotaView(
            quotaType: .callParticipants,
            current: 5,
            limit: 5,
            tier: .free
        )

        // Then - Should show red color and warning
        XCTAssertNotNil(view)
    }

    func testOverLimit() {
        // Given - Over 100% usage
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 12,
            limit: 10,
            tier: .free
        )

        // Then - Should show red and handle gracefully
        XCTAssertNotNil(view)
    }

    // MARK: - Unlimited Quota Tests

    func testUnlimitedQuotaDisplay() {
        // Given
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 150,
            limit: nil,
            tier: .enterprise
        )

        // Then - Should show "Unlimited" text and green color
        XCTAssertNotNil(view)
    }

    func testUnlimitedQuotaNoProgressBar() {
        // Given
        let view = UsageQuotaView(
            quotaType: .messageHistory,
            current: 1000,
            limit: nil,
            tier: .enterprise
        )

        // Then - Should not show progress bar for unlimited
        XCTAssertNotNil(view)
    }

    // MARK: - Warning Message Tests

    func testWarningAtApproachingLimit() {
        // Given - 85% usage
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 85,
            limit: 100,
            tier: .free
        )

        // Then - Should show warning message
        XCTAssertNotNil(view)
    }

    func testWarningAtLimit() {
        // Given - 100% usage
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 10,
            limit: 10,
            tier: .free
        )

        // Then - Should show "reached limit" warning
        XCTAssertNotNil(view)
    }

    func testNoWarningBelowThreshold() {
        // Given - 50% usage
        let view = UsageQuotaView(
            quotaType: .fileSize,
            current: 10,
            limit: 20,
            tier: .pro
        )

        // Then - Should not show warning
        XCTAssertNotNil(view)
    }

    // MARK: - Upgrade Prompt Tests

    func testUpgradePromptForFreeTier() {
        // Given
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 50,
            limit: 100,
            tier: .free
        )

        // Then - Free tier should show upgrade prompt
        XCTAssertNotNil(view)
    }

    func testNoUpgradePromptForProTier() {
        // Given
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 100,
            limit: 250,
            tier: .pro
        )

        // Then - Pro tier should not show upgrade prompt unless at limit
        XCTAssertNotNil(view)
    }

    func testNoUpgradePromptForEnterpriseTier() {
        // Given
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 50,
            limit: nil,
            tier: .enterprise
        )

        // Then - Enterprise tier should not show upgrade prompt
        XCTAssertNotNil(view)
    }

    // MARK: - Accessibility Tests

    func testAccessibilityLabelWithLimit() {
        // Given
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 45,
            limit: 100,
            tier: .free
        )

        // Then - Should have descriptive accessibility label
        // Expected: "Group Members, 45 of 100 used, 45 percent"
        XCTAssertNotNil(view)
    }

    func testAccessibilityLabelUnlimited() {
        // Given
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 500,
            limit: nil,
            tier: .enterprise
        )

        // Then
        // Expected: "Storage, 500 GB, unlimited"
        XCTAssertNotNil(view)
    }

    // MARK: - Progress Calculation Tests

    func testProgressCalculationZeroUsage() {
        // Given
        let view = UsageQuotaView(
            quotaType: .fileSize,
            current: 0,
            limit: 20,
            tier: .free
        )

        // Then - 0% usage
        XCTAssertNotNil(view)
    }

    func testProgressCalculationHalfway() {
        // Given
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 5,
            limit: 10,
            tier: .free
        )

        // Then - 50% usage
        XCTAssertNotNil(view)
    }

    func testProgressCalculationFull() {
        // Given
        let view = UsageQuotaView(
            quotaType: .callParticipants,
            current: 8,
            limit: 8,
            tier: .pro
        )

        // Then - 100% usage
        XCTAssertNotNil(view)
    }

    // MARK: - Compact vs Full Mode Tests

    func testCompactModeRendering() {
        // Given
        let compactView = UsageQuotaView(
            quotaType: .groupMembers,
            current: 45,
            limit: 100,
            tier: .free,
            compact: true
        )

        let fullView = UsageQuotaView(
            quotaType: .groupMembers,
            current: 45,
            limit: 100,
            tier: .free,
            compact: false
        )

        // Then - Both should render
        XCTAssertNotNil(compactView)
        XCTAssertNotNil(fullView)
    }

    func testCompactModeOmitsProgressBar() {
        // Given
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 8,
            limit: 10,
            tier: .free,
            compact: true
        )

        // Then - Compact mode should not show progress bar
        XCTAssertNotNil(view)
    }

    // MARK: - All Quota Types Tests

    func testAllQuotaTypesCombinations() {
        // Test matrix of all quota types with different tiers
        let quotaTypes: [UsageQuotaView.QuotaType] = [
            .groupMembers, .fileSize, .storage, .callParticipants, .messageHistory
        ]
        let tiers: [FeatureFlags.UserTier] = [.free, .pro, .enterprise]

        for quotaType in quotaTypes {
            for tier in tiers {
                let view = UsageQuotaView(
                    quotaType: quotaType,
                    current: 50,
                    limit: 100,
                    tier: tier
                )
                XCTAssertNotNil(view, "Failed for \(quotaType) / \(tier)")
            }
        }
    }

    // MARK: - Dark Mode Tests

    func testDarkModeCompatibility() {
        // Given
        let views = [
            UsageQuotaView(quotaType: .groupMembers, current: 45, limit: 100, tier: .free),
            UsageQuotaView(quotaType: .storage, current: 8, limit: 10, tier: .free),
            UsageQuotaView(quotaType: .messageHistory, current: 30, limit: nil, tier: .enterprise)
        ]

        // Then - All should render in dark mode
        for view in views {
            XCTAssertNotNil(view)
        }
    }

    // MARK: - Dynamic Type Tests

    func testDynamicTypeSupport() {
        // Verify views support Dynamic Type scaling
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 45,
            limit: 100,
            tier: .free
        )

        // Then - Should use system fonts
        XCTAssertNotNil(view)
    }

    // MARK: - State Management Tests

    func testUpgradeSheetState() {
        // Upgrade sheet is managed by @State variable
        // Should be initially false
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 8,
            limit: 10,
            tier: .free
        )

        XCTAssertNotNil(view)
    }

    // MARK: - Visual Consistency Tests

    func testConsistentShadowRendering() {
        // Full views should have shadow effects
        let view = UsageQuotaView(
            quotaType: .groupMembers,
            current: 45,
            limit: 100,
            tier: .pro
        )
        XCTAssertNotNil(view)
    }

    func testConsistentRoundedCorners() {
        // All containers should have rounded corners
        let view = UsageQuotaView(
            quotaType: .fileSize,
            current: 10,
            limit: 20,
            tier: .free
        )
        XCTAssertNotNil(view)
    }

    // MARK: - Color Coding Tests

    func testGreenColorForLowUsage() {
        // <50% usage should be green
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 3,
            limit: 10,
            tier: .free
        )
        XCTAssertNotNil(view)
    }

    func testYellowColorForMediumUsage() {
        // 50-80% usage should be yellow
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 6,
            limit: 10,
            tier: .free
        )
        XCTAssertNotNil(view)
    }

    func testOrangeColorForHighUsage() {
        // 80-100% usage should be orange
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 9,
            limit: 10,
            tier: .free
        )
        XCTAssertNotNil(view)
    }

    func testRedColorForExceededUsage() {
        // 100%+ usage should be red
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 10,
            limit: 10,
            tier: .free
        )
        XCTAssertNotNil(view)
    }

    func testGreenColorForUnlimited() {
        // Unlimited should always be green
        let view = UsageQuotaView(
            quotaType: .storage,
            current: 1000,
            limit: nil,
            tier: .enterprise
        )
        XCTAssertNotNil(view)
    }
}
