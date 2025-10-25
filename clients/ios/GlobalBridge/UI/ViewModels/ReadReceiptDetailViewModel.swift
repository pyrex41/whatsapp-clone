//
//  ReadReceiptDetailViewModel.swift
//  GlobalBridge
//
//  ViewModel for read receipt detail view with real-time updates
//

import Foundation
import Combine

/// UI display model for a participant's read receipt (avoids name clash with Core model)
public struct ReadReceiptDisplay: Identifiable, Equatable {
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

/// UI display model for a conversation participant (avoids name clash with Core model)
public struct ParticipantDisplay: Identifiable, Equatable {
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

    @Published public private(set) var receipts: [ReadReceiptDisplay] = []
    @Published public private(set) var participants: [ParticipantDisplay] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?

    // MARK: - Properties

    let messageId: String
    private let manager: ReadReceiptManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    public var readReceipts: [ReadReceiptDisplay] {
        receipts.sorted { $0.readAt > $1.readAt }
    }

    public var deliveredReceipts: [ReadReceiptDisplay] {
        // Delivered-but-not-read state is not tracked via the Core model; none by default
        []
    }

    public var pendingReceipts: [ParticipantDisplay] {
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

            // Map to display models
            let participantNameById: [String: String] = Dictionary(uniqueKeysWithValues: fetchedParticipants.map { ($0.id, $0.displayName ?? $0.id) })

            receipts = fetchedReceipts.map { core in
                ReadReceiptDisplay(
                    userId: core.userId,
                    userName: participantNameById[core.userId] ?? core.userId,
                    readAt: core.readAt
                )
            }

            participants = fetchedParticipants.map { core in
                ParticipantDisplay(
                    id: core.id,
                    name: core.displayName ?? core.id,
                    avatarUrl: core.avatarUrl
                )
            }
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

            let participantNameById: [String: String] = Dictionary(uniqueKeysWithValues: fetchedParticipants.map { ($0.id, $0.displayName ?? $0.id) })

            receipts = fetchedReceipts.map { core in
                ReadReceiptDisplay(
                    userId: core.userId,
                    userName: participantNameById[core.userId] ?? core.userId,
                    readAt: core.readAt
                )
            }

            participants = fetchedParticipants.map { core in
                ParticipantDisplay(
                    id: core.id,
                    name: core.displayName ?? core.id,
                    avatarUrl: core.avatarUrl
                )
            }
        } catch {
            // Silently fail for refresh
            print("Failed to refresh read receipts: \(error)")
        }
    }

    // MARK: - Private Methods

    private func handleReadReceiptUpdate(_ receipt: ReadReceipt) {
        // Update or add the receipt
        if let index = receipts.firstIndex(where: { $0.userId == receipt.userId }) {
            let updated = ReadReceiptDisplay(
                userId: receipt.userId,
                userName: receipts[index].userName,
                readAt: receipt.readAt,
                isRead: true
            )
            receipts[index] = updated
        } else if let participant = participants.first(where: { $0.id == receipt.userId }) {
            let newReceipt = ReadReceiptDisplay(
                userId: receipt.userId,
                userName: participant.name,
                readAt: receipt.readAt,
                isRead: true
            )
            receipts.append(newReceipt)
        }
    }
}

// MARK: - Mock Data for Testing

#if DEBUG
extension ReadReceiptDetailViewModel {
    static var preview: ReadReceiptDetailViewModel {
        let viewModel = ReadReceiptDetailViewModel(messageId: "test-message", manager: .preview)

        viewModel.receipts = [
            ReadReceiptDisplay(
                userId: "user1",
                userName: "Alice Johnson",
                readAt: Date().addingTimeInterval(-300),
                isRead: true
            ),
            ReadReceiptDisplay(
                userId: "user2",
                userName: "Bob Smith",
                readAt: Date().addingTimeInterval(-120),
                isRead: true
            ),
            ReadReceiptDisplay(
                userId: "user3",
                userName: "Charlie Brown",
                readAt: Date(),
                isRead: false
            )
        ]

        viewModel.participants = [
            ParticipantDisplay(id: "user1", name: "Alice Johnson"),
            ParticipantDisplay(id: "user2", name: "Bob Smith"),
            ParticipantDisplay(id: "user3", name: "Charlie Brown"),
            ParticipantDisplay(id: "user4", name: "Diana Prince"),
            ParticipantDisplay(id: "user5", name: "Eve Miller")
        ]

        return viewModel
    }
}
#endif
