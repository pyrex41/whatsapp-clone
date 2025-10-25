//
//  UsageQuotaView.swift
//  GlobalBridge
//
//  Created by Claude Code on 10/24/25.
//

import SwiftUI

/// Displays usage quotas with progress indicators and upgrade prompts
/// Shows current usage vs. limits with visual feedback for different threshold levels
struct UsageQuotaView: View {
    // MARK: - Properties

    let quotaType: QuotaType
    let current: Int
    let limit: Int?
    let tier: FeatureFlags.UserTier
    let compact: Bool

    @State private var showUpgradePrompt = false

    // MARK: - Quota Types

    enum QuotaType {
        case groupMembers
        case fileSize
        case storage
        case callParticipants
        case messageHistory

        var icon: String {
            switch self {
            case .groupMembers: return "person.3.fill"
            case .fileSize: return "doc.fill"
            case .storage: return "externaldrive.fill"
            case .callParticipants: return "video.fill"
            case .messageHistory: return "clock.fill"
            }
        }

        var title: String {
            switch self {
            case .groupMembers: return "Group Members"
            case .fileSize: return "File Size"
            case .storage: return "Storage"
            case .callParticipants: return "Call Participants"
            case .messageHistory: return "Message History"
            }
        }

        func formatValue(_ value: Int) -> String {
            switch self {
            case .groupMembers, .callParticipants:
                return "\(value)"
            case .fileSize:
                return "\(value) MB"
            case .storage:
                return "\(value) GB"
            case .messageHistory:
                return "\(value) days"
            }
        }
    }

    // MARK: - Initialization

    init(
        quotaType: QuotaType,
        current: Int,
        limit: Int?,
        tier: FeatureFlags.UserTier,
        compact: Bool = false
    ) {
        self.quotaType = quotaType
        self.current = current
        self.limit = limit
        self.tier = tier
        self.compact = compact
    }

    // MARK: - Body

    var body: some View {
        if compact {
            compactView
        } else {
            fullView
        }
    }

    // MARK: - View Components

    private var compactView: some View {
        HStack(spacing: 8) {
            Image(systemName: quotaType.icon)
                .foregroundColor(usageColor)

            if let limit = limit {
                Text("\(current)/\(limit)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            } else {
                Text("Unlimited")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(usageColor.opacity(0.1))
        .foregroundColor(usageColor)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var fullView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: quotaType.icon)
                    .font(.title3)
                    .foregroundColor(usageColor)

                Text(quotaType.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if isApproachingLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            // Usage stats
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(quotaType.formatValue(current))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(usageColor)
                    .monospacedDigit()

                if let limit = limit {
                    Text("of \(quotaType.formatValue(limit))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("(Unlimited)")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }

            // Progress bar
            if let limit = limit {
                ProgressView(value: Double(current), total: Double(limit))
                    .tint(usageColor)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                // Usage percentage
                Text(usagePercentageText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Warning or upgrade prompt
            if isApproachingLimit {
                warningMessage
            } else if tier == .free && limit != nil {
                upgradePromptButton
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .sheet(isPresented: $showUpgradePrompt) {
            upgradeSheet
        }
    }

    private var warningMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")

            Text(warningText)
                .font(.caption)
                .lineLimit(2)

            Spacer()
        }
        .foregroundColor(.orange)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }

    private var upgradePromptButton: some View {
        Button(action: { showUpgradePrompt = true }) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                Text("Upgrade for more")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            )
        }
    }

    private var upgradeSheet: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "star.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)

                Text("Upgrade to Pro")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Get more \(quotaType.title.lowercased()) and unlock premium features")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
                    upgradeFeature("Higher limits", icon: "arrow.up.circle.fill")
                    upgradeFeature("Priority support", icon: "headphones")
                    upgradeFeature("Advanced features", icon: "star.fill")
                }
                .padding()

                Button(action: {
                    // TODO: Implement upgrade flow
                    showUpgradePrompt = false
                }) {
                    Text("Upgrade Now")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Button("Maybe Later") {
                    showUpgradePrompt = false
                }
                .foregroundColor(.secondary)

                Spacer()
            }
            .padding()
            .navigationBarItems(trailing: Button("Close") {
                showUpgradePrompt = false
            })
        }
    }

    private func upgradeFeature(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.purple)
                .frame(width: 24)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Computed Properties

    private var usagePercentage: Double {
        guard let limit = limit, limit > 0 else { return 0 }
        return Double(current) / Double(limit)
    }

    private var usagePercentageText: String {
        guard limit != nil else { return "" }
        let percentage = Int(usagePercentage * 100)
        return "\(percentage)% used"
    }

    private var isApproachingLimit: Bool {
        guard limit != nil else { return false }
        return usagePercentage >= 0.8
    }

    private var isAtLimit: Bool {
        guard let limit = limit else { return false }
        return current >= limit
    }

    private var usageColor: Color {
        guard limit != nil else { return .green }

        if isAtLimit {
            return .red
        } else if isApproachingLimit {
            return .orange
        } else if usagePercentage >= 0.5 {
            return .yellow
        } else {
            return .green
        }
    }

    private var warningText: String {
        if isAtLimit {
            return "You've reached your limit. Upgrade to continue."
        } else {
            return "You're approaching your limit. Consider upgrading."
        }
    }

    private var accessibilityText: String {
        if let limit = limit {
            let percentage = Int(usagePercentage * 100)
            return "\(quotaType.title), \(quotaType.formatValue(current)) of \(quotaType.formatValue(limit)) used, \(percentage) percent"
        } else {
            return "\(quotaType.title), \(quotaType.formatValue(current)), unlimited"
        }
    }
}

// MARK: - Preview Provider

#Preview("Compact Views") {
    VStack(spacing: 16) {
        UsageQuotaView(
            quotaType: .groupMembers,
            current: 45,
            limit: 100,
            tier: .free,
            compact: true
        )

        UsageQuotaView(
            quotaType: .storage,
            current: 8,
            limit: 10,
            tier: .free,
            compact: true
        )

        UsageQuotaView(
            quotaType: .messageHistory,
            current: 30,
            limit: nil,
            tier: .enterprise,
            compact: true
        )
    }
    .padding()
}

#Preview("Full Views - Different States") {
    ScrollView {
        VStack(spacing: 20) {
            // Low usage (green)
            UsageQuotaView(
                quotaType: .groupMembers,
                current: 23,
                limit: 100,
                tier: .free
            )

            // Medium usage (yellow)
            UsageQuotaView(
                quotaType: .storage,
                current: 6,
                limit: 10,
                tier: .free
            )

            // High usage (orange)
            UsageQuotaView(
                quotaType: .fileSize,
                current: 18,
                limit: 20,
                tier: .free
            )

            // At limit (red)
            UsageQuotaView(
                quotaType: .callParticipants,
                current: 5,
                limit: 5,
                tier: .free
            )

            // Unlimited (green)
            UsageQuotaView(
                quotaType: .storage,
                current: 150,
                limit: nil,
                tier: .enterprise
            )
        }
        .padding()
    }
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        UsageQuotaView(
            quotaType: .groupMembers,
            current: 45,
            limit: 100,
            tier: .free
        )

        UsageQuotaView(
            quotaType: .storage,
            current: 8,
            limit: 10,
            tier: .free
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Pro Tier") {
    VStack(spacing: 20) {
        UsageQuotaView(
            quotaType: .groupMembers,
            current: 85,
            limit: 250,
            tier: .pro
        )

        UsageQuotaView(
            quotaType: .fileSize,
            current: 45,
            limit: 100,
            tier: .pro
        )
    }
    .padding()
}
