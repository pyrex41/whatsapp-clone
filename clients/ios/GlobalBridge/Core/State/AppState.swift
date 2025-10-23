//
//  AppState.swift
//  GlobalBridge
//

import Foundation

struct AppState: Equatable {
    var user: User
    var threads: ThreadsState
    var chat: ChatState

    init(
        user: User = .sampleCurrent,
        threads: ThreadsState = .init(),
        chat: ChatState = .init()
    ) {
        self.user = user
        self.threads = threads
        self.chat = chat
    }
}

struct ThreadsState: Equatable {
    var items: [Thread] = []
    var filteredItems: [Thread] {
        guard !searchQuery.isEmpty else { return items }
        return items.filter { ($0.title ?? "").localizedCaseInsensitiveContains(searchQuery) }
    }

    var isLoading: Bool = false
    var hasLoaded: Bool = false
    var searchQuery: String = ""
    var selectedThreadID: Thread.ID?
    var showCreationSheet: Bool = false
    var creationTitle: String = ""
    var isCreatingThread: Bool = false
    var errorMessage: String?
}

struct ChatState: Equatable {
    var currentThread: Thread?
    var messages: [Message] = []
    var isLoadingMessages: Bool = false
    var messageError: String?
    var composer = MessageComposerState()
    var typingUsers: Set<String> = []
}

struct MessageComposerState: Equatable {
    var text: String = ""
    var isSending: Bool = false
}
