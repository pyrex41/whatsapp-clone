//
//  ThreadsListScreen.swift
//  GlobalBridge
//

import SwiftUI

struct ThreadsListScreen: View {
    @ObservedObject var store: Store<AppState, AppAction>
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    private var threadsState: ThreadsState { store.state.threads }
    private var connectionState: ConnectionState { store.state.connectionState }

    var body: some View {
        List {
            Section {
                if threadsState.isLoading && threadsState.items.isEmpty {
                    ProgressView("Loading threads…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if threadsState.items.isEmpty && !threadsState.isLoading {
                    emptyStateView
                } else {
                    ForEach(threadsState.filteredItems, id: \.id) { thread in
                        ThreadRow(
                            thread: thread,
                            isSelected: thread.id == threadsState.selectedThreadID,
                            currentUserId: store.state.user.id,
                            userCache: store.state.userCache
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            print("👆 [UI] Thread tapped: \(thread.id) - \(thread.title ?? "Untitled")")
                            print("👆 [UI] Currently selected: \(threadsState.selectedThreadID?.uuidString ?? "none")")
                            print("👆 [UI] Is same thread: \(thread.id == threadsState.selectedThreadID)")
                            print("👆 [UI] Sending .threadSelected action...")
                            store.send(.threadSelected(thread.id))
                            print("👆 [UI] .threadSelected action sent")
                        }
                        .animation(.easeInOut(duration: 0.15), value: thread.id == threadsState.selectedThreadID)
                    }
                }
            }
        }
        .overlay {
            if let message = threadsState.errorMessage, !connectionState.isConnected {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Connection Error")
                        .font(.headline)
                    
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Retry") {
                        store.send(.onAppear)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .navigationTitle("Threads")
        .searchable(
            text: store.binding(
                get: { $0.threads.searchQuery },
                send: AppAction.setSearchQuery
            ),
            prompt: "Search conversations"
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ConnectionStatusIndicator(state: connectionState)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.send(.toggleCreationSheet(true))
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New thread")
            }
            #if DEBUG
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showDebugMenu = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .accessibilityLabel("Debug Menu")
            }
            #endif
        }
        .sheet(isPresented: creationSheetBinding) {
            NewConversationView(store: store)
        }
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            DebugMenuView()
        }
        #endif
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No conversations yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the compose button to start a conversation")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                store.send(.toggleCreationSheet(true))
            } label: {
                Label("New Conversation", systemImage: "square.and.pencil")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var creationSheetBinding: Binding<Bool> {
        Binding(
            get: { store.state.threads.showCreationSheet },
            set: { isPresented in
                store.send(.toggleCreationSheet(isPresented))
            }
        )
    }
}

struct ThreadRow: View {
    let thread: Thread
    let isSelected: Bool
    let currentUserId: String
    let userCache: [String: CachedUserInfo]

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(initials(for: thread))
                    .font(.headline)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.displayName(currentUserId: currentUserId, userCache: userCache))
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if let lastMessageAt = thread.lastMessageAt {
                        Text(TimestampFormatter.string(for: lastMessageAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text(thread.threadType.rawValue.capitalized)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if thread.unreadCount > 0 {
                Spacer()
                Text("\(thread.unreadCount)")
                    .font(.caption.bold())
                    .padding(6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }

    private func initials(for thread: Thread) -> String {
        // Prefer the resolved display name (DM: other participant; Group: title)
        let name = thread.displayName(currentUserId: currentUserId, userCache: userCache)
        let parts = name.split(whereSeparator: { $0.isWhitespace })
        if parts.count >= 2,
           let first = parts.first?.first,
           let second = parts.dropFirst().first?.first {
            return String([first, second]).uppercased()
        }
        // Fallback to first two visible characters
        return String(name.prefix(2)).uppercased()
    }
}

struct ConnectionStatusIndicator: View {
    let state: ConnectionState
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
            
            if case .connecting = state {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityLabel(state.displayText)
    }
}

struct ThreadsListCompactView: View {
    @ObservedObject var store: Store<AppState, AppAction>
    #if DEBUG
    @State private var showDebugMenu = false
    #endif

    private var threadsState: ThreadsState { store.state.threads }
    private var connectionState: ConnectionState { store.state.connectionState }

    var body: some View {
        List {
            Section {
                if threadsState.isLoading && threadsState.items.isEmpty {
                    ProgressView("Loading threads…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if threadsState.items.isEmpty && !threadsState.isLoading {
                    emptyStateView
                } else {
                    ForEach(threadsState.filteredItems, id: \.id) { thread in
                        NavigationLink(value: thread.id) {
                        ThreadRow(
                            thread: thread,
                            isSelected: thread.id == threadsState.selectedThreadID,
                            currentUserId: store.state.user.id,
                            userCache: store.state.userCache
                        )
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
        }
        .overlay {
            if let message = threadsState.errorMessage, !connectionState.isConnected {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    
                    Text("Connection Error")
                        .font(.headline)
                    
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Retry") {
                        store.send(.onAppear)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .navigationTitle("Threads")
        .searchable(
            text: store.binding(
                get: { $0.threads.searchQuery },
                send: AppAction.setSearchQuery
            ),
            prompt: "Search conversations"
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ConnectionStatusIndicator(state: connectionState)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.send(.toggleCreationSheet(true))
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New thread")
            }
            #if DEBUG
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showDebugMenu = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .accessibilityLabel("Debug Menu")
            }
            #endif
        }
        .sheet(isPresented: creationSheetBinding) {
            NewConversationView(store: store)
        }
        #if DEBUG
        .sheet(isPresented: $showDebugMenu) {
            DebugMenuView()
        }
        #endif
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "message.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No conversations yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the compose button to start a conversation")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                store.send(.toggleCreationSheet(true))
            } label: {
                Label("New Conversation", systemImage: "square.and.pencil")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var creationSheetBinding: Binding<Bool> {
        Binding(
            get: { store.state.threads.showCreationSheet },
            set: { isPresented in
                store.send(.toggleCreationSheet(isPresented))
            }
        )
    }
}
