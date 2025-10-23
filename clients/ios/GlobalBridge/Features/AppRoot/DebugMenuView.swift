//
//  DebugMenuView.swift
//  GlobalBridge
//
//  Developer menu to toggle notification modes at runtime.
//

import SwiftUI

struct DebugMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: NotificationMode = NotificationConfig.runtimeOverride ?? NotificationConfig.current
    @State private var hasOverride: Bool = NotificationConfig.runtimeOverride != nil

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
            }
            .navigationTitle("Debug Menu")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    DebugMenuView()
}
#endif

