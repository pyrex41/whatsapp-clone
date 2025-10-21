//
//  AppReducer.swift
//  GlobalBridge
//

import Foundation

let appReducer: Store<AppState, AppAction>.Reducer = { state, action, environment in
    switch action {
    case .onAppear:
        guard state.threads.hasLoaded == false else { return .none }
        state.threads.isLoading = true
        state.threads.errorMessage = nil
        return .run { send in
            do {
                let threads = try await environment.database.loadThreads()
                await MainActor.run { send(.threadsLoaded(.success(threads))) }
            } catch {
                await MainActor.run { send(.threadsLoaded(.failure(error))) }
            }
        }

    case let .threadsLoaded(result):
        state.threads.isLoading = false
        state.threads.hasLoaded = true
        switch result {
        case let .success(threads):
            state.threads.items = threads
            if let firstThread = threads.first {
                state.threads.selectedThreadID = firstThread.id
                state.chat.currentThread = firstThread
                return .run { send in
                    await MainActor.run { send(.loadMessages(firstThread.id)) }
                }
            }
            return .none

        case let .failure(error):
            state.threads.errorMessage = error.localizedDescription
            return .none
        }

    case let .threadSelected(threadID):
        guard state.threads.selectedThreadID != threadID,
              let thread = state.threads.items.first(where: { $0.id == threadID })
        else { return .none }

        let previousThreadID = state.threads.selectedThreadID
        state.threads.selectedThreadID = threadID
        state.chat.currentThread = thread
        state.chat.messages = []
        state.chat.isLoadingMessages = true
        var commands: [Command<AppAction>] = []
        if let previousThreadID {
            commands.append(.fireAndForget {
                await environment.realtime.disconnect(previousThreadID)
            })
        }
        commands.append(
            .run { send in
                await MainActor.run { send(.loadMessages(threadID)) }
            }
        )
        commands.append(
            .run { send in
                await environment.realtime.connect(threadID) { message in
                    await MainActor.run { send(.receiveRealtimeMessage(message)) }
                }
            }
        )
        return .merge(commands)

    case let .setSearchQuery(query):
        state.threads.searchQuery = query
        return .none

    case let .toggleCreationSheet(isPresented):
        state.threads.showCreationSheet = isPresented
        if !isPresented {
            state.threads.creationTitle = ""
            state.threads.isCreatingThread = false
        }
        return .none

    case let .creationTitleChanged(title):
        state.threads.creationTitle = title
        return .none

    case .createThread:
        guard state.threads.creationTitle.isEmpty == false else { return .none }
        state.threads.isCreatingThread = true
        let title = state.threads.creationTitle
        let user = state.user
        return .run { send in
            do {
                let thread = try await environment.database.createThread(title, user)
                await MainActor.run { send(.threadCreated(.success(thread))) }
            } catch {
                await MainActor.run { send(.threadCreated(.failure(error))) }
            }
        }

    case let .threadCreated(result):
        state.threads.isCreatingThread = false
        switch result {
        case let .success(thread):
            state.threads.items.insert(thread, at: 0)
            state.threads.showCreationSheet = false
            state.threads.creationTitle = ""
            state.threads.selectedThreadID = thread.id
            state.chat.currentThread = thread
            state.chat.messages = Message.samples(for: thread.id, sender: state.user)
            return .run { send in
                await MainActor.run { send(.loadMessages(thread.id)) }
            }

        case let .failure(error):
            state.threads.errorMessage = error.localizedDescription
            return .none
        }

    case let .loadMessages(threadID):
        state.chat.isLoadingMessages = true
        return .run { send in
            do {
                let messages = try await environment.database.loadMessages(threadID)
                await MainActor.run { send(.messagesLoaded(threadID, .success(messages))) }
            } catch {
                await MainActor.run { send(.messagesLoaded(threadID, .failure(error))) }
            }
        }

    case let .messagesLoaded(threadID, result):
        guard state.chat.currentThread?.id == threadID else { return .none }
        state.chat.isLoadingMessages = false
        switch result {
        case let .success(messages):
            state.chat.messages = messages.sorted(by: { $0.createdAt < $1.createdAt })
        case let .failure(error):
            state.chat.messageError = error.localizedDescription
        }
        return .none

    case let .composerTextChanged(text):
        state.chat.composer.text = text
        let maybeThreadID = state.chat.currentThread?.id
        let userID = state.user.id
        let isTyping = !text.isEmpty
        return .fireAndForget {
            guard let threadID = maybeThreadID else { return }
            await environment.realtime.sendTyping(threadID, userID, isTyping)
        }

    case .sendMessage:
        guard let threadID = state.chat.currentThread?.id,
              state.chat.composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              state.chat.composer.isSending == false
        else { return .none }

        let text = state.chat.composer.text
        state.chat.composer.isSending = true
        state.chat.composer.text = ""

        return .run { send in
            do {
                let message = try await environment.database.createMessage(threadID, text, state.user)
                await MainActor.run { send(.messageSent(.success(message))) }
            } catch {
                await MainActor.run { send(.messageSent(.failure(error))) }
            }
        }

    case let .messageSent(result):
        state.chat.composer.isSending = false
        switch result {
        case let .success(message):
            if !state.chat.messages.contains(where: { $0.id == message.id }) {
                state.chat.messages.append(message)
            }
        case let .failure(error):
            state.chat.messageError = error.localizedDescription
        }
        return .none

    case let .receiveRealtimeMessage(message):
        guard state.chat.currentThread?.id == message.threadId else { return .none }
        if !state.chat.messages.contains(where: { $0.id == message.id }) {
            state.chat.messages.append(message)
        }
        return .none

    case let .typingIndicator(threadID, userID, isTyping):
        guard state.chat.currentThread?.id == threadID,
              userID != state.user.id
        else { return .none }
        if isTyping {
            state.chat.typingUsers.insert(userID)
        } else {
            state.chat.typingUsers.remove(userID)
        }
        return .none
    }
}
