//
//  MessageEditView.swift
//  GlobalBridge
//
//  Task #16: Message Edit and Delete
//  UI for editing messages with character limit and validation
//

import SwiftUI
import Combine

/// View for editing a message
struct MessageEditView: View {

    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MessageEditViewModel

    private let message: Message
    private let onSave: (String) async throws -> Void

    // MARK: - Initialization

    init(
        message: Message,
        editManager: MessageEditManager,
        currentUserId: String,
        onSave: @escaping (String) async throws -> Void
    ) {
        self.message = message
        self.onSave = onSave
        self._viewModel = StateObject(
            wrappedValue: MessageEditViewModel(
                message: message,
                editManager: editManager,
                currentUserId: currentUserId
            )
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Editor
                editingArea

                Divider()

                // Footer with character count
                footer
            }
            .navigationTitle("Edit Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.saveEdit()
                            if viewModel.editSucceeded {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .fontWeight(.semibold)
                }
            }
            .alert("Edit Failed", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }

    // MARK: - Components

    private var editingArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Original message preview
            if viewModel.hasChanges {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Original:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.top)
            }

            // Editor
            TextEditor(text: $viewModel.editedContent)
                .font(.body)
                .padding(8)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(viewModel.isContentTooLong ? Color.red : Color.clear, lineWidth: 2)
                )
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Warning if content too long
            if viewModel.isContentTooLong {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Message is too long")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal)
            }
        }
    }

    private var footer: some View {
        HStack {
            // Character count
            Text("\(viewModel.characterCount) / \(MessageEditManager.maxContentLength)")
                .font(.caption)
                .foregroundColor(viewModel.isContentTooLong ? .red : .secondary)

            Spacer()

            // Edit time remaining
            if let timeRemaining = viewModel.editTimeRemaining {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(timeRemaining)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

// MARK: - View Model

@MainActor
final class MessageEditViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var editedContent: String
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var editSucceeded = false

    // MARK: - Private Properties

    private let message: Message
    private let editManager: MessageEditManager
    private let currentUserId: String

    // MARK: - Computed Properties

    var characterCount: Int {
        editedContent.count
    }

    var isContentTooLong: Bool {
        characterCount > MessageEditManager.maxContentLength
    }

    var hasChanges: Bool {
        editedContent.trimmingCharacters(in: .whitespacesAndNewlines) !=
        message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        !editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isContentTooLong &&
        hasChanges
    }

    var editTimeRemaining: String? {
        let elapsed = Date().timeIntervalSince(message.createdAt)
        let remaining = MessageEditManager.editTimeoutSeconds - elapsed

        guard remaining > 0 else {
            return nil
        }

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Initialization

    init(
        message: Message,
        editManager: MessageEditManager,
        currentUserId: String
    ) {
        self.message = message
        self.editManager = editManager
        self.currentUserId = currentUserId
        self.editedContent = message.content
    }

    // MARK: - Actions

    func saveEdit() async {
        do {
            try await editManager.editMessage(
                messageId: message.id,
                threadId: message.threadId,
                newContent: editedContent,
                currentUserId: currentUserId
            )
            editSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Inline Edit Component

/// Inline message edit component (for quick edits)
struct InlineMessageEditView: View {

    @Binding var content: String
    @Binding var isEditing: Bool

    let onSave: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextEditor(text: $content)
                .font(.body)
                .padding(8)
                .frame(minHeight: 60)
                .background(Color(.systemGray6))
                .cornerRadius(8)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(.secondary)

                Spacer()

                Button("Save") {
                    Task {
                        await onSave()
                    }
                }
                .fontWeight(.semibold)
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}

// MARK: - Preview

#Preview("Edit Message") {
    MessageEditView(
        message: Message(
            threadId: UUID(),
            senderId: "user123",
            content: "This is a message that can be edited within 15 minutes of sending.",
            messageType: .text,
            status: .sent
        ),
        editManager: MessageEditManager(
            phoenixChannelManager: PhoenixChannelManager(
                config: PhoenixConfig(
                    socketURL: URL(string: "ws://localhost:4000/socket")!
                )
            ),
            databaseManager: DatabaseManager.shared,
            offlineQueueManager: OfflineQueueManager(databaseManager: DatabaseManager.shared)
        ),
        currentUserId: "user123",
        onSave: { newContent in
            print("Saving: \(newContent)")
        }
    )
}
