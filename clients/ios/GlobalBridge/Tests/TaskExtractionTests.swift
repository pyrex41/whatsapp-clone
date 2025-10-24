//
//  TaskExtractionTests.swift
//  GlobalBridgeTests
//
//  Comprehensive test suite for task extraction functionality
//  Tests ViewModel, Persistence, and Model behavior
//

import XCTest
@testable import GlobalBridge

@MainActor
final class TaskExtractionTests: XCTestCase {

    // MARK: - Properties

    var viewModel: TaskExtractionViewModel!
    var mockAIService: MockAIService!
    var mockPersistenceService: MockTaskPersistenceService!
    var testThreadId: UUID!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        testThreadId = UUID()
        mockAIService = MockAIService()
        mockPersistenceService = MockTaskPersistenceService()

        viewModel = TaskExtractionViewModel(
            threadId: testThreadId,
            aiService: mockAIService,
            persistenceService: mockPersistenceService
        )
    }

    override func tearDown() async throws {
        viewModel = nil
        mockAIService = nil
        mockPersistenceService = nil
        testThreadId = nil

        try await super.tearDown()
    }

    // MARK: - Task Extraction Tests

    func testExtractTasks_Success() async throws {
        // Given
        let mockResponse = createMockTaskExtractionResponse()
        mockAIService.extractTasksDetailedResult = .success(mockResponse)

        // When
        await viewModel.extractTasks()

        // Then
        XCTAssertFalse(viewModel.isExtracting)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(mockPersistenceService.savedTasks.count, 3)
        XCTAssertTrue(mockAIService.extractTasksDetailedCalled)
    }

    func testExtractTasks_Failure() async throws {
        // Given
        mockAIService.extractTasksDetailedResult = .failure(AIServiceError.apiError(message: "Test error"))

        // When
        await viewModel.extractTasks()

        // Then
        XCTAssertFalse(viewModel.isExtracting)
        XCTAssertNotNil(viewModel.lastError)
        XCTAssertEqual(mockPersistenceService.savedTasks.count, 0)
    }

    func testExtractTasks_CustomQuery() async throws {
        // Given
        let customQuery = "urgent deadlines"
        let mockResponse = createMockTaskExtractionResponse()
        mockAIService.extractTasksDetailedResult = .success(mockResponse)

        // When
        await viewModel.extractTasks(customQuery: customQuery)

        // Then
        XCTAssertEqual(mockAIService.lastCustomQuery, customQuery)
        XCTAssertTrue(mockAIService.extractTasksDetailedCalled)
    }

    // MARK: - Task Loading Tests

    func testLoadTasks_Success() async throws {
        // Given
        let mockTasks = createMockTasks(count: 5)
        mockPersistenceService.loadTasksResult = .success(mockTasks)

        // When
        await viewModel.loadTasks()

        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.tasks.count, 5)
    }

    func testLoadTasks_Failure() async throws {
        // Given
        mockPersistenceService.loadTasksResult = .failure(PersistenceError.storageUnavailable)

        // When
        await viewModel.loadTasks()

        // Then
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.lastError)
        XCTAssertEqual(viewModel.tasks.count, 0)
    }

    // MARK: - Task Update Tests

    func testUpdateTaskStatus_Success() async throws {
        // Given
        let task = createMockTask(status: .pending)
        viewModel.tasks = [task]

        // When
        await viewModel.updateTaskStatus(task, status: .completed)

        // Then
        XCTAssertTrue(mockPersistenceService.updateTaskCalled)
        XCTAssertEqual(mockPersistenceService.lastUpdatedTask?.status, .completed)
    }

    func testToggleTaskCompletion() async throws {
        // Given
        let task = createMockTask(status: .pending)
        viewModel.tasks = [task]

        // When
        await viewModel.toggleTaskCompletion(task)

        // Then
        XCTAssertTrue(mockPersistenceService.updateTaskCalled)
        XCTAssertEqual(mockPersistenceService.lastUpdatedTask?.status, .completed)
    }

    func testToggleTaskCompletion_AlreadyCompleted() async throws {
        // Given
        let task = createMockTask(status: .completed)
        viewModel.tasks = [task]

        // When
        await viewModel.toggleTaskCompletion(task)

        // Then
        XCTAssertTrue(mockPersistenceService.updateTaskCalled)
        XCTAssertEqual(mockPersistenceService.lastUpdatedTask?.status, .pending)
    }

    // MARK: - Task Deletion Tests

    func testDeleteTask_Success() async throws {
        // Given
        let task = createMockTask()
        viewModel.tasks = [task]

        // When
        await viewModel.deleteTask(task)

        // Then
        XCTAssertTrue(mockPersistenceService.deleteTaskCalled)
        XCTAssertEqual(mockPersistenceService.lastDeletedTaskId, task.id)
    }

    func testDeleteTasks_Multiple() async throws {
        // Given
        let tasks = createMockTasks(count: 3)
        viewModel.tasks = tasks
        let taskIds = tasks.map { $0.id }

        // When
        await viewModel.deleteTasks(taskIds)

        // Then
        XCTAssertEqual(mockPersistenceService.deleteTaskCallCount, 3)
    }

    // MARK: - Filtering Tests

    func testFilteredTasks_All() {
        // Given
        viewModel.tasks = createMockTasks(count: 5)
        viewModel.filterSelection = .all

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 5)
    }

    func testFilteredTasks_Overdue() {
        // Given
        let overdueTasks = [
            createMockTask(dueDate: Date().addingTimeInterval(-86400)), // Yesterday
            createMockTask(dueDate: Date().addingTimeInterval(-172800)) // 2 days ago
        ]
        let futureTasks = [
            createMockTask(dueDate: Date().addingTimeInterval(86400)) // Tomorrow
        ]
        viewModel.tasks = overdueTasks + futureTasks
        viewModel.filterSelection = .overdue

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.isOverdue })
    }

    func testFilteredTasks_DueSoon() {
        // Given
        let dueSoonTasks = [
            createMockTask(dueDate: Date().addingTimeInterval(3600)), // 1 hour
            createMockTask(dueDate: Date().addingTimeInterval(43200)) // 12 hours
        ]
        let otherTasks = [
            createMockTask(dueDate: Date().addingTimeInterval(172800)) // 2 days
        ]
        viewModel.tasks = dueSoonTasks + otherTasks
        viewModel.filterSelection = .dueSoon

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.isDueSoon })
    }

    func testFilteredTasks_HighPriority() {
        // Given
        let highPriorityTasks = [
            createMockTask(priority: .high),
            createMockTask(priority: .urgent)
        ]
        let lowPriorityTasks = [
            createMockTask(priority: .low),
            createMockTask(priority: .medium)
        ]
        viewModel.tasks = highPriorityTasks + lowPriorityTasks
        viewModel.filterSelection = .highPriority

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.priority == .high || $0.priority == .urgent })
    }

    func testFilteredTasks_ByStatus() {
        // Given
        let inProgressTasks = [
            createMockTask(status: .inProgress),
            createMockTask(status: .inProgress)
        ]
        let otherTasks = [
            createMockTask(status: .pending),
            createMockTask(status: .completed)
        ]
        viewModel.tasks = inProgressTasks + otherTasks
        viewModel.filterSelection = .byStatus(.inProgress)

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.status == .inProgress })
    }

    func testFilteredTasks_HideCompleted() {
        // Given
        let activeTasks = [
            createMockTask(status: .pending),
            createMockTask(status: .inProgress)
        ]
        let completedTasks = [
            createMockTask(status: .completed),
            createMockTask(status: .cancelled)
        ]
        viewModel.tasks = activeTasks + completedTasks
        viewModel.showCompletedTasks = false

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.status != .completed && $0.status != .cancelled })
    }

    // MARK: - Search Tests

    func testSearchQuery_Title() {
        // Given
        viewModel.tasks = [
            createMockTask(title: "Implement feature"),
            createMockTask(title: "Fix bug"),
            createMockTask(title: "Write tests")
        ]
        viewModel.searchQuery = "feature"

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Implement feature")
    }

    func testSearchQuery_CaseInsensitive() {
        // Given
        viewModel.tasks = [
            createMockTask(title: "URGENT TASK"),
            createMockTask(title: "normal task")
        ]
        viewModel.searchQuery = "urgent"

        // When
        let filtered = viewModel.filteredTasks

        // Then
        XCTAssertEqual(filtered.count, 1)
    }

    // MARK: - Sorting Tests

    func testSortedByPriority() {
        // Given
        viewModel.tasks = [
            createMockTask(priority: .low),
            createMockTask(priority: .urgent),
            createMockTask(priority: .medium),
            createMockTask(priority: .high)
        ]
        viewModel.sortOrder = .priority

        // When
        let sorted = viewModel.filteredTasks

        // Then
        XCTAssertEqual(sorted[0].priority, .urgent)
        XCTAssertEqual(sorted[1].priority, .high)
        XCTAssertEqual(sorted[2].priority, .medium)
        XCTAssertEqual(sorted[3].priority, .low)
    }

    func testSortedByDueDate() {
        // Given
        let tomorrow = Date().addingTimeInterval(86400)
        let nextWeek = Date().addingTimeInterval(604800)
        let yesterday = Date().addingTimeInterval(-86400)

        viewModel.tasks = [
            createMockTask(dueDate: nextWeek),
            createMockTask(dueDate: yesterday),
            createMockTask(dueDate: tomorrow)
        ]
        viewModel.sortOrder = .dueDate

        // When
        let sorted = viewModel.filteredTasks

        // Then
        XCTAssertTrue(sorted[0].dueDate! < sorted[1].dueDate!)
        XCTAssertTrue(sorted[1].dueDate! < sorted[2].dueDate!)
    }

    // MARK: - Statistics Tests

    func testStatistics_Calculation() {
        // Given
        viewModel.tasks = [
            createMockTask(status: .completed),
            createMockTask(status: .completed),
            createMockTask(status: .pending, priority: .high, dueDate: Date().addingTimeInterval(-86400)),
            createMockTask(status: .inProgress, priority: .urgent),
            createMockTask(status: .pending)
        ]

        // When
        let stats = viewModel.statistics

        // Then
        XCTAssertEqual(stats.total, 5)
        XCTAssertEqual(stats.completed, 2)
        XCTAssertEqual(stats.overdue, 1)
        XCTAssertEqual(stats.highPriority, 2)
        XCTAssertEqual(stats.completionRate, 0.4, accuracy: 0.01)
    }

    // MARK: - Bulk Operations Tests

    func testMarkTasksComplete_Multiple() async throws {
        // Given
        let tasks = createMockTasks(count: 3)
        viewModel.tasks = tasks
        let taskIds = tasks.map { $0.id }

        // When
        await viewModel.markTasksComplete(taskIds)

        // Then
        XCTAssertEqual(mockPersistenceService.updateTaskCallCount, 3)
    }

    // MARK: - Helper Methods

    private func createMockTask(
        title: String = "Test Task",
        status: ExtractedTask.Status = .pending,
        priority: ExtractedTask.Priority = .medium,
        dueDate: Date? = nil
    ) -> ExtractedTask {
        ExtractedTask(
            threadId: testThreadId,
            title: title,
            description: "Test description",
            priority: priority,
            status: status,
            dueDate: dueDate
        )
    }

    private func createMockTasks(count: Int) -> [ExtractedTask] {
        (0..<count).map { index in
            createMockTask(title: "Task \(index)")
        }
    }

    private func createMockTaskExtractionResponse() -> TaskExtractionAPIResponse {
        TaskExtractionAPIResponse(
            success: true,
            extraction: TaskExtractionAPIResponse.ExtractionData(
                tasks: [
                    TaskExtractionAPIResponse.ExtractionData.TaskDTO(
                        title: "Task 1",
                        description: "Description 1",
                        assignee: nil,
                        dueDate: nil,
                        priority: "medium",
                        taskType: "action",
                        confidence: 0.9,
                        relatedMessageIds: nil,
                        tags: nil
                    ),
                    TaskExtractionAPIResponse.ExtractionData.TaskDTO(
                        title: "Task 2",
                        description: "Description 2",
                        assignee: "John",
                        dueDate: ISO8601DateFormatter().string(from: Date()),
                        priority: "high",
                        taskType: "deadline",
                        confidence: 0.95,
                        relatedMessageIds: nil,
                        tags: ["urgent"]
                    )
                ],
                decisions: [
                    TaskExtractionAPIResponse.ExtractionData.TaskDTO(
                        title: "Decision 1",
                        description: nil,
                        assignee: nil,
                        dueDate: nil,
                        priority: "high",
                        taskType: "decision",
                        confidence: 0.85,
                        relatedMessageIds: nil,
                        tags: nil
                    )
                ],
                deadlines: nil
            ),
            threadId: testThreadId,
            query: nil
        )
    }
}

// MARK: - Mock Services

final class MockAIService: AIService {
    var extractTasksDetailedCalled = false
    var lastCustomQuery: String?
    var extractTasksDetailedResult: Result<TaskExtractionAPIResponse, Error> = .failure(AIServiceError.notAuthenticated)

    override func extractTasksDetailed(threadId: String, query: String?) async throws -> TaskExtractionAPIResponse {
        extractTasksDetailedCalled = true
        lastCustomQuery = query

        switch extractTasksDetailedResult {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

@MainActor
final class MockTaskPersistenceService: TaskPersistenceService {
    var savedTasks: [ExtractedTask] = []
    var loadTasksResult: Result<[ExtractedTask], Error> = .success([])
    var updateTaskCalled = false
    var updateTaskCallCount = 0
    var deleteTaskCalled = false
    var deleteTaskCallCount = 0
    var lastUpdatedTask: ExtractedTask?
    var lastDeletedTaskId: UUID?

    override func saveTask(_ task: ExtractedTask) async throws {
        savedTasks.append(task)
    }

    override func loadTasks(for threadId: UUID) async throws -> [ExtractedTask] {
        switch loadTasksResult {
        case .success(let tasks):
            return tasks
        case .failure(let error):
            throw error
        }
    }

    override func updateTask(_ task: ExtractedTask) async throws {
        updateTaskCalled = true
        updateTaskCallCount += 1
        lastUpdatedTask = task

        // Simulate successful update by updating loadTasksResult
        if case .success(var tasks) = loadTasksResult {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = task
                loadTasksResult = .success(tasks)
            }
        }
    }

    override func deleteTask(_ taskId: UUID) async throws {
        deleteTaskCalled = true
        deleteTaskCallCount += 1
        lastDeletedTaskId = taskId

        // Simulate successful deletion
        if case .success(var tasks) = loadTasksResult {
            tasks.removeAll { $0.id == taskId }
            loadTasksResult = .success(tasks)
        }
    }
}
