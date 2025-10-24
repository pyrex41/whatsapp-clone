//
//  FeatureFlagsExampleView.swift
//  GlobalBridge
//
//  Created by Claude Code on 10/24/25.
//  Example view demonstrating feature flags UI components
//

import SwiftUI

/// Example view demonstrating feature flags UI components in various contexts
struct FeatureFlagsExampleView: View {
    @ObservedObject var featureService = FeatureFlagsService.shared
    @State private var selectedTier: FeatureFlags.UserTier = .free
    @State private var showingFeatureList = false

    var body: some View {
        NavigationView {
            List {
                // Tier Selection (for testing)
                Section {
                    Picker("Test Tier", selection: $selectedTier) {
                        Text("Free").tag(FeatureFlags.UserTier.free)
                        Text("Pro").tag(FeatureFlags.UserTier.pro)
                        Text("Enterprise").tag(FeatureFlags.UserTier.enterprise)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Test Controls")
                } footer: {
                    Text("Switch tiers to see different UI states")
                }

                // Compact Badges
                Section {
                    HStack {
                        Text("Navigation Bar Style")
                        Spacer()
                        FeatureBadgeView(tier: selectedTier, compact: true)
                    }

                    HStack {
                        Text("With Feature Status")
                        Spacer()
                        FeatureBadgeView(
                            tier: selectedTier,
                            feature: .e2ee,
                            isEnabled: selectedTier != .free,
                            compact: true
                        )
                    }
                } header: {
                    Text("Compact Badges")
                }

                // Full Badges
                Section {
                    FeatureBadgeView(tier: selectedTier)

                    FeatureBadgeView(
                        tier: selectedTier,
                        feature: .voiceCalls,
                        isEnabled: selectedTier != .free
                    )
                } header: {
                    Text("Full Badges")
                }

                // Usage Quotas
                Section {
                    UsageQuotaView(
                        quotaType: .groupMembers,
                        current: getMockUsage(for: .groupMembers),
                        limit: getMockLimit(for: .groupMembers),
                        tier: selectedTier
                    )

                    UsageQuotaView(
                        quotaType: .storage,
                        current: getMockUsage(for: .storage),
                        limit: getMockLimit(for: .storage),
                        tier: selectedTier
                    )

                    UsageQuotaView(
                        quotaType: .fileSize,
                        current: getMockUsage(for: .fileSize),
                        limit: getMockLimit(for: .fileSize),
                        tier: selectedTier
                    )
                } header: {
                    Text("Usage Quotas - Full")
                }

                // Compact Quotas
                Section {
                    HStack {
                        Text("Group Members")
                        Spacer()
                        UsageQuotaView(
                            quotaType: .groupMembers,
                            current: getMockUsage(for: .groupMembers),
                            limit: getMockLimit(for: .groupMembers),
                            tier: selectedTier,
                            compact: true
                        )
                    }

                    HStack {
                        Text("Storage")
                        Spacer()
                        UsageQuotaView(
                            quotaType: .storage,
                            current: getMockUsage(for: .storage),
                            limit: getMockLimit(for: .storage),
                            tier: selectedTier,
                            compact: true
                        )
                    }
                } header: {
                    Text("Usage Quotas - Compact")
                }

                // Feature List
                Section {
                    Button(action: { showingFeatureList.toggle() }) {
                        HStack {
                            Text("View All Features")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Features")
                }
            }
            .navigationTitle("Feature Flags UI")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    FeatureBadgeView(tier: selectedTier, compact: true)
                }
            }
            .sheet(isPresented: $showingFeatureList) {
                featureListView
            }
        }
    }

    // MARK: - Supporting Views

    private var featureListView: some View {
        NavigationView {
            List {
                Section {
                    ForEach(mockAvailableFeatures, id: \.self) { feature in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)

                            Text(formatFeatureName(feature))

                            Spacer()
                        }
                    }
                } header: {
                    Text("Available Features")
                }

                Section {
                    ForEach(mockUnavailableFeatures, id: \.self) { feature in
                        HStack {
                            Image(systemName: "lock.circle.fill")
                                .foregroundColor(.gray)

                            Text(formatFeatureName(feature))

                            Spacer()

                            Text("Upgrade")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                } header: {
                    Text("Locked Features")
                }
            }
            .navigationTitle("Features")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingFeatureList = false
                    }
                }
            }
        }
    }

    // MARK: - Mock Data Helpers

    private func getMockUsage(for quotaType: UsageQuotaView.QuotaType) -> Int {
        switch quotaType {
        case .groupMembers:
            return selectedTier == .free ? 45 : selectedTier == .pro ? 180 : 500
        case .fileSize:
            return selectedTier == .free ? 15 : selectedTier == .pro ? 75 : 250
        case .storage:
            return selectedTier == .free ? 8 : selectedTier == .pro ? 65 : 500
        case .callParticipants:
            return selectedTier == .free ? 4 : selectedTier == .pro ? 18 : 80
        case .messageHistory:
            return selectedTier == .free ? 30 : selectedTier == .pro ? 180 : 365
        }
    }

    private func getMockLimit(for quotaType: UsageQuotaView.QuotaType) -> Int? {
        switch selectedTier {
        case .free:
            switch quotaType {
            case .groupMembers: return 100
            case .fileSize: return 20
            case .storage: return 10
            case .callParticipants: return 5
            case .messageHistory: return 30
            }
        case .pro:
            switch quotaType {
            case .groupMembers: return 250
            case .fileSize: return 100
            case .storage: return 100
            case .callParticipants: return 25
            case .messageHistory: return 365
            }
        case .enterprise:
            return nil // Unlimited
        }
    }

    private var mockAvailableFeatures: [FeatureFlags.Feature] {
        switch selectedTier {
        case .free:
            return [.directMessaging, .groupMessaging, .textMessages, .emojiReactions]
        case .pro:
            return [
                .directMessaging, .groupMessaging, .textMessages, .emojiReactions,
                .e2ee, .voiceCalls, .videoCalls, .fileSharing, .largeGroups,
                .messageSearch, .customThemes, .prioritySupport
            ]
        case .enterprise:
            return FeatureFlags.Feature.allCases
        }
    }

    private var mockUnavailableFeatures: [FeatureFlags.Feature] {
        let available = Set(mockAvailableFeatures)
        return FeatureFlags.Feature.allCases.filter { !available.contains($0) }
    }

    private func formatFeatureName(_ feature: FeatureFlags.Feature) -> String {
        feature.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Preview

#Preview {
    FeatureFlagsExampleView()
}

#Preview("Dark Mode") {
    FeatureFlagsExampleView()
        .preferredColorScheme(.dark)
}
