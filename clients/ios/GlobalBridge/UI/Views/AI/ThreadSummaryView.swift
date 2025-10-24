//
//  ThreadSummaryView.swift
//  GlobalBridge
//
//  AI-powered thread summarization display with collapsible sections
//  Shows key points, action items, decisions, and participant highlights
//

import SwiftUI

/// Displays a comprehensive thread summary with collapsible sections
struct ThreadSummaryView: View {
    // MARK: - Properties

    let summary: ThreadSummary
    let onRegenerateTapped: (() -> Void)?
    let onExportTapped: (() -> Void)?
    let onDismissTapped: (() -> Void)?

    @State private var isExpanded: Bool = true
    @State private var expandedSections: Set<SummarySection> = [.keyPoints, .actionItems]
    @State private var selectedActionItem: ThreadSummary.ActionItem?
    @State private var showingShareSheet = false

    // MARK: - Section Types

    enum SummarySection: String, CaseIterable, Identifiable {
        case keyPoints = "Key Points"
        case actionItems = "Action Items"
        case decisions = "Decisions"
        case participants = "Participants"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .keyPoints: return "list.bullet"
            case .actionItems: return "checkmark.circle"
            case .decisions: return "lightbulb"
            case .participants: return "person.2"
            }
        }

        var color: Color {
            switch self {
            case .keyPoints: return .blue
            case .actionItems: return .green
            case .decisions: return .purple
            case .participants: return .orange
            }
        }
    }

    // MARK: - Initialization

    init(
        summary: ThreadSummary,
        onRegenerateTapped: (() -> Void)? = nil,
        onExportTapped: (() -> Void)? = nil,
        onDismissTapped: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.onRegenerateTapped = onRegenerateTapped
        self.onExportTapped = onExportTapped
        self.onDismissTapped = onDismissTapped
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with collapse/expand
            headerView

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Main summary text
                        summaryTextView

                        Divider()
                            .padding(.vertical, 8)

                        // Sections
                        VStack(spacing: 12) {
                            if summary.hasKeyPoints {
                                sectionView(
                                    section: .keyPoints,
                                    items: summary.keyPoints
                                )
                            }

                            if summary.hasActionItems {
                                actionItemsSectionView
                            }

                            if summary.hasDecisions {
                                sectionView(
                                    section: .decisions,
                                    items: summary.decisions
                                )
                            }

                            participantsSectionView
                        }

                        // Metadata footer
                        metadataFooterView
                    }
                    .padding(16)
                }
                .frame(maxHeight: 500)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .sheet(item: $selectedActionItem) { actionItem in
            actionItemDetailView(actionItem)
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            // AI Icon
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Thread Summary")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    if let messageCount = summary.messageCount {
                        Text("\(messageCount) messages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if summary.isStale {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Updated \(timeAgoString)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                if let onExport = onExportTapped {
                    Button(action: onExport) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                }

                if let onRegenerate = onRegenerateTapped {
                    Button(action: onRegenerate) {
                        Image(systemName: "arrow.clockwise")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                }

                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(isExpanded ? 0 : 12)
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Summary Text View

    private var summaryTextView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Summary")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Text(summary.summary)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
        }
    }

    // MARK: - Section View (Generic)

    private func sectionView(section: SummarySection, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button(action: {
                withAnimation {
                    if expandedSections.contains(section) {
                        expandedSections.remove(section)
                    } else {
                        expandedSections.insert(section)
                    }
                }
            }) {
                HStack {
                    Image(systemName: section.icon)
                        .font(.caption)
                        .foregroundColor(section.color)

                    Text(section.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text("(\(items.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: expandedSections.contains(section) ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Section content
            if expandedSections.contains(section) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}")
                                .font(.body)
                                .foregroundColor(section.color)

                            Text(item)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 4)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(12)
        .background(section.color.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Action Items Section

    private var actionItemsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button(action: {
                withAnimation {
                    if expandedSections.contains(.actionItems) {
                        expandedSections.remove(.actionItems)
                    } else {
                        expandedSections.insert(.actionItems)
                    }
                }
            }) {
                HStack {
                    Image(systemName: SummarySection.actionItems.icon)
                        .font(.caption)
                        .foregroundColor(.green)

                    Text("Action Items")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text("(\(summary.actionItems.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if summary.pendingActionItemsCount > 0 {
                        Text("\(summary.pendingActionItemsCount) pending")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Spacer()

                    Image(systemName: expandedSections.contains(.actionItems) ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Action items list
            if expandedSections.contains(.actionItems) {
                VStack(spacing: 8) {
                    ForEach(summary.actionItems) { actionItem in
                        actionItemCard(actionItem)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(12)
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }

    private func actionItemCard(_ actionItem: ThreadSummary.ActionItem) -> some View {
        Button(action: {
            selectedActionItem = actionItem
        }) {
            HStack(alignment: .top, spacing: 12) {
                // Priority indicator
                Circle()
                    .fill(priorityColor(for: actionItem.priority))
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    // Description
                    Text(actionItem.description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    // Metadata row
                    HStack(spacing: 8) {
                        if let assignee = actionItem.assignee {
                            Label(assignee, systemImage: "person")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let dueDate = actionItem.dueDate {
                            Label(formatDate(dueDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(actionItem.isOverdue ? .red : .secondary)
                        }

                        if let status = actionItem.status {
                            statusBadge(status)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func statusBadge(_ status: ThreadSummary.ActionItem.Status) -> some View {
        Text(status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status))
            .cornerRadius(4)
    }

    private func statusColor(_ status: ThreadSummary.ActionItem.Status) -> Color {
        switch status {
        case .pending: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .cancelled: return .red
        }
    }

    // MARK: - Participants Section

    private var participantsSectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button(action: {
                withAnimation {
                    if expandedSections.contains(.participants) {
                        expandedSections.remove(.participants)
                    } else {
                        expandedSections.insert(.participants)
                    }
                }
            }) {
                HStack {
                    Image(systemName: SummarySection.participants.icon)
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("Participants")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text("(\(summary.participants.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: expandedSections.contains(.participants) ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Participants list
            if expandedSections.contains(.participants) {
                VStack(spacing: 6) {
                    ForEach(summary.participants) { participant in
                        HStack {
                            Circle()
                                .fill(Color.blue.gradient)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(initials(for: participant))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(participant.displayName ?? participant.username)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                if let messageCount = participant.messageCount {
                                    Text("\(messageCount) messages")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Metadata Footer

    private var metadataFooterView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let timePeriod = summary.timePeriodSummary {
                        Label(timePeriod, systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Label("Generated \(timeAgoString)", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let provider = summary.provider {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Label(provider.uppercased(), systemImage: "cpu")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Action Item Detail View

    private func actionItemDetailView(_ actionItem: ThreadSummary.ActionItem) -> some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Priority banner
                    if let priority = actionItem.priority {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(priorityColor(for: priority))

                            Text("\(priority.rawValue.capitalized) Priority")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()
                        }
                        .padding(12)
                        .background(priorityColor(for: priority).opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(actionItem.description)
                            .font(.body)
                            .foregroundColor(.primary)
                    }

                    Divider()

                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        if let assignee = actionItem.assignee {
                            detailRow(label: "Assignee", value: assignee, icon: "person.fill")
                        }

                        if let dueDate = actionItem.dueDate {
                            detailRow(
                                label: "Due Date",
                                value: formatDate(dueDate),
                                icon: "calendar",
                                valueColor: actionItem.isOverdue ? .red : .primary
                            )

                            if actionItem.isOverdue {
                                Text("Overdue")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                            } else if actionItem.isDueSoon {
                                Text("Due Soon")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }

                        if let status = actionItem.status {
                            HStack {
                                Label("Status", systemImage: "flag.fill")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Spacer()

                                statusBadge(status)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Action Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        selectedActionItem = nil
                    }
                }
            }
        }
    }

    private func detailRow(label: String, value: String, icon: String, valueColor: Color = .primary) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
    }

    // MARK: - Helper Methods

    private func priorityColor(for priority: ThreadSummary.ActionItem.Priority?) -> Color {
        switch priority {
        case .urgent: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low, .none: return .gray
        }
    }

    private func initials(for participant: ThreadSummary.Participant) -> String {
        let name = participant.displayName ?? participant.username
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var timeAgoString: String {
        let age = summary.age
        if age < 60 {
            return "just now"
        } else if age < 3600 {
            let minutes = Int(age / 60)
            return "\(minutes)m ago"
        } else if age < 86400 {
            let hours = Int(age / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(age / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Preview

#Preview("Standard Summary") {
    ScrollView {
        ThreadSummaryView(
            summary: ThreadSummary(
                threadId: UUID(),
                summary: "Team discussed Q4 roadmap priorities, focusing on mobile app improvements and API performance optimizations. Key decisions were made regarding infrastructure upgrades.",
                keyPoints: [
                    "Mobile app performance improvements are top priority",
                    "API response times need optimization",
                    "Infrastructure upgrade scheduled for November",
                    "New team member starting next week"
                ],
                decisions: [
                    "Approved $50k budget for infrastructure upgrades",
                    "Decided to use Kubernetes for container orchestration",
                    "Selected candidate for senior engineer position"
                ],
                actionItems: [
                    ThreadSummary.ActionItem(
                        id: UUID(),
                        description: "Prepare Q4 roadmap presentation",
                        assignee: "John Doe",
                        dueDate: Date().addingTimeInterval(86400 * 2),
                        priority: .high,
                        status: .inProgress
                    ),
                    ThreadSummary.ActionItem(
                        id: UUID(),
                        description: "Review API performance metrics",
                        assignee: "Jane Smith",
                        dueDate: Date().addingTimeInterval(86400 * 5),
                        priority: .medium,
                        status: .pending
                    ),
                    ThreadSummary.ActionItem(
                        id: UUID(),
                        description: "Schedule infrastructure upgrade",
                        assignee: "DevOps Team",
                        dueDate: Date().addingTimeInterval(-86400),
                        priority: .urgent,
                        status: .pending
                    )
                ],
                participants: [
                    ThreadSummary.Participant(
                        id: UUID(),
                        username: "john.doe",
                        displayName: "John Doe",
                        messageCount: 24
                    ),
                    ThreadSummary.Participant(
                        id: UUID(),
                        username: "jane.smith",
                        displayName: "Jane Smith",
                        messageCount: 18
                    )
                ],
                messageCount: 42,
                provider: "claude-3.5-sonnet"
            ),
            onRegenerateTapped: {},
            onExportTapped: {},
            onDismissTapped: {}
        )
        .padding(.vertical)
    }
}

#Preview("Collapsed Summary") {
    ThreadSummaryView(
        summary: ThreadSummary(
            threadId: UUID(),
            summary: "Brief discussion about project status.",
            keyPoints: ["Status update", "Timeline review"],
            messageCount: 12
        )
    )
}
