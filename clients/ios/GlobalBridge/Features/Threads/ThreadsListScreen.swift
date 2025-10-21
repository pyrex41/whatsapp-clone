//
//  ThreadsListScreen.swift
//  GlobalBridge
//

import SwiftUI

struct ThreadsListScreen: View {
    @ObservedObject var store: Store<AppState, AppAction>

    private var threadsState: ThreadsState { store.state.threads }

    var body: some View {
        List {
            Section {
                if threadsState.isLoading && threadsState.items.isEmpty {
                    ProgressView("Loading threads…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(threadsState.filteredItems, id: \.id) { thread in
                        ThreadRow(
                            thread: thread,
                            isSelected: thread.id == threadsState.selectedThreadID
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            print("👆 [UI] Thread tapped: \(thread.id) - \(thread.title ?? "Untitled")")
                            print("👆 [UI] Sending .threadSelected action...")
                            store.send(.threadSelected(thread.id))
                            print("👆 [UI] .threadSelected action sent")
                        }
                    }
                }
            }
        }
        .overlay {
            if let message = threadsState.errorMessage {
                VStack(spacing: 12) {
                    Text("Unable to load threads")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.send(.toggleCreationSheet(true))
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New thread")
            }
        }
        .sheet(isPresented: creationSheetBinding) {
            ThreadCreationSheet(store: store)
        }
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
                    Text(thread.title ?? "Untitled")
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
        thread.title?
            .split(separator: " ")
            .prefix(2)
            .map { $0.first.map(String.init) ?? "" }
            .joined()
            .uppercased() ?? "GB"
    }
}

struct ThreadsListCompactView: View {
    @ObservedObject var store: Store<AppState, AppAction>

    private var threadsState: ThreadsState { store.state.threads }

    var body: some View {
        List {
            Section {
                if threadsState.isLoading && threadsState.items.isEmpty {
                    ProgressView("Loading threads…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(threadsState.filteredItems, id: \.id) { thread in
                        NavigationLink(value: thread.id) {
                            ThreadRow(
                                thread: thread,
                                isSelected: thread.id == threadsState.selectedThreadID
                            )
                        }
                    }
                }
            }
        }
        .overlay {
            if let message = threadsState.errorMessage {
                VStack(spacing: 12) {
                    Text("Unable to load threads")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.send(.toggleCreationSheet(true))
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New thread")
            }
        }
        .sheet(isPresented: creationSheetBinding) {
            ThreadCreationSheet(store: store)
        }
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
