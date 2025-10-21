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

    case receiveRealtimeMessage(Message)
    case typingIndicator(Thread.ID, userID: UUID, isTyping: Bool)
}
