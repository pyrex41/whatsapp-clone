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

    /// Default configuration for production (Fly.io deployment)
    public static let production = PhoenixConfig(
        socketURL: URL(string: "wss://globalbridge-backend.fly.dev/socket")!,
        authToken: nil,
        connectionTimeout: 10,
        heartbeatInterval: 30,
        maxReconnectAttempts: 10,
        reconnectDelay: 5,
        enableLogging: false
    )
    
    /// Current active configuration (change this to switch environments)
    /// Checks BACKEND_ENV environment variable first:
    /// - "local" or "dev" → localhost
    /// - "production" or "prod" → Fly.io
    /// Falls back to DEBUG build config if not set
    public static var current: PhoenixConfig {
        // Check environment variable first
        if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"] {
            switch backendEnv.lowercased() {
            case "local", "dev", "development":
                return .development
            case "production", "prod":
                return .production
            default:
                print("⚠️ [PhoenixConfig] Unknown BACKEND_ENV value: \(backendEnv), using build default")
            }
        }
        
        // Fall back to build configuration
        #if DEBUG
        return .production  // Use production for simulator (set BACKEND_ENV=local for local dev)
        #else
        return .production  // Production (wss://globalbridge-backend.fly.dev)
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
