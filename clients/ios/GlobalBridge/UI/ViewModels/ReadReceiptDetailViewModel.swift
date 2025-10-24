//
//  ReadReceiptDetailViewModel.swift
//  GlobalBridge
//
//  ViewModel for read receipt detail view with real-time updates
//

import Foundation
import Combine

/// Participant read receipt information
public struct ParticipantReadReceipt: Identifiable, Equatable {
    public let id = UUID()
    public let userId: String
    public let userName: String
    public let readAt: Date
    public let isRead: Bool

    public init(userId: String, userName: String, readAt: Date, isRead: Bool = true) {
        self.userId = userId
        self.userName = userName
        self.readAt = readAt
        self.isRead = isRead
    }
}

/// Conversation participant information
public struct ConversationParticipant: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let avatarUrl: String?

    public init(id: String, name: String, avatarUrl: String? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

/// ViewModel managing read receipt details for a specific message
@MainActor
public class ReadReceiptDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published public private(set) var receipts: [ParticipantReadReceipt] = []
    @Published public private(set) var participants: [ConversationParticipant] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?

    // MARK: - Properties

    let messageId: String
    private let manager: ReadReceiptManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    public var readReceipts: [ParticipantReadReceipt] {
        receipts.filter { $0.isRead }.sorted { $0.readAt > $1.readAt }
    }

    public var deliveredReceipts: [ParticipantReadReceipt] {
        receipts.filter { !$0.isRead }
    }

    public var pendingReceipts: [ConversationParticipant] {
        let readUserIds = Set(receipts.map { $0.userId })
        return participants.filter { !readUserIds.contains($0.id) }
    }

    public var readCount: Int {
        receipts.filter { $0.isRead }.count
    }

    public var totalParticipants: Int {
        participants.count
    }

    public var mostRecentReadTimestamp: Date? {
        readReceipts.first?.readAt
    }

    // MARK: - Initialization

    public init(messageId: String, manager: ReadReceiptManager = .shared) {
        self.messageId = messageId
        self.manager = manager

        setupSubscriptions()
    }

    // MARK: - Setup

    private func setupSubscriptions() {
        // Subscribe to real-time read receipt updates
        manager.readReceiptPublisher
            .filter { [weak self] receipt in
                receipt.messageId == self?.messageId
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] receipt in
                self?.handleReadReceiptUpdate(receipt)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Load read receipts for the message
    public func loadReadReceipts() async {
        isLoading = true
        error = nil

        do {
            // Fetch receipts from manager
            let fetchedReceipts = try await manager.fetchReadReceipts(for: messageId)
            let fetchedParticipants = try await manager.fetchParticipants(for: messageId)

            receipts = fetchedReceipts
            participants = fetchedParticipants
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    /// Refresh read receipts (pull to refresh)
    public func refreshReadReceipts() async {
        do {
            let fetchedReceipts = try await manager.fetchReadReceipts(for: messageId)
            let fetchedParticipants = try await manager.fetchParticipants(for: messageId)

            receipts = fetchedReceipts
            participants = fetchedParticipants
        } catch {
            // Silently fail for refresh
            print("Failed to refresh read receipts: \(error)")
        }
    }

    // MARK: - Private Methods

    private func handleReadReceiptUpdate(_ receipt: ReadReceipt) {
        // Update or add the receipt
        if let index = receipts.firstIndex(where: { $0.userId == receipt.userId }) {
            var updatedReceipt = receipts[index]
            updatedReceipt = ParticipantReadReceipt(
                userId: receipt.userId,
                userName: updatedReceipt.userName,
                readAt: receipt.readAt,
                isRead: true
            )
            receipts[index] = updatedReceipt
        } else {
            // New read receipt - find participant name
            if let participant = participants.first(where: { $0.id == receipt.userId }) {
                let newReceipt = ParticipantReadReceipt(
                    userId: receipt.userId,
                    userName: participant.name,
                    readAt: receipt.readAt,
                    isRead: true
                )
                receipts.append(newReceipt)
            }
        }
    }
}

// MARK: - Mock Data for Testing

#if DEBUG
extension ReadReceiptDetailViewModel {
    static var preview: ReadReceiptDetailViewModel {
        let viewModel = ReadReceiptDetailViewModel(messageId: "test-message", manager: .preview)

        viewModel.receipts = [
            ParticipantReadReceipt(
                userId: "user1",
                userName: "Alice Johnson",
                readAt: Date().addingTimeInterval(-300),
                isRead: true
            ),
            ParticipantReadReceipt(
                userId: "user2",
                userName: "Bob Smith",
                readAt: Date().addingTimeInterval(-120),
                isRead: true
            ),
            ParticipantReadReceipt(
                userId: "user3",
                userName: "Charlie Brown",
                readAt: Date(),
                isRead: false
            )
        ]

        viewModel.participants = [
            ConversationParticipant(id: "user1", name: "Alice Johnson"),
            ConversationParticipant(id: "user2", name: "Bob Smith"),
            ConversationParticipant(id: "user3", name: "Charlie Brown"),
            ConversationParticipant(id: "user4", name: "Diana Prince"),
            ConversationParticipant(id: "user5", name: "Eve Miller")
        ]

        return viewModel
    }
}
#endif
