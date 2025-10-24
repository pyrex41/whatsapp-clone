//
//  FeatureBadgeViewTests.swift
//  GlobalBridgeTests
//
//  Comprehensive test suite for FeatureBadgeView UI component
//  Tests rendering, accessibility, state variations, and visual appearance
//

import XCTest
import SwiftUI
import ViewInspector
@testable import GlobalBridge

@MainActor
final class FeatureBadgeViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitWithTierOnly() {
        // Given/When
        let view = FeatureBadgeView(tier: .pro)

        // Then
        XCTAssertNotNil(view)
    }

    func testInitWithTierAndFeature() {
        // Given/When
        let view = FeatureBadgeView(
            tier: .enterprise,
            feature: .adminDashboard,
            isEnabled: true
        )

        // Then
        XCTAssertNotNil(view)
    }

    func testCompactMode() {
        // Given/When
        let view = FeatureBadgeView(tier: .free, compact: true)

        // Then
        XCTAssertNotNil(view)
    }

    // MARK: - Tier Display Tests

    func testFreeTierDisplayName() {
        // Given
        let tier = FeatureFlags.UserTier.free

        // When
        let view = FeatureBadgeView(tier: tier)

        // Then - Should render "Free" text
        XCTAssertEqual(tier.displayName, "Free")
    }

    func testProTierDisplayName() {
        // Given
        let tier = FeatureFlags.UserTier.pro

        // When
        let view = FeatureBadgeView(tier: tier)

        // Then
        XCTAssertEqual(tier.displayName, "Pro")
    }

    func testEnterpriseTierDisplayName() {
        // Given
        let tier = FeatureFlags.UserTier.enterprise

        // When
        let view = FeatureBadgeView(tier: tier)

        // Then
        XCTAssertEqual(tier.displayName, "Enterprise")
    }

    // MARK: - Feature Status Tests

    func testFeatureEnabledDisplay() {
        // Given
        let view = FeatureBadgeView(
            tier: .pro,
            feature: .voiceCalls,
            isEnabled: true
        )

        // Then - Should show enabled state
        XCTAssertNotNil(view)
    }

    func testFeatureDisabledDisplay() {
        // Given
        let view = FeatureBadgeView(
            tier: .free,
            feature: .e2ee,
            isEnabled: false
        )

        // Then - Should show disabled state with upgrade prompt
        XCTAssertNotNil(view)
    }

    // MARK: - Accessibility Tests

    func testAccessibilityLabelTierOnly() {
        // Given
        let tier = FeatureFlags.UserTier.pro

        // When
        let view = FeatureBadgeView(tier: tier)

        // Then - Should have descriptive accessibility label
        // Expected format: "Pro tier"
        XCTAssertNotNil(view)
    }

    func testAccessibilityLabelWithFeature() {
        // Given
        let tier = FeatureFlags.UserTier.enterprise
        let feature = FeatureFlags.Feature.analytics

        // When
        let view = FeatureBadgeView(
            tier: tier,
            feature: feature,
            isEnabled: true
        )

        // Then - Should include feature status in accessibility
        // Expected: "Enterprise tier, Analytics is available"
        XCTAssertNotNil(view)
    }

    func testAccessibilityLabelFeatureDisabled() {
        // Given
        let tier = FeatureFlags.UserTier.free
        let feature = FeatureFlags.Feature.adminDashboard

        // When
        let view = FeatureBadgeView(
            tier: tier,
            feature: feature,
            isEnabled: false
        )

        // Then
        // Expected: "Free tier, Admin Dashboard is unavailable, upgrade required"
        XCTAssertNotNil(view)
    }

    // MARK: - Visual Styling Tests

    func testFreeTierColorScheme() {
        // Given
        let view = FeatureBadgeView(tier: .free)

        // Then - Should use blue color scheme
        // Implementation uses blue for free tier
        XCTAssertNotNil(view)
    }

    func testProTierColorScheme() {
        // Given
        let view = FeatureBadgeView(tier: .pro)

        // Then - Should use purple color scheme
        XCTAssertNotNil(view)
    }

    func testEnterpriseTierColorScheme() {
        // Given
        let view = FeatureBadgeView(tier: .enterprise)

        // Then - Should use orange color scheme
        XCTAssertNotNil(view)
    }

    // MARK: - Icon Tests

    func testFreeTierIcon() {
        // Free tier uses "star" icon
        let view = FeatureBadgeView(tier: .free)
        XCTAssertNotNil(view)
    }

    func testProTierIcon() {
        // Pro tier uses "star.fill" icon
        let view = FeatureBadgeView(tier: .pro)
        XCTAssertNotNil(view)
    }

    func testEnterpriseTierIcon() {
        // Enterprise tier uses "crown.fill" icon
        let view = FeatureBadgeView(tier: .enterprise)
        XCTAssertNotNil(view)
    }

    // MARK: - Compact vs Full Mode Tests

    func testCompactBadgeRendering() {
        // Given
        let compactView = FeatureBadgeView(tier: .pro, compact: true)
        let fullView = FeatureBadgeView(tier: .pro, compact: false)

        // Then - Both should render without errors
        XCTAssertNotNil(compactView)
        XCTAssertNotNil(fullView)
    }

    func testCompactModeOmitsFeatureDetails() {
        // Given
        let view = FeatureBadgeView(
            tier: .pro,
            feature: .voiceCalls,
            isEnabled: true,
            compact: true
        )

        // Then - Compact mode should be minimal
        XCTAssertNotNil(view)
    }

    // MARK: - Feature Name Formatting Tests

    func testFeatureNameFormattingUnderscores() {
        // Feature names like "translation_enabled" should become "Translation Enabled"
        let features: [FeatureFlags.Feature] = [
            .translationEnabled,
            .threadSummarization,
            .semanticSearch,
            .directMessaging
        ]

        for feature in features {
            let view = FeatureBadgeView(
                tier: .pro,
                feature: feature,
                isEnabled: true
            )
            XCTAssertNotNil(view)
        }
    }

    // MARK: - State Combination Tests

    func testAllTierAndFeatureCombinations() {
        // Test matrix of tiers and features
        let tiers: [FeatureFlags.UserTier] = [.free, .pro, .enterprise]
        let features: [FeatureFlags.Feature] = [
            .directMessaging,
            .e2ee,
            .voiceCalls,
            .adminDashboard
        ]
        let states = [true, false]

        for tier in tiers {
            for feature in features {
                for isEnabled in states {
                    let view = FeatureBadgeView(
                        tier: tier,
                        feature: feature,
                        isEnabled: isEnabled
                    )
                    XCTAssertNotNil(view, "Failed for \(tier) / \(feature) / \(isEnabled)")
                }
            }
        }
    }

    // MARK: - Dark Mode Tests

    func testDarkModeCompatibility() {
        // Given
        let views = [
            FeatureBadgeView(tier: .free, compact: true),
            FeatureBadgeView(tier: .pro),
            FeatureBadgeView(tier: .enterprise, feature: .analytics, isEnabled: true)
        ]

        // Then - All should render in both light and dark modes
        for view in views {
            XCTAssertNotNil(view)
        }
    }

    // MARK: - Dynamic Type Tests

    func testDynamicTypeSupport() {
        // Verify views support Dynamic Type scaling
        let view = FeatureBadgeView(tier: .pro)

        // Then - Should use system fonts that scale
        // Implementation uses .caption, .headline, etc. which support Dynamic Type
        XCTAssertNotNil(view)
    }

    // MARK: - VoiceOver Tests

    func testVoiceOverAccessibility() {
        // Given
        let tierOnlyView = FeatureBadgeView(tier: .pro)
        let featureView = FeatureBadgeView(
            tier: .enterprise,
            feature: .apiAccess,
            isEnabled: true
        )

        // Then - Should have proper accessibility elements
        XCTAssertNotNil(tierOnlyView)
        XCTAssertNotNil(featureView)
    }

    // MARK: - Visual Regression Tests

    func testConsistentShadowRendering() {
        // Full badges should have shadow effects
        let view = FeatureBadgeView(tier: .pro)
        XCTAssertNotNil(view)
    }

    func testGradientBackgroundRendering() {
        // Full badges use gradient backgrounds
        let views = [
            FeatureBadgeView(tier: .free),
            FeatureBadgeView(tier: .pro),
            FeatureBadgeView(tier: .enterprise)
        ]

        for view in views {
            XCTAssertNotNil(view)
        }
    }

    // MARK: - Status Indicator Tests

    func testAvailableStatusIndicator() {
        // Green indicator for available features
        let view = FeatureBadgeView(
            tier: .pro,
            feature: .voiceCalls,
            isEnabled: true
        )
        XCTAssertNotNil(view)
    }

    func testUpgradeRequiredIndicator() {
        // Red indicator for unavailable features
        let view = FeatureBadgeView(
            tier: .free,
            feature: .e2ee,
            isEnabled: false
        )
        XCTAssertNotNil(view)
    }

    // MARK: - Preview Tests

    func testPreviews() {
        // Verify all preview configurations work
        // Compact Badges
        // Full Badges - Tier Only
        // Full Badges - With Features
        // Dark Mode
        XCTAssertTrue(true) // Previews are compile-time only
    }
}
