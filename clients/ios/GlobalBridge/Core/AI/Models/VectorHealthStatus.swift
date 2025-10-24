//
//  VectorHealthStatus.swift
//  GlobalBridge
//
//  Model for vector database health check responses
//  Maps to backend POST /api/v1/ai/vec_health response
//

import Foundation

/// Health status of vector database for a specific thread
struct VectorHealthStatus: Codable, Equatable {
    /// Thread being checked
    let threadId: UUID

    /// Database shard ID where thread's embeddings are stored
    let shardId: String

    /// Overall health status
    let status: HealthStatus

    /// Number of messages with embeddings
    let embeddedMessagesCount: Int

    /// Total number of messages in thread
    let totalMessagesCount: Int

    /// Number of messages pending embedding
    let pendingEmbeddingsCount: Int

    /// Last time embeddings were updated
    let lastEmbeddingUpdate: Date?

    /// Vector database provider (e.g., "sqlite_vec")
    let provider: String?

    /// When this health check was performed
    let checkedAt: Date

    // MARK: - Enums

    enum HealthStatus: String, Codable {
        case healthy
        case degraded
        case unhealthy
        case initializing
        case unavailable
    }

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case shardId = "shard_id"
        case status
        case embeddedMessagesCount = "embedded_messages_count"
        case totalMessagesCount = "total_messages_count"
        case pendingEmbeddingsCount = "pending_embeddings_count"
        case lastEmbeddingUpdate = "last_embedding_update"
        case provider
        case checkedAt = "checked_at"
    }

    // MARK: - Initialization

    init(
        threadId: UUID,
        shardId: String,
        status: HealthStatus,
        embeddedMessagesCount: Int,
        totalMessagesCount: Int,
        pendingEmbeddingsCount: Int,
        lastEmbeddingUpdate: Date? = nil,
        provider: String? = nil,
        checkedAt: Date = Date()
    ) {
        self.threadId = threadId
        self.shardId = shardId
        self.status = status
        self.embeddedMessagesCount = embeddedMessagesCount
        self.totalMessagesCount = totalMessagesCount
        self.pendingEmbeddingsCount = pendingEmbeddingsCount
        self.lastEmbeddingUpdate = lastEmbeddingUpdate
        self.provider = provider
        self.checkedAt = checkedAt
    }
}

// MARK: - Backend API Response DTO

/// Backend API response structure for vector health endpoint
struct VectorHealthAPIResponse: Codable {
    let success: Bool
    let threadId: UUID
    let shardId: String
    let messageCount: Int?
    let embeddedCount: Int?
    let status: String?
    let provider: String?
    let lastUpdate: String?

    enum CodingKeys: String, CodingKey {
        case success
        case threadId = "thread_id"
        case shardId = "shard_id"
        case messageCount = "message_count"
        case embeddedCount = "embedded_count"
        case status
        case provider
        case lastUpdate = "last_update"
    }

    /// Convert API response to domain model
    func toVectorHealthStatus() -> VectorHealthStatus {
        let totalMessages = messageCount ?? 0
        let embeddedMessages = embeddedCount ?? 0
        let pendingMessages = max(0, totalMessages - embeddedMessages)

        let healthStatus: VectorHealthStatus.HealthStatus
        if let statusString = status {
            healthStatus = VectorHealthStatus.HealthStatus(rawValue: statusString.lowercased()) ?? .unavailable
        } else {
            // Infer status based on coverage
            let coverage = totalMessages > 0 ? Double(embeddedMessages) / Double(totalMessages) : 0
            if coverage >= 0.95 {
                healthStatus = .healthy
            } else if coverage >= 0.7 {
                healthStatus = .degraded
            } else if coverage > 0 {
                healthStatus = .initializing
            } else {
                healthStatus = .unavailable
            }
        }

        let lastUpdate = lastUpdate.flatMap { ISO8601DateFormatter().date(from: $0) }

        return VectorHealthStatus(
            threadId: threadId,
            shardId: shardId,
            status: healthStatus,
            embeddedMessagesCount: embeddedMessages,
            totalMessagesCount: totalMessages,
            pendingEmbeddingsCount: pendingMessages,
            lastEmbeddingUpdate: lastUpdate,
            provider: provider,
            checkedAt: Date()
        )
    }
}

// MARK: - API Request DTO

/// Request body for vector health check endpoint
struct VectorHealthRequest: Codable {
    let threadId: UUID

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
    }

    init(threadId: UUID) {
        self.threadId = threadId
    }
}

// MARK: - Helper Extensions

extension VectorHealthStatus {
    /// Percentage of messages that have been embedded (0-100)
    var embeddingCoverage: Double {
        guard totalMessagesCount > 0 else { return 0 }
        return (Double(embeddedMessagesCount) / Double(totalMessagesCount)) * 100
    }

    /// Whether the vector database is ready for search
    var isReadyForSearch: Bool {
        status == .healthy || status == .degraded
    }

    /// Whether embeddings are currently being processed
    var isProcessing: Bool {
        status == .initializing && pendingEmbeddingsCount > 0
    }

    /// Whether the vector database is unavailable
    var isUnavailable: Bool {
        status == .unavailable
    }

    /// Estimated time until all messages are embedded (assumes 1 message/second)
    var estimatedCompletionTime: TimeInterval? {
        guard pendingEmbeddingsCount > 0 else { return nil }
        return TimeInterval(pendingEmbeddingsCount) // Rough estimate: 1 second per message
    }
}

// MARK: - Display Helpers

extension VectorHealthStatus {
    /// Status color for UI display
    var statusColor: String {
        switch status {
        case .healthy: return "green"
        case .degraded: return "yellow"
        case .unhealthy: return "orange"
        case .initializing: return "blue"
        case .unavailable: return "red"
        }
    }

    /// Status icon for UI display
    var statusIcon: String {
        switch status {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .unhealthy: return "xmark.circle.fill"
        case .initializing: return "arrow.triangle.2.circlepath"
        case .unavailable: return "xmark.octagon.fill"
        }
    }

    /// Human-readable status message
    var statusMessage: String {
        switch status {
        case .healthy:
            return "Vector search is ready"
        case .degraded:
            return "Vector search available but some messages are still being indexed"
        case .unhealthy:
            return "Vector search is experiencing issues"
        case .initializing:
            if pendingEmbeddingsCount > 0 {
                return "Indexing \(pendingEmbeddingsCount) messages for search..."
            } else {
                return "Initializing vector search..."
            }
        case .unavailable:
            return "Vector search is not available"
        }
    }

    /// Formatted coverage percentage
    var coverageText: String {
        String(format: "%.0f%% indexed", embeddingCoverage)
    }

    /// Formatted last update time
    var lastUpdateText: String? {
        guard let lastUpdate = lastEmbeddingUpdate else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: lastUpdate, relativeTo: Date()))"
    }

    /// Formatted estimated completion time
    var estimatedCompletionText: String? {
        guard let timeInterval = estimatedCompletionTime else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 2

        guard let timeString = formatter.string(from: timeInterval) else { return nil }
        return "Ready in ~\(timeString)"
    }

    /// Detailed status description for debugging
    var detailedDescription: String {
        """
        Vector Health Status:
        - Thread ID: \(threadId)
        - Shard ID: \(shardId)
        - Status: \(status.rawValue)
        - Coverage: \(coverageText) (\(embeddedMessagesCount)/\(totalMessagesCount))
        - Pending: \(pendingEmbeddingsCount) messages
        - Provider: \(provider ?? "unknown")
        - Last Update: \(lastUpdateText ?? "never")
        """
    }
}
