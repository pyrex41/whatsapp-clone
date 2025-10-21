import Foundation

/// Feature flags system for tier-based feature gating
/// Integrates with backend feature API to determine available features
class FeatureFlags {

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
    func fetchFeatures(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/v1/features") else {
            completion(.failure(FeatureFlagsError.invalidURL))
            return
        }

        guard let token = AuthManager.shared.getAccessToken() else {
            completion(.failure(FeatureFlagsError.notAuthenticated))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(FeatureFlagsError.noData))
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(FeatureResponse.self, from: data)

                DispatchQueue.main.async {
                    self?.updateFeatures(
                        tier: response.data.tier,
                        features: response.data.features,
                        limits: response.data.limits
                    )
                    completion(.success(()))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// Check a specific feature from API
    func checkFeature(_ feature: Feature, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let url = URL(string: "\(APIConfig.baseURL)/api/v1/features/\(feature.rawValue)") else {
            completion(.failure(FeatureFlagsError.invalidURL))
            return
        }

        guard let token = AuthManager.shared.getAccessToken() else {
            completion(.failure(FeatureFlagsError.notAuthenticated))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(FeatureFlagsError.noData))
                return
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(FeatureCheckResponse.self, from: data)
                completion(.success(response.data.hasAccess))
            } catch {
                completion(.failure(error))
            }
        }.resume()
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
    static let baseURL = "http://localhost:4000" // Update with actual API URL
}
