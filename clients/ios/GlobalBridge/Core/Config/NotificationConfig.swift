//
//  NotificationConfig.swift
//  GlobalBridge
//
//  Centralized configuration for notification mode selection.
//

import Foundation

extension Notification.Name {
    static let notificationModeChanged = Notification.Name("notificationModeChanged")
    static let newThreadReceived = Notification.Name("newThreadReceived")
}

enum NotificationMode: String {
    case banner = "BANNER"
    case system = "SYSTEM"
    case auto   = "AUTO"
}

struct NotificationConfig {
    private static let overrideKey = "ios_notifications_mode_override"

    /// Optional runtime override stored in UserDefaults
    static var runtimeOverride: NotificationMode? {
        get {
            if let raw = UserDefaults.standard.string(forKey: overrideKey),
               let mode = NotificationMode(rawValue: raw) {
                return mode
            }
            return nil
        }
        set {
            if let mode = newValue {
                UserDefaults.standard.set(mode.rawValue, forKey: overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: overrideKey)
            }
            NotificationCenter.default.post(name: .notificationModeChanged, object: nil)
        }
    }
    static var current: NotificationMode {
        // 1) Runtime override takes precedence
        if let override = runtimeOverride { return override }

        // 2) Scheme environment variable
        if let raw = ProcessInfo.processInfo.environment["IOS_NOTIFICATIONS_MODE"],
           let mode = NotificationMode(rawValue: raw.uppercased()) {
            return mode
        }
        // 3) Compile-time defaults
        #if DEBUG
        return .banner
        #else
        return .system
        #endif
    }

    /// Update the runtime override (nil clears it)
    static func setRuntimeOverride(_ mode: NotificationMode?) {
        runtimeOverride = mode
    }
}
