//
//  FeatureBadgeView.swift
//  GlobalBridge
//
//  Created by Claude Code on 10/24/25.
//

import SwiftUI

/// Displays tier badge and feature availability status
/// Shows "Free", "Pro", or "Enterprise" with appropriate styling
struct FeatureBadgeView: View {
    // MARK: - Properties

    let tier: FeatureFlags.UserTier
    let isFeatureEnabled: Bool
    let feature: FeatureFlags.Feature?
    let compact: Bool

    // MARK: - Initialization

    /// Create a badge showing only the tier
    init(tier: FeatureFlags.UserTier, compact: Bool = false) {
        self.tier = tier
        self.isFeatureEnabled = true
        self.feature = nil
        self.compact = compact
    }

    /// Create a badge showing tier and specific feature status
    init(tier: FeatureFlags.UserTier, feature: FeatureFlags.Feature, isEnabled: Bool, compact: Bool = false) {
        self.tier = tier
        self.feature = feature
        self.isFeatureEnabled = isEnabled
        self.compact = compact
    }

    // MARK: - Body

    var body: some View {
        if compact {
            compactBadge
        } else {
            fullBadge
        }
    }

    // MARK: - View Components

    private var compactBadge: some View {
        HStack(spacing: 4) {
            tierIcon

            Text(tier.displayName)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tierColor.opacity(0.15))
        .foregroundColor(tierColor)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var fullBadge: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tierIcon
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName)
                        .font(.headline)
                        .fontWeight(.bold)

                    if let feature = feature {
                        Text(featureStatusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(tierGradient)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: tierColor.opacity(0.3), radius: 4, x: 0, y: 2)

            if let feature = feature {
                featureStatusIndicator
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var tierIcon: some View {
        Group {
            switch tier {
            case .free:
                Image(systemName: "star")
            case .pro:
                Image(systemName: "star.fill")
            case .enterprise:
                Image(systemName: "crown.fill")
            }
        }
    }

    private var featureStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isFeatureEnabled ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isFeatureEnabled ? "Available" : "Upgrade Required")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isFeatureEnabled ? .green : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }

    // MARK: - Computed Properties

    private var tierColor: Color {
        switch tier {
        case .free:
            return Color.blue
        case .pro:
            return Color.purple
        case .enterprise:
            return Color.orange
        }
    }

    private var tierGradient: LinearGradient {
        switch tier {
        case .free:
            return LinearGradient(
                colors: [Color.blue, Color.blue.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pro:
            return LinearGradient(
                colors: [Color.purple, Color.purple.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .enterprise:
            return LinearGradient(
                colors: [Color.orange, Color.orange.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var featureStatusText: String {
        guard let feature = feature else { return "" }
        return isFeatureEnabled ? "\(formatFeatureName(feature)) enabled" : "\(formatFeatureName(feature)) requires upgrade"
    }

    private var accessibilityText: String {
        if let feature = feature {
            return "\(tier.displayName) tier, \(formatFeatureName(feature)) is \(isFeatureEnabled ? "available" : "unavailable, upgrade required")"
        } else {
            return "\(tier.displayName) tier"
        }
    }

    private func formatFeatureName(_ feature: FeatureFlags.Feature) -> String {
        feature.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Preview Provider

#Preview("Compact Badges") {
    VStack(spacing: 16) {
        FeatureBadgeView(tier: .free, compact: true)
        FeatureBadgeView(tier: .pro, compact: true)
        FeatureBadgeView(tier: .enterprise, compact: true)
    }
    .padding()
}

#Preview("Full Badges - Tier Only") {
    VStack(spacing: 20) {
        FeatureBadgeView(tier: .free)
        FeatureBadgeView(tier: .pro)
        FeatureBadgeView(tier: .enterprise)
    }
    .padding()
}

#Preview("Full Badges - With Features") {
    ScrollView {
        VStack(spacing: 20) {
            FeatureBadgeView(
                tier: .free,
                feature: .directMessaging,
                isEnabled: true
            )

            FeatureBadgeView(
                tier: .free,
                feature: .e2ee,
                isEnabled: false
            )

            FeatureBadgeView(
                tier: .pro,
                feature: .voiceCalls,
                isEnabled: true
            )

            FeatureBadgeView(
                tier: .pro,
                feature: .adminDashboard,
                isEnabled: false
            )

            FeatureBadgeView(
                tier: .enterprise,
                feature: .analytics,
                isEnabled: true
            )
        }
        .padding()
    }
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        FeatureBadgeView(tier: .free, compact: true)
        FeatureBadgeView(tier: .pro)
        FeatureBadgeView(
            tier: .enterprise,
            feature: .apiAccess,
            isEnabled: true
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}
