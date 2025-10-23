import Foundation

/// Feature flags system for tier-based feature gating
/// Integrates with backend feature API to determine available features
public class FeatureFlags {

    // MARK: - Singleton

    static let shared = FeatureFlags()

    // MARK: - Properties

    private var currentTier: UserTier = .free
    private var features: [String: Bool] = [:]
    private var limits: TierLimits?

    // MARK: - Tier Definition

    enum UserTier: String, Codable {
        case free
        case pro
        case enterprise

        var displayName: String {
            switch self {
            case .free: return "Free"
            case .pro: return "Pro"
            case .enterprise: return "Enterprise"
            }
        }
    }

    // MARK: - Feature Names

    enum Feature: String {
        // Free tier
        case directMessaging = "direct_messaging"
        case groupMessaging = "group_messaging"
        case textMessages = "text_messages"
        case emojiReactions = "emoji_reactions"

        // Pro tier
        case e2ee = "e2ee"
        case voiceCalls = "voice_calls"
        case videoCalls = "video_calls"
        case fileSharing = "file_sharing"
        case largeGroups = "large_groups"
        case messageSearch = "message_search"
        case customThemes = "custom_themes"
        case prioritySupport = "priority_support"

        // Enterprise tier
        case adminDashboard = "admin_dashboard"
        case analytics = "analytics"
        case ssoIntegration = "sso_integration"
        case unlimitedStorage = "unlimited_storage"
        case unlimitedGroups = "unlimited_groups"
        case customBranding = "custom_branding"
        case apiAccess = "api_access"
        case dedicatedSupport = "dedicated_support"
        case slaGuarantee = "sla_guarantee"
        case auditLogs = "audit_logs"
    }

    // MARK: - Tier Limits

    struct TierLimits: Codable {
        let maxGroupMembers: Int?
        let maxFileSizeMb: Int?
        let maxStorageGb: Int?
        let maxCallParticipants: Int?
        let messageHistoryDays: Int?

        enum CodingKeys: String, CodingKey {
            case maxGroupMembers = "max_group_members"
            case maxFileSizeMb = "max_file_size_mb"
            case maxStorageGb = "max_storage_gb"
            case maxCallParticipants = "max_call_participants"
            case messageHistoryDays = "message_history_days"
        }
    }

    // MARK: - Initialization

    private init() {
        loadCachedFeatures()
    }

    // MARK: - Public Methods

    /// Check if a feature is available for the current user
    func hasFeature(_ feature: Feature) -> Bool {
        return features[feature.rawValue] ?? false
    }

    /// Get current user tier
    func getCurrentTier() -> UserTier {
        return currentTier
    }

    /// Get tier limits
    func getLimits() -> TierLimits? {
        return limits
    }

    /// Fetch features from API
    func fetchFeatures() async throws {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/v1/features") else {
            throw FeatureFlagsError.invalidURL
        }

        guard let token = await AuthManager.shared.getAccessToken() else {
            throw FeatureFlagsError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        let response = try decoder.decode(FeatureResponse.self, from: data)

        await MainActor.run {
            updateFeatures(
                tier: response.data.tier,
                features: response.data.features,
                limits: response.data.limits
            )
        }
    }

    /// Check a specific feature from API
    func checkFeature(_ feature: Feature) async throws -> Bool {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/v1/features/\(feature.rawValue)") else {
            throw FeatureFlagsError.invalidURL
        }

        guard let token = await AuthManager.shared.getAccessToken() else {
            throw FeatureFlagsError.notAuthenticated
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)

        let decoder = JSONDecoder()
        let response = try decoder.decode(FeatureCheckResponse.self, from: data)
        return response.data.hasAccess
    }

    // MARK: - Private Methods

    private func updateFeatures(tier: String, features: [String: Bool], limits: TierLimits) {
        self.currentTier = UserTier(rawValue: tier) ?? .free
        self.features = features
        self.limits = limits
        cacheFeatures()

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .featureFlagsUpdated,
            object: nil
        )
    }

    private func cacheFeatures() {
        let cache = FeatureCache(
            tier: currentTier.rawValue,
            features: features,
            limits: limits
        )

        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: "cached_features")
        }
    }

    private func loadCachedFeatures() {
        guard let data = UserDefaults.standard.data(forKey: "cached_features"),
              let cache = try? JSONDecoder().decode(FeatureCache.self, from: data) else {
            return
        }

        self.currentTier = UserTier(rawValue: cache.tier) ?? .free
        self.features = cache.features
        self.limits = cache.limits
    }

    /// Clear cached feature flags (call on logout)
    public func clearCache() {
        UserDefaults.standard.removeObject(forKey: "cached_features")
        currentTier = .free
        features = [:]
        limits = nil
        print("🗑️ [FEATURE_FLAGS] Cache cleared")
    }

    // MARK: - Supporting Types

    private struct FeatureCache: Codable {
        let tier: String
        let features: [String: Bool]
        let limits: TierLimits?
    }

    private nonisolated struct FeatureResponse: Codable {
        let data: FeatureData

        struct FeatureData: Codable {
            let tier: String
            let features: [String: Bool]
            let limits: TierLimits
        }
    }

    private nonisolated struct FeatureCheckResponse: Codable {
        let data: FeatureCheckData

        struct FeatureCheckData: Codable {
            let feature: String
            let hasAccess: Bool
            let tier: String

            enum CodingKeys: String, CodingKey {
                case feature
                case hasAccess = "has_access"
                case tier
            }
        }
    }

    enum FeatureFlagsError: Error, LocalizedError {
        case invalidURL
        case notAuthenticated
        case noData

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .notAuthenticated:
                return "User not authenticated"
            case .noData:
                return "No data received from server"
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let featureFlagsUpdated = Notification.Name("featureFlagsUpdated")
}

// MARK: - API Configuration

private struct APIConfig {
    static var baseURL: String {
        // Check environment variable first
        if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"],
           backendEnv.lowercased() == "production" {
            return "https://globalbridge-backend.fly.dev"
        }

        // Default to localhost for Debug, production for Release
        #if DEBUG
        return "http://localhost:4000"
        #else
        return "https://globalbridge-backend.fly.dev"
        #endif
    }
}
