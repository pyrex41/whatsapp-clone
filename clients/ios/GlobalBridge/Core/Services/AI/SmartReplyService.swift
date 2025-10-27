//
//  SmartReplyService.swift
//  GlobalBridge
//
//  Provides smart reply suggestions, user style profiling, and feedback tracking
//  Integrates with Phoenix backend AI suggestion endpoints
//

import Foundation
import Combine

/// Smart reply service for generating contextual message suggestions
@MainActor
final class SmartReplyService: ObservableObject {

    // MARK: - Singleton

    static let shared = SmartReplyService()

    // MARK: - Published Properties

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: AIServiceError?
    @Published private(set) var requestCount: Int = 0

    // MARK: - Dependencies

    private let session: URLSession
    private let authManager: AuthManager
    private let baseURL: URL
    private let clock: ClockProtocol

    // MARK: - Configuration

    private let requestTimeout: TimeInterval = 30.0
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0

    // MARK: - Caching

    private let cache = NSCache<NSString, CachedSuggestions>()
    private let suggestionCacheTTL: TimeInterval = 60.0 // 60 seconds

    private final class CachedSuggestions {
        let suggestions: [SmartReplySuggestion]
        let timestamp: Date
        let ttl: TimeInterval

        init(suggestions: [SmartReplySuggestion], timestamp: Date, ttl: TimeInterval) {
            self.suggestions = suggestions
            self.timestamp = timestamp
            self.ttl = ttl
        }

        func isValid(clock: ClockProtocol) -> Bool {
            clock.now().timeIntervalSince(timestamp) < ttl
        }
    }

    // MARK: - Initialization

    init(
        session: URLSession = .shared,
        authManager: AuthManager = .shared,
        baseURL: URL? = nil,
        clock: ClockProtocol = SystemClock.shared
    ) {
        self.session = session
        self.authManager = authManager
        self.clock = clock

        // Determine base URL based on environment
        if let providedURL = baseURL {
            self.baseURL = providedURL
        } else {
            #if DEBUG
            // Check for production override
            if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"],
               backendEnv.lowercased() == "production" {
                self.baseURL = URL(string: "https://globalbridge-backend.fly.dev")!
            } else {
                self.baseURL = URL(string: "http://localhost:4000")!
            }
            #else
            self.baseURL = URL(string: "https://globalbridge-backend.fly.dev")!
            #endif
        }

        // Configure cache limits
        cache.countLimit = 100 // Maximum 100 cached thread suggestions
        cache.totalCostLimit = 10 * 1024 * 1024 // 10MB

        print("🎯 [SMART_REPLY_SERVICE] Initialized with base URL: \(self.baseURL.absoluteString)")
    }

    // MARK: - Public Methods

    /// Fetch smart reply suggestions for a thread
    /// - Parameters:
    ///   - threadId: Thread UUID to generate suggestions for
    ///   - limit: Maximum number of suggestions (1-10, defaults to 3)
    /// - Returns: Array of SmartReplySuggestion sorted by confidence
    /// - Throws: AIServiceError for various failure cases
    func fetchSuggestions(
        threadId: UUID,
        limit: Int = 3
    ) async throws -> [SmartReplySuggestion] {
        // Validate input
        guard (1...10).contains(limit) else {
            throw AIServiceError.invalidInput(reason: "Limit must be between 1 and 10")
        }

        // Check cache first
        let cacheKey = "suggestions_\(threadId.uuidString)" as NSString
        if let cached = cache.object(forKey: cacheKey), cached.isValid(clock: clock) {
            print("✅ [SMART_REPLY_SERVICE] Returning cached suggestions for thread: \(threadId)")
            return Array(cached.suggestions.prefix(limit))
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/suggest_replies")
        let requestBody: [String: Any] = [
            "thread_id": threadId.uuidString,
            "limit": limit
        ]

        print("🎯 [SMART_REPLY_SERVICE] Fetching suggestions for thread: \(threadId) (limit: \(limit))")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct SuggestionsResponse: Decodable {
            let success: Bool
            let suggestions: [SuggestionItem]

            struct SuggestionItem: Decodable {
                let id: String
                let type: String
                let content: String
                let confidence: Double
                let position: Int
                let context: String
                let timestamp: String
            }
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(SuggestionsResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.backendError(message: "Failed to fetch suggestions")
        }

        // Convert to domain models
        let suggestions = try response.suggestions.map { item -> SmartReplySuggestion in
            guard let id = UUID(uuidString: item.id) else {
                throw AIServiceError.decodingError(
                    NSError(domain: "SmartReplyService", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: "Invalid suggestion ID"])
                )
            }

            guard let timestamp = ISO8601DateFormatter().date(from: item.timestamp) else {
                throw AIServiceError.decodingError(
                    NSError(domain: "SmartReplyService", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: "Invalid timestamp"])
                )
            }

            return SmartReplySuggestion(
                id: id,
                type: item.type,
                content: item.content,
                translatedText: nil,
                confidence: item.confidence,
                position: item.position,
                context: item.context,
                timestamp: timestamp
            )
        }

        // Cache the results
        let cachedValue = CachedSuggestions(
            suggestions: suggestions,
            timestamp: clock.now(),
            ttl: suggestionCacheTTL
        )
        cache.setObject(cachedValue, forKey: cacheKey)

        print("✅ [SMART_REPLY_SERVICE] Received \(suggestions.count) suggestions")
        incrementRequestCount()

        return suggestions
    }

    /// Record user feedback on a suggestion
    /// - Parameter feedback: SuggestionFeedback containing user interaction data
    /// - Throws: AIServiceError for various failure cases
    func recordFeedback(_ feedback: SuggestionFeedback) async throws {
        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/record_feedback")

        var requestBody: [String: Any] = [
            "suggestion_id": feedback.suggestionId.uuidString,
            "accepted": feedback.accepted
        ]

        if let modifiedContent = feedback.modifiedContent {
            requestBody["modified_content"] = modifiedContent
        }

        if let rejectionReason = feedback.rejectionReason {
            requestBody["rejection_reason"] = rejectionReason
        }

        if let timeToResponse = feedback.timeToResponseMs {
            requestBody["time_to_response_ms"] = timeToResponse
        }

        print("🎯 [SMART_REPLY_SERVICE] Recording feedback for suggestion: \(feedback.suggestionId) (accepted: \(feedback.accepted))")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct FeedbackResponse: Decodable {
            let success: Bool
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(FeedbackResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.backendError(message: "Failed to record feedback")
        }

        print("✅ [SMART_REPLY_SERVICE] Feedback recorded successfully")
        incrementRequestCount()
    }

    /// Get user's messaging style profile
    /// - Returns: UserStyleProfile with user's writing characteristics
    /// - Throws: AIServiceError for various failure cases
    func getUserStyleProfile() async throws -> UserStyleProfile {
        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/style_profile")

        print("🎯 [SMART_REPLY_SERVICE] Fetching user style profile")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil
        )

        // Parse response
        struct StyleProfileResponse: Decodable {
            let success: Bool
            let profile: ProfileData

            struct ProfileData: Decodable {
                let userId: String
                let formalityLevel: Double
                let emojiFrequency: Double
                let avgSentenceLength: Double
                let messagesAnalyzed: Int
                let confidenceScore: Double
                let lastUpdatedAt: String

                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case formalityLevel = "formality_level"
                    case emojiFrequency = "emoji_frequency"
                    case avgSentenceLength = "avg_sentence_length"
                    case messagesAnalyzed = "messages_analyzed"
                    case confidenceScore = "confidence_score"
                    case lastUpdatedAt = "last_updated_at"
                }
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(StyleProfileResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.backendError(message: "Failed to fetch style profile")
        }

        // Convert to domain model
        guard let userId = UUID(uuidString: response.profile.userId) else {
            throw AIServiceError.decodingError(
                NSError(domain: "SmartReplyService", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
            )
        }

        guard let lastUpdatedAt = ISO8601DateFormatter().date(from: response.profile.lastUpdatedAt) else {
            throw AIServiceError.decodingError(
                NSError(domain: "SmartReplyService", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "Invalid timestamp"])
            )
        }

        let profile = UserStyleProfile(
            userId: userId,
            formalityLevel: response.profile.formalityLevel,
            emojiFrequency: response.profile.emojiFrequency,
            avgSentenceLength: response.profile.avgSentenceLength,
            messagesAnalyzed: response.profile.messagesAnalyzed,
            confidenceScore: response.profile.confidenceScore,
            lastUpdatedAt: lastUpdatedAt
        )

        print("✅ [SMART_REPLY_SERVICE] Style profile retrieved (confidence: \(profile.confidenceScore))")
        incrementRequestCount()

        return profile
    }

    /// Clear cached suggestions for a specific thread
    /// - Parameter threadId: Thread UUID to clear cache for
    func clearCache(for threadId: UUID) {
        let cacheKey = "suggestions_\(threadId.uuidString)" as NSString
        cache.removeObject(forKey: cacheKey)
        print("🗑️  [SMART_REPLY_SERVICE] Cleared cache for thread: \(threadId)")
    }

    /// Clear all cached suggestions
    func clearAllCache() {
        cache.removeAllObjects()
        print("🗑️  [SMART_REPLY_SERVICE] Cleared all cached suggestions")
    }

    // MARK: - Private HTTP Methods

    /// Perform HTTP request with authentication and retry logic
    private func performRequest(
        endpoint: URL,
        method: String,
        body: [String: Any]? = nil,
        attempt: Int = 1
    ) async throws -> Data {
        // Get authentication token
        guard let token = await authManager.getAccessToken() else {
            print("❌ [SMART_REPLY_SERVICE] No authentication token available")
            throw AIServiceError.unauthorized
        }

        // Build request
        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add body if present
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw AIServiceError.decodingError(error)
            }
        }

        // Perform request
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }

            print("📡 [SMART_REPLY_SERVICE] Response status: \(httpResponse.statusCode)")

            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                return data

            case 401:
                // Unauthorized - token may be expired
                print("⚠️  [SMART_REPLY_SERVICE] Unauthorized (401) - attempting token refresh")
                throw AIServiceError.unauthorized

            case 403:
                // Forbidden - likely feature not available for tier
                throw AIServiceError.forbidden

            case 429:
                // Rate limit exceeded
                print("⚠️  [SMART_REPLY_SERVICE] Rate limit exceeded (429)")

                // Parse rate limit headers
                let resetTime = parseRateLimitReset(from: httpResponse)

                // Retry after delay if we haven't exceeded max retries
                if attempt < maxRetries {
                    let delay = resetTime ?? retryDelay * Double(attempt)
                    print("🔄 [SMART_REPLY_SERVICE] Retrying after \(delay) seconds (attempt \(attempt + 1)/\(maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
                } else {
                    // Convert TimeInterval (seconds from now) to Date
                    let retryAfterDate = resetTime.map { Date().addingTimeInterval($0) }
                    throw AIServiceError.rateLimitExceeded(retryAfter: retryAfterDate, remainingQuota: nil, tierLimit: nil)
                }

            case 400...499:
                // Client error
                let errorMessage = parseErrorMessage(from: data)
                throw AIServiceError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)

            case 500...599:
                // Server error - retry with exponential backoff
                if attempt < maxRetries {
                    let delay = retryDelay * Double(attempt)
                    print("🔄 [SMART_REPLY_SERVICE] Server error (\(httpResponse.statusCode)) - retrying after \(delay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
                } else {
                    throw AIServiceError.backendError(message: "Server error")
                }

            default:
                throw AIServiceError.httpError(statusCode: httpResponse.statusCode, message: "Unexpected status code")
            }

        } catch let error as AIServiceError {
            // Re-throw AIService errors
            throw error
        } catch {
            // Network or other errors
            print("❌ [SMART_REPLY_SERVICE] Network error: \(error.localizedDescription)")

            // Retry on network errors
            if attempt < maxRetries {
                let delay = retryDelay * Double(attempt)
                print("🔄 [SMART_REPLY_SERVICE] Network error - retrying after \(delay) seconds")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
            } else {
                throw AIServiceError.networkError(error)
            }
        }
    }

    /// Parse rate limit reset time from response headers
    private func parseRateLimitReset(from response: HTTPURLResponse) -> TimeInterval? {
        // Check for X-RateLimit-Reset header (Unix timestamp)
        if let resetHeader = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = TimeInterval(resetHeader) {
            let resetDate = Date(timeIntervalSince1970: resetTimestamp)
            let delay = resetDate.timeIntervalSinceNow
            return max(0, delay)
        }

        // Check for Retry-After header (seconds)
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let delay = TimeInterval(retryAfter) {
            return delay
        }

        return nil
    }

    /// Parse error message from response data
    private func parseErrorMessage(from data: Data) -> String {
        struct ErrorResponse: Decodable {
            let message: String?
            let error: String?
        }

        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            return "Unknown error"
        }

        return response.message ?? response.error ?? "Unknown error"
    }

    // MARK: - State Management

    private func setProcessing(_ value: Bool) async {
        await MainActor.run {
            self.isProcessing = value
        }
    }

    private func incrementRequestCount() {
        Task { @MainActor in
            self.requestCount += 1
        }
    }

    /// Clear last error
    func clearError() {
        lastError = nil
    }

    /// Reset request count (useful for testing or analytics)
    func resetRequestCount() {
        requestCount = 0
    }
}
