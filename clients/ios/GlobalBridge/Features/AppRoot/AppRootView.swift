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
        let _ = print("📱 [APP_ROOT] Rendering - horizontalSizeClass: \(horizontalSizeClass == .compact ? "compact (iPhone)" : "regular (iPad)")")
        if horizontalSizeClass == .compact {
            let _ = print("📱 [APP_ROOT] Using NavigationStack with compact view")
            NavigationStack {
                ThreadsListCompactView(store: store)
                    .navigationDestination(for: Thread.ID.self) { threadID in
                        let _ = print("🎬 [NAVIGATION] Navigation destination triggered for thread: \(threadID)")
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
                print("📱 [APP_ROOT] NavigationStack appeared, sending .onAppear")
                store.send(.onAppear)
            }
        } else {
            let _ = print("📱 [APP_ROOT] Using NavigationSplitView")
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
