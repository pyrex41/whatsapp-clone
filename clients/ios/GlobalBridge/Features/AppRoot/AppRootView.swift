//
//  AppRootView.swift
//  GlobalBridge
//

import SwiftUI

struct AppRootView: View {
    @ObservedObject var store: Store<AppState, AppAction>
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .compact {
            NavigationStack {
                ThreadsListCompactView(store: store)
                    .navigationDestination(for: Thread.ID.self) { threadID in
                        ChatScreen(store: store)
                            .onAppear {
                                store.send(.threadSelected(threadID))
                            }
                    }
            }
            .onAppear {
                store.send(.onAppear)
            }
        } else {
            NavigationSplitView {
                ThreadsListScreen(store: store)
            } detail: {
                ChatScreen(store: store)
            }
            .onAppear {
                store.send(.onAppear)
            }
        }
    }
}

#Preview {
    AppRootView(
        store: Store(
            initialState: AppState(),
            reducer: appReducer,
            environment: .preview
        )
    )
}
