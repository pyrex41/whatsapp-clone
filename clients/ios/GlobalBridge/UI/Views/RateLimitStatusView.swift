//
//  RateLimitStatusView.swift
//  GlobalBridge
//
//  Rate limit quota display with per-feature tracking and upgrade prompts
//  - Real-time quota usage monitoring
//  - Visual progress bars with color-coded thresholds
//  - Time until quota reset
//  - Upgrade prompts when approaching limits
//  - Per-feature breakdown (translation, summarization, search, tasks)
//

import SwiftUI

/// Comprehensive rate limit status display with quota tracking and upgrade prompts
@MainActor
struct RateLimitStatusView: View {

    // MARK: - Properties

    @ObservedObject private var rateLimitTracker = RateLimitTracker.shared
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @State private var quotaSummaries: [RateLimitTracker.AIFeature: QuotaSummary] = [:]
    @State private var showUpgradeSheet = false
    @State private var selectedFeature: RateLimitTracker.AIFeature?
    @State private var timeUntilReset: String = ""

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Display Mode

    enum DisplayMode {
        case compact        // Single line summary
        case summary        // Card with overall status
        case detailed       // Full breakdown by feature
    }

    let mode: DisplayMode

    // MARK: - Initialization

    init(mode: DisplayMode = .detailed) {
        self.mode = mode
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch mode {
            case .compact:
                compactView
            case .summary:
                summaryView
            case .detailed:
                detailedView
            }
        }
        .onAppear {
            updateQuotaSummaries()
            updateTimeUntilReset()
        }
        .onReceive(timer) { _ in
            updateTimeUntilReset()
        }
        .onChange(of: rateLimitTracker.getQuotaSummary()) { _ in
            updateQuotaSummaries()
        }
        .sheet(isPresented: $showUpgradeSheet) {
            upgradeSheet
        }
    }

    // MARK: - Compact View

    private var compactView: some View {
        HStack(spacing: 8) {
            Image(systemName: overallStatusIcon)
                .foregroundColor(overallStatusColor)
                .font(.caption)

            Text(compactStatusText)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            if shouldShowUpgradePrompt {
                Button(action: { showUpgradeSheet = true }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(overallStatusColor.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rate limit status: \(compactStatusText)")
    }

    // MARK: - Summary View

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)

                Text("API Usage")
                    .font(.headline)

                Spacer()

                if shouldShowUpgradePrompt {
                    Button(action: { showUpgradeSheet = true }) {
                        Text("Upgrade")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }

            // Overall status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentTier.displayName)
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(timeUntilReset)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Quick stats
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(totalUsedRequests)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    Text("requests today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Most used feature
            if let topFeature = mostUsedFeature {
                Divider()

                HStack {
                    Text("Most used:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(topFeature.displayName)
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()

                    if let summary = quotaSummaries[topFeature] {
                        quotaBadge(for: summary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Detailed View

    private var detailedView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header card
                headerCard

                // Per-feature quota cards
                ForEach(RateLimitTracker.AIFeature.allCases, id: \.self) { feature in
                    if let summary = quotaSummaries[feature] {
                        featureQuotaCard(feature: feature, summary: summary)
                    }
                }

                // Upgrade prompt for free tier
                if shouldShowUpgradePrompt {
                    upgradePromptCard
                }
            }
            .padding()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("API Usage Limits")
                        .font(.headline)

                    Text(currentTier.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: overallStatusIcon)
                    .font(.title)
                    .foregroundColor(overallStatusColor)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resets")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(timeUntilReset)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Today")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(totalUsedRequests) requests")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Feature Quota Card

    private func featureQuotaCard(
        feature: RateLimitTracker.AIFeature,
        summary: QuotaSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: iconForFeature(feature))
                    .foregroundColor(colorForSummary(summary))

                Text(feature.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if !summary.enabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            // Usage stats
            if summary.enabled {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(summary.used)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(colorForSummary(summary))
                        .monospacedDigit()

                    if let limit = summary.limit {
                        Text("of \(limit)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("(Unlimited)")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }

                // Progress bar
                if let limit = summary.limit {
                    ProgressView(value: Double(summary.used), total: Double(limit))
                        .tint(colorForSummary(summary))
                        .scaleEffect(x: 1, y: 2, anchor: .center)

                    HStack {
                        Text("\(Int(summary.percentageUsed))% used")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        if let remaining = summary.remaining {
                            Text("\(remaining) remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Warning message
                if summary.isExceeded {
                    warningMessage(
                        text: "Quota exceeded. Requests will be blocked until reset.",
                        color: .red
                    )
                } else if summary.isNearLimit {
                    warningMessage(
                        text: "Approaching limit. Consider upgrading for more capacity.",
                        color: .orange
                    )
                }
            } else {
                Text("This feature is not available on your current plan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
        .opacity(summary.enabled ? 1.0 : 0.6)
        .onTapGesture {
            if !summary.enabled {
                selectedFeature = feature
                showUpgradeSheet = true
            }
        }
    }

    // MARK: - Warning Message

    private func warningMessage(text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")

            Text(text)
                .font(.caption)
                .lineLimit(2)

            Spacer()
        }
        .foregroundColor(color)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Quota Badge

    private func quotaBadge(for summary: QuotaSummary) -> some View {
        HStack(spacing: 4) {
            if let limit = summary.limit {
                Text("\(summary.used)/\(limit)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
            } else {
                Text("∞")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(colorForSummary(summary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(colorForSummary(summary).opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Upgrade Prompt Card

    private var upgradePromptCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 40))
                .foregroundColor(.purple)

            Text("Upgrade to Pro")
                .font(.headline)

            Text("Get higher limits and unlock premium AI features")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showUpgradeSheet = true }) {
                Text("View Plans")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Upgrade Sheet

    private var upgradeSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Hero section
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)

                        Text("Unlock More AI Power")
                            .font(.title)
                            .fontWeight(.bold)

                        if let feature = selectedFeature {
                            Text("Get more \(feature.displayName) capacity")
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Higher limits for all AI features")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top)

                    // Comparison table
                    VStack(spacing: 16) {
                        tierComparisonRow("Translation", free: "100/day", pro: "1000/day", enterprise: "Unlimited")
                        tierComparisonRow("Summarization", free: "10/day", pro: "100/day", enterprise: "Unlimited")
                        tierComparisonRow("Search", free: "50/day", pro: "500/day", enterprise: "Unlimited")
                        tierComparisonRow("Task Extraction", free: "20/day", pro: "200/day", enterprise: "Unlimited")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )

                    // CTA
                    VStack(spacing: 12) {
                        Button(action: {
                            // TODO: Implement upgrade flow
                            showUpgradeSheet = false
                        }) {
                            Text("Upgrade to Pro - $9.99/mo")
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

                        Button(action: {
                            // TODO: Contact sales for enterprise
                            showUpgradeSheet = false
                        }) {
                            Text("Contact Sales for Enterprise")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationBarItems(trailing: Button("Close") {
                showUpgradeSheet = false
                selectedFeature = nil
            })
        }
    }

    // MARK: - Tier Comparison Row

    private func tierComparisonRow(_ feature: String, free: String, pro: String, enterprise: String) -> some View {
        HStack {
            Text(feature)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(free)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(pro)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(enterprise)
                    .font(.caption)
                    .foregroundColor(.purple)
            }
            .frame(width: 80, alignment: .trailing)
        }
    }

    // MARK: - Helper Methods

    private func updateQuotaSummaries() {
        quotaSummaries = rateLimitTracker.getQuotaSummary()
    }

    private func updateTimeUntilReset() {
        let resetDate = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400) // Next midnight
        let now = Date()
        let interval = resetDate.timeIntervalSince(now)

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            timeUntilReset = "Resets in \(hours)h \(minutes)m"
        } else {
            timeUntilReset = "Resets in \(minutes) minutes"
        }
    }

    private func iconForFeature(_ feature: RateLimitTracker.AIFeature) -> String {
        switch feature {
        case .translation: return "globe"
        case .summarization: return "doc.text.fill"
        case .search: return "magnifyingglass"
        case .taskExtraction: return "checklist"
        }
    }

    private func colorForSummary(_ summary: QuotaSummary) -> Color {
        if !summary.enabled {
            return .gray
        }

        if summary.isExceeded {
            return .red
        } else if summary.isNearLimit {
            return .orange
        } else if summary.percentageUsed >= 50 {
            return .yellow
        } else {
            return .green
        }
    }

    // MARK: - Computed Properties

    private var currentTier: FeatureFlags.UserTier {
        featureFlags.getCurrentTier()
    }

    private var totalUsedRequests: Int {
        quotaSummaries.values.reduce(0) { $0 + $1.used }
    }

    private var mostUsedFeature: RateLimitTracker.AIFeature? {
        quotaSummaries
            .filter { $0.value.enabled && $0.value.used > 0 }
            .max(by: { $0.value.used < $1.value.used })?
            .key
    }

    private var shouldShowUpgradePrompt: Bool {
        currentTier == .free && quotaSummaries.values.contains { $0.isNearLimit || $0.isExceeded }
    }

    private var overallStatusIcon: String {
        let hasExceeded = quotaSummaries.values.contains { $0.isExceeded }
        let hasNearLimit = quotaSummaries.values.contains { $0.isNearLimit }

        if hasExceeded {
            return "exclamationmark.circle.fill"
        } else if hasNearLimit {
            return "exclamationmark.triangle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var overallStatusColor: Color {
        let hasExceeded = quotaSummaries.values.contains { $0.isExceeded }
        let hasNearLimit = quotaSummaries.values.contains { $0.isNearLimit }

        if hasExceeded {
            return .red
        } else if hasNearLimit {
            return .orange
        } else {
            return .green
        }
    }

    private var compactStatusText: String {
        let hasExceeded = quotaSummaries.values.contains { $0.isExceeded }
        let hasNearLimit = quotaSummaries.values.contains { $0.isNearLimit }

        if hasExceeded {
            return "Quota exceeded"
        } else if hasNearLimit {
            return "Approaching limit"
        } else {
            return "\(totalUsedRequests) requests today"
        }
    }
}

// MARK: - Preview Provider

#Preview("Compact") {
    VStack(spacing: 16) {
        RateLimitStatusView(mode: .compact)
        RateLimitStatusView(mode: .compact)
        RateLimitStatusView(mode: .compact)
    }
    .padding()
}

#Preview("Summary") {
    RateLimitStatusView(mode: .summary)
        .padding()
}

#Preview("Detailed") {
    RateLimitStatusView(mode: .detailed)
}

#Preview("Dark Mode") {
    RateLimitStatusView(mode: .detailed)
        .preferredColorScheme(.dark)
}
