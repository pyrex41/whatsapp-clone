//
//  ContentView.swift
//  GlobalBridge
//
//  Created by Reuben Brooks on 10/20/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = Store(
        initialState: AppState(),
        reducer: appReducer,
        environment: .preview
    )

    var body: some View {
        AppRootView(store: store)
    }
}

#Preview {
    ContentView()
}
