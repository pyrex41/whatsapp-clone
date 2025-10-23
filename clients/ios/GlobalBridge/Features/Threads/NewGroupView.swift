//
//  NewGroupView.swift
//  GlobalBridge
//
//  View for creating a new group conversation
//

import SwiftUI

/// View for creating a new group with multiple participants
struct NewGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store<AppState, AppAction>
    
    @State private var groupName = ""
    @State private var searchQuery = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var selectedUsers: Set<String> = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Group name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter group name", text: $groupName)
                        .textFieldStyle(.roundedBorder)
                }
                .padding()
                .background(Color(.systemBackground))
                
                Divider()
                
                // Selected participants
                if !selectedUsers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(selectedUsers), id: \.self) { userId in
                                if let user = searchResults.first(where: { $0.id == userId }) {
                                    SelectedUserChip(user: user) {
                                        selectedUsers.remove(userId)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 80)
                    .background(Color(.systemGray6))
                    
                    Divider()
                }
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search users to add", text: $searchQuery)
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
                
                // Results
                if isSearching {
                    ProgressView()
                        .padding()
                    Spacer()
                } else if searchQuery.isEmpty && selectedUsers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Search and add people to your group")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else if searchResults.isEmpty && !searchQuery.isEmpty {
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
                        Button(action: { toggleUser(user) }) {
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
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.white)
                                            .font(.title3)
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
                                
                                // Selection indicator
                                if selectedUsers.contains(user.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title2)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                        .font(.title2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGroup()
                    }
                    .disabled(groupName.isEmpty || selectedUsers.count < 2)
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
    
    private func toggleUser(_ user: UserSearchResult) {
        if selectedUsers.contains(user.id) {
            selectedUsers.remove(user.id)
        } else {
            selectedUsers.insert(user.id)
        }
    }
    
    private func createGroup() {
        let participantIds = Array(selectedUsers)
        store.send(.createGroupThread(
            title: groupName,
            participantIds: participantIds
        ))
        dismiss()
    }
}

/// Chip view for selected user
struct SelectedUserChip: View {
    let user: UserSearchResult
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
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
                            .font(.title3)
                    )
                
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white))
                }
                .offset(x: 5, y: -5)
            }
            
            Text(user.displayName ?? user.username)
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
    }
}

#Preview {
    NewGroupView(
        store: Store(
            initialState: AppState(),
            reducer: appReducer,
            environment: .preview
        )
    )
}

