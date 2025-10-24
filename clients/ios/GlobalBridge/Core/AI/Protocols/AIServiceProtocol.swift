//
//  AIServiceProtocol.swift
//  GlobalBridge
//
//  Protocol defining all AI service operations for the WhatsApp-clone application.
//  This protocol provides a contract for AI features including translation, summarization,
//  semantic search, and task extraction.
//
//  Architecture: Protocol-oriented design for testability and flexibility
//  Backend: Integrates with Phoenix backend AI endpoints at /api/v1/ai/*
//

import Foundation

/// Protocol defining all AI service operations with async/await patterns
/// All operations require authentication via JWT tokens
/// All operations are subject to tier-based rate limiting
protocol AIServiceProtocol {

    // MARK: - Translation

    /// Translates text from one language to another using backend AI service
    ///
    /// Backend endpoint: POST /api/v1/ai/translate
    /// Rate limited: Yes (per user tier)
    /// Authentication: Required
    ///
    /// - Parameters:
    ///   - text: The text to translate
    ///   - from: Source language code (ISO 639-1 format, e.g., "en", "es"). Use "auto" for automatic detection
    ///   - to: Target language code (ISO 639-1 format)
    /// - Returns: TranslationResult containing translated text, detected source language, and metadata
    /// - Throws: AIServiceError for network, authentication, rate limiting, or parsing failures
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult

    // MARK: - Thread Summarization

    /// Generates a concise summary of a conversation thread
    ///
    /// Backend endpoint: POST /api/v1/ai/summarize_thread
    /// Rate limited: Yes (per user tier)
    /// Authentication: Required
    ///
    /// - Parameters:
    ///   - threadId: UUID of the thread to summarize
    ///   - maxLength: Optional maximum length of summary in characters (defaults to backend setting)
    /// - Returns: ThreadSummary with key points, decisions, and action items
    /// - Throws: AIServiceError for network, authentication, rate limiting, or parsing failures
    func summarizeThread(
        threadId: UUID,
        maxLength: Int?
    ) async throws -> ThreadSummary

    // MARK: - Semantic Search

    /// Performs semantic search across messages using vector embeddings
    ///
    /// Backend endpoint: POST /api/v1/ai/search_semantic
    /// Rate limited: Yes (per user tier)
    /// Authentication: Required
    ///
    /// - Parameters:
    ///   - query: Natural language search query
    ///   - threadId: Optional thread UUID to scope search (nil = search all threads)
    ///   - limit: Maximum number of results (default: 10)
    ///   - recencyBias: Whether to bias results toward recent messages (default: true)
    ///   - translate: Whether to translate results to user's language (default: false)
    /// - Returns: Array of SearchResult objects ordered by relevance
    /// - Throws: AIServiceError for network, authentication, rate limiting, or parsing failures
    func searchSemantic(
        query: String,
        in threadId: UUID?,
        limit: Int,
        recencyBias: Bool,
        translate: Bool
    ) async throws -> [SearchResult]

    // MARK: - Task Extraction

    /// Extracts actionable tasks from conversation messages
    ///
    /// Backend endpoint: POST /api/v1/ai/extract_tasks
    /// Rate limited: Yes (per user tier)
    /// Authentication: Required
    ///
    /// - Parameters:
    ///   - threadId: UUID of the thread to analyze
    ///   - query: Optional query to filter tasks (e.g., "tasks, deadlines, decisions")
    /// - Returns: Array of ExtractedTask objects with assignees, deadlines, and priority
    /// - Throws: AIServiceError for network, authentication, rate limiting, or parsing failures
    func extractTasks(
        from threadId: UUID,
        query: String?
    ) async throws -> [ExtractedTask]

    // MARK: - Health Check

    /// Checks vector database health for a specific thread
    ///
    /// Backend endpoint: POST /api/v1/ai/vec_health
    /// Rate limited: No
    /// Authentication: Required
    ///
    /// - Parameter threadId: UUID of the thread to check
    /// - Returns: VectorHealthStatus with message count, shard info, and status
    /// - Throws: AIServiceError for network, authentication, or parsing failures
    func checkVectorHealth(
        for threadId: UUID
    ) async throws -> VectorHealthStatus
}

// MARK: - Default Parameter Values

extension AIServiceProtocol {
    /// Convenience method with default parameters for translation
    func translate(
        text: String,
        from sourceLanguage: String = "auto",
        to targetLanguage: String
    ) async throws -> TranslationResult {
        try await translate(text: text, from: sourceLanguage, to: targetLanguage)
    }

    /// Convenience method with default parameters for thread summarization
    func summarizeThread(threadId: UUID) async throws -> ThreadSummary {
        try await summarizeThread(threadId: threadId, maxLength: nil)
    }

    /// Convenience method with default parameters for semantic search
    func searchSemantic(
        query: String,
        in threadId: UUID? = nil,
        limit: Int = 10,
        recencyBias: Bool = true,
        translate: Bool = false
    ) async throws -> [SearchResult] {
        try await searchSemantic(
            query: query,
            in: threadId,
            limit: limit,
            recencyBias: recencyBias,
            translate: translate
        )
    }

    /// Convenience method with default parameters for task extraction
    func extractTasks(from threadId: UUID) async throws -> [ExtractedTask] {
        try await extractTasks(from: threadId, query: nil)
    }
}

// MARK: - Architecture Notes

/*
 DESIGN DECISIONS:

 1. Protocol-Oriented Design
    - Enables easy testing with mock implementations
    - Allows for future alternative implementations (e.g., local AI models)
    - Follows Swift best practices and iOS architecture patterns

 2. Async/Await
    - Modern Swift concurrency for cleaner code
    - Avoids callback hell and completion handler complexity
    - Better error handling with structured concurrency

 3. Typed Errors
    - AIServiceError enum provides clear error cases
    - Enables proper error handling and recovery strategies
    - Supports rate limiting retry logic

 4. Rate Limiting Support
    - Protocol designed with rate limiting in mind
    - Implementations can parse X-RateLimit-* headers
    - Supports exponential backoff and retry strategies

 5. Feature Flag Integration
    - Implementations should check FeatureFlags before API calls
    - Graceful degradation when features are disabled
    - Tier-aware functionality

 6. Backend Contract Compliance
    - All methods map directly to backend API endpoints
    - Request/response models match backend JSON schemas
    - Snake_case backend fields converted to camelCase Swift

 7. Authentication
    - All methods require JWT authentication
    - Implementations use AuthManager for token management
    - Automatic token refresh on 401 responses

 8. Caching Strategy
    - Protocol is cache-agnostic for flexibility
    - Implementations can add caching layers
    - Translation results are good candidates for caching

 9. Error Recovery
    - Network errors trigger automatic retry with backoff
    - Rate limit errors include retry-after timing
    - Authentication errors trigger token refresh flow

 10. Scalability
     - Thread-safe implementations using actors
     - Supports concurrent requests with proper queuing
     - Memory-efficient streaming for large results (future)
*/
