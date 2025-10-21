//
//  Command.swift
//  GlobalBridge
//
//  Lightweight command abstraction inspired by The Elm Architecture.
//

import Foundation

enum Command<Action> {
    case none
    case run(priority: TaskPriority? = nil, (@MainActor @escaping (Action) -> Void) async -> Void)
    case merge([Command<Action>])

    static func run(
        priority: TaskPriority? = nil,
        _ work: @escaping (@MainActor @escaping (Action) -> Void) async -> Void
    ) -> Command<Action> {
        .run(priority: priority, work)
    }

    static func fireAndForget(
        priority: TaskPriority? = nil,
        _ work: @escaping () async -> Void
    ) -> Command<Action> {
        .run(priority: priority) { _ in await work() }
    }

    static func merge(_ commands: Command<Action>...) -> Command<Action> {
        .merge(commands)
    }
}

extension Command {
    func perform(send: @MainActor @escaping (Action) -> Void) {
        switch self {
        case .none:
            return
        case let .run(priority, work):
            Task(priority: priority) {
                await work(send)
            }
        case let .merge(commands):
            commands.forEach { $0.perform(send: send) }
        }
    }
}
