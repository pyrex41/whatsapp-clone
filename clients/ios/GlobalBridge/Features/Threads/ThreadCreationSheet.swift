//
//  ThreadCreationSheet.swift
//  GlobalBridge
//

import SwiftUI

struct ThreadCreationSheet: View {
    @ObservedObject var store: Store<AppState, AppAction>

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
                        store.send(.createThread)
                    }
                    .disabled(threadsState.creationTitle.trimmingCharacters(in: .whitespaces).isEmpty || threadsState.isCreatingThread)
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
}
