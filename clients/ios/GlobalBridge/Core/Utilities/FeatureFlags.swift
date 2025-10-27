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
    private var translationLimit: Int?

    // Service dependency
    private let service: FeatureFlagsService

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

    enum Feature: String, CaseIterable {
        // Core AI Features (from backend API)
        case translationEnabled = "translation_enabled"
        case threadSummarization = "thread_summarization"
        case semanticSearch = "semantic_search"
        case styleLearning = "style_learning"

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

    private init(service: FeatureFlagsService = FeatureFlagsService()) {
        self.service = service
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

    /// Get translation limit for current tier
    func getTranslationLimit() -> Int? {
        return translationLimit
    }

    /// Check if user has remaining translation capacity
    func hasTranslationCapacity(currentUsage: Int) -> Bool {
        guard hasFeature(.translationEnabled) else { return false }

        // Enterprise and some tiers may have unlimited translations (nil limit)
        guard let limit = translationLimit else { return true }

        return currentUsage < limit
    }

    /// Fetch features from API using the service layer
    func fetchFeatures() async throws {
        print("🔄 [FEATURE_FLAGS] Fetching features from backend...")

        do {
            let response = try await service.fetchFeatures()

            await MainActor.run {
                updateFeaturesFromService(response)
            }

            print("✅ [FEATURE_FLAGS] Features updated successfully")
        } catch let error as FeatureFlagsServiceError {
            print("❌ [FEATURE_FLAGS] Service error: \(error.localizedDescription)")

            // On network error, fall back to cached features
            if case .networkError = error {
                print("📦 [FEATURE_FLAGS] Using cached features (offline mode)")
                // Cached features already loaded in init
            }

            throw FeatureFlagsError.serviceError(error)
        } catch {
            print("❌ [FEATURE_FLAGS] Unexpected error: \(error.localizedDescription)")
            throw FeatureFlagsError.unknown
        }
    }

    /// Check a specific feature from API
    func checkFeature(_ feature: Feature) async throws -> Bool {
        do {
            let hasAccess = try await service.checkFeature(feature.rawValue)
            print("✅ [FEATURE_FLAGS] Feature check for \(feature.rawValue): \(hasAccess)")
            return hasAccess
        } catch {
            print("❌ [FEATURE_FLAGS] Feature check failed: \(error.localizedDescription)")
            // Fall back to local cache
            return hasFeature(feature)
        }
    }

    // MARK: - Private Methods

    /// Update features from service response
    private func updateFeaturesFromService(_ response: FeaturesResponse) {
        self.currentTier = UserTier(rawValue: response.tier) ?? .free
        self.features = response.toFeaturesDictionary()
        self.translationLimit = response.translationLimit

        print("📊 [FEATURE_FLAGS] Updated features:")
        print("   - Tier: \(self.currentTier.rawValue)")
        print("   - Translation Enabled: \(response.translationEnabled)")
        print("   - Translation Limit: \(response.translationLimit?.description ?? "unlimited")")
        print("   - Thread Summarization: \(response.threadSummarization)")
        print("   - Semantic Search: \(response.semanticSearch)")

        cacheFeatures()

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .featureFlagsUpdated,
            object: nil
        )
    }

    /// Legacy update method for compatibility (kept for potential direct updates)
    private func updateFeatures(tier: String, features: [String: Bool], limits: TierLimits?) {
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
            limits: limits,
            translationLimit: translationLimit
        )

        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: "cached_features")
            print("💾 [FEATURE_FLAGS] Features cached to UserDefaults")
        }
    }

    private func loadCachedFeatures() {
        guard let data = UserDefaults.standard.data(forKey: "cached_features"),
              let cache = try? JSONDecoder().decode(FeatureCache.self, from: data) else {
            print("ℹ️  [FEATURE_FLAGS] No cached features found, using defaults")
            // Enable translation by default in development
            #if DEBUG
            self.features[Feature.translationEnabled.rawValue] = true
            self.features[Feature.threadSummarization.rawValue] = true
            self.features[Feature.semanticSearch.rawValue] = true
            self.features[Feature.styleLearning.rawValue] = true
            self.translationLimit = nil // Unlimited in dev
            print("🛠️  [FEATURE_FLAGS] Development mode: All AI features enabled")
            #endif
            return
        }

        self.currentTier = UserTier(rawValue: cache.tier) ?? .free
        self.features = cache.features
        self.limits = cache.limits
        self.translationLimit = cache.translationLimit

        print("📦 [FEATURE_FLAGS] Loaded cached features:")
        print("   - Tier: \(self.currentTier.rawValue)")
        print("   - Features: \(self.features)")
        print("   - Translation Limit: \(self.translationLimit?.description ?? "unlimited")")
    }

    /// Clear cached feature flags (call on logout)
    public func clearCache() {
        UserDefaults.standard.removeObject(forKey: "cached_features")
        currentTier = .free
        features = [:]
        limits = nil
        translationLimit = nil
        print("🗑️ [FEATURE_FLAGS] Cache cleared")
    }

    // MARK: - Supporting Types

    private struct FeatureCache: Codable {
        let tier: String
        let features: [String: Bool]
        let limits: TierLimits?
        let translationLimit: Int?

        enum CodingKeys: String, CodingKey {
            case tier
            case features
            case limits
            case translationLimit = "translation_limit"
        }
    }

    enum FeatureFlagsError: Error, LocalizedError {
        case invalidURL
        case notAuthenticated
        case noData
        case serviceError(FeatureFlagsServiceError)
        case unknown

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .notAuthenticated:
                return "User not authenticated"
            case .noData:
                return "No data received from server"
            case .serviceError(let serviceError):
                return "Service error: \(serviceError.localizedDescription)"
            case .unknown:
                return "An unknown error occurred"
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
