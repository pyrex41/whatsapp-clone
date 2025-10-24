//
//  TaskPersistenceService.swift
//  GlobalBridge
//
//  Service for persisting extracted tasks locally
//  Uses UserDefaults for simple key-value storage with Codable
//

import Foundation
import Combine

/// Service managing local persistence of extracted tasks
@MainActor
final class TaskPersistenceService: ObservableObject {

    // MARK: - Singleton

    static let shared = TaskPersistenceService()

    // MARK: - Published Properties

    /// Publisher for task updates
    let tasksPublisher = PassthroughSubject<[ExtractedTask], Never>()

    // MARK: - Private Properties

    private let userDefaults: UserDefaults
    private let tasksKey = "com.globalbridge.extractedTasks"
    private var tasks: [UUID: ExtractedTask] = [:]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Configure encoder/decoder for ISO8601 dates
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        // Load tasks from persistence
        Task {
            await loadAllTasks()
        }
    }

    // MARK: - Task Operations

    /// Save a task to persistence
    func saveTask(_ task: ExtractedTask) async throws {
        tasks[task.id] = task
        try await persistTasks()
        tasksPublisher.send(Array(tasks.values))
    }

    /// Load tasks for a specific thread
    func loadTasks(for threadId: UUID) async throws -> [ExtractedTask] {
        return tasks.values.filter { $0.threadId == threadId }.sorted { $0.extractedAt > $1.extractedAt }
    }

    /// Load all tasks
    func loadAllTasks() async -> [ExtractedTask] {
        if tasks.isEmpty {
            do {
                try await loadTasksFromStorage()
            } catch {
                print("❌ [PERSISTENCE] Failed to load tasks: \(error)")
            }
        }
        return Array(tasks.values)
    }

    /// Update an existing task
    func updateTask(_ task: ExtractedTask) async throws {
        guard tasks[task.id] != nil else {
            throw PersistenceError.taskNotFound(task.id)
        }

        tasks[task.id] = task
        try await persistTasks()
        tasksPublisher.send(Array(tasks.values))
    }

    /// Delete a task
    func deleteTask(_ taskId: UUID) async throws {
        guard tasks[taskId] != nil else {
            throw PersistenceError.taskNotFound(taskId)
        }

        tasks.removeValue(forKey: taskId)
        try await persistTasks()
        tasksPublisher.send(Array(tasks.values))
    }

    /// Delete all tasks for a thread
    func deleteAllTasks(for threadId: UUID) async throws {
        let threadTaskIds = tasks.values.filter { $0.threadId == threadId }.map { $0.id }

        for taskId in threadTaskIds {
            tasks.removeValue(forKey: taskId)
        }

        try await persistTasks()
        tasksPublisher.send(Array(tasks.values))
    }

    /// Clear all tasks
    func clearAllTasks() async throws {
        tasks.removeAll()
        try await persistTasks()
        tasksPublisher.send([])
    }

    // MARK: - Search & Query

    /// Search tasks by query
    func searchTasks(query: String) async -> [ExtractedTask] {
        guard !query.isEmpty else {
            return Array(tasks.values)
        }

        return tasks.values.filter { task in
            task.title.localizedCaseInsensitiveContains(query) ||
            (task.description?.localizedCaseInsensitiveContains(query) ?? false) ||
            (task.assignee?.localizedCaseInsensitiveContains(query) ?? false) ||
            task.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    /// Get tasks by status
    func tasks(withStatus status: ExtractedTask.Status) async -> [ExtractedTask] {
        return tasks.values.filter { $0.status == status }
    }

    /// Get tasks by priority
    func tasks(withPriority priority: ExtractedTask.Priority) async -> [ExtractedTask] {
        return tasks.values.filter { $0.priority == priority }
    }

    /// Get overdue tasks
    func overdueTasks() async -> [ExtractedTask] {
        return tasks.values.filter { $0.isOverdue }
    }

    /// Get tasks due soon
    func tasksDueSoon() async -> [ExtractedTask] {
        return tasks.values.filter { $0.isDueSoon }
    }

    // MARK: - Private Methods

    /// Load tasks from UserDefaults
    private func loadTasksFromStorage() async throws {
        guard let data = userDefaults.data(forKey: tasksKey) else {
            print("📦 [PERSISTENCE] No saved tasks found")
            return
        }

        do {
            let taskArray = try decoder.decode([ExtractedTask].self, from: data)
            tasks = Dictionary(uniqueKeysWithValues: taskArray.map { ($0.id, $0) })
            print("✅ [PERSISTENCE] Loaded \(tasks.count) tasks from storage")
            tasksPublisher.send(Array(tasks.values))
        } catch {
            print("❌ [PERSISTENCE] Failed to decode tasks: \(error)")
            throw PersistenceError.decodingFailed(error)
        }
    }

    /// Persist tasks to UserDefaults
    private func persistTasks() async throws {
        do {
            let taskArray = Array(tasks.values)
            let data = try encoder.encode(taskArray)
            userDefaults.set(data, forKey: tasksKey)
            print("💾 [PERSISTENCE] Saved \(tasks.count) tasks to storage")
        } catch {
            print("❌ [PERSISTENCE] Failed to encode tasks: \(error)")
            throw PersistenceError.encodingFailed(error)
        }
    }
}

// MARK: - Error Types

enum PersistenceError: LocalizedError {
    case taskNotFound(UUID)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .encodingFailed(let error):
            return "Failed to encode tasks: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode tasks: \(error.localizedDescription)"
        case .storageUnavailable:
            return "Storage is unavailable"
        }
    }
}
