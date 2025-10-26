//
//  Store.swift
//  GlobalBridge
//
//  Generic observable store implementing The Elm Architecture loop.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class Store<State: Equatable, Action>: ObservableObject {

    typealias Reducer = @MainActor (inout State, Action, AppEnvironment) -> Command<Action>

    @Published private(set) var state: State

    private let reducer: Reducer
    let environment: AppEnvironment  // Internal access for AIBroadcastCoordinator
    private var cancellables: Set<AnyCancellable> = []

    init(
        initialState: State,
        reducer: @escaping Reducer,
        environment: AppEnvironment
    ) {
        self.state = initialState
        self.reducer = reducer
        self.environment = environment
    }

    func send(_ action: Action) {
        let command = reducer(&state, action, environment)
        command.perform(send: { [weak self] action in
            self?.send(action)
        })
    }

    func binding<Value: Equatable>(
        get: @escaping (State) -> Value,
        send action: @escaping (Value) -> Action
    ) -> Binding<Value> {
        Binding(
            get: { get(self.state) },
            set: { [weak self] newValue in
                self?.send(action(newValue))
            }
        )
    }
}
