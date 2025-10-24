//
//  TaskExtractionView.swift
//  GlobalBridge
//
//  Main view for displaying and managing extracted tasks
//  Auto-detected action items from conversation threads
//

import SwiftUI

/// Main view for task extraction and management
struct TaskExtractionView: View {

    // MARK: - Properties

    @StateObject private var viewModel: TaskExtractionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilterSheet = false
    @State private var showingSortSheet = false
    @State private var showingTaskDetail = false
    @State private var showingDeleteConfirmation = false
    @State private var taskToDelete: ExtractedTask?
    @State private var selectedTasks: Set<UUID> = []
    @State private var isInSelectionMode = false
    @State private var customQuery: String = ""
    @State private var showingCustomQueryAlert = false

    // MARK: - Initialization

    init(threadId: UUID) {
        _viewModel = StateObject(wrappedValue: TaskExtractionViewModel(threadId: threadId))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Loading tasks...")
                } else if viewModel.tasks.isEmpty {
                    emptyStateView
                } else {
                    taskListView
                }
            }
            .navigationTitle("Action Items")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    closeButton
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    trailingToolbar
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search tasks...")
            .sheet(isPresented: $showingFilterSheet) {
                filterSheet
            }
            .sheet(isPresented: $showingSortSheet) {
                sortSheet
            }
            .sheet(item: $viewModel.selectedTask) { task in
                TaskDetailView(task: task, viewModel: viewModel)
            }
            .alert("Delete Task", isPresented: $showingDeleteConfirmation, presenting: taskToDelete) { task in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteTask(task)
                    }
                }
            } message: { task in
                Text("Are you sure you want to delete '\(task.title)'?")
            }
            .alert("Custom Extraction Query", isPresented: $showingCustomQueryAlert) {
                TextField("Enter custom query", text: $customQuery)
                Button("Cancel", role: .cancel) {}
                Button("Extract") {
                    Task {
                        await viewModel.extractTasks(customQuery: customQuery.isEmpty ? nil : customQuery)
                    }
                }
            } message: {
                Text("Enter a custom query to extract specific types of tasks (e.g., 'urgent decisions', 'next week deadlines')")
            }
            .overlay {
                if let error = viewModel.lastError {
                    errorOverlay(error: error)
                }
            }
            .task {
                await viewModel.loadTasks()
            }
        }
    }

    // MARK: - Subviews

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }

    private var trailingToolbar: some View {
        Menu {
            extractTasksButton
            Divider()
            filterButton
            sortButton
            Divider()
            toggleCompletedButton
            selectionModeButton
            if isInSelectionMode {
                bulkActionsMenu
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
        }
    }

    private var extractTasksButton: some View {
        Menu {
            Button {
                Task {
                    await viewModel.extractTasks()
                }
            } label: {
                Label("Extract Tasks", systemImage: "sparkles")
            }

            Button {
                showingCustomQueryAlert = true
            } label: {
                Label("Custom Query...", systemImage: "text.magnifyingglass")
            }
        } label: {
            Label("Extract Tasks", systemImage: "sparkles")
        }
    }

    private var filterButton: some View {
        Button {
            showingFilterSheet = true
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var sortButton: some View {
        Button {
            showingSortSheet = true
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down.circle")
        }
    }

    private var toggleCompletedButton: some View {
        Button {
            viewModel.showCompletedTasks.toggle()
        } label: {
            Label(
                viewModel.showCompletedTasks ? "Hide Completed" : "Show Completed",
                systemImage: viewModel.showCompletedTasks ? "eye.slash" : "eye"
            )
        }
    }

    private var selectionModeButton: some View {
        Button {
            isInSelectionMode.toggle()
            if !isInSelectionMode {
                selectedTasks.removeAll()
            }
        } label: {
            Label(
                isInSelectionMode ? "Cancel Selection" : "Select Tasks",
                systemImage: isInSelectionMode ? "xmark.circle" : "checkmark.circle"
            )
        }
    }

    private var bulkActionsMenu: some View {
        Menu {
            Button {
                Task {
                    await viewModel.markTasksComplete(Array(selectedTasks))
                    selectedTasks.removeAll()
                    isInSelectionMode = false
                }
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle.fill")
            }
            .disabled(selectedTasks.isEmpty)

            Button(role: .destructive) {
                Task {
                    await viewModel.deleteTasks(Array(selectedTasks))
                    selectedTasks.removeAll()
                    isInSelectionMode = false
                }
            } label: {
                Label("Delete Selected", systemImage: "trash")
            }
            .disabled(selectedTasks.isEmpty)
        } label: {
            Label("Bulk Actions (\(selectedTasks.count))", systemImage: "square.stack.3d.up")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 72))
                .foregroundColor(.secondary)

            Text("No Action Items")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Extract tasks from this conversation to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task {
                    await viewModel.extractTasks()
                }
            } label: {
                Label("Extract Tasks", systemImage: "sparkles")
                    .font(.headline)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExtracting)

            if viewModel.isExtracting {
                ProgressView()
                    .padding(.top)
            }
        }
        .padding()
    }

    private var taskListView: some View {
        List {
            statisticsSection

            if viewModel.filteredTasks.isEmpty {
                Section {
                    Text("No tasks match your filters")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }
            } else {
                ForEach(viewModel.filteredTasks) { task in
                    TaskRowView(
                        task: task,
                        isSelected: selectedTasks.contains(task.id),
                        isInSelectionMode: isInSelectionMode,
                        onTap: {
                            if isInSelectionMode {
                                toggleSelection(task.id)
                            } else {
                                viewModel.selectedTask = task
                            }
                        },
                        onToggleComplete: {
                            Task {
                                await viewModel.toggleTaskCompletion(task)
                            }
                        },
                        onDelete: {
                            taskToDelete = task
                            showingDeleteConfirmation = true
                        }
                    )
                }
            }

            if viewModel.isExtracting {
                Section {
                    HStack {
                        ProgressView()
                        Text("Extracting tasks...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var statisticsSection: some View {
        Section {
            TaskStatisticsView(statistics: viewModel.statistics)
        }
    }

    private var filterSheet: some View {
        NavigationStack {
            List {
                Section("Quick Filters") {
                    FilterOptionRow(
                        title: "All Tasks",
                        icon: "tray.fill",
                        isSelected: viewModel.filterSelection == .all
                    ) {
                        viewModel.filterSelection = .all
                        showingFilterSheet = false
                    }

                    FilterOptionRow(
                        title: "Overdue",
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        isSelected: viewModel.filterSelection == .overdue
                    ) {
                        viewModel.filterSelection = .overdue
                        showingFilterSheet = false
                    }

                    FilterOptionRow(
                        title: "Due Soon",
                        icon: "clock.fill",
                        color: .orange,
                        isSelected: viewModel.filterSelection == .dueSoon
                    ) {
                        viewModel.filterSelection = .dueSoon
                        showingFilterSheet = false
                    }

                    FilterOptionRow(
                        title: "High Priority",
                        icon: "exclamationmark.2",
                        color: .red,
                        isSelected: viewModel.filterSelection == .highPriority
                    ) {
                        viewModel.filterSelection = .highPriority
                        showingFilterSheet = false
                    }

                    FilterOptionRow(
                        title: "Unassigned",
                        icon: "person.crop.circle.badge.questionmark",
                        isSelected: viewModel.filterSelection == .unassigned
                    ) {
                        viewModel.filterSelection = .unassigned
                        showingFilterSheet = false
                    }
                }

                Section("By Status") {
                    ForEach([ExtractedTask.Status.pending, .inProgress, .blocked], id: \.self) { status in
                        FilterOptionRow(
                            title: status.rawValue.capitalized,
                            icon: statusIcon(for: status),
                            color: statusColor(for: status),
                            isSelected: viewModel.filterSelection == .byStatus(status)
                        ) {
                            viewModel.filterSelection = .byStatus(status)
                            showingFilterSheet = false
                        }
                    }
                }

                Section("By Priority") {
                    ForEach(ExtractedTask.Priority.allCases, id: \.self) { priority in
                        FilterOptionRow(
                            title: priority.rawValue.capitalized,
                            icon: priorityIcon(for: priority),
                            color: priorityColor(for: priority),
                            isSelected: viewModel.filterSelection == .byPriority(priority)
                        ) {
                            viewModel.filterSelection = .byPriority(priority)
                            showingFilterSheet = false
                        }
                    }
                }
            }
            .navigationTitle("Filter Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingFilterSheet = false
                    }
                }
            }
        }
    }

    private var sortSheet: some View {
        NavigationStack {
            List {
                ForEach(TaskSortOrder.allCases) { order in
                    Button {
                        viewModel.sortOrder = order
                        showingSortSheet = false
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            Spacer()
                            if viewModel.sortOrder == order {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Sort By")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingSortSheet = false
                    }
                }
            }
        }
    }

    private func errorOverlay(error: Error) -> some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(error.localizedDescription)
                    .foregroundColor(.white)
                    .font(.subheadline)
                Spacer()
                Button {
                    viewModel.clearError()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.red)
            .cornerRadius(12)
            .padding()
        }
    }

    // MARK: - Helper Methods

    private func toggleSelection(_ taskId: UUID) {
        if selectedTasks.contains(taskId) {
            selectedTasks.remove(taskId)
        } else {
            selectedTasks.insert(taskId)
        }
    }

    private func statusIcon(for status: ExtractedTask.Status) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .blocked: return "hand.raised.fill"
        }
    }

    private func statusColor(for status: ExtractedTask.Status) -> Color {
        switch status {
        case .pending: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .gray
        case .blocked: return .red
        }
    }

    private func priorityIcon(for priority: ExtractedTask.Priority) -> String {
        switch priority {
        case .urgent: return "exclamationmark.3"
        case .high: return "exclamationmark.2"
        case .medium: return "exclamationmark"
        case .low: return "minus"
        }
    }

    private func priorityColor(for priority: ExtractedTask.Priority) -> Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .gray
        }
    }
}

// MARK: - Supporting Views

/// Task row component
struct TaskRowView: View {
    let task: ExtractedTask
    let isSelected: Bool
    let isInSelectionMode: Bool
    let onTap: () -> Void
    let onToggleComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isInSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title3)
            } else {
                Button(action: onToggleComplete) {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.status == .completed ? .green : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .strikethrough(task.status == .completed)

                    Spacer()

                    if let taskType = task.taskType {
                        Image(systemName: task.taskTypeIcon)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let description = task.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    // Priority badge
                    PriorityBadge(priority: task.priority)

                    // Due date badge
                    if let dueDate = task.formattedDueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(dueDate)
                        }
                        .font(.caption2)
                        .foregroundColor(task.isOverdue ? .red : task.isDueSoon ? .orange : .secondary)
                    }

                    // Assignee badge
                    if let assignee = task.assignee {
                        HStack(spacing: 4) {
                            Image(systemName: "person")
                            Text(assignee)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Confidence badge
                    if let confidence = task.confidencePercentage, task.isHighConfidence {
                        Text(confidence)
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Priority badge component
struct PriorityBadge: View {
    let priority: ExtractedTask.Priority

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(priority.rawValue.capitalized)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(4)
    }

    private var icon: String {
        switch priority {
        case .urgent: return "exclamationmark.3"
        case .high: return "exclamationmark.2"
        case .medium: return "exclamationmark"
        case .low: return "minus"
        }
    }

    private var color: Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .gray
        }
    }
}

/// Task statistics view
struct TaskStatisticsView: View {
    let statistics: TaskStatistics

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                StatisticBadge(
                    title: "Total",
                    value: "\(statistics.total)",
                    icon: "list.bullet",
                    color: .blue
                )

                StatisticBadge(
                    title: "Completed",
                    value: "\(statistics.completed)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                StatisticBadge(
                    title: "Overdue",
                    value: "\(statistics.overdue)",
                    icon: "exclamationmark.triangle.fill",
                    color: .red
                )
            }

            if statistics.total > 0 {
                ProgressView(value: statistics.completionRate) {
                    Text("Completion Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } currentValueLabel: {
                    Text("\(Int(statistics.completionRate * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tint(.green)
            }
        }
        .padding(.vertical, 8)
    }
}

/// Statistic badge component
struct StatisticBadge: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Filter option row component
struct FilterOptionRow: View {
    let title: String
    let icon: String
    var color: Color = .accentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)

                Text(title)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Preview

#Preview {
    TaskExtractionView(threadId: UUID())
}
