//
//  SearchResultsView.swift
//  GlobalBridge
//
//  Displays semantic search results grouped by thread and date
//  Shows relevance scores, message previews, and quick actions
//

import SwiftUI

/// Displays search results with grouping, highlighting, and actions
struct SearchResultsView: View {
    let results: [SearchResult]
    let query: String
    let onResultTap: (SearchResult) -> Void
    let onReply: (SearchResult) -> Void
    let onCopy: (SearchResult) -> Void
    let onTranslate: (SearchResult) -> Void

    @State private var groupingMode: GroupingMode = .thread
    @State private var selectedResult: SearchResult?
    @State private var showingActions = false

    var body: some View {
        VStack(spacing: 0) {
            // Results header with grouping toggle
            resultsHeader

            Divider()

            // Results list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if groupingMode == .thread {
                        threadGroupedResults
                    } else {
                        dateGroupedResults
                    }
                }
            }
        }
        .confirmationDialog("Actions", isPresented: $showingActions, presenting: selectedResult) { result in
            Button("Reply") {
                onReply(result)
            }

            Button("Copy") {
                onCopy(result)
            }

            Button("Translate") {
                onTranslate(result)
            }

            Button("Go to Message") {
                onResultTap(result)
            }

            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search results")
    }

    // MARK: - Results Header

    private var resultsHeader: some View {
        HStack {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            Picker("Group By", selection: $groupingMode) {
                Label("Thread", systemImage: "bubble.left.and.bubble.right").tag(GroupingMode.thread)
                Label("Date", systemImage: "calendar").tag(GroupingMode.date)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .accessibilityLabel("Group results by")
        }
        .padding()
        .background(Color(.systemGray6))
    }

    // MARK: - Thread Grouped Results

    private var threadGroupedResults: some View {
        ForEach(groupedByThread, id: \.key) { group in
            Section {
                ForEach(group.value, id: \.messageId) { result in
                    SearchResultRow(
                        result: result,
                        query: query,
                        onTap: { onResultTap(result) },
                        onLongPress: {
                            selectedResult = result
                            showingActions = true
                        }
                    )

                    if result.messageId != group.value.last?.messageId {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.blue)
                        .accessibilityHidden(true)

                    Text(group.key)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(group.value.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Thread: \(group.key), \(group.value.count) result\(group.value.count == 1 ? "" : "s")")
        }
    }

    // MARK: - Date Grouped Results

    private var dateGroupedResults: some View {
        ForEach(groupedByDate, id: \.key) { group in
            Section {
                ForEach(group.value, id: \.messageId) { result in
                    SearchResultRow(
                        result: result,
                        query: query,
                        onTap: { onResultTap(result) },
                        onLongPress: {
                            selectedResult = result
                            showingActions = true
                        }
                    )

                    if result.messageId != group.value.last?.messageId {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)
                        .accessibilityHidden(true)

                    Text(group.key)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(group.value.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Date: \(group.key), \(group.value.count) result\(group.value.count == 1 ? "" : "s")")
        }
    }

    // MARK: - Grouping Logic

    private var groupedByThread: [(key: String, value: [SearchResult])] {
        let grouped = Dictionary(grouping: results) { result in
            result.threadId ?? "Unknown Thread"
        }
        return grouped.sorted { $0.key < $1.key }
    }

    private var groupedByDate: [(key: String, value: [SearchResult])] {
        let dateFormatter = ISO8601DateFormatter()

        let grouped = Dictionary(grouping: results) { result in
            guard let timestamp = result.timestamp,
                  let date = dateFormatter.date(from: timestamp) else {
                return "Unknown Date"
            }
            return formatDateGroup(date)
        }

        return grouped.sorted { key1, key2 in
            // Sort with most recent first
            let order = ["Today", "Yesterday", "This Week", "Last Week", "This Month", "Earlier", "Unknown Date"]
            let index1 = order.firstIndex(of: key1.key) ?? order.count
            let index2 = order.firstIndex(of: key2.key) ?? order.count
            return index1 < index2
        }
    }

    private func formatDateGroup(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(date, equalTo: Date().addingTimeInterval(-7 * 24 * 3600), toGranularity: .weekOfYear) {
            return "Last Week"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else {
            return "Earlier"
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult
    let query: String
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Relevance indicator
                RelevanceIndicator(score: result.relevanceScore)

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    // Message content with highlighting
                    HighlightedText(text: result.content, query: query)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(3)

                    // Metadata
                    HStack(spacing: 12) {
                        // Thread indicator
                        if let threadId = result.threadId {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.caption2)
                                Text(threadId.prefix(8))
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }

                        // Timestamp
                        if let timestamp = result.timestamp {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                Text(formatTimestamp(timestamp))
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Relevance score
                        Text(String(format: "%.0f%%", result.relevanceScore * 100))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(relevanceColor(result.relevanceScore))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(relevanceColor(result.relevanceScore).opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress()
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view message, long press for actions")
    }

    private var accessibilityLabel: String {
        var label = "Message with \(Int(result.relevanceScore * 100))% relevance: \(result.content)"

        if let timestamp = result.timestamp {
            label += ", sent \(formatTimestamp(timestamp))"
        }

        if let threadId = result.threadId {
            label += ", in thread \(threadId.prefix(8))"
        }

        return label
    }

    private func formatTimestamp(_ timestamp: String) -> String {
        let dateFormatter = ISO8601DateFormatter()
        guard let date = dateFormatter.date(from: timestamp) else {
            return timestamp
        }

        let interval = Date().timeIntervalSince(date)
        let calendar = Calendar.current

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if interval < 604800 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func relevanceColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .blue
        } else if score >= 0.4 {
            return .orange
        } else {
            return .secondary
        }
    }
}

// MARK: - Relevance Indicator

struct RelevanceIndicator: View {
    let score: Double

    private var barCount: Int {
        if score >= 0.8 {
            return 5
        } else if score >= 0.6 {
            return 4
        } else if score >= 0.4 {
            return 3
        } else if score >= 0.2 {
            return 2
        } else {
            return 1
        }
    }

    private var color: Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .blue
        } else if score >= 0.4 {
            return .orange
        } else {
            return .secondary
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < barCount ? color : Color(.systemGray5))
                    .frame(width: 4, height: 6)
            }
        }
        .frame(width: 12, height: 40)
        .accessibilityLabel("Relevance: \(Int(score * 100))%")
        .accessibilityHidden(true) // Already announced in parent
    }
}

// MARK: - Highlighted Text

struct HighlightedText: View {
    let text: String
    let query: String

    var body: some View {
        // Split text and highlight query matches
        let components = highlightedComponents()

        // Use Text concatenation for proper formatting
        components.reduce(Text("")) { result, component in
            result + Text(component.text)
                .foregroundColor(component.isHighlighted ? .primary : .primary)
                .fontWeight(component.isHighlighted ? .semibold : .regular)
                .background(component.isHighlighted ? Color.yellow.opacity(0.3) : Color.clear)
        }
    }

    private func highlightedComponents() -> [(text: String, isHighlighted: Bool)] {
        guard !query.isEmpty else {
            return [(text, false)]
        }

        var components: [(String, Bool)] = []
        var remainingText = text

        // Split query into words
        let queryWords = query.lowercased().split(separator: " ").map { String($0) }

        for word in queryWords {
            var searchRange = remainingText.startIndex..<remainingText.endIndex

            while let range = remainingText.range(of: word, options: .caseInsensitive, range: searchRange) {
                // Add non-highlighted part before match
                if range.lowerBound > searchRange.lowerBound {
                    let beforeMatch = String(remainingText[searchRange.lowerBound..<range.lowerBound])
                    if !beforeMatch.isEmpty {
                        components.append((beforeMatch, false))
                    }
                }

                // Add highlighted match
                let match = String(remainingText[range])
                components.append((match, true))

                // Update search range
                searchRange = range.upperBound..<remainingText.endIndex
            }

            // Add remaining text
            if searchRange.lowerBound < remainingText.endIndex {
                let remaining = String(remainingText[searchRange.lowerBound...])
                components.append((remaining, false))
            }
        }

        // If no matches found, return original text
        if components.isEmpty {
            components.append((text, false))
        }

        return components
    }
}

// MARK: - Grouping Mode

enum GroupingMode {
    case thread
    case date
}

// MARK: - Preview

#Preview("With Results") {
    let mockResults = [
        SearchResult(
            messageId: "msg1",
            content: "Hey, let's meet for dinner tomorrow at 7pm. How does that sound?",
            relevanceScore: 0.92,
            threadId: "thread1",
            timestamp: ISO8601DateFormatter().string(from: Date())
        ),
        SearchResult(
            messageId: "msg2",
            content: "I'll bring the dinner supplies we talked about.",
            relevanceScore: 0.85,
            threadId: "thread1",
            timestamp: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        ),
        SearchResult(
            messageId: "msg3",
            content: "What time should we plan for dinner?",
            relevanceScore: 0.78,
            threadId: "thread2",
            timestamp: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        )
    ]

    return SearchResultsView(
        results: mockResults,
        query: "dinner",
        onResultTap: { _ in },
        onReply: { _ in },
        onCopy: { _ in },
        onTranslate: { _ in }
    )
}

#Preview("Empty") {
    SearchResultsView(
        results: [],
        query: "test",
        onResultTap: { _ in },
        onReply: { _ in },
        onCopy: { _ in },
        onTranslate: { _ in }
    )
}
