//
//  ThreadSettingsView.swift
//  GlobalBridge
//
//  Thread settings view showing bridge configuration and status
//

import SwiftUI
import Observation

/// Settings view for a thread, showing bridge configuration and status
struct ThreadSettingsView: View {
    @Bindable var phoenixState: PhoenixStateManager
    let threadId: String
    let currentUserId: String

    @State private var bridges: [String: Bridge] = [:]
    @State private var showingCreateBridge = false

    var body: some View {
        NavigationView {
            List {
                // Bridge Configuration Section
                Section(header: Text("Bridge Configuration")) {
                    if let bridge = activeBridge {
                        BridgeConfigurationRow(bridge: bridge)
                    } else {
                        Button(action: { showingCreateBridge = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Set up Bridge")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Bridge Status Section
                if let bridge = activeBridge {
                    Section(header: Text("Bridge Status")) {
                        BridgeStatusRow(bridge: bridge)
                    }

                    // Bridge Actions Section
                    Section(header: Text("Bridge Actions")) {
                        BridgeActionRow(bridge: bridge, phoenixState: phoenixState)
                    }
                }

                // Thread Information Section
                Section(header: Text("Thread Information")) {
                    HStack {
                        Text("Thread ID")
                        Spacer()
                        Text(threadId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Participants")
                        Spacer()
                        Text("\(participantCount)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Thread Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCreateBridge) {
                BridgeSetupView(phoenixState: phoenixState, threadId: threadId)
            }
        }
        .task {
            // Monitor bridge updates
            for await _ in Timer.publish(every: 2, on: .main, in: .common).autoconnect().values {
                let newBridges = await phoenixState.getBridges()
                if bridges != newBridges {
                    bridges = newBridges
                }
            }
        }
        .onAppear {
            Task {
                bridges = await phoenixState.getBridges()
            }
        }
    }

    private var activeBridge: Bridge? {
        // Find bridge associated with this thread
        // TODO: Implement proper thread-bridge association
        return bridges.values.first
    }

    private var participantCount: Int {
        let presences = phoenixState.getPresence(for: threadId)
        return presences.count + 1 // Including current user
    }
}

/// Bridge configuration row
struct BridgeConfigurationRow: View {
    let bridge: Bridge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: bridgeIcon)
                    .foregroundColor(bridgeColor)
                    .font(.title2)

                VStack(alignment: .leading) {
                    Text(bridgeTypeName)
                        .font(.headline)

                    if let phoneNumber = bridge.phoneNumber {
                        Text(phoneNumber)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                BridgeStatusBadge(status: bridge.status)
            }
        }
        .padding(.vertical, 4)
    }

    private var bridgeIcon: String {
        switch bridge.bridgeType {
        case .telegram:
            return "paperplane.fill"
        case .whatsapp:
            return "message.fill"
        }
    }

    private var bridgeColor: Color {
        switch bridge.bridgeType {
        case .telegram:
            return .blue
        case .whatsapp:
            return .green
        }
    }

    private var bridgeTypeName: String {
        switch bridge.bridgeType {
        case .telegram:
            return "Telegram Bridge"
        case .whatsapp:
            return "WhatsApp Bridge"
        }
    }
}

/// Bridge status row with detailed information
struct BridgeStatusRow: View {
    let bridge: Bridge

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status
            HStack {
                Text("Status")
                Spacer()
                BridgeStatusBadge(status: bridge.status)
            }

            // Last connected
            if let lastConnected = bridge.lastConnectedAt {
                HStack {
                    Text("Last Connected")
                    Spacer()
                    Text(formatDate(lastConnected))
                        .foregroundColor(.secondary)
                }
            }

            // Error message
            if let errorMessage = bridge.errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Error")
                        .foregroundColor(.red)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Bridge status badge
struct BridgeStatusBadge: View {
    let status: Bridge.Status

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.displayStatus)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(statusColor.opacity(0.1))
        )
    }

    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .disconnected:
            return .gray
        case .error:
            return .red
        case .connecting:
            return .orange
        }
    }
}

/// Bridge action row
struct BridgeActionRow: View {
    let bridge: Bridge
    @Bindable var phoenixState: PhoenixStateManager

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 8) {
            if bridge.isActive {
                Button(action: deactivateBridge) {
                    HStack {
                        Image(systemName: "pause.circle")
                            .foregroundColor(.orange)
                        Text("Deactivate Bridge")
                            .foregroundColor(.orange)
                    }
                }
            } else {
                Button(action: activateBridge) {
                    HStack {
                        Image(systemName: "play.circle")
                            .foregroundColor(.green)
                        Text("Activate Bridge")
                            .foregroundColor(.green)
                    }
                }
            }

            Button(action: { showingDeleteConfirmation = true }) {
                HStack {
                    Image(systemName: "trash.circle")
                        .foregroundColor(.red)
                    Text("Delete Bridge")
                        .foregroundColor(.red)
                }
            }
            .confirmationDialog(
                "Delete Bridge",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteBridge)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the bridge configuration. Messages will no longer be synced.")
            }
        }
    }

    private func activateBridge() {
        // TODO: Implement bridge activation
        print("Activating bridge \(bridge.id)")
    }

    private func deactivateBridge() {
        // TODO: Implement bridge deactivation
        print("Deactivating bridge \(bridge.id)")
    }

    private func deleteBridge() {
        // TODO: Implement bridge deletion
        print("Deleting bridge \(bridge.id)")
    }
}

/// Bridge setup view for creating new bridges
struct BridgeSetupView: View {
    @Bindable var phoenixState: PhoenixStateManager
    let threadId: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedBridgeType: Bridge.BridgeType = .telegram
    @State private var phoneNumber = ""
    @State private var isCreating = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Bridge Type")) {
                    Picker("Type", selection: $selectedBridgeType) {
                        Text("Telegram").tag(Bridge.BridgeType.telegram)
                        Text("WhatsApp").tag(Bridge.BridgeType.whatsapp)
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Configuration")) {
                    TextField("Phone Number", text: $phoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }

                Section {
                    Button(action: createBridge) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create Bridge")
                        }
                    }
                    .disabled(phoneNumber.isEmpty || isCreating)
                }
            }
            .navigationTitle("Set up Bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func createBridge() {
        isCreating = true

        Task {
            // TODO: Implement bridge creation API call
            print("Creating \(selectedBridgeType.rawValue) bridge for phone: \(phoneNumber)")

            // Simulate API delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            isCreating = false
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    ThreadSettingsView(
        phoenixState: PhoenixStateManager.preview,
        threadId: "thread123",
        currentUserId: "user1"
    )
}