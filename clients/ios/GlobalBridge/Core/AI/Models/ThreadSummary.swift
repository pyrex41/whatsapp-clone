//
//  ThreadSummary.swift
//  GlobalBridge
//
//  Model for thread summarization API responses
//  Maps to backend POST /api/v1/ai/summarize_thread response
//

import Foundation

/// Summary of a conversation thread with key points and action items
struct ThreadSummary: Codable, Equatable, Identifiable {
    /// Unique identifier for this summary
    let id: UUID

    /// Thread that was summarized
    let threadId: UUID

    /// Concise summary of the conversation
    let summary: String

    /// Key discussion points or topics
    let keyPoints: [String]

    /// Identified decisions made in the conversation
    let decisions: [String]

    /// Action items extracted from the conversation
    let actionItems: [ActionItem]

    /// Participants in the conversation
    let participants: [Participant]

    /// Time period covered by this summary
    let startDate: Date?
    let endDate: Date?

    /// Number of messages summarized
    let messageCount: Int?

    /// Maximum length requested for summary
    let maxLength: Int?

    /// AI provider used for summarization
    let provider: String?

    /// When this summary was generated
    let generatedAt: Date

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case summary
        case keyPoints = "key_points"
        case decisions
        case actionItems = "action_items"
        case participants
        case startDate = "start_date"
        case endDate = "end_date"
        case messageCount = "message_count"
        case maxLength = "max_length"
        case provider
        case generatedAt = "generated_at"
    }

    // MARK: - Nested Types

    /// Action item extracted from conversation
    struct ActionItem: Codable, Equatable, Identifiable {
        let id: UUID
        let description: String
        let assignee: String?
        let dueDate: Date?
        let priority: Priority?
        let status: Status?

        enum Priority: String, Codable {
            case low
            case medium
            case high
            case urgent
        }

        enum Status: String, Codable {
            case pending
            case inProgress = "in_progress"
            case completed
            case cancelled
        }

        enum CodingKeys: String, CodingKey {
            case id
            case description
            case assignee
            case dueDate = "due_date"
            case priority
            case status
        }
    }

    /// Participant in the conversation
    struct Participant: Codable, Equatable, Identifiable {
        let id: UUID
        let username: String
        let displayName: String?
        let messageCount: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case username
            case displayName = "display_name"
            case messageCount = "message_count"
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        threadId: UUID,
        summary: String,
        keyPoints: [String] = [],
        decisions: [String] = [],
        actionItems: [ActionItem] = [],
        participants: [Participant] = [],
        startDate: Date? = nil,
        endDate: Date? = nil,
        messageCount: Int? = nil,
        maxLength: Int? = nil,
        provider: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.summary = summary
        self.keyPoints = keyPoints
        self.decisions = decisions
        self.actionItems = actionItems
        self.participants = participants
        self.startDate = startDate
        self.endDate = endDate
        self.messageCount = messageCount
        self.maxLength = maxLength
        self.provider = provider
        self.generatedAt = generatedAt
    }
}

// MARK: - Backend API Response DTO

/// Backend API response structure for thread summarization endpoint
struct ThreadSummaryAPIResponse: Codable {
    let success: Bool
    let summary: String
    let threadId: UUID
    let maxLength: Int?
    let keyTopics: [String]?
    let decisions: [String]?
    let actionItems: [ActionItemDTO]?
    let participants: [ParticipantDTO]?
    let messageCount: Int?
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case success
        case summary
        case threadId = "thread_id"
        case maxLength = "max_length"
        case keyTopics = "key_topics"
        case decisions
        case actionItems = "action_items"
        case participants
        case messageCount = "message_count"
        case provider
    }

    struct ActionItemDTO: Codable {
        let description: String
        let assignee: String?
        let dueDate: String?
        let priority: String?

        enum CodingKeys: String, CodingKey {
            case description
            case assignee
            case dueDate = "due_date"
            case priority
        }
    }

    struct ParticipantDTO: Codable {
        let userId: UUID
        let username: String
        let displayName: String?
        let messageCount: Int?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case username
            case displayName = "display_name"
            case messageCount = "message_count"
        }
    }

    /// Convert API response to domain model
    func toThreadSummary() -> ThreadSummary {
        ThreadSummary(
            threadId: threadId,
            summary: summary,
            keyPoints: keyTopics ?? [],
            decisions: decisions ?? [],
            actionItems: actionItems?.map { item in
                ThreadSummary.ActionItem(
                    id: UUID(),
                    description: item.description,
                    assignee: item.assignee,
                    dueDate: item.dueDate.flatMap { ISO8601DateFormatter().date(from: $0) },
                    priority: item.priority.flatMap { ThreadSummary.ActionItem.Priority(rawValue: $0.lowercased()) },
                    status: .pending
                )
            } ?? [],
            participants: participants?.map { p in
                ThreadSummary.Participant(
                    id: p.userId,
                    username: p.username,
                    displayName: p.displayName,
                    messageCount: p.messageCount
                )
            } ?? [],
            messageCount: messageCount,
            maxLength: maxLength,
            provider: provider,
            generatedAt: Date()
        )
    }
}

// MARK: - API Request DTO

/// Request body for thread summarization API endpoint
struct ThreadSummaryRequest: Codable {
    let threadId: UUID
    let maxLength: Int?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case maxLength = "max_length"
    }

    init(threadId: UUID, maxLength: Int? = nil) {
        self.threadId = threadId
        self.maxLength = maxLength
    }
}

// MARK: - Helper Extensions

extension ThreadSummary {
    /// Whether this summary has action items
    var hasActionItems: Bool {
        !actionItems.isEmpty
    }

    /// Whether this summary has decisions
    var hasDecisions: Bool {
        !decisions.isEmpty
    }

    /// Whether this summary has key points
    var hasKeyPoints: Bool {
        !keyPoints.isEmpty
    }

    /// Number of pending action items
    var pendingActionItemsCount: Int {
        actionItems.filter { $0.status == .pending || $0.status == .inProgress }.count
    }

    /// High priority action items
    var highPriorityActionItems: [ActionItem] {
        actionItems.filter { $0.priority == .high || $0.priority == .urgent }
    }

    /// Age of the summary in seconds
    var age: TimeInterval {
        Date().timeIntervalSince(generatedAt)
    }

    /// Whether this summary is stale (older than 1 hour)
    var isStale: Bool {
        age > 3600 // 1 hour
    }
}

// MARK: - Display Helpers

extension ThreadSummary {
    /// Formatted participant list (e.g., "John, Jane, and 3 others")
    var participantsSummary: String {
        let names = participants.compactMap { $0.displayName ?? $0.username }
        guard !names.isEmpty else { return "No participants" }

        if names.count <= 2 {
            return names.joined(separator: " and ")
        } else {
            let first = names[0]
            let second = names[1]
            let remaining = names.count - 2
            return "\(first), \(second), and \(remaining) other\(remaining == 1 ? "" : "s")"
        }
    }

    /// Formatted time period (e.g., "Oct 20 - Oct 24")
    var timePeriodSummary: String? {
        guard let start = startDate, let end = endDate else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

// MARK: - Action Item Helpers

extension ThreadSummary.ActionItem {
    /// Whether this action item is overdue
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .completed && status != .cancelled
    }

    /// Whether this action item is due soon (within 24 hours)
    var isDueSoon: Bool {
        guard let dueDate = dueDate else { return false }
        let tomorrow = Date().addingTimeInterval(86400) // 24 hours
        return dueDate <= tomorrow && dueDate >= Date() && status != .completed && status != .cancelled
    }

    /// Priority color for UI display
    var priorityColor: String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .medium: return "yellow"
        case .low, .none: return "gray"
        }
    }
}
