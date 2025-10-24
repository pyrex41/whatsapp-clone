//
//  AIService.swift
//  GlobalBridge
//
//  AI-powered features service with intelligent caching and rate limiting
//  - Translation with cultural context
//  - Thread summarization
//  - Semantic search across languages
//  - Task extraction from conversations
//  - Automatic rate limiting and retry logic
//  - Multi-tier caching (memory + disk)
//

import Foundation

/// Service for AI-powered communication features
@MainActor
final class AIService {

    // MARK: - Singleton

    static let shared = AIService()

    // MARK: - Properties

    private let baseURL: URL
    private let session: URLSession
    private let authManager: AuthManager
    private let cache: AIServiceCache
    private let rateLimiter: RateLimitTracker

    /// Configuration
    private let config: AIServiceConfiguration

    // MARK: - Configuration

    struct AIServiceConfiguration {
        let maxRetries: Int
        let requestTimeout: TimeInterval
        let enableCaching: Bool

        static let `default` = AIServiceConfiguration(
            maxRetries: 3,
            requestTimeout: 30,
            enableCaching: true
        )
    }

    // MARK: - Initialization

    private init(
        baseURL: URL? = nil,
        config: AIServiceConfiguration = .default,
        session: URLSession = .shared,
        authManager: AuthManager = .shared,
        cache: AIServiceCache = .shared,
        rateLimiter: RateLimitTracker = .shared
    ) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.config = config
        self.session = session
        self.authManager = authManager
        self.cache = cache
        self.rateLimiter = rateLimiter

        print("✅ [AI_SERVICE] Initialized with base URL: \(self.baseURL)")
    }

    private static var defaultBaseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:4000")!
        #else
        return URL(string: "https://globalbridge-backend.fly.dev")!
        #endif
    }

    // MARK: - Translation

    /// Translate text with caching
    func translate(
        text: String,
        targetLanguage: String,
        sourceLanguage: String? = nil
    ) async throws -> TranslationResult {
        // Generate cache key
        let cacheKey = translationCacheKey(text: text, target: targetLanguage, source: sourceLanguage)

        // Check cache first
        if config.enableCaching,
           let cached: TranslationResult = await cache.retrieve(forKey: cacheKey, type: .translation) {
            print("✅ [AI_SERVICE] Translation cache hit")
            return cached
        }

        // Check rate limit
        let rateLimitCheck = rateLimiter.canMakeRequest(for: .translation)
        guard rateLimitCheck.isAllowed else {
            throw AIServiceError.rateLimited(rateLimitCheck.errorMessage ?? "Rate limit exceeded")
        }

        // Make request with retry logic
        let result = try await performTranslation(
            text: text,
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage
        )

        // Record usage
        rateLimiter.recordRequest(for: .translation)

        // Cache result
        if config.enableCaching {
            await cache.store(result, forKey: cacheKey, type: .translation)
        }

        return result
    }

    private func performTranslation(
        text: String,
        targetLanguage: String,
        sourceLanguage: String?,
        attempt: Int = 1
    ) async throws -> TranslationResult {
        let url = baseURL.appendingPathComponent("api/v1/ai/translate")
        var request = URLRequest(url: url, timeoutInterval: config.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth header
        if let token = await authManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Request body
        let body: [String: Any] = [
            "text": text,
            "target_language": targetLanguage,
            "source_language": sourceLanguage ?? "auto"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }

            // Process rate limit headers
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String, let value = pair.value as? String {
                    result[key] = value
                }
            }
            rateLimiter.processRateLimitHeaders(headers, for: .translation)

            // Handle 429 with exponential backoff
            if httpResponse.statusCode == 429 {
                let retryAfter = parseRetryAfterHeader(headers)
                rateLimiter.handle429Response(for: .translation, retryAfter: retryAfter)

                // Retry if attempts remain
                if attempt < config.maxRetries {
                    let backoffTime = retryAfter ?? pow(2.0, Double(attempt)) // Exponential backoff
                    print("⏰ [AI_SERVICE] 429 response - retrying in \(backoffTime)s (attempt \(attempt + 1))")

                    try await Task.sleep(nanoseconds: UInt64(backoffTime * 1_000_000_000))
                    return try await performTranslation(
                        text: text,
                        targetLanguage: targetLanguage,
                        sourceLanguage: sourceLanguage,
                        attempt: attempt + 1
                    )
                } else {
                    throw AIServiceError.rateLimited("Too many requests. Please try again later.")
                }
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let apiResponse = try decoder.decode(TranslationAPIResponse.self, from: data)

            return apiResponse.toTranslationResult()
        } catch {
            if let aiError = error as? AIServiceError {
                throw aiError
            }
            throw AIServiceError.networkError(error)
        }
    }

    // MARK: - Thread Summarization

    /// Summarize a thread with caching
    func summarizeThread(threadId: String, invalidateCache: Bool = false) async throws -> ThreadSummary {
        let cacheKey = "thread_\(threadId)"

        // Invalidate cache if requested (new messages)
        if invalidateCache {
            cache.remove(forKey: cacheKey, type: .summary)
        }

        // Check cache
        if config.enableCaching,
           let cached: ThreadSummary = await cache.retrieve(forKey: cacheKey, type: .summary) {
            print("✅ [AI_SERVICE] Summary cache hit for thread \(threadId)")
            return cached
        }

        // Check rate limit
        let rateLimitCheck = rateLimiter.canMakeRequest(for: .summarization)
        guard rateLimitCheck.isAllowed else {
            throw AIServiceError.rateLimited(rateLimitCheck.errorMessage ?? "Rate limit exceeded")
        }

        // Make request
        let summary = try await performSummarization(threadId: threadId)

        // Record usage
        rateLimiter.recordRequest(for: .summarization)

        // Cache result
        if config.enableCaching {
            await cache.store(summary, forKey: cacheKey, type: .summary)
        }

        return summary
    }

    private func performSummarization(threadId: String) async throws -> ThreadSummary {
        let url = baseURL.appendingPathComponent("api/v1/ai/summarize")
        var request = URLRequest(url: url, timeoutInterval: config.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await authManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ["thread_id": threadId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        // Process rate limit headers
        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        rateLimiter.processRateLimitHeaders(headers, for: .summarization)

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                rateLimiter.handle429Response(for: .summarization, retryAfter: parseRetryAfterHeader(headers))
            }
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ThreadSummary.self, from: data)
    }

    // MARK: - Semantic Search

    /// Search messages semantically with caching
    func semanticSearch(query: String, threadId: String? = nil) async throws -> [SearchResult] {
        let cacheKey = searchCacheKey(query: query, threadId: threadId)

        // Check cache
        if config.enableCaching,
           let cached: [SearchResult] = await cache.retrieve(forKey: cacheKey, type: .search) {
            print("✅ [AI_SERVICE] Search cache hit for query: \(query)")
            return cached
        }

        // Check rate limit
        let rateLimitCheck = rateLimiter.canMakeRequest(for: .search)
        guard rateLimitCheck.isAllowed else {
            throw AIServiceError.rateLimited(rateLimitCheck.errorMessage ?? "Rate limit exceeded")
        }

        // Make request
        let results = try await performSearch(query: query, threadId: threadId)

        // Record usage
        rateLimiter.recordRequest(for: .search)

        // Cache results
        if config.enableCaching {
            await cache.store(results, forKey: cacheKey, type: .search)
        }

        return results
    }

    private func performSearch(query: String, threadId: String?) async throws -> [SearchResult] {
        let url = baseURL.appendingPathComponent("api/v1/ai/search")
        var request = URLRequest(url: url, timeoutInterval: config.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await authManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["query": query]
        if let threadId = threadId {
            body["thread_id"] = threadId
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        rateLimiter.processRateLimitHeaders(headers, for: .search)

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                rateLimiter.handle429Response(for: .search, retryAfter: parseRetryAfterHeader(headers))
            }
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let apiResponse = try decoder.decode(SearchAPIResponse.self, from: data)
        return apiResponse.results
    }

    // MARK: - Task Extraction

    /// Extract tasks from thread
    func extractTasks(threadId: String) async throws -> [ExtractedTask] {
        // No caching for task extraction (tasks change frequently)

        // Check rate limit
        let rateLimitCheck = rateLimiter.canMakeRequest(for: .taskExtraction)
        guard rateLimitCheck.isAllowed else {
            throw AIServiceError.rateLimited(rateLimitCheck.errorMessage ?? "Rate limit exceeded")
        }

        let tasks = try await performTaskExtraction(threadId: threadId)

        // Record usage
        rateLimiter.recordRequest(for: .taskExtraction)

        return tasks
    }

    private func performTaskExtraction(threadId: String) async throws -> [ExtractedTask] {
        let url = baseURL.appendingPathComponent("api/v1/ai/extract-tasks")
        var request = URLRequest(url: url, timeoutInterval: config.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await authManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = ["thread_id": threadId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        rateLimiter.processRateLimitHeaders(headers, for: .taskExtraction)

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                rateLimiter.handle429Response(for: .taskExtraction, retryAfter: parseRetryAfterHeader(headers))
            }
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let apiResponse = try decoder.decode(TaskExtractionAPIResponse.self, from: data)
        return apiResponse.tasks
    }

    // MARK: - Utilities

    /// Get quota summary for UI display
    func getQuotaSummary() -> [RateLimitTracker.AIFeature: QuotaSummary] {
        return rateLimiter.getQuotaSummary()
    }

    /// Get cache metrics
    func getCacheMetrics() -> CacheMetrics {
        return cache.getMetrics()
    }

    /// Clear all caches
    func clearCaches() async {
        await cache.clearAll()
    }

    /// Reset rate limits (for testing)
    func resetRateLimits() {
        rateLimiter.resetQuotas()
    }

    // MARK: - Private Helpers

    private func translationCacheKey(text: String, target: String, source: String?) -> String {
        let sourceKey = source ?? "auto"
        return "\(text)_\(sourceKey)_\(target)".data(using: .utf8)?.base64EncodedString() ?? text
    }

    private func searchCacheKey(query: String, threadId: String?) -> String {
        if let threadId = threadId {
            return "\(query)_thread_\(threadId)"
        }
        return query
    }

    private func parseRetryAfterHeader(_ headers: [String: String]) -> TimeInterval? {
        guard let retryAfter = headers["Retry-After"] else {
            return nil
        }

        // Try parsing as seconds
        if let seconds = TimeInterval(retryAfter) {
            return seconds
        }

        // Try parsing as HTTP date
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        if let date = formatter.date(from: retryAfter) {
            return date.timeIntervalSinceNow
        }

        return nil
    }
}

// MARK: - API Response Models

private struct TranslationAPIResponse: Codable {
    let translatedText: String
    let detectedLanguage: String?
    let confidence: Double?

    func toTranslationResult() -> TranslationResult {
        return TranslationResult(
            translatedText: translatedText,
            detectedLanguage: detectedLanguage,
            confidence: confidence
        )
    }
}

private struct SearchAPIResponse: Codable {
    let results: [SearchResult]
}

private struct TaskExtractionAPIResponse: Codable {
    let tasks: [ExtractedTask]
}

// MARK: - Public Models

struct TranslationResult: Codable {
    let translatedText: String
    let detectedLanguage: String?
    let confidence: Double?
}

struct ThreadSummary: Codable {
    let summary: String
    let keyPoints: [String]?
    let participantCount: Int?
    let messageCount: Int?
}

struct SearchResult: Codable {
    let messageId: String
    let threadId: String
    let content: String
    let score: Double
    let timestamp: Date
}

struct ExtractedTask: Codable {
    let description: String
    let assignee: String?
    let dueDate: Date?
    let priority: String?
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case invalidResponse
    case rateLimited(String)
    case httpError(statusCode: Int)
    case networkError(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .rateLimited(let message):
            return message
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .notAuthenticated:
            return "Please log in to use AI features"
        }
    }
}
