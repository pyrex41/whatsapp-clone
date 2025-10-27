//
//  AppAction.swift
//  GlobalBridge
//

import Foundation

enum AppAction {
    case onAppear
    case checkAuthentication
    case authenticationChecked(isAuthenticated: Bool)
    case userAuthenticated
    case loadUserAndThreads
    case threadsLoaded(Result<(user: User, threads: [Thread]), Error>)
    case threadSelected(Thread.ID)
    case setSearchQuery(String)
    case toggleCreationSheet(Bool)
    case creationTitleChanged(String)
    case createThread
    case threadCreated(Result<Thread, Error>)

    case loadMessages(Thread.ID)
    case messagesLoaded(Thread.ID, Result<[Message], Error>)
    case loadOlderMessages(Thread.ID)  // For pagination

    case composerTextChanged(String)
    case sendMessage
    case messageSent(Result<Message, Error>)
    case messageStatusUpdated(Message.ID, Message.Status)

    case receiveRealtimeMessage(Message)
    case typingIndicator(Thread.ID, userID: String, isTyping: Bool)
    case handleOrphanedThread(Thread.ID)

    // Notification actions
    case markMessageRead(threadID: Thread.ID, messageID: String)
    case sendQuickReply(threadID: Thread.ID, text: String)
    
    // Thread creation actions
    case createDirectMessage(userId: String, displayName: String?, username: String)
    case directMessageCreated(Result<Thread, Error>)
    case createGroupThread(title: String, participantIds: [String])
    case groupThreadCreated(Result<Thread, Error>)
    
    // Historical message fetch
    case fetchHistoricalMessages(Thread.ID)
    
    // Connection state
    case connectionStateChanged(ConnectionState)
    
    // User cache
    case cacheUsers([String: CachedUserInfo])

    // MARK: - AI Features: Smart Reply

    /// Trigger fetch of smart reply suggestions for a thread
    case fetchSmartReplies(threadId: String)

    /// Smart reply suggestions received from backend
    case smartRepliesReceived(threadId: String, Result<[SmartReplySuggestion], Error>)

    /// User accepted a suggestion (for feedback and composer insertion)
    case acceptSuggestion(threadId: String, suggestion: SmartReplySuggestion, modifiedContent: String?)

    /// User rejected a suggestion (for feedback learning)
    case rejectSuggestion(threadId: String, suggestionId: UUID, reason: String?)

    /// Record user feedback on suggestion usage
    case recordFeedback(SuggestionFeedback)

    // MARK: - AI Features: Conversation Monitoring

    /// Toggle monitoring for a specific thread (adds/removes from monitored set)
    case toggleMonitoring(threadId: String)

    /// Start monitoring a thread for AI suggestions
    case startMonitoring(threadId: String)

    /// Stop monitoring a thread
    case stopMonitoring(threadId: String)

    /// Received proactive AI suggestion broadcast from monitoring
    case aiSuggestionBroadcast(threadId: String, suggestion: SmartReplySuggestion)

    // MARK: - AI Features: Translation

    /// Translate a message to target language
    case translateMessage(messageId: String, targetLanguage: String)

    /// Translation result received
    case translationReceived(messageId: String, Result<String, Error>)

    /// Update user translation preferences
    case updateTranslationPreferences(TranslationPreferences)

    // MARK: - Thread-Specific Translation Settings

    /// Update thread translation settings
    case updateThreadTranslationSettings(threadId: String, settings: ThreadTranslationSettings)

    /// Toggle show suggestions for a thread
    case toggleShowSuggestions(threadId: String)

    /// Set translation mode for a thread
    case setTranslationMode(threadId: String, mode: TranslationMode)

    /// Set formality level for a thread
    case setFormality(threadId: String, level: FormalityLevel)

    /// Toggle auto-translate incoming messages for a thread
    case toggleAutoTranslateIncoming(threadId: String)

    /// Set target language for a thread
    case setThreadTargetLanguage(threadId: String, language: String)

    // MARK: - AI Features: Style Learning

    /// User style profile updated from backend
    case styleProfileUpdated(UserStyleProfile)

    /// Fetch latest user style profile
    case fetchStyleProfile

    /// Style profile fetch result
    case styleProfileReceived(Result<UserStyleProfile, Error>)

    /// Toggle style learning on/off
    case toggleStyleLearning

    // MARK: - AI Features: Insights & UI

    /// Toggle AI insights panel visibility
    case toggleInsightsVisible

    /// Set current active thread for insights
    case setCurrentThread(threadId: String?)

    // MARK: - AI Features: Thread Summarization

    /// Trigger fetch of thread summary
    case fetchThreadSummary(threadId: String)

    /// Thread summary received from backend
    case threadSummaryReceived(threadId: String, Result<ThreadSummary, Error>)

    /// Clear thread summary for a specific thread
    case clearThreadSummary(threadId: String)

    // MARK: - User Preferences

    /// Set user's home language for UI and suggestions
    case setUserLanguage(String)
}
