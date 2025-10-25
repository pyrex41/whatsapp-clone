//
//  RateLimitTracker.swift
//  GlobalBridge
//
//  Rate limiting and quota tracking for AI service requests
//  - Tier-aware rate limits (free/pro/enterprise)
//  - Per-feature quota tracking
//  - Backend rate limit header parsing
//  - Exponential backoff for 429 responses
//  - Daily quota resets
//

import Foundation

/// Tracks rate limits and quotas for AI service requests
@MainActor
final class RateLimitTracker {

    // MARK: - Singleton

    static let shared = RateLimitTracker()

    // MARK: - Properties

    private let featureFlags: FeatureFlags
    private let userDefaults: UserDefaults

    /// Current quota usage per feature
    private var quotaUsage: [AIFeature: QuotaInfo] = [:]

    /// Backend rate limit state from response headers
    private var backendRateLimits: [AIFeature: BackendRateLimit] = [:]

    /// Exponential backoff state per feature
    private var backoffState: [AIFeature: BackoffState] = [:]

    // MARK: - Constants

    private let quotaStorageKey = "ai_service_quota_usage"
    private let lastResetDateKey = "ai_service_last_reset_date"

    // MARK: - AI Features

    enum AIFeature: String, CaseIterable, Codable {
        case translation
        case summarization
        case search
        case taskExtraction

        var displayName: String {
            switch self {
            case .translation: return "Translation"
            case .summarization: return "Thread Summarization"
            case .search: return "Semantic Search"
            case .taskExtraction: return "Task Extraction"
            }
        }
    }

    // MARK: - Initialization

    private init(
        featureFlags: FeatureFlags = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.featureFlags = featureFlags
        self.userDefaults = userDefaults

        loadQuotaUsage()
        checkDailyReset()

        print("✅ [RATE_LIMIT] Initialized tracker")
    }

    // MARK: - Public Interface

    /// Check if a request can be made for the given feature
    func canMakeRequest(for feature: AIFeature) -> RateLimitCheckResult {
        // Check if feature is enabled
        guard isFeatureEnabled(feature) else {
            return .denied(reason: .featureDisabled)
        }

        // Check backend rate limit (429 response tracking)
        if let backendLimit = backendRateLimits[feature],
           backendLimit.isLimited {
            let waitTime = backendLimit.resetDate.timeIntervalSinceNow
            return .rateLimited(resetDate: backendLimit.resetDate, waitTime: waitTime)
        }

        // Check exponential backoff state
        if let backoff = backoffState[feature],
           backoff.isInBackoff {
            _ = backoff.nextRetryDate.timeIntervalSinceNow
            return .backoff(retryAfter: backoff.nextRetryDate, attemptCount: backoff.attemptCount)
        }

        // Check tier quota
        let tierLimit = getTierLimit(for: feature)
        let currentUsage = getUsage(for: feature)

        // Unlimited quota (nil limit for enterprise or certain features)
        if tierLimit == nil {
            return .allowed(remaining: nil, resetDate: nextResetDate())
        }

        // Check if quota exceeded
        if let limit = tierLimit, currentUsage >= limit {
            return .quotaExceeded(
                limit: limit,
                used: currentUsage,
                resetDate: nextResetDate()
            )
        }

        let remaining = tierLimit.map { $0 - currentUsage }
        return .allowed(remaining: remaining, resetDate: nextResetDate())
    }

    /// Record a successful request
    func recordRequest(for feature: AIFeature) {
        var quota = quotaUsage[feature] ?? QuotaInfo(count: 0, lastUpdated: Date())
        quota.count += 1
        quota.lastUpdated = Date()
        quotaUsage[feature] = quota

        // Reset backoff on success
        backoffState[feature] = nil

        saveQuotaUsage()

        print("📊 [RATE_LIMIT] Recorded \(feature.rawValue) - usage: \(quota.count)")
    }

    /// Process backend rate limit headers from HTTP response
    func processRateLimitHeaders(_ headers: [String: String], for feature: AIFeature) {
        // Parse X-RateLimit-* headers
        guard let limitStr = headers["X-RateLimit-Limit"],
              let remainingStr = headers["X-RateLimit-Remaining"],
              let resetStr = headers["X-RateLimit-Reset"],
              let limit = Int(limitStr),
              let remaining = Int(remainingStr),
              let resetTimestamp = TimeInterval(resetStr) else {
            return
        }

        let resetDate = Date(timeIntervalSince1970: resetTimestamp)

        backendRateLimits[feature] = BackendRateLimit(
            limit: limit,
            remaining: remaining,
            resetDate: resetDate
        )

        print("📊 [RATE_LIMIT] Backend limit for \(feature.rawValue): \(remaining)/\(limit), resets \(resetDate)")
    }

    /// Handle 429 Too Many Requests response
    func handle429Response(for feature: AIFeature, retryAfter: TimeInterval?) {
        // Exponential backoff
        var backoff = backoffState[feature] ?? BackoffState(attemptCount: 0)
        backoff.attemptCount += 1

        // Use Retry-After header if provided, otherwise use exponential backoff
        let waitTime = retryAfter ?? backoff.calculateBackoffTime()
        backoff.nextRetryDate = Date().addingTimeInterval(waitTime)

        backoffState[feature] = backoff

        print("⏰ [RATE_LIMIT] 429 for \(feature.rawValue) - backoff: \(waitTime)s, attempt: \(backoff.attemptCount)")

        // Also mark in backend rate limits
        backendRateLimits[feature] = BackendRateLimit(
            limit: 0,
            remaining: 0,
            resetDate: backoff.nextRetryDate
        )
    }

    /// Get current usage for a feature
    func getUsage(for feature: AIFeature) -> Int {
        return quotaUsage[feature]?.count ?? 0
    }

    /// Get remaining quota for a feature
    func getRemainingQuota(for feature: AIFeature) -> Int? {
        guard let limit = getTierLimit(for: feature) else {
            return nil // Unlimited
        }

        let usage = getUsage(for: feature)
        return max(0, limit - usage)
    }

    /// Get quota summary for all features
    func getQuotaSummary() -> [AIFeature: QuotaSummary] {
        var summary: [AIFeature: QuotaSummary] = [:]

        for feature in AIFeature.allCases {
            let limit = getTierLimit(for: feature)
            let used = getUsage(for: feature)
            let remaining = limit.map { max(0, $0 - used) }

            summary[feature] = QuotaSummary(
                feature: feature,
                limit: limit,
                used: used,
                remaining: remaining,
                resetDate: nextResetDate(),
                enabled: isFeatureEnabled(feature)
            )
        }

        return summary
    }

    /// Reset all quotas (called daily or on user request)
    func resetQuotas() {
        quotaUsage.removeAll()
        backendRateLimits.removeAll()
        backoffState.removeAll()
        saveQuotaUsage()

        userDefaults.set(Date(), forKey: lastResetDateKey)

        print("🔄 [RATE_LIMIT] Reset all quotas")
    }

    /// Clear all data (logout)
    func clearAll() {
        quotaUsage.removeAll()
        backendRateLimits.removeAll()
        backoffState.removeAll()
        userDefaults.removeObject(forKey: quotaStorageKey)
        userDefaults.removeObject(forKey: lastResetDateKey)

        print("🗑️ [RATE_LIMIT] Cleared all data")
    }

    // MARK: - Private Methods

    private func isFeatureEnabled(_ feature: AIFeature) -> Bool {
        switch feature {
        case .translation:
            return featureFlags.hasFeature(.translationEnabled)
        case .summarization:
            return featureFlags.hasFeature(.threadSummarization)
        case .search:
            return featureFlags.hasFeature(.semanticSearch)
        case .taskExtraction:
            // Task extraction typically requires summarization
            return featureFlags.hasFeature(.threadSummarization)
        }
    }

    private func getTierLimit(for feature: AIFeature) -> Int? {
        let tier = featureFlags.getCurrentTier()

        switch feature {
        case .translation:
            // Use backend-provided translation limit
            return featureFlags.getTranslationLimit()

        case .summarization:
            // Summarization limits per tier
            switch tier {
            case .free: return 10     // 10 summaries/day
            case .pro: return 100     // 100 summaries/day
            case .enterprise: return nil  // Unlimited
            }

        case .search:
            // Search limits per tier
            switch tier {
            case .free: return 50     // 50 searches/day
            case .pro: return 500     // 500 searches/day
            case .enterprise: return nil  // Unlimited
            }

        case .taskExtraction:
            // Task extraction limits per tier
            switch tier {
            case .free: return 20     // 20 extractions/day
            case .pro: return 200     // 200 extractions/day
            case .enterprise: return nil  // Unlimited
            }
        }
    }

    private func nextResetDate() -> Date {
        // Reset at midnight UTC
        let calendar = Calendar.current
        let now = Date()

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
            return now.addingTimeInterval(86400) // Fallback: 24 hours from now
        }

        let components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        return calendar.date(from: components) ?? tomorrow
    }

    private func checkDailyReset() {
        guard let lastReset = userDefaults.object(forKey: lastResetDateKey) as? Date else {
            // First launch
            userDefaults.set(Date(), forKey: lastResetDateKey)
            return
        }

        let calendar = Calendar.current
        if !calendar.isDateInToday(lastReset) {
            // It's a new day - reset quotas
            resetQuotas()
        }
    }

    private func saveQuotaUsage() {
        if let encoded = try? JSONEncoder().encode(quotaUsage) {
            userDefaults.set(encoded, forKey: quotaStorageKey)
        }
    }

    private func loadQuotaUsage() {
        guard let data = userDefaults.data(forKey: quotaStorageKey),
              let decoded = try? JSONDecoder().decode([AIFeature: QuotaInfo].self, from: data) else {
            return
        }

        quotaUsage = decoded
        print("📦 [RATE_LIMIT] Loaded quota usage: \(quotaUsage)")
    }
}

// MARK: - Supporting Types

/// Result of rate limit check
enum RateLimitCheckResult {
    case allowed(remaining: Int?, resetDate: Date)
    case quotaExceeded(limit: Int, used: Int, resetDate: Date)
    case rateLimited(resetDate: Date, waitTime: TimeInterval)
    case backoff(retryAfter: Date, attemptCount: Int)
    case denied(reason: DenialReason)

    enum DenialReason {
        case featureDisabled
        case notAuthenticated
    }

    var isAllowed: Bool {
        if case .allowed = self {
            return true
        }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .allowed:
            return nil
        case .quotaExceeded(let limit, let used, let resetDate):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Daily quota exceeded (\(used)/\(limit)). Resets at \(formatter.string(from: resetDate))."
        case .rateLimited(let resetDate, _):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Rate limited. Try again at \(formatter.string(from: resetDate))."
        case .backoff(let retryDate, let attemptCount):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Too many requests (attempt \(attemptCount)). Retry at \(formatter.string(from: retryDate))."
        case .denied(let reason):
            switch reason {
            case .featureDisabled:
                return "This feature is not available on your current plan."
            case .notAuthenticated:
                return "Please log in to use this feature."
            }
        }
    }
}

/// Quota usage information
private struct QuotaInfo: Codable {
    var count: Int
    var lastUpdated: Date
}

/// Backend rate limit state (from response headers)
private struct BackendRateLimit {
    let limit: Int
    let remaining: Int
    let resetDate: Date

    var isLimited: Bool {
        return remaining <= 0 && Date() < resetDate
    }
}

/// Exponential backoff state
private struct BackoffState {
    var attemptCount: Int
    var nextRetryDate: Date = Date()

    var isInBackoff: Bool {
        return Date() < nextRetryDate
    }

    /// Calculate exponential backoff time: 2^attempt seconds (capped at 5 minutes)
    func calculateBackoffTime() -> TimeInterval {
        let exponentialTime = pow(2.0, Double(attemptCount))
        return min(exponentialTime, 300) // Max 5 minutes
    }
}

/// Quota summary for UI display
struct QuotaSummary {
    let feature: RateLimitTracker.AIFeature
    let limit: Int?  // nil = unlimited
    let used: Int
    let remaining: Int?
    let resetDate: Date
    let enabled: Bool

    var percentageUsed: Double {
        guard let limit = limit, limit > 0 else {
            return 0.0 // Unlimited or no limit
        }
        return Double(used) / Double(limit) * 100.0
    }

    var isNearLimit: Bool {
        return percentageUsed >= 80.0
    }

    var isExceeded: Bool {
        guard let limit = limit else { return false }
        return used >= limit
    }
}
