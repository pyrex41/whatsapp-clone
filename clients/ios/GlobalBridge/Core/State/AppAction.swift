//
//  AppAction.swift
//  GlobalBridge
//

import Foundation

enum AppAction {
    case onAppear
    case threadsLoaded(Result<[Thread], Error>)
    case threadSelected(Thread.ID)
    case setSearchQuery(String)
    case toggleCreationSheet(Bool)
    case creationTitleChanged(String)
    case createThread
    case threadCreated(Result<Thread, Error>)

    case loadMessages(Thread.ID)
    case messagesLoaded(Thread.ID, Result<[Message], Error>)

    case composerTextChanged(String)
    case sendMessage
    case messageSent(Result<Message, Error>)
    case messageStatusUpdated(Message.ID, Message.Status)

    case receiveRealtimeMessage(Message)
    case typingIndicator(Thread.ID, userID: UUID, isTyping: Bool)
    case handleOrphanedThread(Thread.ID)

    // Auth
    case authenticationFailed(Error)
    case dismissAuthError
    
    // Connection state
    case connectionStateChanged(ConnectionState)
    
    // Phoenix Channel actions
    case phoenixChannel(PhoenixChannelAction)
}

enum PhoenixChannelAction {
    case searchUsers(query: String)
    case userSearchResults(Result<[UserSearchResult], Error>)
    case createDM(userId: String)
    case createGroup(title: String, participantIds: [String])
    case dmCreated(Result<Thread, Error>)
    case groupCreated(Result<Thread, Error>)
}
