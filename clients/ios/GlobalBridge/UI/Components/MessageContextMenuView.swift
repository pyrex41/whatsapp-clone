//
//  MessageContextMenuView.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  Context menu for message actions (edit, delete, copy, etc.)
//

import SwiftUI

/// Context menu actions for messages
struct MessageContextMenuView: View {

    // MARK: - Properties

    let message: Message
    let currentUserId: String
    let editManager: MessageEditManager
    let deletionHandler: MessageDeletionHandler

    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var selectedDeletionScope: DeletionScope = .forMe

    // MARK: - Callbacks

    let onEdit: () -> Void
    let onDelete: (DeletionScope) -> Void
    let onCopy: () -> Void
    let onReply: () -> Void

    // MARK: - Body

    var body: some View {
        Group {
            // Reply
            Button {
                onReply()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }

            // Copy
            Button {
                onCopy()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            // Edit (only for own messages within timeout)
            if editManager.canEditMessage(message, currentUserId: currentUserId) {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Divider()

            // Delete
            deleteMenu
        }
    }

    // MARK: - Delete Menu

    private var deleteMenu: some View {
        Group {
            if deletionHandler.canDeleteForEveryone(message, currentUserId: currentUserId) {
                // Show both options if user is the sender
                Menu {
                    Button(role: .destructive) {
                        selectedDeletionScope = .forMe
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete for Me", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        selectedDeletionScope = .forEveryone
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete for Everyone", systemImage: "trash.fill")
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                // Only show "Delete for Me" for other users' messages
                Button(role: .destructive) {
                    selectedDeletionScope = .forMe
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete for Me", systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            "Delete Message",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete(selectedDeletionScope)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var deleteConfirmationMessage: String {
        switch selectedDeletionScope {
        case .forMe:
            return "This message will be deleted for you only."
        case .forEveryone:
            return "This message will be deleted for everyone in this conversation."
        }
    }
}

// MARK: - Message Long Press Actions

/// Extension to add context menu to message views
extension View {
    func messageContextMenu(
        message: Message,
        currentUserId: String,
        editManager: MessageEditManager,
        deletionHandler: MessageDeletionHandler,
        onEdit: @escaping () -> Void,
        onDelete: @escaping (DeletionScope) -> Void,
        onCopy: @escaping () -> Void,
        onReply: @escaping () -> Void
    ) -> some View {
        self.contextMenu {
            MessageContextMenuView(
                message: message,
                currentUserId: currentUserId,
                editManager: editManager,
                deletionHandler: deletionHandler,
                onEdit: onEdit,
                onDelete: onDelete,
                onCopy: onCopy,
                onReply: onReply
            )
        }
    }
}

// MARK: - Deleted Message Tombstone View

/// View shown for deleted messages
struct DeletedMessageTombstoneView: View {

    let message: Message
    let currentUserId: String
    let deletionHandler: MessageDeletionHandler
    let isOwnMessage: Bool

    var body: some View {
        HStack {
            if isOwnMessage {
                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "trash.slash")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(deletionHandler.getTombstoneMessage(message: message, currentUserId: currentUserId))
                    .font(.body)
                    .italic()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )

            if !isOwnMessage {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Context Menu") {
    VStack(spacing: 20) {
        // Own message
        Text("Long press for menu")
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
            .messageContextMenu(
                message: Message(
                    threadId: UUID(),
                    senderId: "user123",
                    content: "Test message",
                    messageType: .text,
                    status: .sent
                ),
                currentUserId: "user123",
                editManager: MessageEditManager(
                    phoenixChannelManager: PhoenixChannelManager(
                        config: PhoenixConfig(
                            socketURL: URL(string: "ws://localhost:4000/socket")!
                        )
                    ),
                    databaseManager: DatabaseManager(),
                    offlineQueueManager: OfflineQueueManager(databaseManager: DatabaseManager())
                ),
                deletionHandler: MessageDeletionHandler(
                    phoenixChannelManager: PhoenixChannelManager(
                        config: PhoenixConfig(
                            socketURL: URL(string: "ws://localhost:4000/socket")!
                        )
                    ),
                    databaseManager: DatabaseManager(),
                    offlineQueueManager: OfflineQueueManager(databaseManager: DatabaseManager())
                ),
                onEdit: { print("Edit") },
                onDelete: { print("Delete: \($0)") },
                onCopy: { print("Copy") },
                onReply: { print("Reply") }
            )

        // Deleted message tombstone
        DeletedMessageTombstoneView(
            message: Message(
                threadId: UUID(),
                senderId: "user123",
                content: "Deleted",
                messageType: .text,
                status: .sent,
                deletedAt: Date()
            ),
            currentUserId: "user123",
            deletionHandler: MessageDeletionHandler(
                phoenixChannelManager: PhoenixChannelManager(
                    config: PhoenixConfig(
                        socketURL: URL(string: "ws://localhost:4000/socket")!
                    )
                ),
                databaseManager: DatabaseManager(),
                offlineQueueManager: OfflineQueueManager(databaseManager: DatabaseManager())
            ),
            isOwnMessage: true
        )
    }
    .padding()
}
