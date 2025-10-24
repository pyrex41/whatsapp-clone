//
//  ReadReceiptSettingsView.swift
//  GlobalBridge
//
//  Settings view for read receipt privacy controls
//

import SwiftUI

/// Settings view for managing read receipt preferences
public struct ReadReceiptSettingsView: View {
    @StateObject private var manager = ReadReceiptManager.shared
    @State private var showingInfo = false

    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { manager.readReceiptsEnabled },
                    set: { manager.setReadReceiptsEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Read Receipts")
                            .font(.body)

                        Text("Let others see when you've read their messages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tint(.blue)
            } header: {
                Text("Privacy")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When read receipts are enabled:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Others can see when you read their messages", systemImage: "checkmark.circle")
                        Label("You can see when others read your messages", systemImage: "eye")
                        Label("Blue checkmarks indicate messages have been read", systemImage: "info.circle")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Section {
                Button {
                    showingInfo = true
                } label: {
                    HStack {
                        Label("About Read Receipts", systemImage: "info.circle")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Read Receipts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingInfo) {
            ReadReceiptInfoView()
        }
    }
}

/// Information view explaining read receipts
struct ReadReceiptInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)

                        Text("About Read Receipts")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom)

                    // Status indicators
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Status Indicators")
                            .font(.headline)

                        StatusIndicatorRow(
                            icon: "clock.fill",
                            color: .secondary,
                            title: "Sending",
                            description: "Your message is being sent"
                        )

                        StatusIndicatorRow(
                            icon: "checkmark",
                            color: .secondary,
                            title: "Sent",
                            description: "Message delivered to server"
                        )

                        StatusIndicatorRow(
                            icon: "checkmark",
                            color: .secondary,
                            title: "Delivered",
                            description: "Message delivered to recipient's device",
                            isDouble: true
                        )

                        StatusIndicatorRow(
                            icon: "checkmark",
                            color: .blue,
                            title: "Read",
                            description: "Recipient has opened and read your message",
                            isDouble: true
                        )
                    }

                    Divider()

                    // Privacy section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Privacy")
                            .font(.headline)

                        Text("When you disable read receipts:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("Others won't see when you read their messages")
                            BulletPoint("You won't see when others read your messages")
                            BulletPoint("You'll still see delivery confirmations")
                        }
                    }

                    Divider()

                    // Group chats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Group Chats")
                            .font(.headline)

                        Text("In group conversations, you'll see:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            BulletPoint("How many people have read your message")
                            BulletPoint("Tap the checkmark to see who read the message")
                            BulletPoint("Individual timestamps for each reader")
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Read Receipts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Helper Views

struct StatusIndicatorRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    var isDouble: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isDouble {
                    HStack(spacing: -4) {
                        Image(systemName: icon)
                        Image(systemName: icon)
                    }
                } else {
                    Image(systemName: icon)
                }
            }
            .font(.title3)
            .foregroundColor(color)
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(.secondary)
                .padding(.top, 6)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Settings") {
    NavigationView {
        ReadReceiptSettingsView()
    }
}

#Preview("Info View") {
    ReadReceiptInfoView()
}

#Preview("Dark Mode") {
    NavigationView {
        ReadReceiptSettingsView()
    }
    .preferredColorScheme(.dark)
}
