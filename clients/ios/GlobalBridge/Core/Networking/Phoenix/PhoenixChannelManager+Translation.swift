//
//  PhoenixChannelManager+Translation.swift
//  GlobalBridge
//
//  Translation-specific methods for Phoenix Channel Manager
//  Handles thread-specific language preferences and translation settings
//

import Foundation
@preconcurrency import SwiftPhoenixClient

/// Translation preference response from backend
public struct TranslationPreferenceResponse: Sendable {
    let success: Bool
    let targetLanguage: String?
    let enabled: Bool

    init(success: Bool, targetLanguage: String?, enabled: Bool) {
        self.success = success
        self.targetLanguage = targetLanguage
        self.enabled = enabled
    }
}

/// Extension to PhoenixChannelManager to support translation features
extension PhoenixChannelManager {

    // MARK: - Translation Preferences

    /// Set translation preference for a specific thread
    /// - Parameters:
    ///   - threadId: Thread ID to set preference for
    ///   - targetLanguage: Target language code (e.g., "en", "es", "fr")
    ///   - enabled: Whether translation is enabled for this thread
    /// - Throws: PhoenixError if channel not joined or request fails
    ///
    /// This sets a thread-specific language override that applies to all messages
    /// in this conversation. The backend stores this preference per thread and uses
    /// it for automatic translation of incoming/outgoing messages.
    func setTranslationPreference(
        threadId: String,
        targetLanguage: String,
        enabled: Bool
    ) async throws {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            throw PhoenixError.channelNotJoined
        }

        print("🌐 [PHOENIX_TRANSLATION] Setting translation preference for thread: \(threadId), language: \(targetLanguage), enabled: \(enabled)")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                // Backend expects: scope, auto_translate_incoming, auto_translate_outgoing, preferred_thread_language
                let payload: [String: Any] = [
                    "scope": "thread",
                    "auto_translate_incoming": enabled,
                    "auto_translate_outgoing": enabled,
                    "preferred_thread_language": targetLanguage
                ]

                let push = sendableChannel.channel.push("set_translation_preference", payload: payload)

                push.receive("ok") { response in
                    print("✅ [PHOENIX_TRANSLATION] Translation preference set successfully")
                    print("   Response: \(response.payload)")
                    continuation.resume(returning: ())
                }

                push.receive("error") { message in
                    print("❌ [PHOENIX_TRANSLATION] Failed to set translation preference: \(message.payload)")
                    continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                }

                push.receive("timeout") { _ in
                    print("⏱️  [PHOENIX_TRANSLATION] Translation preference request timeout")
                    continuation.resume(throwing: PhoenixError.timeout)
                }
            }
        }
    }

    /// Get translation preference for a specific thread
    /// - Parameter threadId: Thread ID to get preference for
    /// - Returns: TranslationPreferenceResponse with current settings
    /// - Throws: PhoenixError if channel not joined or request fails
    ///
    /// Retrieves the current thread-specific translation settings from the backend.
    /// This includes the target language and whether translation is enabled.
    func getTranslationPreference(
        threadId: String
    ) async throws -> TranslationPreferenceResponse {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            throw PhoenixError.channelNotJoined
        }

        print("🌐 [PHOENIX_TRANSLATION] Getting translation preferences for thread: \(threadId)")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TranslationPreferenceResponse, Error>) in
            Task { @MainActor in
                // Backend expects no payload for get_translation_preferences
                let payload: [String: Any] = [:]

                // Backend uses plural "preferences" not singular "preference"
                let push = sendableChannel.channel.push("get_translation_preferences", payload: payload)

                push.receive("ok") { response in
                    print("✅ [PHOENIX_TRANSLATION] Translation preferences retrieved")
                    print("   Response: \(response.payload)")

                    // Backend returns: auto_translate_incoming, auto_translate_outgoing, preferred_thread_language
                    let autoTranslateIncoming = response.payload["auto_translate_incoming"] as? Bool ?? false
                    let autoTranslateOutgoing = response.payload["auto_translate_outgoing"] as? Bool ?? false
                    let preferredLanguage = response.payload["preferred_thread_language"] as? String

                    // Consider enabled if either incoming or outgoing translation is on
                    let enabled = autoTranslateIncoming || autoTranslateOutgoing

                    let result = TranslationPreferenceResponse(
                        success: true,
                        targetLanguage: preferredLanguage,
                        enabled: enabled
                    )

                    continuation.resume(returning: result)
                }

                push.receive("error") { message in
                    print("❌ [PHOENIX_TRANSLATION] Failed to get translation preferences: \(message.payload)")
                    continuation.resume(throwing: PhoenixError.sendFailed(PhoenixPayload(message.payload)))
                }

                push.receive("timeout") { _ in
                    print("⏱️  [PHOENIX_TRANSLATION] Translation preferences request timeout")
                    continuation.resume(throwing: PhoenixError.timeout)
                }
            }
        }
    }

    /// Subscribe to translation preference changes for a thread
    /// - Parameters:
    ///   - threadId: Thread ID to subscribe to
    ///   - handler: Callback when translation preferences change
    ///
    /// Listens for real-time updates when translation preferences are changed
    /// by other clients or the backend. Useful for keeping UI in sync.
    func subscribeToTranslationUpdates(
        threadId: String,
        handler: @escaping @Sendable (String, Bool) -> Void
    ) async throws {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            throw PhoenixError.channelNotJoined
        }

        let eventName = "translation_preference_updated"

        print("🌐 [PHOENIX_TRANSLATION] Subscribing to translation updates for thread: \(threadId)")

        // Register event handler for translation preference updates
        _ = await MainActor.run {
            sendableChannel.channel.on(eventName) { message in
                let payload = message.payload
                guard let targetLanguage = payload["target_language"] as? String,
                      let enabled = payload["enabled"] as? Bool else {
                    print("⚠️  [PHOENIX_TRANSLATION] Invalid translation update payload")
                    return
                }

                print("✅ [PHOENIX_TRANSLATION] Translation preference updated: \(targetLanguage), enabled: \(enabled)")
                handler(targetLanguage, enabled)
            }
        }
    }

    /// Unsubscribe from translation preference updates
    /// - Parameter threadId: Thread ID to unsubscribe from
    func unsubscribeFromTranslationUpdates(threadId: String) async {
        guard let sendableChannel = await sendableChannel(for: threadId) else {
            return
        }

        print("🌐 [PHOENIX_TRANSLATION] Unsubscribing from translation updates for thread: \(threadId)")

        _ = await MainActor.run {
            sendableChannel.channel.off("translation_preference_updated")
        }
    }
}
