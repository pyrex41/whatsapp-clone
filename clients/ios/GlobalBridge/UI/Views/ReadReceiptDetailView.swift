//
//  ReadReceiptDetailView.swift
//  GlobalBridge
//
//  Detailed read receipt view showing who read the message and when
//  Includes real-time updates and participant avatars
//

import SwiftUI

/// Detailed view showing read receipt information for a message
public struct ReadReceiptDetailView: View {
    // MARK: - Properties

    let messageId: String

    @StateObject private var viewModel: ReadReceiptDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Initialization

    public init(messageId: String, manager: ReadReceiptManager? = nil) {
        self.messageId = messageId
        self._viewModel = StateObject(
            wrappedValue: ReadReceiptDetailViewModel(
                messageId: messageId,
                manager: manager ?? .shared
            )
        )
    }

    // MARK: - Body

    public var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationTitle("Read By")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadReadReceipts()
        }
        .onReceive(viewModel.$receipts) { _ in
            // Real-time updates trigger view refresh
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        List {
            // Summary section
            Section {
                summaryRow
            }

            // Read receipts
            if !viewModel.readReceipts.isEmpty {
                Section("Read") {
                    ForEach(viewModel.readReceipts, id: \.userId) { receipt in
                        ReadReceiptRow(receipt: receipt)
                    }
                }
            }

            // Delivered but not read
            if !viewModel.deliveredReceipts.isEmpty {
                Section("Delivered") {
                    ForEach(viewModel.deliveredReceipts, id: \.userId) { receipt in
                        DeliveredReceiptRow(receipt: receipt)
                    }
                }
            }

            // Not yet delivered
            if !viewModel.pendingReceipts.isEmpty {
                Section("Pending") {
                    ForEach(viewModel.pendingReceipts, id: \.userId) { participant in
                        PendingReceiptRow(participant: participant)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refreshReadReceipts()
        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(summaryText)
                    .font(.headline)

                if let timestamp = viewModel.mostRecentReadTimestamp {
                    Text("Last read \(formatTimestamp(timestamp))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            readStatusIcon
                .font(.title2)
        }
        .padding(.vertical, 8)
    }

    private var summaryText: String {
        let readCount = viewModel.readCount
        let totalCount = viewModel.totalParticipants - 1 // Exclude sender

        if readCount == 0 {
            return "Not yet read"
        } else if readCount == totalCount {
            return "Read by everyone"
        } else {
            return "Read by \(readCount) of \(totalCount)"
        }
    }

    private var readStatusIcon: some View {
        ZStack {
            if viewModel.readCount == viewModel.totalParticipants - 1 {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            } else if viewModel.readCount > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "clock.fill")
                    .foregroundColor(.secondary)
            }
        }
        .symbolRenderingMode(.hierarchical)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading read receipts...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Failed to load read receipts")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                Task {
                    await viewModel.loadReadReceipts()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "at " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "yesterday at " + formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE 'at' h:mm a"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d 'at' h:mm a"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Read Receipt Row

struct ReadReceiptRow: View {
    let receipt: ParticipantReadReceipt

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarBackgroundColor)
                    .frame(width: 44, height: 44)

                Text(receipt.userName.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundColor(.white)
            }

            // Name and timestamp
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.userName)
                    .font(.body)

                Text(formatReadTime(receipt.readAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Read indicator
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }

    private var avatarBackgroundColor: Color {
        // Simple color based on user ID hash
        let colors: [Color] = [.blue, .green, .purple, .orange, .pink, .red]
        let index = abs(receipt.userId.hashValue) % colors.count
        return colors[index]
    }

    private func formatReadTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Delivered Receipt Row

struct DeliveredReceiptRow: View {
    let receipt: ParticipantReadReceipt

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)

                Text(receipt.userName.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.userName)
                    .font(.body)

                Text("Delivered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Delivered indicator
            HStack(spacing: -4) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pending Receipt Row

struct PendingReceiptRow: View {
    let participant: ConversationParticipant

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(participant.name.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            // Name
            VStack(alignment: .leading, spacing: 4) {
                Text(participant.name)
                    .font(.body)
                    .foregroundColor(.secondary)

                Text("Not yet delivered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Pending indicator
            Image(systemName: "clock.fill")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Read Receipts") {
    ReadReceiptDetailView(messageId: "test-message-1")
}

#Preview("Loading") {
    struct LoadingPreview: View {
        var body: some View {
            ReadReceiptDetailView(messageId: "loading-test")
        }
    }

    return LoadingPreview()
}

#Preview("Dark Mode") {
    ReadReceiptDetailView(messageId: "test-message-1")
        .preferredColorScheme(.dark)
}
