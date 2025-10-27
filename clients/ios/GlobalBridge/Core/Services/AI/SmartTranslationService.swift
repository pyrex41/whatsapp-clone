//
//  SmartTranslationService.swift
//  GlobalBridge
//
//  Provides smart translation with user preferences and per-contact/thread overrides
//  Integrates with Phoenix backend AI translation endpoints
//

import Foundation
import Combine

/// Smart translation service with user preferences and caching
@MainActor
final class SmartTranslationService: ObservableObject {

    // MARK: - Singleton

    static let shared = SmartTranslationService()

    // MARK: - Published Properties

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: AIServiceError?
    @Published private(set) var preferences: TranslationPreferences = .default

    // MARK: - Dependencies

    private let session: URLSession
    private let authManager: AuthManager
    private let baseURL: URL

    // MARK: - Configuration

    private let requestTimeout: TimeInterval = 30.0
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0

    // MARK: - Caching

    private let cache = NSCache<NSString, CachedTranslation>()
    private let translationCacheTTL: TimeInterval = 3600.0 // 1 hour

    private final class CachedTranslation {
        let translation: String
        let timestamp: Date
        let ttl: TimeInterval

        init(translation: String, timestamp: Date, ttl: TimeInterval) {
            self.translation = translation
            self.timestamp = timestamp
            self.ttl = ttl
        }

        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    // MARK: - Initialization

    init(
        session: URLSession = .shared,
        authManager: AuthManager = .shared,
        baseURL: URL? = nil
    ) {
        self.session = session
        self.authManager = authManager

        // Determine base URL based on environment
        if let providedURL = baseURL {
            self.baseURL = providedURL
        } else {
            #if DEBUG
            // Check for local development override
            if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"],
               backendEnv.lowercased() == "local" {
                self.baseURL = URL(string: "http://localhost:4000")!
            } else {
                self.baseURL = URL(string: "https://globalbridge-backend.fly.dev")!
            }
            #else
            self.baseURL = URL(string: "https://globalbridge-backend.fly.dev")!
            #endif
        }

        // Configure cache limits
        cache.countLimit = 1000 // Maximum 1000 cached translations
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB

        print("🌐 [SMART_TRANSLATION_SERVICE] Initialized with base URL: \(self.baseURL.absoluteString)")

        // Load preferences asynchronously on init
        Task {
            do {
                try await loadPreferences()
            } catch {
                print("⚠️  [SMART_TRANSLATION_SERVICE] Failed to load initial preferences: \(error)")
            }
        }
    }

    // MARK: - Public Methods

    /// Translate a message to the target language
    /// - Parameters:
    ///   - messageId: Message UUID for caching
    ///   - text: Text to translate (max 10,000 characters)
    ///   - targetLanguage: Target language code (e.g., "en", "es", "fr")
    /// - Returns: Translated text string
    /// - Throws: AIServiceError for various failure cases
    func translateMessage(
        messageId: UUID,
        text: String,
        targetLanguage: String
    ) async throws -> String {
        // Validate input
        guard !text.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Text cannot be empty")
        }

        guard text.count <= 10000 else {
            throw AIServiceError.invalidInput(reason: "Text exceeds 10,000 character limit")
        }

        guard !targetLanguage.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Target language cannot be empty")
        }

        // Check cache first
        let cacheKey = "translation_\(messageId)_\(targetLanguage)" as NSString
        if let cached = cache.object(forKey: cacheKey), cached.isValid {
            print("✅ [SMART_TRANSLATION_SERVICE] Returning cached translation for message: \(messageId)")
            return cached.translation
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/translate")
        let requestBody: [String: Any] = [
            "message_id": messageId.uuidString,
            "text": text,
            "target_language": targetLanguage
        ]

        print("🌐 [SMART_TRANSLATION_SERVICE] Translating message: \(messageId) to \(targetLanguage) (\(text.count) chars)")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct TranslationResponse: Decodable {
            let success: Bool
            let translation: String
            let sourceLanguage: String?

            enum CodingKeys: String, CodingKey {
                case success
                case translation
                case sourceLanguage = "source_language"
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(TranslationResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.backendError(message: "Translation failed")
        }

        // Cache the translation
        let cachedValue = CachedTranslation(
            translation: response.translation,
            timestamp: Date(),
            ttl: translationCacheTTL
        )
        cache.setObject(cachedValue, forKey: cacheKey)

        print("✅ [SMART_TRANSLATION_SERVICE] Translation successful (source: \(response.sourceLanguage ?? "auto"))")

        return response.translation
    }

    /// Update user translation preferences
    /// - Parameter prefs: New TranslationPreferences to save
    /// - Throws: AIServiceError for various failure cases
    func updatePreferences(_ prefs: TranslationPreferences) async throws {
        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/translation_preferences")
        let requestBody: [String: Any] = [
            "preferred_language": prefs.preferredLanguage,
            "auto_translate_enabled": prefs.autoTranslateEnabled,
            "contact_overrides": prefs.contactOverrides,
            "thread_overrides": prefs.threadOverrides
        ]

        print("🌐 [SMART_TRANSLATION_SERVICE] Updating translation preferences (preferred: \(prefs.preferredLanguage))")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "PUT",
            body: requestBody
        )

        // Parse response
        struct PreferencesResponse: Decodable {
            let success: Bool
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(PreferencesResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.backendError(message: "Failed to update preferences")
        }

        // Update local preferences
        await MainActor.run {
            self.preferences = prefs
        }

        print("✅ [SMART_TRANSLATION_SERVICE] Preferences updated successfully")
    }

    /// Get user translation preferences from backend
    /// - Returns: TranslationPreferences for current user
    /// - Throws: AIServiceError for various failure cases
    func getPreferences() async throws -> TranslationPreferences {
        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/translation_preferences")

        print("🌐 [SMART_TRANSLATION_SERVICE] Fetching translation preferences")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil
        )

        // Parse response
        struct PreferencesResponse: Decodable {
            let success: Bool
            let preferences: PreferencesData

            struct PreferencesData: Decodable {
                let preferredLanguage: String
                let autoTranslateEnabled: Bool
                let contactOverrides: [String: Bool]
                let threadOverrides: [String: Bool]

                enum CodingKeys: String, CodingKey {
                    case preferredLanguage = "preferred_language"
                    case autoTranslateEnabled = "auto_translate_enabled"
                    case contactOverrides = "contact_overrides"
                    case threadOverrides = "thread_overrides"
                }
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(PreferencesResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.backendError(message: "Failed to fetch preferences")
        }

        // Convert to domain model
        let prefs = TranslationPreferences(
            preferredLanguage: response.preferences.preferredLanguage,
            autoTranslateEnabled: response.preferences.autoTranslateEnabled,
            contactOverrides: response.preferences.contactOverrides,
            threadOverrides: response.preferences.threadOverrides
        )

        // Update local preferences
        await MainActor.run {
            self.preferences = prefs
        }

        print("✅ [SMART_TRANSLATION_SERVICE] Preferences fetched (preferred: \(prefs.preferredLanguage))")

        return prefs
    }

    /// Clear cached translation for a specific message
    /// - Parameters:
    ///   - messageId: Message UUID
    ///   - targetLanguage: Target language code
    func clearCache(for messageId: UUID, targetLanguage: String) {
        let cacheKey = "translation_\(messageId)_\(targetLanguage)" as NSString
        cache.removeObject(forKey: cacheKey)
        print("🗑️  [SMART_TRANSLATION_SERVICE] Cleared cache for message: \(messageId) (\(targetLanguage))")
    }

    /// Clear all cached translations
    func clearAllCache() {
        cache.removeAllObjects()
        print("🗑️  [SMART_TRANSLATION_SERVICE] Cleared all cached translations")
    }

    // MARK: - Private Methods

    /// Load preferences on initialization
    private func loadPreferences() async throws {
        do {
            _ = try await getPreferences()
        } catch {
            print("⚠️  [SMART_TRANSLATION_SERVICE] Failed to load preferences, using defaults: \(error)")
            // Keep using default preferences if load fails
        }
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
            print("❌ [SMART_TRANSLATION_SERVICE] No authentication token available")
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

            print("📡 [SMART_TRANSLATION_SERVICE] Response status: \(httpResponse.statusCode)")

            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                return data

            case 401:
                // Unauthorized - token may be expired
                print("⚠️  [SMART_TRANSLATION_SERVICE] Unauthorized (401) - attempting token refresh")
                throw AIServiceError.unauthorized

            case 403:
                // Forbidden - likely feature not available for tier
                throw AIServiceError.forbidden

            case 429:
                // Rate limit exceeded
                print("⚠️  [SMART_TRANSLATION_SERVICE] Rate limit exceeded (429)")

                // Parse rate limit headers
                let resetTime = parseRateLimitReset(from: httpResponse)

                // Retry after delay if we haven't exceeded max retries
                if attempt < maxRetries {
                    let delay = resetTime ?? retryDelay * Double(attempt)
                    print("🔄 [SMART_TRANSLATION_SERVICE] Retrying after \(delay) seconds (attempt \(attempt + 1)/\(maxRetries))")
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
                    print("🔄 [SMART_TRANSLATION_SERVICE] Server error (\(httpResponse.statusCode)) - retrying after \(delay) seconds")
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
            print("❌ [SMART_TRANSLATION_SERVICE] Network error: \(error.localizedDescription)")

            // Retry on network errors
            if attempt < maxRetries {
                let delay = retryDelay * Double(attempt)
                print("🔄 [SMART_TRANSLATION_SERVICE] Network error - retrying after \(delay) seconds")
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

    /// Clear last error
    func clearError() {
        lastError = nil
    }
}
