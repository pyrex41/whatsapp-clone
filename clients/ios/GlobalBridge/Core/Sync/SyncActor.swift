//
//  SyncActor.swift
//  GlobalBridge
//
//  Task 16.2: Background sync actor with connectivity monitoring and retry logic
//

import Foundation

/// Result of a sync operation
struct SyncResult {
    let success: Bool
    let syncedCount: Int
    let failedCount: Int
    let batchSize: Int
    let error: String?
    let duration: TimeInterval
}

/// Actor for thread-safe background sync operations
actor SyncActor {

    // MARK: - Properties

    private let queueManager: OfflineQueueManager
    private let stateManager: PhoenixStateManager
    private let databaseManager: DatabaseManager

    private var isMonitoringConnectivity = false
    private var monitoringTask: Task<Void, Never>?
    private var syncTasks: [String: Task<SyncResult, Never>] = [:]

    // Retry configuration
    private let maxRetryAttempts = 5
    private let baseRetryDelay: TimeInterval = 1.0 // 1 second
    private let maxRetryDelay: TimeInterval = 60.0 // 60 seconds

    // Batch configuration
    private let batchSize = 100

    // MARK: - Initialization

    init(
        queueManager: OfflineQueueManager,
        stateManager: PhoenixStateManager,
        databaseManager: DatabaseManager
    ) {
        self.queueManager = queueManager
        self.stateManager = stateManager
        self.databaseManager = databaseManager
    }

    // MARK: - Public Interface

    /// Start monitoring network connectivity
    @MainActor
    func startMonitoring() {
        guard !isMonitoringConnectivity else { return }

        print("🔄 Starting connectivity monitoring...")
        isMonitoringConnectivity = true

        monitoringTask = Task {
            await self.monitorConnectivity()
        }
    }

    /// Stop monitoring network connectivity
    @MainActor
    func stopMonitoring() {
        print("⏹️ Stopping connectivity monitoring...")
        isMonitoringConnectivity = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Check if currently monitoring
    var isMonitoring: Bool {
        return isMonitoringConnectivity
    }

    /// Manually trigger sync for a shard
    /// - Parameter shardId: The database shard ID
    /// - Returns: Sync result
    func triggerSync(shardId: String) async -> SyncResult {
        print("🔄 Triggering sync for shard: \(shardId)")

        let startTime = Date()

        // Check if already syncing this shard
        if syncTasks[shardId] != nil {
            print("⚠️ Sync already in progress for shard: \(shardId)")
            return SyncResult(
                success: false,
                syncedCount: 0,
                failedCount: 0,
                batchSize: batchSize,
                error: "Sync already in progress",
                duration: 0
            )
        }

        // Create sync task
        let syncTask = Task {
            await self.performSync(shardId: shardId, attemptNumber: 0)
        }

        syncTasks[shardId] = syncTask

        let result = await syncTask.value

        syncTasks.removeValue(forKey: shardId)

        let duration = Date().timeIntervalSince(startTime)

        print("✅ Sync completed for shard: \(shardId) - Synced: \(result.syncedCount), Failed: \(result.failedCount), Duration: \(duration)s")

        return SyncResult(
            success: result.success,
            syncedCount: result.syncedCount,
            failedCount: result.failedCount,
            batchSize: batchSize,
            error: result.error,
            duration: duration
        )
    }

    /// Calculate retry delay with exponential backoff
    /// - Parameter attemptNumber: Current attempt number (0-based)
    /// - Returns: Delay in seconds
    func calculateRetryDelay(attemptNumber: Int) -> TimeInterval {
        let delay = baseRetryDelay * pow(2.0, Double(attemptNumber))
        return min(delay, maxRetryDelay)
    }

    // MARK: - Private Methods

    /// Monitor connectivity and trigger sync when online
    private func monitorConnectivity() async {
        print("👁️ Monitoring connectivity...")

        var wasConnected = false

        while !Task.isCancelled && isMonitoringConnectivity {
            let isConnected = await checkConnectivity()

            // Trigger sync when transitioning from offline to online
            if isConnected && !wasConnected {
                print("🌐 Connection restored - triggering sync...")
                await triggerSyncForAllShards()
            }

            wasConnected = isConnected

            // Check every 5 seconds
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }

        print("👁️ Connectivity monitoring stopped")
    }

    /// Check if device is connected
    /// - Returns: True if connected
    @MainActor
    private func checkConnectivity() async -> Bool {
        // Check Phoenix connection state
        let connectionState = stateManager.connectionState

        switch connectionState {
        case .connected:
            return true
        case .connecting, .disconnected, .error:
            return false
        }
    }

    /// Trigger sync for all shards
    private func triggerSyncForAllShards() async {
        // Get all shards with queued messages
        // In a real implementation, you would fetch all threads
        // and check their queue status

        print("🔄 Triggering sync for all shards...")

        // For now, we'll just log
        // In production, you would:
        // 1. Fetch all threads
        // 2. For each thread with queued messages, trigger sync
    }

    /// Perform sync operation with retry logic
    /// - Parameters:
    ///   - shardId: Database shard ID
    ///   - attemptNumber: Current attempt number
    /// - Returns: Sync result
    private func performSync(shardId: String, attemptNumber: Int) async -> SyncResult {
        print("📤 Performing sync for shard: \(shardId) (attempt \(attemptNumber + 1))")

        do {
            // Fetch queued messages in batches
            let queuedMessages = try await queueManager.getQueuedMessages(
                shardId: shardId,
                limit: batchSize
            )

            if queuedMessages.isEmpty {
                print("✅ No messages to sync for shard: \(shardId)")
                return SyncResult(
                    success: true,
                    syncedCount: 0,
                    failedCount: 0,
                    batchSize: batchSize,
                    error: nil,
                    duration: 0
                )
            }

            print("📦 Found \(queuedMessages.count) messages to sync")

            // Process messages in batch
            var syncedCount = 0
            var failedCount = 0

            for message in queuedMessages {
                do {
                    // Simulate sending message
                    // In real implementation, this would call CDCManager.push()
                    try await sendMessage(message)

                    // Mark as sent
                    try await queueManager.markMessageAsSent(
                        messageId: message.id,
                        shardId: shardId
                    )

                    syncedCount += 1

                    print("✅ Message synced: \(message.id)")
                } catch {
                    print("❌ Failed to sync message: \(message.id) - \(error)")
                    failedCount += 1
                }
            }

            let allSucceeded = failedCount == 0

            return SyncResult(
                success: allSucceeded,
                syncedCount: syncedCount,
                failedCount: failedCount,
                batchSize: batchSize,
                error: allSucceeded ? nil : "Some messages failed to sync",
                duration: 0
            )

        } catch {
            print("❌ Sync failed for shard: \(shardId) - \(error)")

            // Retry if not exceeded max attempts
            if attemptNumber < maxRetryAttempts {
                let delay = calculateRetryDelay(attemptNumber: attemptNumber)
                print("🔄 Retrying in \(delay) seconds...")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                return await performSync(shardId: shardId, attemptNumber: attemptNumber + 1)
            } else {
                print("❌ Max retry attempts reached for shard: \(shardId)")

                return SyncResult(
                    success: false,
                    syncedCount: 0,
                    failedCount: 0,
                    batchSize: batchSize,
                    error: error.localizedDescription,
                    duration: 0
                )
            }
        }
    }

    /// Send a message (simulated for now)
    /// - Parameter message: Message to send
    private func sendMessage(_ message: Message) async throws {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // In real implementation, this would:
        // 1. Call PhoenixChannelManager to send message
        // 2. Wait for acknowledgment
        // 3. Handle errors appropriately

        print("📤 Sending message: \(message.id)")
    }

    // MARK: - Cleanup

    deinit {
        monitoringTask?.cancel()
        for (_, task) in syncTasks {
            task.cancel()
        }
    }
}

// MARK: - Connection State Extension

extension PhoenixConnectionState {
    /// Whether the connection is established
    var isConnected: Bool {
        return self == .connected
    }

    /// Whether the connection is in an error state
    var isError: Bool {
        return self == .error
    }
}
