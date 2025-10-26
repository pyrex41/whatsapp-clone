//
//  DebugMenuView.swift
//  GlobalBridge
//
//  Developer menu to toggle notification modes at runtime.
//

import SwiftUI

struct DebugMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store<AppState, AppAction>
    @State private var selected: NotificationMode = NotificationConfig.runtimeOverride ?? NotificationConfig.current
    @State private var hasOverride: Bool = NotificationConfig.runtimeOverride != nil
    @State private var testThreadId: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var alertMessage: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Notification Mode")) {
                    Picker("Mode", selection: $selected) {
                        Text("Banner").tag(NotificationMode.banner)
                        Text("System").tag(NotificationMode.system)
                        Text("Auto").tag(NotificationMode.auto)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Effective mode")
                        Spacer()
                        Text(NotificationConfig.current.rawValue)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Override active")
                        Spacer()
                        Text(hasOverride ? "Yes" : "No")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Actions")) {
                    Button("Apply Override") {
                        NotificationConfig.setRuntimeOverride(selected)
                        hasOverride = true
                    }
                    Button("Use Default (Clear Override)") {
                        NotificationConfig.setRuntimeOverride(nil)
                        selected = NotificationConfig.current
                        hasOverride = false
                    }
                }

                #if DEBUG
                Section(header: Text("AI Testing")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Thread: \(store.state.currentThreadId ?? "None")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Test Thread ID (optional)", text: $testThreadId)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }

                    Button("Send Test AI Suggestion") {
                        sendTestAISuggestion()
                    }
                    .disabled(store.state.currentThreadId == nil && testThreadId.isEmpty)
                }
                #endif
            }
            .navigationTitle("Debug Menu")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("AI Test", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    #if DEBUG
    private func sendTestAISuggestion() {
        // Use custom thread ID if provided, otherwise use current thread
        let threadId = testThreadId.isEmpty ? (store.state.currentThreadId ?? "") : testThreadId

        guard !threadId.isEmpty else {
            alertMessage = "No thread ID available. Open a chat or enter a thread ID."
            showSuccessAlert = true
            return
        }

        Task { @MainActor in
            AIBroadcastCoordinator.shared.simulateProactiveSuggestion(threadId: threadId)
            alertMessage = "Test AI suggestion sent for thread:\n\(threadId)"
            showSuccessAlert = true
        }
    }
    #endif
}

#if DEBUG
#Preview {
    DebugMenuView()
}
#endif

