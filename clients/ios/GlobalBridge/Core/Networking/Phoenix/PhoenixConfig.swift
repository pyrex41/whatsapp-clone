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
        socketURL: URL(string: "wss://globalbridge.fly.dev/socket")!,  // UPDATE THIS after deploying
        authToken: nil,
        connectionTimeout: 10,
        heartbeatInterval: 30,
        maxReconnectAttempts: 10,
        reconnectDelay: 5,
        enableLogging: false
    )
    
    /// Current active configuration (change this to switch environments)
    public static var current: PhoenixConfig {
        return .production   // Production (wss://your-app.fly.dev)
        #if DEBUG
        return .development  // Local development (ws://localhost:4000)
        #else
        return .production  // Production (wss://globalbridge.fly.dev)
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
