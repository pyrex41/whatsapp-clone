//
//  ThreadSettingsView.swift
//  GlobalBridge
//
//  Thread settings view showing bridge configuration and status
//

import SwiftUI
import Observation
import Combine

/// Settings view for a thread, showing bridge configuration and status
struct ThreadSettingsView: View {
    @Bindable var phoenixState: PhoenixStateManager
    let threadId: String
    let currentUserId: String

    @State private var bridges: [String: Bridge] = [:]
    @State private var showingCreateBridge = false
    @State private var bridgeService: BridgeServiceProtocol = BridgeService()
    @State private var cancellables = Set<AnyCancellable>()

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
        // For now, return the first active bridge
        // In production, this should query the backend for thread-specific bridge
        return bridges.values.first { bridge in
            bridge.isActive && bridge.userId == currentUserId
        }
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
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var bridgeService: BridgeServiceProtocol = BridgeService()
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 8) {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }

            if bridge.isActive {
                Button(action: deactivateBridge) {
                    HStack {
                        if isUpdating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "pause.circle")
                                .foregroundColor(.orange)
                            Text("Deactivate Bridge")
                                .foregroundColor(.orange)
                        }
                    }
                }
                .disabled(isUpdating)
            } else {
                Button(action: activateBridge) {
                    HStack {
                        if isUpdating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "play.circle")
                                .foregroundColor(.green)
                            Text("Activate Bridge")
                                .foregroundColor(.green)
                        }
                    }
                }
                .disabled(isUpdating)
            }

            Button(action: { showingDeleteConfirmation = true }) {
                HStack {
                    Image(systemName: "trash.circle")
                        .foregroundColor(.red)
                    Text("Delete Bridge")
                        .foregroundColor(.red)
                }
            }
            .disabled(isUpdating)
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
        isUpdating = true
        errorMessage = nil

        bridgeService.updateBridgeStatus(id: bridge.id, isActive: true)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isUpdating = false
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to activate bridge: \(error.localizedDescription)"
                    }
                },
                receiveValue: { updatedBridge in
                    print("Bridge activated: \(updatedBridge.id)")
                }
            )
            .store(in: &cancellables)
    }

    private func deactivateBridge() {
        isUpdating = true
        errorMessage = nil

        bridgeService.updateBridgeStatus(id: bridge.id, isActive: false)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isUpdating = false
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to deactivate bridge: \(error.localizedDescription)"
                    }
                },
                receiveValue: { updatedBridge in
                    print("Bridge deactivated: \(updatedBridge.id)")
                }
            )
            .store(in: &cancellables)
    }

    private func deleteBridge() {
        isUpdating = true
        errorMessage = nil

        bridgeService.deleteBridge(id: bridge.id)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isUpdating = false
                    if case .failure(let error) = completion {
                        errorMessage = "Failed to delete bridge: \(error.localizedDescription)"
                    }
                },
                receiveValue: { _ in
                    print("Bridge deleted: \(bridge.id)")
                }
            )
            .store(in: &cancellables)
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
    @State private var errorMessage: String?
    @State private var bridgeService: BridgeServiceProtocol = BridgeService()
    @State private var cancellables = Set<AnyCancellable>()

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
                        .autocorrectionDisabled()

                    Text("Format: +1234567890")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button(action: createBridge) {
                        if isCreating {
                            HStack {
                                ProgressView()
                                Text("Creating...")
                            }
                        } else {
                            Text("Create Bridge")
                        }
                    }
                    .disabled(phoneNumber.isEmpty || isCreating || !isValidPhoneNumber)
                }
            }
            .navigationTitle("Set up Bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
        }
    }

    private var isValidPhoneNumber: Bool {
        // Basic validation: starts with + and has 10-15 digits
        let cleaned = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^\\+[1-9]\\d{9,14}$"
        return cleaned.range(of: pattern, options: .regularExpression) != nil
    }

    private func createBridge() {
        isCreating = true
        errorMessage = nil

        // Validate phone number format
        guard isValidPhoneNumber else {
            errorMessage = "Please enter a valid phone number (e.g., +1234567890)"
            isCreating = false
            return
        }

        bridgeService.createBridge(
            type: selectedBridgeType.rawValue,
            phoneNumber: phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [self] completion in
                isCreating = false
                if case .failure(let error) = completion {
                    if let bridgeError = error as? BridgeServiceError {
                        switch bridgeError {
                        case .unauthorized:
                            errorMessage = "Authentication failed. Please log in again."
                        case .validationError:
                            errorMessage = "Invalid phone number or bridge already exists."
                        case .networkError:
                            errorMessage = "Network error. Please check your connection."
                        case .notFound:
                            errorMessage = "Service not available."
                        case .decodingError:
                            errorMessage = "Failed to process server response."
                        }
                    } else {
                        errorMessage = "Failed to create bridge: \(error.localizedDescription)"
                    }
                }
            },
            receiveValue: { [self] newBridge in
                print("Bridge created successfully: \(newBridge.id)")
                dismiss()
            }
        )
        .store(in: &cancellables)
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