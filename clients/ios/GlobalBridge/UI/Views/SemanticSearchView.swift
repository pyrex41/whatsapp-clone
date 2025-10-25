//
//  SemanticSearchView.swift
//  GlobalBridge
//
//  Semantic search interface for natural language message search
//  Provides real-time search with history, filters, and accessibility
//

import SwiftUI
import Combine

/// Main semantic search view with natural language query support
struct SemanticSearchView: View {
    @StateObject private var viewModel: SemanticSearchViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool

    init(aiService: AIService = .shared) {
        _viewModel = StateObject(wrappedValue: SemanticSearchViewModel(aiService: aiService))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar with natural language hints
                searchBar

                // Filters row (collapsible)
                if viewModel.showFilters {
                    filtersSection
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Divider()

                // Main content area
                ZStack {
                    if viewModel.searchQuery.isEmpty && !viewModel.hasSearchHistory {
                        emptySearchState
                    } else if viewModel.searchQuery.isEmpty && viewModel.hasSearchHistory {
                        searchHistoryView
                    } else if viewModel.isSearching {
                        searchingState
                    } else if let error = viewModel.searchError {
                        errorState(error)
                    } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                        noResultsState
                    } else {
                        SearchResultsView(
                            results: viewModel.searchResults,
                            query: viewModel.searchQuery,
                            onResultTap: { result in
                                viewModel.addToHistory(result)
                                handleResultSelection(result)
                            },
                            onReply: { result in
                                handleReply(to: result)
                            },
                            onCopy: { result in
                                copyToClipboard(result.content)
                            },
                            onTranslate: { result in
                                handleTranslate(result)
                            }
                        )
                    }
                }
            }
            .navigationTitle("Search Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.showFilters.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .accessibilityLabel(viewModel.showFilters ? "Hide filters" : "Show filters")
                    }
                }
            }
        }
        .onAppear {
            isSearchFieldFocused = true
            viewModel.loadSearchHistory()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Semantic Search")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)

                TextField("Find messages about dinner plans...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: viewModel.searchQuery) { oldValue, newValue in
                        viewModel.handleSearchQueryChange(newValue)
                    }
                    .onSubmit {
                        Task {
                            await viewModel.performSearch()
                            announceSearchResults()
                        }
                    }
                    .accessibilityLabel("Search query")
                    .accessibilityHint("Enter natural language query to search messages")

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.clearSearch()
                        isSearchFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Natural language examples
            if viewModel.searchQuery.isEmpty && !viewModel.hasSearchHistory {
                exampleQueriesView
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Example Queries

    private var exampleQueriesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try searching for:")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.exampleQueries, id: \.self) { query in
                        Button {
                            viewModel.searchQuery = query
                            Task {
                                await viewModel.performSearch()
                            }
                        } label: {
                            Text(query)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray6))
                                .foregroundColor(.primary)
                                .cornerRadius(16)
                        }
                        .accessibilityLabel("Search for: \(query)")
                    }
                }
            }
        }
    }

    // MARK: - Filters Section

    private var filtersSection: some View {
        VStack(spacing: 12) {
            // Thread filter
            if !viewModel.availableThreads.isEmpty {
                HStack {
                    Text("Thread:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Thread", selection: $viewModel.selectedThreadId) {
                        Text("All Threads").tag(nil as String?)
                        ForEach(viewModel.availableThreads, id: \.id) { thread in
                            Text(thread.title ?? "Unknown").tag(thread.id.uuidString as String?)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Filter by thread")
                }
            }

            // Date range filter
            HStack {
                Text("Date Range:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Date Range", selection: $viewModel.dateRange) {
                    Text("Any Time").tag(DateRange.anytime)
                    Text("Today").tag(DateRange.today)
                    Text("Last Week").tag(DateRange.lastWeek)
                    Text("Last Month").tag(DateRange.lastMonth)
                    Text("Custom").tag(DateRange.custom)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Filter by date range")
            }

            // Custom date picker
            if viewModel.dateRange == .custom {
                HStack {
                    DatePicker("From", selection: $viewModel.customStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("Start date")

                    Text("to")
                        .foregroundColor(.secondary)

                    DatePicker("To", selection: $viewModel.customEndDate, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("End date")
                }
            }

            // Result limit and recency bias
            HStack {
                Text("Max Results:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Limit", selection: $viewModel.resultLimit) {
                    Text("10").tag(10)
                    Text("25").tag(25)
                    Text("50").tag(50)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Maximum results")

                Spacer()

                Toggle("Recent First", isOn: $viewModel.recencyBias)
                    .font(.subheadline)
                    .accessibilityLabel("Prioritize recent messages")
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    // MARK: - Search History

    private var searchHistoryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recent Searches")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top)

                    Spacer()

                    Button("Clear") {
                        viewModel.clearSearchHistory()
                    }
                    .font(.subheadline)
                    .padding(.horizontal)
                    .padding(.top)
                    .accessibilityLabel("Clear search history")
                }

                ForEach(viewModel.searchHistory, id: \.self) { query in
                    Button {
                        viewModel.searchQuery = query
                        Task {
                            await viewModel.performSearch()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)

                            Text(query)
                                .foregroundColor(.primary)

                            Spacer()

                            Button {
                                viewModel.removeFromHistory(query)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Remove \(query) from history")
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                    .accessibilityLabel("Search for: \(query)")

                    Divider()
                }
            }
        }
    }

    // MARK: - States

    private var emptySearchState: some View {
        VStack(spacing: 24) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Semantic Search")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Search messages using natural language")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureItem(icon: "brain", text: "Natural language queries")
                FeatureItem(icon: "sparkles", text: "Context-aware results")
                FeatureItem(icon: "clock", text: "Search history")
                FeatureItem(icon: "slider.horizontal.3", text: "Advanced filters")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Semantic search ready. Enter a natural language query to find messages.")
    }

    private var searchingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Searching...")
                .font(.headline)
                .foregroundColor(.secondary)

            if !viewModel.searchQuery.isEmpty {
                Text("Finding messages about: \(viewModel.searchQuery)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Searching for: \(viewModel.searchQuery)")
    }

    private func errorState(_ error: AIServiceError) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
                .accessibilityHidden(true)

            Text("Search Failed")
                .font(.headline)

            Text(error.errorDescription ?? "Unknown error")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Try Again") {
                Task {
                    await viewModel.performSearch()
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Retry search")
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search failed: \(error.errorDescription ?? "Unknown error")")
    }

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            Text("No Results Found")
                .font(.headline)

            Text("Try different keywords or adjust filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if !viewModel.searchQuery.isEmpty {
                Button("Clear Search") {
                    viewModel.clearSearch()
                    isSearchFieldFocused = true
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Clear search and try again")
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results found for: \(viewModel.searchQuery)")
    }

    // MARK: - Actions

    private func handleResultSelection(_ result: SearchResult) {
        // TODO: Navigate to message in thread
        print("📍 Navigate to message: \(result.message.id.uuidString) in thread: \(result.message.threadId.uuidString)")
    }

    private func handleReply(to result: SearchResult) {
        // TODO: Open reply compose sheet
        print("💬 Reply to message: \(result.message.id.uuidString)")
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        // TODO: Show toast notification
        announceToVoiceOver("Copied to clipboard")
    }

    private func handleTranslate(_ result: SearchResult) {
        // TODO: Open translation overlay
        print("🌐 Translate message: \(result.message.id.uuidString)")
    }

    private func announceSearchResults() {
        let count = viewModel.searchResults.count
        let announcement = count == 0 ? "No results found" : "\(count) result\(count == 1 ? "" : "s") found"
        announceToVoiceOver(announcement)
    }

    private func announceToVoiceOver(_ announcement: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }
}

// MARK: - Feature Item View

private struct FeatureItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - View Model

@MainActor
class SemanticSearchViewModel: ObservableObject {
    // Published properties
    @Published var searchQuery = ""
    @Published var searchResults: [SearchResult] = []
    @Published var searchHistory: [String] = []
    @Published var isSearching = false
    @Published var searchError: AIServiceError?
    @Published var showFilters = false

    // Filter properties
    @Published var selectedThreadId: String?
    @Published var dateRange: DateRange = .anytime
    @Published var customStartDate = Date().addingTimeInterval(-7 * 24 * 3600)
    @Published var customEndDate = Date()
    @Published var resultLimit = 10
    @Published var recencyBias = true

    // Data
    @Published var availableThreads: [Thread] = []

    // Dependencies
    private let aiService: AIService
    private var searchTask: Task<Void, Never>?
    private let debounceInterval: TimeInterval = 0.5

    var hasSearchHistory: Bool {
        !searchHistory.isEmpty
    }

    let exampleQueries = [
        "dinner plans",
        "meeting notes",
        "shared photos",
        "tomorrow's schedule",
        "project updates"
    ]

    init(aiService: AIService = .shared) {
        self.aiService = aiService
        loadAvailableThreads()
    }

    // MARK: - Search

    func handleSearchQueryChange(_ newValue: String) {
        // Cancel previous search task
        searchTask?.cancel()

        // Clear results and error immediately
        if newValue.isEmpty {
            searchResults = []
            searchError = nil
            return
        }

        // Debounce search
        searchTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))

            if !Task.isCancelled {
                await performSearch()
            }
        }
    }

    func performSearch() async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        searchError = nil

        do {
            let results = try await aiService.searchSemantic(
                query: searchQuery,
                threadId: selectedThreadId,
                limit: resultLimit,
                recencyBias: recencyBias
            )

            // Filter by date range if needed
            let filteredResults = filterByDateRange(results)

            searchResults = filteredResults

            // Add to history on successful search
            if !searchQuery.isEmpty && !searchHistory.contains(searchQuery) {
                searchHistory.insert(searchQuery, at: 0)
                if searchHistory.count > 20 {
                    searchHistory = Array(searchHistory.prefix(20))
                }
                saveSearchHistory()
            }
        } catch let error as AIServiceError {
            searchError = error
            searchResults = []
        } catch {
            searchError = .unknown(error)
            searchResults = []
        }

        isSearching = false
    }

    private func filterByDateRange(_ results: [SearchResult]) -> [SearchResult] {
        switch dateRange {
        case .anytime:
            return results
        case .today:
            let startOfDay = Calendar.current.startOfDay(for: Date())
            return results.filter { result in
                return result.message.timestamp >= startOfDay
            }
        case .lastWeek:
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
            return results.filter { result in
                return result.message.timestamp >= weekAgo
            }
        case .lastMonth:
            let monthAgo = Date().addingTimeInterval(-30 * 24 * 3600)
            return results.filter { result in
                return result.message.timestamp >= monthAgo
            }
        case .custom:
            let startOfStartDay = Calendar.current.startOfDay(for: customStartDate)
            let endOfEndDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: customEndDate) ?? customEndDate
            return results.filter { result in
                let date = result.message.timestamp
                return date >= startOfStartDay && date <= endOfEndDay
            }
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchError = nil
        searchTask?.cancel()
    }

    // MARK: - History Management

    func loadSearchHistory() {
        if let history = UserDefaults.standard.stringArray(forKey: "semanticSearchHistory") {
            searchHistory = history
        }
    }

    private func saveSearchHistory() {
        UserDefaults.standard.set(searchHistory, forKey: "semanticSearchHistory")
    }

    func clearSearchHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: "semanticSearchHistory")
    }

    func removeFromHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        saveSearchHistory()
    }

    func addToHistory(_ result: SearchResult) {
        // Track clicked results for analytics
        // TODO: Implement analytics tracking
    }

    // MARK: - Thread Management

    private func loadAvailableThreads() {
        // TODO: Load from ThreadService
        // For now, use empty array
        availableThreads = []
    }
}

// MARK: - Date Range Enum

enum DateRange: String, CaseIterable {
    case anytime = "Any Time"
    case today = "Today"
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case custom = "Custom"
}

// MARK: - Preview

#Preview("Empty State") {
    SemanticSearchView()
}

#Preview("With Results") {
    let view = SemanticSearchView()
    return view
}
