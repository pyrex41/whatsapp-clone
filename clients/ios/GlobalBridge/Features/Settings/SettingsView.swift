//
//  SettingsView.swift
//  GlobalBridge
//
//  User settings including home language preferences
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store<AppState, AppAction>
    @State private var displayName: String = ""
    @State private var isEditingDisplayName: Bool = false
    @State private var isSavingDisplayName: Bool = false

    var body: some View {
        NavigationView {
            Form {
                // MARK: - Language Settings
                Section {
                    LanguageSettingRow(store: store)
                } header: {
                    Text("Language")
                } footer: {
                    Text("Your home language is used for smart reply suggestions and the app interface.")
                }

                // MARK: - Account
                Section("Account") {
                    let user = store.state.user

                    // Display Name Editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Enter your name", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isSavingDisplayName)

                            if isEditingDisplayName {
                                Button(action: saveDisplayName) {
                                    if isSavingDisplayName {
                                        ProgressView()
                                    } else {
                                        Text("Save")
                                            .bold()
                                    }
                                }
                                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingDisplayName)
                            }
                        }

                        Text("This name will be shown to other users in conversations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .onAppear {
                        displayName = user.displayName
                    }
                    .onChange(of: displayName) { oldValue, newValue in
                        isEditingDisplayName = newValue.trimmingCharacters(in: .whitespacesAndNewlines) != user.displayName
                    }

                    HStack {
                        Text("Email")
                        Spacer()
                        Text(user.email)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("User ID")
                        Spacer()
                        Text(user.id)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Notifications (from old debug menu)
                Section {
                    NotificationModeSettings()
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Control how notifications appear when the app is in use.")
                }

                #if DEBUG
                // MARK: - Developer Tools
                Section {
                    AITestingTools(store: store)
                } header: {
                    Text("Developer Tools")
                } footer: {
                    Text("Debug tools for testing AI features")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Actions

    private func saveDisplayName() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isSavingDisplayName = true

        Task {
            do {
                // Call backend to update display name
                try await updateDisplayNameOnBackend(trimmedName)

                // Update local state
                await MainActor.run {
                    store.send(.updateUserDisplayName(trimmedName))
                    isEditingDisplayName = false
                    isSavingDisplayName = false
                }
            } catch {
                await MainActor.run {
                    isSavingDisplayName = false
                    // Show error to user
                    print("❌ Failed to update display name: \(error)")
                }
            }
        }
    }

    private func updateDisplayNameOnBackend(_ newName: String) async throws {
        guard let phoenixManager = store.environment.phoenixManager else {
            throw NSError(domain: "Settings", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phoenix manager not available"])
        }

        try await phoenixManager.updateDisplayName(newName)
    }
}

// MARK: - Language Setting Row

struct LanguageSettingRow: View {
    @ObservedObject var store: Store<AppState, AppAction>
    @State private var showLanguagePicker = false

    private let supportedLanguages: [(code: String, name: String, flag: String)] = [
        ("en", "English", "🇺🇸"),
        ("es", "Spanish", "🇪🇸"),
        ("fr", "French", "🇫🇷"),
        ("de", "German", "🇩🇪"),
        ("it", "Italian", "🇮🇹"),
        ("pt", "Portuguese", "🇵🇹"),
        ("zh", "Chinese", "🇨🇳"),
        ("ja", "Japanese", "🇯🇵"),
        ("ko", "Korean", "🇰🇷"),
        ("ar", "Arabic", "🇸🇦"),
    ]

    private var currentLanguage: (code: String, name: String, flag: String) {
        supportedLanguages.first { $0.code == store.state.userLanguage } ?? supportedLanguages[0]
    }

    var body: some View {
        Button(action: {
            showLanguagePicker = true
        }) {
            HStack {
                Text("Home Language")
                    .foregroundColor(.primary)
                Spacer()
                Text("\(currentLanguage.flag) \(currentLanguage.name)")
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showLanguagePicker) {
            NavigationView {
                List {
                    ForEach(supportedLanguages, id: \.code) { language in
                        Button(action: {
                            store.send(.setUserLanguage(language.code))
                            showLanguagePicker = false
                        }) {
                            HStack {
                                Text(language.flag)
                                    .font(.title2)
                                Text(language.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if language.code == store.state.userLanguage {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Select Language")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showLanguagePicker = false }
                    }
                }
            }
        }
    }
}

// MARK: - Notification Mode Settings

struct NotificationModeSettings: View {
    @State private var selected: NotificationMode = NotificationConfig.runtimeOverride ?? NotificationConfig.current
    @State private var hasOverride: Bool = NotificationConfig.runtimeOverride != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: $selected) {
                Text("Banner").tag(NotificationMode.banner)
                Text("System").tag(NotificationMode.system)
                Text("Auto").tag(NotificationMode.auto)
            }
            .pickerStyle(.segmented)
            .onChange(of: selected) { _, newValue in
                NotificationConfig.setRuntimeOverride(newValue)
                hasOverride = true
            }

            HStack {
                Text("Effective mode")
                    .font(.caption)
                Spacer()
                Text(NotificationConfig.current.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if hasOverride {
                Button("Reset to Default") {
                    NotificationConfig.setRuntimeOverride(nil)
                    selected = NotificationConfig.current
                    hasOverride = false
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - AI Testing Tools (Debug Only)

#if DEBUG
struct AITestingTools: View {
    @ObservedObject var store: Store<AppState, AppAction>
    @State private var testThreadId: String = ""
    @State private var showSuccessAlert: Bool = false
    @State private var alertMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Thread: \(store.state.currentThreadId ?? "None")")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Test Thread ID (optional)", text: $testThreadId)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()

            Button("Send Test AI Suggestion") {
                sendTestAISuggestion()
            }
            .disabled(store.state.currentThreadId == nil && testThreadId.isEmpty)
        }
        .alert("AI Test", isPresented: $showSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func sendTestAISuggestion() {
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
}
#endif

// MARK: - Previews

#Preview {
    SettingsView(
        store: Store(
            initialState: AppState(),
            reducer: appReducer,
            environment: .preview
        )
    )
}
