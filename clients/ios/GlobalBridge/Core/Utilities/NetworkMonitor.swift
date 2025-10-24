//
//  NetworkMonitor.swift
//  GlobalBridge
//
//  Real-time network connectivity monitoring using Network framework
//  Provides accurate online/offline status for intelligent provider selection
//
//  Features:
//  - Real-time connectivity monitoring
//  - Network type detection (WiFi, Cellular, Wired)
//  - Observable state for SwiftUI integration
//  - Automatic reconnection detection
//  - Low overhead monitoring
//

import Foundation
import Network
import Combine

/// Monitor network connectivity status in real-time
@MainActor
final class NetworkMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    /// Whether device is connected to the internet
    @Published private(set) var isConnected = true

    /// Whether device is connected via expensive network (cellular)
    @Published private(set) var isExpensive = false

    /// Current network connection type
    @Published private(set) var connectionType: ConnectionType = .unknown

    // MARK: - Connection Type

    enum ConnectionType: String {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case wired = "Ethernet"
        case unknown = "Unknown"
    }

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.globalbridge.networkmonitor", qos: .utility)

    // MARK: - Initialization

    private init() {
        monitor = NWPathMonitor()
        startMonitoring()
        print("📡 [NETWORK_MONITOR] Network monitoring started")
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public Methods

    /// Check if network is available (synchronous check)
    var hasConnection: Bool {
        return isConnected
    }

    /// Check if on WiFi (preferred for large downloads)
    var isOnWiFi: Bool {
        return connectionType == .wifi
    }

    /// Check if on cellular (may want to avoid large downloads)
    var isOnCellular: Bool {
        return connectionType == .cellular
    }

    // MARK: - Private Methods

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self = self else { return }

                // Update connection status
                let wasConnected = self.isConnected
                self.isConnected = path.status == .satisfied

                // Log connection state changes
                if wasConnected != self.isConnected {
                    if self.isConnected {
                        print("✅ [NETWORK_MONITOR] Connected to network")
                    } else {
                        print("❌ [NETWORK_MONITOR] Disconnected from network")
                    }
                }

                // Update expense status
                self.isExpensive = path.isExpensive

                // Determine connection type
                if path.usesInterfaceType(.wifi) {
                    self.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionType = .wired
                } else {
                    self.connectionType = .unknown
                }

                // Log detailed status
                print("📊 [NETWORK_MONITOR] Status: \(self.isConnected ? "Online" : "Offline"), Type: \(self.connectionType.rawValue), Expensive: \(self.isExpensive)")
            }
        }

        monitor.start(queue: queue)
    }

    private func stopMonitoring() {
        monitor.cancel()
        print("🔌 [NETWORK_MONITOR] Network monitoring stopped")
    }
}

// MARK: - Testing Support

extension NetworkMonitor {
    /// Simulate offline mode for testing
    /// - Warning: Only use for testing/debugging
    func simulateOffline() {
        #if DEBUG
        isConnected = false
        connectionType = .unknown
        print("🧪 [NETWORK_MONITOR] Simulating offline mode (DEBUG only)")
        #endif
    }

    /// Restore real network monitoring
    /// - Warning: Only use for testing/debugging
    func restoreRealMonitoring() {
        #if DEBUG
        // Force path update by restarting monitor
        stopMonitoring()
        startMonitoring()
        print("🧪 [NETWORK_MONITOR] Restored real monitoring (DEBUG only)")
        #endif
    }
}
