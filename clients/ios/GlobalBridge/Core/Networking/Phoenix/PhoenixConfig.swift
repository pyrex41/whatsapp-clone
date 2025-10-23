//
//  PhoenixConfig.swift
//  GlobalBridge
//
//  Phoenix Channel Configuration
//

import Foundation

/// Configuration for Phoenix Channel connections
public struct PhoenixConfig: Sendable {
    /// WebSocket URL for Phoenix server
    let socketURL: URL

    /// Authentication token for secure connections
    let authToken: String?

    /// Connection timeout in seconds
    let connectionTimeout: TimeInterval

    /// Heartbeat interval in seconds
    let heartbeatInterval: TimeInterval

    /// Maximum reconnection attempts
    let maxReconnectAttempts: Int

    /// Reconnection delay in seconds
    let reconnectDelay: TimeInterval

    /// Enable debug logging
    let enableLogging: Bool

    /// Default configuration for development
    public static let development = PhoenixConfig(
        socketURL: URL(string: "ws://localhost:4000/socket")!,
        authToken: nil,
        connectionTimeout: 10,
        heartbeatInterval: 30,
        maxReconnectAttempts: 5,
        reconnectDelay: 2,
        enableLogging: true
    )

    /// Default configuration for production (Fly.io)
    public static let production = PhoenixConfig(
        socketURL: URL(string: "wss://globalbridge-backend.fly.dev/socket")!,
        authToken: nil,
        connectionTimeout: 10,
        heartbeatInterval: 30,
        maxReconnectAttempts: 10,
        reconnectDelay: 5,
        enableLogging: false
    )

    /// Current active configuration - automatically selects based on environment
    /// Set BACKEND_ENV=production in Xcode scheme to use production backend
    /// Defaults to development (localhost) for Debug builds
    public static var current: PhoenixConfig {
        // Check environment variable first
        if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"] {
            if backendEnv.lowercased() == "production" {
                print("🌐 [PhoenixConfig] Using PRODUCTION backend: globalbridge-backend.fly.dev")
                return .production
            }
        }

        // Default to development for Debug builds, production for Release
        #if DEBUG
        print("🏠 [PhoenixConfig] Using LOCAL backend: localhost:4000")
        return .development
        #else
        print("🌐 [PhoenixConfig] Using PRODUCTION backend: globalbridge-backend.fly.dev")
        return .production
        #endif
    }

    public init(
        socketURL: URL,
        authToken: String? = nil,
        connectionTimeout: TimeInterval = 10,
        heartbeatInterval: TimeInterval = 30,
        maxReconnectAttempts: Int = 5,
        reconnectDelay: TimeInterval = 2,
        enableLogging: Bool = false
    ) {
        self.socketURL = socketURL
        self.authToken = authToken
        self.connectionTimeout = connectionTimeout
        self.heartbeatInterval = heartbeatInterval
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelay = reconnectDelay
        self.enableLogging = enableLogging
    }
}
