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
    var userCache: [String: CachedUserInfo] = [:]  // userId -> display info

    // MARK: - AI Features - Smart Reply
    var smartReplySuggestions: [String: [SmartReplySuggestion]] = [:] // threadId -> suggestions
    var smartReplyLoading: [String: Bool] = [:] // threadId -> loading state
    var smartReplyErrors: [String: String] = [:] // threadId -> error message

    // MARK: - AI Features - Style Learning
    var userStyleProfile: UserStyleProfile?
    var styleLearningEnabled: Bool = true // Style learning active by default

    // MARK: - AI Features - Translation
    var translationPreferences: TranslationPreferences = .default
    var messageTranslations: [String: String] = [:] // messageId -> translated text
    var threadTranslationSettings: [String: ThreadTranslationSettings] = [:] // threadId -> settings

    // MARK: - AI Features - Monitoring
    var monitoredThreads: Set<String> = []
    var aiInsightsVisible: Bool = false
    var currentThreadId: String?

    // MARK: - AI Features - Thread Summarization
    var threadSummaries: [String: ThreadSummary] = [:] // threadId -> summary
    var threadSummaryLoading: [String: Bool] = [:] // threadId -> loading state
    var threadSummaryErrors: [String: String] = [:] // threadId -> error message

    // MARK: - User Preferences
    var userLanguage: String = "en" // User's home language for UI and suggestions

    init(
        user: User = .sampleCurrent,
        threads: ThreadsState = .init(),
        chat: ChatState = .init(),
        authError: String? = nil,
        connectionState: ConnectionState = .disconnected,
        userCache: [String: CachedUserInfo] = [:],
        smartReplySuggestions: [String: [SmartReplySuggestion]] = [:],
        smartReplyLoading: [String: Bool] = [:],
        smartReplyErrors: [String: String] = [:],
        userStyleProfile: UserStyleProfile? = nil,
        styleLearningEnabled: Bool = true,
        translationPreferences: TranslationPreferences = .default,
        messageTranslations: [String: String] = [:],
        threadTranslationSettings: [String: ThreadTranslationSettings] = [:],
        monitoredThreads: Set<String> = [],
        aiInsightsVisible: Bool = false,
        currentThreadId: String? = nil,
        threadSummaries: [String: ThreadSummary] = [:],
        threadSummaryLoading: [String: Bool] = [:],
        threadSummaryErrors: [String: String] = [:],
        userLanguage: String = "en"
    ) {
        self.user = user
        self.threads = threads
        self.chat = chat
        self.authError = authError
        self.connectionState = connectionState
        self.userCache = userCache
        self.smartReplySuggestions = smartReplySuggestions
        self.smartReplyLoading = smartReplyLoading
        self.smartReplyErrors = smartReplyErrors
        self.userStyleProfile = userStyleProfile
        self.styleLearningEnabled = styleLearningEnabled
        self.translationPreferences = translationPreferences
        self.messageTranslations = messageTranslations
        self.threadTranslationSettings = threadTranslationSettings
        self.monitoredThreads = monitoredThreads
        self.aiInsightsVisible = aiInsightsVisible
        self.currentThreadId = currentThreadId
        self.threadSummaries = threadSummaries
        self.threadSummaryLoading = threadSummaryLoading
        self.threadSummaryErrors = threadSummaryErrors
        self.userLanguage = userLanguage
    }
}

/// Cached user display information
struct CachedUserInfo: Equatable, Codable {
    let id: String
    let displayName: String?
    let username: String
    let avatarUrl: String?
    
    var effectiveDisplayName: String {
        displayName ?? username
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
    var isLoadingOlderMessages: Bool = false  // For pagination
    var hasMoreMessages: Bool = true  // Whether there are older messages to load
    var messageError: String?
    var composer = MessageComposerState()
    var typingUsers: Set<String> = []
    var needsHistoricalFetch: Bool = false  // Flag to fetch from backend after channel joins
}

struct MessageComposerState: Equatable {
    var text: String = ""
    var isSending: Bool = false
}
