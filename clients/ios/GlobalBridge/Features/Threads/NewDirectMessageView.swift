//
//  NewDirectMessageView.swift
//  GlobalBridge
//
//  View for creating a new direct message
//

import SwiftUI

/// View for searching and selecting a user for DM
struct NewDirectMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store<AppState, AppAction>
    
    @State private var searchQuery = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search by email or username", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: searchQuery) { _, newValue in
                            if newValue.count >= 2 {
                                performSearch(query: newValue)
                            } else {
                                searchResults = []
                            }
                        }
                    
                    if !searchQuery.isEmpty {
                        Button(action: { searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                // Results
                if isSearching {
                    ProgressView()
                        .padding()
                } else if let error = searchError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if searchQuery.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Search for someone to message")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No users found")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(searchResults) { user in
                        Button(action: { createDM(with: user) }) {
                            HStack(spacing: 12) {
                                // Avatar
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white)
                                    )
                                
                                // User info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.displayName ?? user.username)
                                        .font(.headline)
                                    
                                    if let email = user.email {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Online indicator
                                if user.isOnline {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func performSearch(query: String) {
        // Cancel previous search task
        searchTask?.cancel()
        
        isSearching = true
        searchError = nil
        
        searchTask = Task {
            do {
                // Small delay to debounce rapid typing
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                
                guard !Task.isCancelled else { return }
                
                // Call the realtime client directly via the environment
                // This is a workaround since we don't have reactive state updates yet
                let environment = AppEnvironment.live
                let results = try await environment.realtime.searchUsers(query)
                
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    searchError = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }
    
    private func createDM(with user: UserSearchResult) {
        // Send create DM request
        store.send(.createDirectMessage(userId: user.id))
        dismiss()
    }
}

#Preview {
    NewDirectMessageView(
        store: Store(
            initialState: AppState(),
            reducer: appReducer,
            environment: .preview
        )
    )
}

