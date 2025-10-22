//
//  ThreadCreationSheet.swift
//  GlobalBridge
//

import SwiftUI

struct ThreadCreationSheet: View {
    @ObservedObject var store: Store<AppState, AppAction>
    @State private var searchQuery = ""
    @State private var contacts: [Contact] = []
    @State private var searchResults: [Contact.ContactUser] = []
    @State private var selectedParticipants: Set<String> = []
    @State private var isSearching = false

    private var threadsState: ThreadsState {
        store.state.threads
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Thread Details")) {
                    TextField("Thread title", text: titleBinding)
                        .textInputAutocapitalization(.words)
                }
                
                Section(header: Text("Add Participants")) {
                    TextField("Search contacts or enter email", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .onChange(of: searchQuery) { _, newValue in
                            searchContactsOrEmail(newValue)
                        }
                    
                    if !selectedParticipants.isEmpty {
                        Text("Selected: \(selectedParticipants.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Show matching contacts
                if !contacts.isEmpty {
                    Section(header: Text("Contacts")) {
                        ForEach(contacts, id: \.id) { contact in
                            ContactSelectionRow(
                                contact: contact,
                                isSelected: selectedParticipants.contains(contact.contactUserId),
                                onToggle: {
                                    toggleSelection(contact.contactUserId)
                                }
                            )
                        }
                    }
                }
                
                // Show email search results for non-contacts
                if !searchResults.isEmpty {
                    Section(header: Text("Search Results")) {
                        ForEach(searchResults, id: \.id) { user in
                            UserSelectionRow(
                                user: user,
                                isSelected: selectedParticipants.contains(user.id),
                                onToggle: {
                                    toggleSelection(user.id)
                                }
                            )
                        }
                    }
                }
                
                if isSearching {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("New Thread")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.send(.toggleCreationSheet(false))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createThread()
                    }
                    .disabled(threadsState.creationTitle.trimmingCharacters(in: .whitespaces).isEmpty || 
                             selectedParticipants.isEmpty ||
                             threadsState.isCreatingThread)
                }
            }
            .overlay {
                if threadsState.isCreatingThread {
                    ProgressView("Creating thread…")
                }
            }
        }
    }

    private var titleBinding: Binding<String> {
        store.binding(
            get: { $0.threads.creationTitle },
            send: AppAction.creationTitleChanged
        )
    }
    
    private func searchContactsOrEmail(_ query: String) {
        guard !query.isEmpty else {
            contacts = []
            searchResults = []
            return
        }
        
        isSearching = true
        
        Task {
            defer { isSearching = false }
            
            do {
                // TODO: Wire up ContactManager when available
                // For now, stub implementation
                contacts = []
                
                // If query contains @, search for users by email
                if query.contains("@") {
                    searchResults = []
                    // TODO: searchResults = try await contactManager.searchUsersByEmail(query: query)
                } else {
                    searchResults = []
                }
            } catch {
                print("❌ [SEARCH] Failed to search: \(error)")
                contacts = []
                searchResults = []
            }
        }
    }
    
    private func toggleSelection(_ userId: String) {
        if selectedParticipants.contains(userId) {
            selectedParticipants.remove(userId)
        } else {
            selectedParticipants.insert(userId)
        }
    }
    
    private func createThread() {
        // TODO: Update AppAction to include selectedParticipants
        // For now, use existing createThread action
        store.send(.createThread)
    }
}

// MARK: - Helper Views

private struct ContactSelectionRow: View {
    let contact: Contact
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading) {
                    Text(contact.displayName)
                        .font(.body)
                    if let email = contact.user.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct UserSelectionRow: View {
    let user: Contact.ContactUser
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading) {
                    if let displayName = user.displayName {
                        Text(displayName)
                            .font(.body)
                    }
                    Text(user.email)
                        .font(.caption)
                        .foregroundColor(user.displayName != nil ? .secondary : .primary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
