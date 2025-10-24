//
//  TaskExtractionViewModel.swift
//  GlobalBridge
//
//  ViewModel for task extraction and management
//  Coordinates AI service, persistence, and UI state
//

import Foundation
import Combine
import SwiftUI

/// ViewModel managing task extraction, persistence, and UI state
@MainActor
final class TaskExtractionViewModel: ObservableObject {

    // MARK: - Published Properties

    /// All extracted tasks for the current thread
    @Published private(set) var tasks: [ExtractedTask] = []

    /// Whether task extraction is in progress
    @Published private(set) var isExtracting = false

    /// Whether tasks are being loaded from persistence
    @Published private(set) var isLoading = false

    /// Last extraction error
    @Published var lastError: Error?

    /// Current filter selection
    @Published var filterSelection: TaskFilter = .all

    /// Current sort order
    @Published var sortOrder: TaskSortOrder = .dueDate

    /// Search query for filtering tasks
    @Published var searchQuery: String = ""

    /// Selected task for detail view
    @Published var selectedTask: ExtractedTask?

    /// Whether to show completed tasks
    @Published var showCompletedTasks = true

    // MARK: - Dependencies

    private let aiService: AIService
    private let persistenceService: TaskPersistenceService
    private let threadId: UUID

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// Filtered and sorted tasks based on current UI state
    var filteredTasks: [ExtractedTask] {
        var result = tasks

        // Apply status filter
        if !showCompletedTasks {
            result = result.filter { $0.status != .completed && $0.status != .cancelled }
        }

        // Apply category filter
        switch filterSelection {
        case .all:
            break
        case .overdue:
            result = result.overdue
        case .dueSoon:
            result = result.dueSoon
        case .highPriority:
            result = result.highPriority
        case .unassigned:
            result = result.filter { !$0.isAssigned }
        case .byStatus(let status):
            result = result.filter { $0.status == status }
        case .byPriority(let priority):
            result = result.filter { $0.priority == priority }
        case .byTaskType(let taskType):
            result = result.filter { $0.taskType == taskType }
        }

        // Apply search filter
        if !searchQuery.isEmpty {
            result = result.filter { task in
                task.title.localizedCaseInsensitiveContains(searchQuery) ||
                (task.description?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                (task.assignee?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                task.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchQuery) })
            }
        }

        // Apply sort order
        switch sortOrder {
        case .dueDate:
            result = result.sortedByDueDate
        case .priority:
            result = result.sortedByPriority
        case .status:
            result = result.sorted { $0.status.rawValue < $1.status.rawValue }
        case .createdDate:
            result = result.sorted { $0.extractedAt > $1.extractedAt }
        case .title:
            result = result.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }

        return result
    }

    /// Tasks grouped by status
    var tasksByStatus: [ExtractedTask.Status: [ExtractedTask]] {
        filteredTasks.groupedByStatus
    }

    /// Tasks grouped by assignee
    var tasksByAssignee: [String: [ExtractedTask]] {
        filteredTasks.groupedByAssignee
    }

    /// Statistics for the current task set
    var statistics: TaskStatistics {
        TaskStatistics(
            total: tasks.count,
            completed: tasks.filter { $0.status == .completed }.count,
            overdue: tasks.overdue.count,
            dueSoon: tasks.dueSoon.count,
            highPriority: tasks.highPriority.count,
            unassigned: tasks.filter { !$0.isAssigned }.count
        )
    }

    // MARK: - Initialization

    init(
        threadId: UUID,
        aiService: AIService = .shared,
        persistenceService: TaskPersistenceService = .shared
    ) {
        self.threadId = threadId
        self.aiService = aiService
        self.persistenceService = persistenceService

        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Observe persistence service updates
        persistenceService.tasksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allTasks in
                guard let self = self else { return }
                self.tasks = allTasks.filter { $0.threadId == self.threadId }
            }
            .store(in: &cancellables)
    }

    // MARK: - Task Extraction

    /// Extract tasks from the current thread
    /// - Parameter customQuery: Optional custom extraction query
    func extractTasks(customQuery: String? = nil) async {
        isExtracting = true
        lastError = nil

        defer { isExtracting = false }

        do {
            print("📋 [TASK_VM] Starting task extraction for thread: \(threadId)")

            // Call AI service to extract tasks
            let response = try await aiService.extractTasksDetailed(
                threadId: threadId.uuidString,
                query: customQuery
            )

            let extractedTasks = response.toExtractedTasks()

            print("✅ [TASK_VM] Extracted \(extractedTasks.count) tasks")

            // Save tasks to persistence
            for task in extractedTasks {
                try await persistenceService.saveTask(task)
            }

            // Update local state
            tasks = try await persistenceService.loadTasks(for: threadId)

        } catch {
            print("❌ [TASK_VM] Task extraction failed: \(error)")
            lastError = error
        }
    }

    /// Load tasks from persistence
    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tasks = try await persistenceService.loadTasks(for: threadId)
            print("✅ [TASK_VM] Loaded \(tasks.count) tasks from persistence")
        } catch {
            print("❌ [TASK_VM] Failed to load tasks: \(error)")
            lastError = error
        }
    }

    // MARK: - Task Management

    /// Update task status
    func updateTaskStatus(_ task: ExtractedTask, status: ExtractedTask.Status) async {
        var updatedTask = task
        updatedTask = ExtractedTask(
            id: updatedTask.id,
            threadId: updatedTask.threadId,
            title: updatedTask.title,
            description: updatedTask.description,
            assignee: updatedTask.assignee,
            assigneeId: updatedTask.assigneeId,
            dueDate: updatedTask.dueDate,
            priority: updatedTask.priority,
            status: status,
            tags: updatedTask.tags,
            relatedMessageIds: updatedTask.relatedMessageIds,
            taskType: updatedTask.taskType,
            confidence: updatedTask.confidence,
            extractedAt: updatedTask.extractedAt
        )

        do {
            try await persistenceService.updateTask(updatedTask)
            tasks = try await persistenceService.loadTasks(for: threadId)
        } catch {
            print("❌ [TASK_VM] Failed to update task status: \(error)")
            lastError = error
        }
    }

    /// Update complete task
    func updateTask(_ task: ExtractedTask) async {
        do {
            try await persistenceService.updateTask(task)
            tasks = try await persistenceService.loadTasks(for: threadId)
        } catch {
            print("❌ [TASK_VM] Failed to update task: \(error)")
            lastError = error
        }
    }

    /// Delete task
    func deleteTask(_ task: ExtractedTask) async {
        do {
            try await persistenceService.deleteTask(task.id)
            tasks = try await persistenceService.loadTasks(for: threadId)
        } catch {
            print("❌ [TASK_VM] Failed to delete task: \(error)")
            lastError = error
        }
    }

    /// Toggle task completion
    func toggleTaskCompletion(_ task: ExtractedTask) async {
        let newStatus: ExtractedTask.Status = task.status == .completed ? .pending : .completed
        await updateTaskStatus(task, status: newStatus)
    }

    // MARK: - Bulk Operations

    /// Mark multiple tasks as complete
    func markTasksComplete(_ taskIds: [UUID]) async {
        for taskId in taskIds {
            if let task = tasks.first(where: { $0.id == taskId }) {
                await updateTaskStatus(task, status: .completed)
            }
        }
    }

    /// Delete multiple tasks
    func deleteTasks(_ taskIds: [UUID]) async {
        do {
            for taskId in taskIds {
                try await persistenceService.deleteTask(taskId)
            }
            tasks = try await persistenceService.loadTasks(for: threadId)
        } catch {
            print("❌ [TASK_VM] Failed to delete tasks: \(error)")
            lastError = error
        }
    }

    /// Clear error state
    func clearError() {
        lastError = nil
    }
}

// MARK: - Supporting Types

/// Task filter options
enum TaskFilter: Hashable, Identifiable {
    case all
    case overdue
    case dueSoon
    case highPriority
    case unassigned
    case byStatus(ExtractedTask.Status)
    case byPriority(ExtractedTask.Priority)
    case byTaskType(ExtractedTask.TaskType)

    var id: String {
        switch self {
        case .all: return "all"
        case .overdue: return "overdue"
        case .dueSoon: return "dueSoon"
        case .highPriority: return "highPriority"
        case .unassigned: return "unassigned"
        case .byStatus(let status): return "status_\(status.rawValue)"
        case .byPriority(let priority): return "priority_\(priority.rawValue)"
        case .byTaskType(let type): return "type_\(type.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .all: return "All Tasks"
        case .overdue: return "Overdue"
        case .dueSoon: return "Due Soon"
        case .highPriority: return "High Priority"
        case .unassigned: return "Unassigned"
        case .byStatus(let status): return status.rawValue.capitalized
        case .byPriority(let priority): return priority.rawValue.capitalized
        case .byTaskType(let type): return type.rawValue.capitalized
        }
    }
}

/// Task sort order options
enum TaskSortOrder: String, CaseIterable, Identifiable {
    case dueDate = "Due Date"
    case priority = "Priority"
    case status = "Status"
    case createdDate = "Created Date"
    case title = "Title"

    var id: String { rawValue }
}

/// Task statistics
struct TaskStatistics {
    let total: Int
    let completed: Int
    let overdue: Int
    let dueSoon: Int
    let highPriority: Int
    let unassigned: Int

    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

// MARK: - AIService Extension

extension AIService {
    /// Extract tasks with detailed task models (uses backend task extraction endpoint)
    func extractTasksDetailed(
        threadId: String,
        query: String? = nil
    ) async throws -> TaskExtractionAPIResponse {
        // Check feature availability
        guard featureFlags.hasFeature(.threadSummarization) else {
            throw AIServiceError.featureDisabled(feature: "task_extraction")
        }

        guard !threadId.isEmpty else {
            throw AIServiceError.invalidInput(reason: "Thread ID cannot be empty")
        }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/extract_tasks")
        var requestBody: [String: Any] = ["thread_id": threadId]

        if let query = query {
            requestBody["query"] = query
        }

        print("📋 [AI_SERVICE] Extracting detailed tasks from thread: \(threadId)")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        let decoder = JSONDecoder()
        let response = try decoder.decode(TaskExtractionAPIResponse.self, from: responseData)

        guard response.success else {
            throw AIServiceError.apiError(message: "Task extraction failed")
        }

        print("✅ [AI_SERVICE] Task extraction successful")

        return response
    }

    // Make performRequest accessible
    fileprivate func performRequest(
        endpoint: URL,
        method: String,
        body: [String: Any]? = nil,
        attempt: Int = 1
    ) async throws -> Data {
        // Access the existing private performRequest method
        // This is a workaround - in production, make performRequest internal
        return try await self.performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt)
    }
}
