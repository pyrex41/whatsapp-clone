//
//  AppState.swift
//  GlobalBridge
//

import Foundation
import SwiftUI

struct AppState: Equatable {
    var user: User
    var threads: ThreadsState
    var chat: ChatState
    var authError: String?
    var connectionState: ConnectionState = .disconnected

    init(
        user: User = .sampleCurrent,
        threads: ThreadsState = .init(),
        chat: ChatState = .init(),
        authError: String? = nil,
        connectionState: ConnectionState = .disconnected
    ) {
        self.user = user
        self.threads = threads
        self.chat = chat
        self.authError = authError
        self.connectionState = connectionState
    }
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
    
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
    
    var displayText: String {
        switch self {
        case .disconnected: return "Offline"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Connection Error"
        }
    }
    
    var color: Color {
        switch self {
        case .disconnected: return .red
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
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
    var needsHistoricalFetch: Bool = false  // Flag to fetch from backend after channel joins
}

struct MessageComposerState: Equatable {
    var text: String = ""
    var isSending: Bool = false
}
