//
//  SearchResult.swift
//  GlobalBridge
//
//  Model for semantic search API responses
//  Maps to backend POST /api/v1/ai/search_semantic response
//

import Foundation

/// Result from semantic search containing matching messages with relevance scores
struct SearchResult: Codable, Equatable, Identifiable {
    /// Unique identifier for this search result
    let id: UUID

    /// The matching message
    let message: MessageInfo

    /// Relevance score (0.0 to 1.0, higher is more relevant)
    let relevanceScore: Double

    /// Highlighted snippet showing match context
    let snippet: String?

    /// Whether this result was translated
    let translated: Bool

    /// Original language if translated
    let originalLanguage: String?

    /// Ranking position in search results (1-based)
    let rank: Int?

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case id
        case message
        case relevanceScore = "relevance_score"
        case snippet
        case translated
        case originalLanguage = "original_language"
        case rank
    }

    // MARK: - Nested Types

    /// Message information in search results
    struct MessageInfo: Codable, Equatable, Identifiable {
        let id: UUID
        let threadId: UUID
        let senderId: UUID
        let senderUsername: String
        let senderDisplayName: String?
        let content: String
        let timestamp: Date
        let isEdited: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case threadId = "thread_id"
            case senderId = "sender_id"
            case senderUsername = "sender_username"
            case senderDisplayName = "sender_display_name"
            case content
            case timestamp
            case isEdited = "is_edited"
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        message: MessageInfo,
        relevanceScore: Double,
        snippet: String? = nil,
        translated: Bool = false,
        originalLanguage: String? = nil,
        rank: Int? = nil
    ) {
        self.id = id
        self.message = message
        self.relevanceScore = relevanceScore
        self.snippet = snippet
        self.translated = translated
        self.originalLanguage = originalLanguage
        self.rank = rank
    }
}

// MARK: - Backend API Response DTO

/// Backend API response structure for semantic search endpoint
struct SearchAPIResponse: Codable {
    let success: Bool
    let results: [SearchResultDTO]
    let totalResults: Int
    let threadId: UUID?
    let query: String?

    enum CodingKeys: String, CodingKey {
        case success
        case results
        case totalResults = "total_results"
        case threadId = "thread_id"
        case query
    }

    struct SearchResultDTO: Codable {
        let messageId: UUID
        let threadId: UUID
        let content: String
        let senderId: UUID
        let senderUsername: String
        let senderDisplayName: String?
        let timestamp: String
        let relevanceScore: Double
        let snippet: String?
        let translated: Bool?
        let originalLanguage: String?

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case threadId = "thread_id"
            case content
            case senderId = "sender_id"
            case senderUsername = "sender_username"
            case senderDisplayName = "sender_display_name"
            case timestamp
            case relevanceScore = "relevance_score"
            case snippet
            case translated
            case originalLanguage = "original_language"
        }
    }

    /// Convert API response to domain models
    func toSearchResults() -> [SearchResult] {
        results.enumerated().map { index, dto in
            SearchResult(
                message: SearchResult.MessageInfo(
                    id: dto.messageId,
                    threadId: dto.threadId,
                    senderId: dto.senderId,
                    senderUsername: dto.senderUsername,
                    senderDisplayName: dto.senderDisplayName,
                    content: dto.content,
                    timestamp: ISO8601DateFormatter().date(from: dto.timestamp) ?? Date(),
                    isEdited: nil
                ),
                relevanceScore: dto.relevanceScore,
                snippet: dto.snippet,
                translated: dto.translated ?? false,
                originalLanguage: dto.originalLanguage,
                rank: index + 1
            )
        }
    }
}

// MARK: - API Request DTO

/// Request body for semantic search API endpoint
struct SearchRequest: Codable {
    let query: String
    let threadId: UUID?
    let limit: Int?
    let recencyBias: Bool?
    let translate: Bool?

    enum CodingKeys: String, CodingKey {
        case query
        case threadId = "thread_id"
        case limit
        case recencyBias = "recency_bias"
        case translate
    }

    init(
        query: String,
        threadId: UUID? = nil,
        limit: Int? = 10,
        recencyBias: Bool? = true,
        translate: Bool? = false
    ) {
        self.query = query
        self.threadId = threadId
        self.limit = limit
        self.recencyBias = recencyBias
        self.translate = translate
    }
}

// MARK: - Helper Extensions

extension SearchResult {
    /// Whether this result is highly relevant (score > 0.8)
    var isHighlyRelevant: Bool {
        relevanceScore > 0.8
    }

    /// Whether this result is moderately relevant (score > 0.5)
    var isModeratelyRelevant: Bool {
        relevanceScore > 0.5
    }

    /// Relevance percentage (0-100)
    var relevancePercentage: Int {
        Int(relevanceScore * 100)
    }

    /// Age of the message in seconds
    var messageAge: TimeInterval {
        Date().timeIntervalSince(message.timestamp)
    }

    /// Whether the message is recent (less than 24 hours old)
    var isRecent: Bool {
        messageAge < 86400 // 24 hours
    }

    /// Sender's display name or username
    var senderName: String {
        message.senderDisplayName ?? message.senderUsername
    }
}

// MARK: - Display Helpers

extension SearchResult {
    /// Formatted relevance (e.g., "95% match")
    var relevanceText: String {
        "\(relevancePercentage)% match"
    }

    /// Formatted timestamp (e.g., "2 hours ago", "Oct 24")
    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: message.timestamp, relativeTo: Date())
    }

    /// Preview text (snippet if available, otherwise truncated content)
    var previewText: String {
        if let snippet = snippet, !snippet.isEmpty {
            return snippet
        } else {
            let maxLength = 150
            if message.content.count > maxLength {
                return String(message.content.prefix(maxLength)) + "..."
            } else {
                return message.content
            }
        }
    }

    /// Color indicator based on relevance
    var relevanceColor: String {
        if isHighlyRelevant {
            return "green"
        } else if isModeratelyRelevant {
            return "yellow"
        } else {
            return "gray"
        }
    }

    /// Language label for translated results
    var languageLabel: String? {
        guard translated, let originalLanguage = originalLanguage else { return nil }
        let languageName = Locale.current.localizedString(forLanguageCode: originalLanguage) ?? originalLanguage
        return "Translated from \(languageName)"
    }
}

// MARK: - Sorting Helpers

extension Array where Element == SearchResult {
    /// Sort results by relevance (highest first)
    var sortedByRelevance: [SearchResult] {
        sorted { $0.relevanceScore > $1.relevanceScore }
    }

    /// Sort results by recency (newest first)
    var sortedByRecency: [SearchResult] {
        sorted { $0.message.timestamp > $1.message.timestamp }
    }

    /// Filter to only highly relevant results
    var highlyRelevant: [SearchResult] {
        filter { $0.isHighlyRelevant }
    }

    /// Filter to results from a specific thread
    func from(threadId: UUID) -> [SearchResult] {
        filter { $0.message.threadId == threadId }
    }

    /// Group results by thread
    var groupedByThread: [UUID: [SearchResult]] {
        Dictionary(grouping: self) { $0.message.threadId }
    }
}
