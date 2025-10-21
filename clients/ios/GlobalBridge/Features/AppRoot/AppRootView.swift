//
//  AppRootView.swift
//  GlobalBridge
//

import SwiftUI
import Combine

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
                                print("🎬 [UI] ChatScreen appeared for thread: \(threadID)")
                                print("🎬 [UI] Sending .threadSelected action...")
                                store.send(.threadSelected(threadID))
                                print("🎬 [UI] .threadSelected action sent")
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
