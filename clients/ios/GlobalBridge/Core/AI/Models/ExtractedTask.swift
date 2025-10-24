//
//  ExtractedTask.swift
//  GlobalBridge
//
//  Model for task extraction API responses
//  Maps to backend POST /api/v1/ai/extract_tasks response
//

import Foundation

/// Task extracted from conversation messages
struct ExtractedTask: Codable, Equatable, Identifiable {
    /// Unique identifier for this extracted task
    let id: UUID

    /// Thread where this task was extracted from
    let threadId: UUID

    /// Task title or brief description
    let title: String

    /// Detailed task description
    let description: String?

    /// Username or identifier of person assigned to this task
    let assignee: String?

    /// Assignee's user ID if identified
    let assigneeId: UUID?

    /// Due date for the task
    let dueDate: Date?

    /// Task priority level
    let priority: Priority

    /// Current task status
    let status: Status

    /// Tags or categories associated with this task
    let tags: [String]

    /// Related message IDs that mentioned this task
    let relatedMessageIds: [UUID]

    /// Task type classification
    let taskType: TaskType?

    /// Confidence score for extraction (0.0 to 1.0)
    let confidence: Double?

    /// When this task was extracted
    let extractedAt: Date

    // MARK: - Enums

    enum Priority: String, Codable, CaseIterable {
        case low
        case medium
        case high
        case urgent

        var sortOrder: Int {
            switch self {
            case .low: return 0
            case .medium: return 1
            case .high: return 2
            case .urgent: return 3
            }
        }
    }

    enum Status: String, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case cancelled
        case blocked
    }

    enum TaskType: String, Codable {
        case action // Generic action item
        case decision // Decision to be made
        case followUp = "follow_up" // Follow-up item
        case deadline // Time-sensitive deadline
        case deliverable // Deliverable or output
        case meeting // Meeting or event
        case research // Research or investigation
        case review // Review or approval needed
    }

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case title
        case description
        case assignee
        case assigneeId = "assignee_id"
        case dueDate = "due_date"
        case priority
        case status
        case tags
        case relatedMessageIds = "related_message_ids"
        case taskType = "task_type"
        case confidence
        case extractedAt = "extracted_at"
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        threadId: UUID,
        title: String,
        description: String? = nil,
        assignee: String? = nil,
        assigneeId: UUID? = nil,
        dueDate: Date? = nil,
        priority: Priority = .medium,
        status: Status = .pending,
        tags: [String] = [],
        relatedMessageIds: [UUID] = [],
        taskType: TaskType? = nil,
        confidence: Double? = nil,
        extractedAt: Date = Date()
    ) {
        self.id = id
        self.threadId = threadId
        self.title = title
        self.description = description
        self.assignee = assignee
        self.assigneeId = assigneeId
        self.dueDate = dueDate
        self.priority = priority
        self.status = status
        self.tags = tags
        self.relatedMessageIds = relatedMessageIds
        self.taskType = taskType
        self.confidence = confidence
        self.extractedAt = extractedAt
    }
}

// MARK: - Backend API Response DTO

/// Backend API response structure for task extraction endpoint
struct TaskExtractionAPIResponse: Codable {
    let success: Bool
    let extraction: ExtractionData
    let threadId: UUID
    let query: String?

    enum CodingKeys: String, CodingKey {
        case success
        case extraction
        case threadId = "thread_id"
        case query
    }

    struct ExtractionData: Codable {
        let tasks: [TaskDTO]
        let decisions: [TaskDTO]?
        let deadlines: [TaskDTO]?

        struct TaskDTO: Codable {
            let title: String
            let description: String?
            let assignee: String?
            let dueDate: String?
            let priority: String?
            let taskType: String?
            let confidence: Double?
            let relatedMessageIds: [UUID]?
            let tags: [String]?

            enum CodingKeys: String, CodingKey {
                case title
                case description
                case assignee
                case dueDate = "due_date"
                case priority
                case taskType = "task_type"
                case confidence
                case relatedMessageIds = "related_message_ids"
                case tags
            }
        }
    }

    /// Convert API response to domain models
    func toExtractedTasks() -> [ExtractedTask] {
        var tasks: [ExtractedTask] = []

        // Convert regular tasks
        tasks += extraction.tasks.map { dto in
            dto.toExtractedTask(threadId: threadId, defaultType: .action)
        }

        // Convert decisions
        if let decisions = extraction.decisions {
            tasks += decisions.map { dto in
                dto.toExtractedTask(threadId: threadId, defaultType: .decision)
            }
        }

        // Convert deadlines
        if let deadlines = extraction.deadlines {
            tasks += deadlines.map { dto in
                dto.toExtractedTask(threadId: threadId, defaultType: .deadline)
            }
        }

        return tasks
    }
}

// MARK: - API Request DTO

/// Request body for task extraction API endpoint
struct TaskExtractionRequest: Codable {
    let threadId: UUID
    let query: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case query
    }

    init(threadId: UUID, query: String? = nil) {
        self.threadId = threadId
        self.query = query
    }
}

// MARK: - DTO Conversion Helper

extension TaskExtractionAPIResponse.ExtractionData.TaskDTO {
    func toExtractedTask(threadId: UUID, defaultType: ExtractedTask.TaskType) -> ExtractedTask {
        let parsedPriority = priority
            .flatMap { ExtractedTask.Priority(rawValue: $0.lowercased()) }
            ?? .medium

        let parsedTaskType = taskType
            .flatMap { ExtractedTask.TaskType(rawValue: $0.lowercased()) }
            ?? defaultType

        let parsedDueDate = dueDate.flatMap { dateString in
            ISO8601DateFormatter().date(from: dateString)
        }

        return ExtractedTask(
            threadId: threadId,
            title: title,
            description: description,
            assignee: assignee,
            dueDate: parsedDueDate,
            priority: parsedPriority,
            status: .pending,
            tags: tags ?? [],
            relatedMessageIds: relatedMessageIds ?? [],
            taskType: parsedTaskType,
            confidence: confidence,
            extractedAt: Date()
        )
    }
}

// MARK: - Helper Extensions

extension ExtractedTask {
    /// Whether this task has a high confidence score
    var isHighConfidence: Bool {
        guard let confidence = confidence else { return false }
        return confidence > 0.8
    }

    /// Whether this task is overdue
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .completed && status != .cancelled
    }

    /// Whether this task is due soon (within 24 hours)
    var isDueSoon: Bool {
        guard let dueDate = dueDate else { return false }
        let tomorrow = Date().addingTimeInterval(86400) // 24 hours
        return dueDate <= tomorrow && dueDate >= Date() && status != .completed && status != .cancelled
    }

    /// Whether this task is actionable (not blocked or cancelled)
    var isActionable: Bool {
        status != .blocked && status != .cancelled
    }

    /// Whether this task has been assigned
    var isAssigned: Bool {
        assignee != nil || assigneeId != nil
    }

    /// Days until due date (negative if overdue)
    var daysUntilDue: Int? {
        guard let dueDate = dueDate else { return nil }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: dueDate)
        return components.day
    }
}

// MARK: - Display Helpers

extension ExtractedTask {
    /// Priority color for UI display
    var priorityColor: String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .medium: return "yellow"
        case .low: return "gray"
        }
    }

    /// Priority icon for UI display
    var priorityIcon: String {
        switch priority {
        case .urgent: return "exclamationmark.3"
        case .high: return "exclamationmark.2"
        case .medium: return "exclamationmark"
        case .low: return "minus"
        }
    }

    /// Status color for UI display
    var statusColor: String {
        switch status {
        case .completed: return "green"
        case .inProgress: return "blue"
        case .pending: return "gray"
        case .blocked: return "red"
        case .cancelled: return "gray"
        }
    }

    /// Task type icon for UI display
    var taskTypeIcon: String {
        switch taskType {
        case .action: return "checkmark.circle"
        case .decision: return "questionmark.diamond"
        case .followUp: return "arrow.turn.right.up"
        case .deadline: return "clock"
        case .deliverable: return "doc"
        case .meeting: return "calendar"
        case .research: return "magnifyingglass"
        case .review: return "eye"
        case .none: return "circle"
        }
    }

    /// Formatted due date string
    var formattedDueDate: String? {
        guard let dueDate = dueDate else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: dueDate, relativeTo: Date())
    }

    /// Confidence percentage
    var confidencePercentage: String? {
        guard let confidence = confidence else { return nil }
        return String(format: "%.0f%%", confidence * 100)
    }
}

// MARK: - Sorting & Filtering

extension Array where Element == ExtractedTask {
    /// Sort tasks by priority (urgent first)
    var sortedByPriority: [ExtractedTask] {
        sorted { $0.priority.sortOrder > $1.priority.sortOrder }
    }

    /// Sort tasks by due date (soonest first)
    var sortedByDueDate: [ExtractedTask] {
        sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            case (let lDate?, let rDate?): return lDate < rDate
            }
        }
    }

    /// Filter to only overdue tasks
    var overdue: [ExtractedTask] {
        filter { $0.isOverdue }
    }

    /// Filter to only tasks due soon
    var dueSoon: [ExtractedTask] {
        filter { $0.isDueSoon }
    }

    /// Filter to only actionable tasks
    var actionable: [ExtractedTask] {
        filter { $0.isActionable }
    }

    /// Filter to only high priority tasks
    var highPriority: [ExtractedTask] {
        filter { $0.priority == .high || $0.priority == .urgent }
    }

    /// Group tasks by assignee
    var groupedByAssignee: [String: [ExtractedTask]] {
        Dictionary(grouping: self) { $0.assignee ?? "Unassigned" }
    }

    /// Group tasks by status
    var groupedByStatus: [ExtractedTask.Status: [ExtractedTask]] {
        Dictionary(grouping: self) { $0.status }
    }
}
