//
//  TaskDetailView.swift
//  GlobalBridge
//
//  Detailed view for task management and editing
//  Allows editing task properties, adding notes, and exporting
//

import SwiftUI
@preconcurrency import EventKit

/// Detailed view for viewing and editing a task
struct TaskDetailView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: TaskExtractionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var task: ExtractedTask
    @State private var isEditing = false
    @State private var showingDeleteConfirmation = false
    @State private var showingExportSheet = false
    @State private var showingMessageLink = false
    @State private var editedTitle: String
    @State private var editedDescription: String
    @State private var editedAssignee: String
    @State private var editedDueDate: Date?
    @State private var editedPriority: ExtractedTask.Priority
    @State private var editedStatus: ExtractedTask.Status
    @State private var editedTags: String
    @State private var hasDueDate: Bool

    // MARK: - Initialization

    init(task: ExtractedTask, viewModel: TaskExtractionViewModel) {
        self.viewModel = viewModel
        _task = State(initialValue: task)
        _editedTitle = State(initialValue: task.title)
        _editedDescription = State(initialValue: task.description ?? "")
        _editedAssignee = State(initialValue: task.assignee ?? "")
        _editedDueDate = State(initialValue: task.dueDate)
        _editedPriority = State(initialValue: task.priority)
        _editedStatus = State(initialValue: task.status)
        _editedTags = State(initialValue: task.tags.joined(separator: ", "))
        _hasDueDate = State(initialValue: task.dueDate != nil)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if isEditing {
                    editingSections
                } else {
                    viewingSections
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    closeButton
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        saveButton
                    } else {
                        editButton
                    }
                }
            }
            .alert("Delete Task", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteTask(task)
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure you want to delete this task?")
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportTaskSheet(task: task)
            }
        }
    }

    // MARK: - Viewing Sections

    @ViewBuilder
    private var viewingSections: some View {
        Section("Details") {
            DetailRow(label: "Title", value: task.title, icon: "text.alignleft")

            if let description = task.description {
                DetailRow(label: "Description", value: description, icon: "text.quote")
            }

            DetailRow(label: "Status", icon: "circle.fill") {
                StatusBadge(status: task.status)
            }

            DetailRow(label: "Priority", icon: "exclamationmark.circle") {
                PriorityBadge(priority: task.priority)
            }

            if let taskType = task.taskType {
                DetailRow(label: "Type", value: taskType.rawValue.capitalized, icon: task.taskTypeIcon)
            }
        }

        Section("Assignment") {
            if let assignee = task.assignee {
                DetailRow(label: "Assignee", value: assignee, icon: "person.fill")
            } else {
                Text("Unassigned")
                    .foregroundColor(.secondary)
            }

            if let dueDate = task.dueDate {
                DetailRow(label: "Due Date", icon: "calendar") {
                    VStack(alignment: .trailing) {
                        Text(dueDate, style: .date)
                        Text(dueDate, style: .time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if task.isOverdue {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Overdue")
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    }
                } else if task.isDueSoon {
                    HStack {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundColor(.orange)
                        Text("Due Soon")
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                }

                if let daysUntil = task.daysUntilDue {
                    DetailRow(
                        label: "Days Until Due",
                        value: "\(abs(daysUntil)) days \(daysUntil < 0 ? "overdue" : "remaining")",
                        icon: "calendar.badge.clock"
                    )
                }
            }
        }

        if !task.tags.isEmpty {
            Section("Tags") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(task.tags, id: \.self) { tag in
                            TagBadge(tag: tag)
                        }
                    }
                }
            }
        }

        Section("Metadata") {
            DetailRow(
                label: "Extracted",
                value: task.extractedAt.formatted(date: .abbreviated, time: .shortened),
                icon: "clock.arrow.circlepath"
            )

            if let confidence = task.confidencePercentage {
                DetailRow(label: "Confidence", value: confidence, icon: "chart.bar.fill")
            }

            if !task.relatedMessageIds.isEmpty {
                Button {
                    showingMessageLink = true
                } label: {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("View Related Messages (\(task.relatedMessageIds.count))")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        Section("Actions") {
            Button {
                Task {
                    await toggleCompletion()
                }
            } label: {
                HStack {
                    Image(systemName: task.status == .completed ? "arrow.uturn.backward" : "checkmark.circle.fill")
                    Text(task.status == .completed ? "Mark Incomplete" : "Mark Complete")
                }
                .foregroundColor(task.status == .completed ? .orange : .green)
            }

            Button {
                showingExportSheet = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Task")
                }
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Task")
                }
            }
        }
    }

    // MARK: - Editing Sections

    @ViewBuilder
    private var editingSections: some View {
        Section("Details") {
            TextField("Title", text: $editedTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $editedDescription)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            Picker("Status", selection: $editedStatus) {
                ForEach([ExtractedTask.Status.pending, .inProgress, .completed, .blocked, .cancelled], id: \.self) { status in
                    Text(status.rawValue.capitalized).tag(status)
                }
            }

            Picker("Priority", selection: $editedPriority) {
                ForEach(ExtractedTask.Priority.allCases, id: \.self) { priority in
                    Text(priority.rawValue.capitalized).tag(priority)
                }
            }
        }

        Section("Assignment") {
            TextField("Assignee", text: $editedAssignee)
                .textFieldStyle(.roundedBorder)

            Toggle("Has Due Date", isOn: $hasDueDate)

            if hasDueDate {
                DatePicker(
                    "Due Date",
                    selection: Binding(
                        get: { editedDueDate ?? Date() },
                        set: { editedDueDate = $0 }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        }

        Section("Tags") {
            TextField("Tags (comma separated)", text: $editedTags)
                .textFieldStyle(.roundedBorder)

            Text("Separate tags with commas")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Toolbar Buttons

    private var closeButton: some View {
        Button {
            if isEditing {
                isEditing = false
            } else {
                dismiss()
            }
        } label: {
            Text(isEditing ? "Cancel" : "Close")
        }
    }

    private var editButton: some View {
        Button {
            isEditing = true
        } label: {
            Text("Edit")
        }
    }

    private var saveButton: some View {
        Button {
            saveChanges()
        } label: {
            Text("Save")
                .fontWeight(.semibold)
        }
        .disabled(editedTitle.isEmpty)
    }

    // MARK: - Helper Methods

    private func saveChanges() {
        let tags = editedTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let updatedTask = ExtractedTask(
            id: task.id,
            threadId: task.threadId,
            title: editedTitle,
            description: editedDescription.isEmpty ? nil : editedDescription,
            assignee: editedAssignee.isEmpty ? nil : editedAssignee,
            assigneeId: task.assigneeId,
            dueDate: hasDueDate ? editedDueDate : nil,
            priority: editedPriority,
            status: editedStatus,
            tags: tags,
            relatedMessageIds: task.relatedMessageIds,
            taskType: task.taskType,
            confidence: task.confidence,
            extractedAt: task.extractedAt
        )

        Task {
            await viewModel.updateTask(updatedTask)
            task = updatedTask
            isEditing = false
        }
    }

    private func toggleCompletion() async {
        await viewModel.toggleTaskCompletion(task)

        // Reload task from viewModel
        if let updatedTask = viewModel.tasks.first(where: { $0.id == task.id }) {
            task = updatedTask
        }
    }
}

// MARK: - Supporting Views

/// Detail row component
struct DetailRow<Content: View>: View {
    let label: String
    let icon: String
    let content: Content

    init(label: String, icon: String = "", @ViewBuilder content: () -> Content) {
        self.label = label
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        HStack {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
            }

            Text(label)
                .foregroundColor(.secondary)

            Spacer()

            content
        }
    }
}

extension DetailRow where Content == Text {
    init(label: String, value: String, icon: String = "") {
        self.label = label
        self.icon = icon
        self.content = Text(value)
    }
}

/// Status badge component
struct StatusBadge: View {
    let status: ExtractedTask.Status

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(status.rawValue.capitalized)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .cornerRadius(6)
    }

    private var icon: String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .blocked: return "hand.raised.fill"
        }
    }

    private var color: Color {
        switch status {
        case .pending: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .gray
        case .blocked: return .red
        }
    }
}

/// Tag badge component
struct TagBadge: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(12)
    }
}

/// Export task sheet
struct ExportTaskSheet: View {
    let task: ExtractedTask
    @Environment(\.dismiss) private var dismiss

    @State private var showingCalendarPermissionAlert = false
    @State private var showingRemindersPermissionAlert = false
    @State private var exportSuccess = false

    var body: some View {
        NavigationStack {
            List {
                Section("Export Options") {
                    Button {
                        exportToCalendar()
                    } label: {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                            Text("Export to Calendar")
                        }
                    }

                    Button {
                        exportToReminders()
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                            Text("Export to Reminders")
                        }
                    }

                    Button {
                        shareTask()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Task")
                        }
                    }
                }

                Section("Task Information") {
                    Text(task.title)
                        .font(.headline)

                    if let description = task.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let dueDate = task.dueDate {
                        HStack {
                            Image(systemName: "calendar")
                            Text(dueDate, style: .date)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Export Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Calendar Access Required", isPresented: $showingCalendarPermissionAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("Please grant calendar access in Settings to export tasks.")
            }
            .alert("Reminders Access Required", isPresented: $showingRemindersPermissionAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("Please grant reminders access in Settings to export tasks.")
            }
        }
    }

    // MARK: - Export Methods

    private func exportToCalendar() {
        let store = EKEventStore()
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    // Use a fresh store instance inside the closure to avoid capturing non-Sendable
                    createCalendarEvent(eventStore: EKEventStore())
                } else {
                    showingCalendarPermissionAlert = true
                }
            }
        }
    }

    private func createCalendarEvent(eventStore: EKEventStore) {
        let event = EKEvent(eventStore: eventStore)
        event.title = task.title
        event.notes = task.description

        if let dueDate = task.dueDate {
            event.startDate = dueDate
            event.endDate = dueDate.addingTimeInterval(3600) // 1 hour duration
        } else {
            event.startDate = Date()
            event.endDate = Date().addingTimeInterval(3600)
        }

        event.calendar = eventStore.defaultCalendarForNewEvents

        // Add alarm if due date exists
        if task.dueDate != nil {
            let alarm = EKAlarm(relativeOffset: -3600) // 1 hour before
            event.addAlarm(alarm)
        }

        do {
            try eventStore.save(event, span: .thisEvent)
            print("✅ [EXPORT] Task exported to Calendar")
            exportSuccess = true
        } catch {
            print("❌ [EXPORT] Failed to save event: \(error)")
        }
    }

    private func exportToReminders() {
        let store = EKEventStore()
        store.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    // Use a fresh store instance inside the closure to avoid capturing non-Sendable
                    createReminder(eventStore: EKEventStore())
                } else {
                    showingRemindersPermissionAlert = true
                }
            }
        }
    }

    private func createReminder(eventStore: EKEventStore) {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = task.title
        reminder.notes = task.description
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let dueDate = task.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)

            let alarm = EKAlarm(absoluteDate: dueDate.addingTimeInterval(-3600))
            reminder.addAlarm(alarm)
        }

        // Set priority
        switch task.priority {
        case .urgent:
            reminder.priority = 1
        case .high:
            reminder.priority = 5
        case .medium:
            reminder.priority = 5
        case .low:
            reminder.priority = 9
        }

        do {
            try eventStore.save(reminder, commit: true)
            print("✅ [EXPORT] Task exported to Reminders")
            exportSuccess = true
        } catch {
            print("❌ [EXPORT] Failed to save reminder: \(error)")
        }
    }

    private func shareTask() {
        var text = "Task: \(task.title)\n"

        if let description = task.description {
            text += "\nDescription: \(description)\n"
        }

        if let assignee = task.assignee {
            text += "\nAssignee: \(assignee)\n"
        }

        if let dueDate = task.dueDate {
            text += "\nDue: \(dueDate.formatted(date: .long, time: .shortened))\n"
        }

        text += "\nPriority: \(task.priority.rawValue.capitalized)\n"
        text += "Status: \(task.status.rawValue.capitalized)\n"

        if !task.tags.isEmpty {
            text += "\nTags: \(task.tags.joined(separator: ", "))\n"
        }

        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Preview

#Preview {
    TaskDetailView(
        task: ExtractedTask(
            threadId: UUID(),
            title: "Implement feature",
            description: "Add new functionality to the app",
            assignee: "John Doe",
            dueDate: Date().addingTimeInterval(86400),
            priority: .high,
            status: .inProgress,
            tags: ["feature", "urgent"],
            taskType: .action,
            confidence: 0.95
        ),
        viewModel: TaskExtractionViewModel(threadId: UUID())
    )
}
