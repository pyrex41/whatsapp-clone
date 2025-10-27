//
//  FeatureFlagsService.swift
//  GlobalBridge
//
//  Service for fetching feature flags from backend API with caching and offline support
//

import Foundation

/// Service responsible for fetching feature flags from the backend API
struct FeatureFlagsService {
    let baseURL: URL
    let session: URLSession
    let authManager: AuthManager

    /// Returns the appropriate backend URL based on environment
    static var defaultBaseURL: URL {
        // Check environment variable first
        if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"],
           backendEnv.lowercased() == "local" {
            return URL(string: "http://localhost:4000")!
        }

        // Default to production for both Debug and Release
        return URL(string: "https://globalbridge-backend.fly.dev")!
    }

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        authManager: AuthManager = .shared
    ) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session
        self.authManager = authManager
    }

    /// Fetch all feature flags for the current user from the backend
    /// Returns tier information and available features
    func fetchFeatures() async throws -> FeaturesResponse {
        let url = baseURL.appendingPathComponent("api/v1/features")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication header if available
        if let token = await authManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("🔐 [FEATURE_FLAGS_SERVICE] Fetching features with auth token")
        } else {
            print("⚠️  [FEATURE_FLAGS_SERVICE] No auth token available, using default features")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeatureFlagsServiceError.invalidResponse
            }

            print("📊 [FEATURE_FLAGS_SERVICE] Response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    throw FeatureFlagsServiceError.unauthorized
                }
                throw FeatureFlagsServiceError.httpError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            let apiResponse = try decoder.decode(FeatureFlagsAPIResponse.self, from: data)

            print("✅ [FEATURE_FLAGS_SERVICE] Successfully fetched features")
            print("   - Tier: \(apiResponse.tier)")
            print("   - Features: \(apiResponse.features)")

            return apiResponse.toFeaturesResponse()
        } catch let error as FeatureFlagsServiceError {
            print("❌ [FEATURE_FLAGS_SERVICE] Service error: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ [FEATURE_FLAGS_SERVICE] Network error: \(error.localizedDescription)")
            throw FeatureFlagsServiceError.networkError(error)
        }
    }

    /// Check a specific feature flag
    func checkFeature(_ featureName: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("api/v1/features/\(featureName)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = await authManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeatureFlagsServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw FeatureFlagsServiceError.unauthorized
            }
            throw FeatureFlagsServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let checkResponse = try decoder.decode(FeatureCheckAPIResponse.self, from: data)

        return checkResponse.data.hasAccess
    }
}

// MARK: - API Response DTOs

/// API response from GET /api/v1/features
private struct FeatureFlagsAPIResponse: Decodable {
    let tier: String
    let features: Features

    struct Features: Decodable {
        let translationEnabled: Bool
        let translationLimit: Int?
        let threadSummarization: Bool
        let semanticSearch: Bool

        enum CodingKeys: String, CodingKey {
            case translationEnabled = "translation_enabled"
            case translationLimit = "translation_limit"
            case threadSummarization = "thread_summarization"
            case semanticSearch = "semantic_search"
        }
    }

    /// Convert API response to domain model
    func toFeaturesResponse() -> FeaturesResponse {
        FeaturesResponse(
            tier: tier,
            translationEnabled: features.translationEnabled,
            translationLimit: features.translationLimit,
            threadSummarization: features.threadSummarization,
            semanticSearch: features.semanticSearch
        )
    }
}

/// API response from GET /api/v1/features/:feature
private struct FeatureCheckAPIResponse: Decodable {
    let data: FeatureCheckData

    struct FeatureCheckData: Decodable {
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

// MARK: - Domain Models

/// Domain model for features response
struct FeaturesResponse {
    let tier: String
    let translationEnabled: Bool
    let translationLimit: Int?
    let threadSummarization: Bool
    let semanticSearch: Bool

    /// Convert to dictionary for compatibility with existing FeatureFlags
    func toFeaturesDictionary() -> [String: Bool] {
        return [
            "translation_enabled": translationEnabled,
            "thread_summarization": threadSummarization,
            "semantic_search": semanticSearch
        ]
    }
}

// MARK: - Service Errors

enum FeatureFlagsServiceError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "User not authenticated. Please log in."
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}
