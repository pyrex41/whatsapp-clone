//
//  PhoenixChannelManager+AI.swift
//  GlobalBridge
//
//  Task 11: AI-specific methods for Phoenix Channel Manager
//  Handles AI suggestion broadcasts and style learning triggers
//

import Foundation
@preconcurrency import SwiftPhoenixClient

/// AI-specific handler for suggestion broadcasts
typealias AISuggestionHandler = @Sendable (SmartReplySuggestion) -> Void

/// Extension to PhoenixChannelManager to support AI features
extension PhoenixChannelManager {

    // MARK: - AI Suggestion Subscription

    /// Subscribe to AI suggestion broadcasts for a thread
    /// - Parameters:
    ///   - threadId: Thread ID to subscribe to
    ///   - handler: Callback for proactive suggestions from backend
    /// - Throws: PhoenixError if channel not joined
    ///
    /// This method listens for `ai_suggestions` events broadcast from the Phoenix backend
    /// when the AI monitoring service detects opportunities for proactive suggestions.
    /// The handler is called with each suggestion as it arrives in real-time.
    func subscribeToAISuggestions(
        threadId: String,
        handler: @escaping AISuggestionHandler
    ) async throws {
        // Use sendableChannel to avoid concurrency warnings
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            throw PhoenixError.channelNotJoined
        }

        let eventName = "ai_suggestions"

        print("🤖 [PHOENIX_AI] Subscribing to AI suggestions for thread: \(threadId)")

        // Register event handler for AI suggestions broadcast
        _ = await MainActor.run {
            sendableChannel.channel.on(eventName) { [weak self] message in
                guard let self else { return }

                Task {
                    do {
                        // Parse suggestion from payload
                        let payload = message.payload
                        guard let suggestionData = payload["suggestion"] as? [String: Any] else {
                            print("⚠️  [PHOENIX_AI] Invalid AI suggestion payload")
                            return
                        }

                        let suggestion = try self.parseAISuggestion(from: suggestionData)

                        print("✅ [PHOENIX_AI] Received AI suggestion: \(suggestion.id)")

                        // Dispatch to app via NotificationCenter (Redux will handle via middleware)
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("AIProactiveSuggestion"),
                                object: nil,
                                userInfo: [
                                    "threadId": threadId,
                                    "suggestion": suggestion
                                ]
                            )
                        }

                        // Call the handler
                        handler(suggestion)
                    } catch {
                        print("❌ [PHOENIX_AI] Failed to parse AI suggestion: \(error)")
                    }
                }
            }
        }
    }

    /// Unsubscribe from AI suggestion broadcasts for a thread
    /// - Parameter threadId: Thread ID to unsubscribe from
    func unsubscribeFromAISuggestions(threadId: String) async {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            return
        }

        print("🤖 [PHOENIX_AI] Unsubscribing from AI suggestions for thread: \(threadId)")

        // Off all handlers for ai_suggestions event
        _ = await MainActor.run {
            sendableChannel.channel.off("ai_suggestions")
        }
    }

    // MARK: - Style Learning Triggers

    /// Trigger style learning analysis when user sends a message
    /// - Parameters:
    ///   - messageId: ID of the sent message
    ///   - threadId: Thread ID where message was sent
    ///
    /// This is a fire-and-forget operation that notifies the backend to update
    /// the user's style profile based on the newly sent message. The backend
    /// performs async analysis without blocking the message send flow.
    func triggerStyleLearning(messageId: String, threadId: String) async {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            print("⚠️  [PHOENIX_AI] Cannot trigger style learning - channel not joined for thread: \(threadId)")
            return
        }

        let payload: [String: Any] = [
            "message_id": messageId,
            "thread_id": threadId
        ]

        print("🧠 [PHOENIX_AI] Triggering style learning for message: \(messageId)")

        // Fire-and-forget push (no need to wait for response)
        _ = await MainActor.run {
            sendableChannel.channel.push("style:learn", payload: payload)
                .receive("ok") { _ in
                    print("✅ [PHOENIX_AI] Style learning triggered successfully")
                }
                .receive("error") { message in
                    print("⚠️  [PHOENIX_AI] Style learning failed: \(message.payload)")
                }
        }
    }

    /// Start AI monitoring for a thread
    /// - Parameter threadId: Thread ID to start monitoring
    ///
    /// Sends a channel event to enable backend AI monitoring for proactive suggestions.
    /// The backend will analyze conversation context and broadcast suggestions via
    /// the `ai_suggestions` event (subscribe using subscribeToAISuggestions).
    func startAIMonitoring(threadId: String) async throws {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            throw PhoenixError.channelNotJoined
        }

        print("👁️  [PHOENIX_AI] Starting AI monitoring for thread: \(threadId)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let payload: [String: Any] = [
                    "thread_id": threadId,
                    "enabled": true
                ]

                sendableChannel.channel.push("ai:monitor", payload: payload)
                    .receive("ok") { _ in
                        print("✅ [PHOENIX_AI] AI monitoring started")
                        continuation.resume()
                    }
                    .receive("error") { message in
                        print("❌ [PHOENIX_AI] AI monitoring failed: \(message.payload)")
                        continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                    }
                    .receive("timeout") { _ in
                        print("⏱️  [PHOENIX_AI] AI monitoring request timeout")
                        continuation.resume(throwing: PhoenixError.timeout)
                    }
            }
        }
    }

    /// Stop AI monitoring for a thread
    /// - Parameter threadId: Thread ID to stop monitoring
    func stopAIMonitoring(threadId: String) async throws {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            throw PhoenixError.channelNotJoined
        }

        print("👁️  [PHOENIX_AI] Stopping AI monitoring for thread: \(threadId)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                let payload: [String: Any] = [
                    "thread_id": threadId,
                    "enabled": false
                ]

                sendableChannel.channel.push("ai:monitor", payload: payload)
                    .receive("ok") { _ in
                        print("✅ [PHOENIX_AI] AI monitoring stopped")
                        continuation.resume()
                    }
                    .receive("error") { message in
                        print("❌ [PHOENIX_AI] Stop monitoring failed: \(message.payload)")
                        continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                    }
                    .receive("timeout") { _ in
                        print("⏱️  [PHOENIX_AI] Stop monitoring request timeout")
                        continuation.resume(throwing: PhoenixError.timeout)
                    }
            }
        }
    }

    // MARK: - Private Helpers

    /// Parse AI suggestion from Phoenix message payload
    nonisolated private func parseAISuggestion(from dict: [String: Any]) throws -> SmartReplySuggestion {
        guard let idStr = dict["id"] as? String,
              let id = UUID(uuidString: idStr),
              let type = dict["type"] as? String,
              let content = dict["content"] as? String,
              let confidence = dict["confidence"] as? Double,
              let position = dict["position"] as? Int,
              let context = dict["context"] as? String,
              let timestampStr = dict["timestamp"] as? String,
              let timestamp = ISO8601DateFormatter().date(from: timestampStr) else {
            throw PhoenixError.decodingFailed(
                NSError(
                    domain: "AISuggestionParsing",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid AI suggestion data"]
                )
            )
        }

        // Extract optional translatedText field
        let translatedText = dict["translated_text"] as? String

        return SmartReplySuggestion(
            id: id,
            type: type,
            content: content,
            translatedText: translatedText,
            confidence: confidence,
            position: position,
            context: context,
            timestamp: timestamp
        )
    }
}
