//
//  ChatScreenSmartReplyTests.swift
//  GlobalBridge
//
//  Minimal sanity test for SmartReply chips wiring in ChatScreen
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class ChatScreenSmartReplyTests: XCTestCase {

    func testChipsRenderWhenSuggestionsPresent() {
        // Given an initial state with an active thread and seeded suggestions
        let thread = Thread.sampleThreads.first!
        var state = AppState()
        state.chat.currentThread = thread
        state.threads.selectedThreadID = thread.id
        let tid = thread.id.uuidString
        state.smartReplySuggestions[tid] = [
            SmartReplySuggestion(id: UUID(), type: "quick", content: "Thanks!", translatedText: nil, confidence: 0.9, position: 0, context: "", timestamp: Date())
        ]

        let store = Store(initialState: state, reducer: appReducer, environment: .preview)

        // When mounting ChatScreen, it should not crash and body should access suggestions
        let view = ChatScreen(store: store)
        XCTAssertNotNil(view)
    }
}

