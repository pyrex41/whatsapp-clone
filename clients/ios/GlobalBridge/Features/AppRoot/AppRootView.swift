//
//  AppRootView.swift
//  GlobalBridge
//

import SwiftUI

struct AppRootView: View {
    @ObservedObject var store: Store<AppState, AppAction>

    var body: some View {
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

#Preview {
    AppRootView(
        store: Store(
            initialState: AppState(),
            reducer: appReducer,
            environment: .preview
        )
    )
}
