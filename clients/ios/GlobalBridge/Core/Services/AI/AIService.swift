//
//  AIService.swift
//  GlobalBridge
//
//  Concrete implementation of AIServiceProtocol with full HTTP networking layer
//  Integrates with Auth0 authentication and FeatureFlags tier checking
//

import Foundation
import Combine

/// Concrete AI service implementation with HTTP networking and authentication
@MainActor
final class AIService: ObservableObject {

    // MARK: - Singleton

    static let shared = AIService()

    // MARK: - Published Properties

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: AIServiceError?
    @Published private(set) var requestCount: Int = 0

    // MARK: - Dependencies

    private let session: URLSession
    private let authManager: AuthManager
    private let featureFlags: FeatureFlags
    private let baseURL: URL

    // MARK: - Configuration

    private let requestTimeout: TimeInterval = 30.0
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0

    // MARK: - Initialization

    init(
        session: URLSession = .shared,
        authManager: AuthManager = .shared,
        featureFlags: FeatureFlags = .shared,
        baseURL: URL? = nil
    ) {
        self.session = session
        self.authManager = authManager
        self.featureFlags = featureFlags

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

        print("🤖 [AI_SERVICE] Initialized with base URL: \(self.baseURL.absoluteString)")
    }

    // MARK: - Translation

    /// Translate text from one language to another
    /// - Parameters:
    ///   - text: Text to translate (max 10,000 characters)
    ///   - sourceLanguage: Source language code (optional, defaults to "auto")
    ///   - targetLanguage: Target language code (required)
    /// - Returns: TranslationResult with translated text and metadata
    /// - Throws: AIServiceError for various failure cases
    func translate(
        text: String,
        sourceLanguage: String? = "auto",
        targetLanguage: String
    ) async throws -> TranslationResult {
        // Check feature availability
        guard featureFlags.hasFeature(.translationEnabled) else {
            print("❌ [AI_SERVICE] Translation feature not enabled for tier")
            throw AIServiceError.featureDisabled(feature: "translation")
        }

        // Validate input
        guard !text.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Text cannot be empty")
        }

        guard text.count <= 10000 else {
            throw AIServiceError.invalidInput(reason: "Text exceeds 10,000 character limit")
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/translate")
        let requestBody: [String: Any] = [
            "text": text,
            "source_language": sourceLanguage ?? "auto",
            "target_language": targetLanguage
        ]

        print("🌐 [AI_SERVICE] Translating text (\(text.count) chars) from \(sourceLanguage ?? "auto") to \(targetLanguage)")

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
            let targetLanguage: String

            enum CodingKeys: String, CodingKey {
                case success
                case translation
                case sourceLanguage = "source_language"
                case targetLanguage = "target_language"
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(TranslationResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.apiError(message: "Translation failed")
        }

        let result = TranslationResult(
            originalText: text,
            translatedText: response.translation,
            sourceLanguage: response.sourceLanguage ?? sourceLanguage ?? "auto",
            targetLanguage: response.targetLanguage,
            confidence: nil // Backend doesn't return confidence for now
        )

        print("✅ [AI_SERVICE] Translation successful")
        incrementRequestCount()

        return result
    }

    // MARK: - Summarization

    /// Summarize a thread conversation
    /// - Parameters:
    ///   - threadId: Thread UUID to summarize
    ///   - maxLength: Maximum summary length (1-1,000 characters, defaults to 200)
    /// - Returns: SummarizationResult with summary text and metadata
    /// - Throws: AIServiceError for various failure cases
    func summarizeThread(
        threadId: String,
        maxLength: Int = 200
    ) async throws -> SummarizationResult {
        // Check feature availability
        guard featureFlags.hasFeature(.threadSummarization) else {
            print("❌ [AI_SERVICE] Thread summarization not enabled for tier")
            throw AIServiceError.featureDisabled(feature: "thread_summarization")
        }

        // Validate input
        guard !threadId.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Thread ID cannot be empty")
        }

        guard (1...1000).contains(maxLength) else {
            throw AIServiceError.invalidInput(reason: "Max length must be between 1 and 1,000")
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/summarize_thread")
        let requestBody: [String: Any] = [
            "thread_id": threadId,
            "max_length": maxLength
        ]

        print("📝 [AI_SERVICE] Summarizing thread: \(threadId) (max length: \(maxLength))")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct SummarizationResponse: Decodable {
            let success: Bool
            let summary: String
            let threadId: String
            let maxLength: Int

            enum CodingKeys: String, CodingKey {
                case success
                case summary
                case threadId = "thread_id"
                case maxLength = "max_length"
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(SummarizationResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.apiError(message: "Summarization failed")
        }

        let result = SummarizationResult(
            summary: response.summary,
            threadId: response.threadId,
            messageCount: nil // Backend doesn't return message count
        )

        print("✅ [AI_SERVICE] Thread summarization successful")
        incrementRequestCount()

        return result
    }

    // MARK: - Semantic Search

    /// Search messages using semantic similarity
    /// - Parameters:
    ///   - query: Search query (max 1,000 characters)
    ///   - threadId: Optional thread to search within
    ///   - limit: Maximum results (1-50, defaults to 10)
    ///   - recencyBias: Prioritize recent messages (defaults to true)
    /// - Returns: Array of SearchResult with matching messages
    /// - Throws: AIServiceError for various failure cases
    func searchSemantic(
        query: String,
        threadId: String? = nil,
        limit: Int = 10,
        recencyBias: Bool = true
    ) async throws -> [SearchResult] {
        // Check feature availability
        guard featureFlags.hasFeature(.semanticSearch) else {
            print("❌ [AI_SERVICE] Semantic search not enabled for tier")
            throw AIServiceError.featureDisabled(feature: "semantic_search")
        }

        // Validate input
        guard !query.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Query cannot be empty")
        }

        guard query.count <= 1000 else {
            throw AIServiceError.invalidInput(reason: "Query exceeds 1,000 character limit")
        }

        guard (1...50).contains(limit) else {
            throw AIServiceError.invalidInput(reason: "Limit must be between 1 and 50")
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/search_semantic")
        var requestBody: [String: Any] = [
            "query": query,
            "limit": limit,
            "recency_bias": recencyBias,
            "translate": false
        ]

        if let threadId = threadId {
            requestBody["thread_id"] = threadId
        }

        print("🔍 [AI_SERVICE] Semantic search: '\(query)' (limit: \(limit), thread: \(threadId ?? "all"))")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct SearchResponse: Decodable {
            let success: Bool
            let results: [ResultItem]

            struct ResultItem: Decodable {
                let messageId: String
                let content: String
                let score: Double
                let threadId: String?
                let timestamp: String?

                enum CodingKeys: String, CodingKey {
                    case messageId = "message_id"
                    case content
                    case score
                    case threadId = "thread_id"
                    case timestamp
                }
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(SearchResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.apiError(message: "Semantic search failed")
        }

        let results = response.results.map { item in
            SearchResult(
                messageId: item.messageId,
                content: item.content,
                relevanceScore: item.score,
                threadId: item.threadId,
                timestamp: item.timestamp
            )
        }

        print("✅ [AI_SERVICE] Semantic search returned \(results.count) results")
        incrementRequestCount()

        return results
    }

    // MARK: - Task Extraction

    /// Extract actionable tasks from a thread conversation
    /// - Parameters:
    ///   - threadId: Thread UUID to analyze
    ///   - query: Optional custom query (defaults to "tasks, deadlines, decisions, commitments")
    /// - Returns: TaskExtractionResult with extracted tasks and metadata
    /// - Throws: AIServiceError for various failure cases
    func extractTasks(
        threadId: String,
        query: String? = nil
    ) async throws -> TaskExtractionResult {
        // Check feature availability (using thread_summarization as proxy for task extraction)
        guard featureFlags.hasFeature(.threadSummarization) else {
            print("❌ [AI_SERVICE] Task extraction not enabled for tier")
            throw AIServiceError.featureDisabled(feature: "task_extraction")
        }

        // Validate input
        guard !threadId.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Thread ID cannot be empty")
        }

        if let query = query, query.count > 1000 {
            throw AIServiceError.invalidInput(reason: "Query exceeds 1,000 character limit")
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/extract_tasks")
        var requestBody: [String: Any] = [
            "thread_id": threadId
        ]

        if let query = query {
            requestBody["query"] = query
        }

        print("📋 [AI_SERVICE] Extracting tasks from thread: \(threadId)")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct TaskExtractionResponse: Decodable {
            let success: Bool
            let extraction: ExtractionData

            struct ExtractionData: Decodable {
                let tasks: [String]
                let deadlines: [String]?
                let decisions: [String]?
                let commitments: [String]?
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(TaskExtractionResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.apiError(message: "Task extraction failed")
        }

        let result = TaskExtractionResult(
            tasks: response.extraction.tasks,
            deadlines: response.extraction.deadlines ?? [],
            decisions: response.extraction.decisions ?? [],
            threadId: threadId
        )

        print("✅ [AI_SERVICE] Extracted \(result.tasks.count) tasks")
        incrementRequestCount()

        return result
    }

    // MARK: - Tone Analysis

    /// Analyze the emotional tone of text
    /// - Parameters:
    ///   - text: Text to analyze (max 10,000 characters)
    ///   - language: Language code (optional, defaults to "en")
    /// - Returns: ToneAnalysisResult with tone classification and confidence
    /// - Throws: AIServiceError for various failure cases
    func analyzeTone(
        text: String,
        language: String = "en"
    ) async throws -> ToneAnalysisResult {
        // Validate input
        guard !text.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Text cannot be empty")
        }

        guard text.count <= 10000 else {
            throw AIServiceError.invalidInput(reason: "Text exceeds 10,000 character limit")
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/analyze_tone")
        let requestBody: [String: Any] = [
            "text": text,
            "language": language
        ]

        print("🎭 [AI_SERVICE] Analyzing tone for text (\(text.count) chars, lang: \(language))")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct ToneAnalysisResponse: Decodable {
            let success: Bool
            let analysis: AnalysisData

            struct AnalysisData: Decodable {
                let tone: String
                let confidence: Double
                let emotions: [String]?
                let language: String
            }
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(ToneAnalysisResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.apiError(message: "Tone analysis failed")
        }

        let result = ToneAnalysisResult(
            tone: response.analysis.tone,
            confidence: response.analysis.confidence,
            emotions: response.analysis.emotions ?? [],
            language: response.analysis.language
        )

        print("✅ [AI_SERVICE] Tone analysis complete: \(result.tone) (confidence: \(result.confidence))")
        incrementRequestCount()

        return result
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
            print("❌ [AI_SERVICE] No authentication token available")
            throw AIServiceError.notAuthenticated
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
                throw AIServiceError.encodingError(error)
            }
        }

        // Perform request
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }

            print("📡 [AI_SERVICE] Response status: \(httpResponse.statusCode)")

            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                return data

            case 401:
                // Unauthorized - token may be expired
                print("⚠️  [AI_SERVICE] Unauthorized (401) - attempting token refresh")
                throw AIServiceError.unauthorized

            case 403:
                // Forbidden - likely feature not available for tier
                throw AIServiceError.forbidden

            case 429:
                // Rate limit exceeded
                print("⚠️  [AI_SERVICE] Rate limit exceeded (429)")

                // Parse rate limit headers
                let resetTime = parseRateLimitReset(from: httpResponse)

                // Retry after delay if we haven't exceeded max retries
                if attempt < maxRetries {
                    let delay = resetTime ?? retryDelay * Double(attempt)
                    print("🔄 [AI_SERVICE] Retrying after \(delay) seconds (attempt \(attempt + 1)/\(maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
                } else {
                    throw AIServiceError.rateLimitExceeded(retryAfter: resetTime)
                }

            case 400...499:
                // Client error
                let errorMessage = parseErrorMessage(from: data)
                throw AIServiceError.clientError(statusCode: httpResponse.statusCode, message: errorMessage)

            case 500...599:
                // Server error - retry with exponential backoff
                if attempt < maxRetries {
                    let delay = retryDelay * Double(attempt)
                    print("🔄 [AI_SERVICE] Server error (\(httpResponse.statusCode)) - retrying after \(delay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
                } else {
                    throw AIServiceError.serverError(statusCode: httpResponse.statusCode)
                }

            default:
                throw AIServiceError.unexpectedStatusCode(httpResponse.statusCode)
            }

        } catch let error as AIServiceError {
            // Re-throw AIService errors
            throw error
        } catch {
            // Network or other errors
            print("❌ [AI_SERVICE] Network error: \(error.localizedDescription)")

            // Retry on network errors
            if attempt < maxRetries {
                let delay = retryDelay * Double(attempt)
                print("🔄 [AI_SERVICE] Network error - retrying after \(delay) seconds")
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

// MARK: - Result Types

/// Translation result with metadata
struct TranslationResult {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let confidence: Double?
}

/// Thread summarization result
struct SummarizationResult {
    let summary: String
    let threadId: String
    let messageCount: Int?
}

/// Semantic search result
struct SearchResult {
    let messageId: String
    let content: String
    let relevanceScore: Double
    let threadId: String?
    let timestamp: String?
}

/// Task extraction result
struct TaskExtractionResult {
    let tasks: [String]
    let deadlines: [String]
    let decisions: [String]
    let threadId: String
}

/// Tone analysis result
struct ToneAnalysisResult {
    let tone: String
    let confidence: Double
    let emotions: [String]
    let language: String
}

// MARK: - Error Types

/// Comprehensive error type for AI service operations
enum AIServiceError: LocalizedError, Equatable {
    case notAuthenticated
    case unauthorized
    case forbidden
    case featureDisabled(feature: String)
    case invalidInput(reason: String)
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case quotaExceeded
    case invalidResponse
    case encodingError(Error)
    case networkError(Error)
    case clientError(statusCode: Int, message: String)
    case serverError(statusCode: Int)
    case unexpectedStatusCode(Int)
    case apiError(message: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please log in."
        case .unauthorized:
            return "Authentication token expired. Please log in again."
        case .forbidden:
            return "Access forbidden. This feature may not be available for your account tier."
        case .featureDisabled(let feature):
            return "Feature '\(feature)' is not enabled for your account tier."
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .rateLimitExceeded(let retryAfter):
            if let delay = retryAfter {
                return "Rate limit exceeded. Please try again in \(Int(delay)) seconds."
            }
            return "Rate limit exceeded. Please try again later."
        case .quotaExceeded:
            return "Usage quota exceeded. Please upgrade your plan."
        case .invalidResponse:
            return "Invalid response from server."
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .clientError(let statusCode, let message):
            return "Client error (\(statusCode)): \(message)"
        case .serverError(let statusCode):
            return "Server error (\(statusCode)). Please try again later."
        case .unexpectedStatusCode(let code):
            return "Unexpected status code: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .timeout:
            return "Request timed out. Please try again."
        }
    }

    static func == (lhs: AIServiceError, rhs: AIServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.invalidResponse, .invalidResponse),
             (.quotaExceeded, .quotaExceeded),
             (.timeout, .timeout):
            return true
        case (.featureDisabled(let lhsFeature), .featureDisabled(let rhsFeature)):
            return lhsFeature == rhsFeature
        case (.invalidInput(let lhsReason), .invalidInput(let rhsReason)):
            return lhsReason == rhsReason
        case (.rateLimitExceeded(let lhsRetry), .rateLimitExceeded(let rhsRetry)):
            return lhsRetry == rhsRetry
        case (.clientError(let lhsCode, let lhsMsg), .clientError(let rhsCode, let rhsMsg)):
            return lhsCode == rhsCode && lhsMsg == rhsMsg
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.unexpectedStatusCode(let lhsCode), .unexpectedStatusCode(let rhsCode)):
            return lhsCode == rhsCode
        case (.apiError(let lhsMsg), .apiError(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}
