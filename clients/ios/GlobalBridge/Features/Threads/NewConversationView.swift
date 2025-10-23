//
//  NewConversationView.swift
//  GlobalBridge
//
//  View for creating new conversations (DM or Group)
//

import SwiftUI

/// Main view for creating a new conversation
struct NewConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store<AppState, AppAction>
    @State private var showingDMSearch = false
    @State private var showingGroupCreation = false
    
    var body: some View {
        NavigationView {
            List {
                Button(action: { showingDMSearch = true }) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading) {
                            Text("New Direct Message")
                                .font(.headline)
                            Text("Start a conversation with someone")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Button(action: { showingGroupCreation = true }) {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading) {
                            Text("New Group")
                                .font(.headline)
                            Text("Create a group conversation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingDMSearch) {
                NewDirectMessageView(store: store)
            }
            .sheet(isPresented: $showingGroupCreation) {
                NewGroupView(store: store)
            }
        }
    }
}

#Preview {
    NewConversationView(
        store: Store(
            initialState: AppState(),
            reducer: appReducer,
            environment: .preview
        )
    )
}

