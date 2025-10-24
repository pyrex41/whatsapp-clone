//
//  ReadReceiptManager.swift
//  GlobalBridge
//
//  Manages read receipts with Phoenix Channel real-time updates
//  Handles optimistic UI updates and settings privacy controls
//

import Foundation
import Combine

/// Manager for read receipt functionality with Phoenix integration
@MainActor
public class ReadReceiptManager: ObservableObject {
    // MARK: - Singleton

    public static let shared = ReadReceiptManager()

    // MARK: - Published Properties

    @Published public private(set) var readReceiptsEnabled = true
    @Published public private(set) var isConnected = false

    // MARK: - Properties

    private var receiptCache: [String: ReadReceiptState] = [:]
    private let readReceiptSubject = PassthroughSubject<ReadReceipt, Never>()
    private var cancellables = Set<AnyCancellable>()

    public var readReceiptPublisher: AnyPublisher<ReadReceipt, Never> {
        readReceiptSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {
        setupPhoenixIntegration()
        loadSettings()
    }

    // MARK: - Setup

    private func setupPhoenixIntegration() {
        // Subscribe to Phoenix Channel events for read receipts
        // This would integrate with PhoenixChannelManager in production

        // Simulate connection status
        isConnected = true
    }

    private func loadSettings() {
        // Load read receipts settings from UserDefaults
        readReceiptsEnabled = UserDefaults.standard.bool(forKey: "read_receipts_enabled") != false
    }

    // MARK: - Public Methods

    /// Enable or disable read receipts
    public func setReadReceiptsEnabled(_ enabled: Bool) {
        readReceiptsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "read_receipts_enabled")

        // Notify backend of setting change via Phoenix
        Task {
            await updateReadReceiptsSetting(enabled)
        }
    }

    /// Mark message as read (optimistic update)
    public func markAsRead(messageId: String, userId: String) async {
        guard readReceiptsEnabled else { return }

        // Optimistic update
        let receipt = ReadReceipt(
            userId: userId,
            conversationId: "", // Will be filled by backend
            messageId: messageId,
            readAt: Date()
        )

        updateLocalCache(receipt)
        readReceiptSubject.send(receipt)

        // Send to backend via Phoenix
        do {
            try await sendReadReceipt(receipt)
        } catch {
            print("Failed to send read receipt: \(error)")
            // Could implement retry logic here
        }
    }

    /// Fetch read receipts for a specific message
    public func fetchReadReceipts(for messageId: String) async throws -> [ParticipantReadReceipt] {
        // Check cache first
        if let cached = receiptCache[messageId] {
            return convertToParticipantReceipts(cached, messageId: messageId)
        }

        // Fetch from backend
        let receipts = try await fetchReadReceiptsFromBackend(messageId)

        // Update cache
        var state = ReadReceiptState()
        for receipt in receipts {
            state.markAsRead(
                messageId: messageId,
                userId: receipt.userId,
                at: receipt.readAt
            )
        }
        receiptCache[messageId] = state

        return receipts
    }

    /// Fetch conversation participants
    public func fetchParticipants(for messageId: String) async throws -> [ConversationParticipant] {
        // Fetch from backend
        return try await fetchParticipantsFromBackend(messageId)
    }

    /// Get read count for a message
    public func getReadCount(for messageId: String) -> Int {
        receiptCache[messageId]?.readCount(for: messageId) ?? 0
    }

    /// Handle real-time read receipt from Phoenix
    public func handleReadReceiptEvent(_ receipt: ReadReceipt) {
        updateLocalCache(receipt)
        readReceiptSubject.send(receipt)
    }

    // MARK: - Private Methods

    private func updateLocalCache(_ receipt: ReadReceipt) {
        if receiptCache[receipt.messageId] == nil {
            receiptCache[receipt.messageId] = ReadReceiptState()
        }

        receiptCache[receipt.messageId]?.markAsRead(
            messageId: receipt.messageId,
            userId: receipt.userId,
            at: receipt.readAt
        )
    }

    private func convertToParticipantReceipts(
        _ state: ReadReceiptState,
        messageId: String
    ) -> [ParticipantReadReceipt] {
        guard let readers = state.receipts[messageId] else {
            return []
        }

        return readers.map { userId, readAt in
            ParticipantReadReceipt(
                userId: userId,
                userName: userId, // Would fetch real name from user service
                readAt: readAt,
                isRead: true
            )
        }
    }

    // MARK: - Backend Communication

    private func sendReadReceipt(_ receipt: ReadReceipt) async throws {
        // Send via Phoenix Channel
        // In production, this would use PhoenixChannelManager

        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Phoenix push would look like:
        // channel.push("message:read", payload: [
        //     "message_id": receipt.messageId,
        //     "read_at": receipt.readAt.ISO8601Format()
        // ])
    }

    private func updateReadReceiptsSetting(_ enabled: Bool) async {
        // Update setting on backend via Phoenix
        // channel.push("settings:update", payload: [
        //     "read_receipts_enabled": enabled
        // ])
    }

    private func fetchReadReceiptsFromBackend(_ messageId: String) async throws -> [ParticipantReadReceipt] {
        // Fetch from backend API
        // In production, this would call the backend API endpoint

        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Mock data for testing
        return [
            ParticipantReadReceipt(
                userId: "user1",
                userName: "Alice",
                readAt: Date().addingTimeInterval(-300),
                isRead: true
            ),
            ParticipantReadReceipt(
                userId: "user2",
                userName: "Bob",
                readAt: Date().addingTimeInterval(-120),
                isRead: true
            )
        ]
    }

    private func fetchParticipantsFromBackend(_ messageId: String) async throws -> [ConversationParticipant] {
        // Fetch from backend API
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Mock data for testing
        return [
            ConversationParticipant(id: "user1", name: "Alice"),
            ConversationParticipant(id: "user2", name: "Bob"),
            ConversationParticipant(id: "user3", name: "Charlie"),
            ConversationParticipant(id: "user4", name: "Diana")
        ]
    }
}

// MARK: - Preview Support

#if DEBUG
extension ReadReceiptManager {
    static var preview: ReadReceiptManager {
        let manager = ReadReceiptManager()
        manager.readReceiptsEnabled = true
        manager.isConnected = true
        return manager
    }
}
#endif

// MARK: - Phoenix Channel Integration Extension

extension ReadReceiptManager {
    /// Setup Phoenix Channel subscription for read receipts
    func setupPhoenixChannelSubscription(channelManager: Any) {
        // In production, this would integrate with PhoenixChannelManager
        // Example:
        //
        // channelManager.subscribe(to: "read_receipts") { [weak self] event in
        //     guard let self = self else { return }
        //
        //     switch event {
        //     case .messageRead(let receipt):
        //         Task { @MainActor in
        //             self.handleReadReceiptEvent(receipt)
        //         }
        //     default:
        //         break
        //     }
        // }
    }

    /// Handle Phoenix presence events for read status
    func handlePhoenixPresenceEvent(_ event: [String: Any]) {
        // Parse presence event for read receipts
        // Example Phoenix presence payload:
        // {
        //   "user_id": "123",
        //   "message_id": "msg-456",
        //   "read_at": "2025-10-24T12:34:56Z"
        // }

        guard
            let userId = event["user_id"] as? String,
            let messageId = event["message_id"] as? String,
            let readAtString = event["read_at"] as? String,
            let readAt = ISO8601DateFormatter().date(from: readAtString)
        else {
            return
        }

        let receipt = ReadReceipt(
            userId: userId,
            conversationId: "",
            messageId: messageId,
            readAt: readAt
        )

        handleReadReceiptEvent(receipt)
    }
}

// MARK: - Errors

public enum ReadReceiptError: Error, LocalizedError {
    case notEnabled
    case networkError(Error)
    case invalidResponse
    case notAuthorized

    public var errorDescription: String? {
        switch self {
        case .notEnabled:
            return "Read receipts are disabled"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .notAuthorized:
            return "Not authorized to view read receipts"
        }
    }
}
