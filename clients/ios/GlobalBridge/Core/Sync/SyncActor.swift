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

/// Summary returned from CDC Manager sync operations
struct SyncSummary {
    let pulledCount: Int
    let pushedCount: Int

    var totalChanges: Int { pulledCount + pushedCount }
}

/// Actor for thread-safe background sync operations
actor SyncActor {

    // MARK: - Properties

    private let phoenixManager: PhoenixChannelManagerProtocol
    private let databaseManager: DatabaseManager
    private let cdcManager: CDCManaging

    private var monitoringTask: Task<Void, Never>?
    private var syncTasks: [UUID: Task<SyncResult, Never>] = [:]

    // Retry configuration
    private let maxRetryAttempts = 5
    private let baseRetryDelay: TimeInterval = 1.0 // 1 second
    private let maxRetryDelay: TimeInterval = 60.0 // 60 seconds

    // Batch configuration (retained for logging purposes)
    private let batchSize = 100

    private var _isMonitoringConnectivity = false

    // MARK: - Initialization

    init(
        phoenixManager: PhoenixChannelManagerProtocol,
        databaseManager: DatabaseManager,
        cdcManager: CDCManaging
    ) {
        self.phoenixManager = phoenixManager
        self.databaseManager = databaseManager
        self.cdcManager = cdcManager
    }

    // MARK: - Public Interface

    /// Start monitoring network connectivity
    func startMonitoring() {
        guard !isMonitoringConnectivity else { return }

        print("🔄 Starting connectivity monitoring...")
        isMonitoringConnectivity = true

        monitoringTask = Task { [weak self] in
            await self?.monitorConnectivity()
        }
    }

    /// Stop monitoring network connectivity
    func stopMonitoring() {
        print("⏹️ Stopping connectivity monitoring...")
        isMonitoringConnectivity = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Check if currently monitoring (nonisolated accessor)
    nonisolated var isMonitoring: Bool {
        get async { await isMonitoringConnectivity }
    }

    /// Manually trigger sync for a specific thread
    /// - Parameter threadId: The thread identifier
    /// - Returns: Sync result metadata
    func triggerSync(threadId: UUID) async -> SyncResult {
        let shardLabel = threadId.uuidString
        print("🔄 Triggering sync for thread: \(shardLabel)")

        let startTime = Date()

        // Avoid launching duplicate sync tasks for same thread
        if syncTasks[threadId] != nil {
            print("⚠️ Sync already in progress for thread: \(shardLabel)")
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
        let syncTask = Task { [weak self] in
            await self?.performSync(threadId: threadId, attemptNumber: 0) ?? SyncResult(
                success: false,
                syncedCount: 0,
                failedCount: 0,
                batchSize: self?.batchSize ?? 0,
                error: "Sync actor not available",
                duration: 0
            )
        }

        syncTasks[threadId] = syncTask

        let result = await syncTask.value

        syncTasks.removeValue(forKey: threadId)

        let duration = Date().timeIntervalSince(startTime)

        print("✅ Sync completed for thread: \(shardLabel) - Synced: \(result.syncedCount), Failed: \(result.failedCount), Duration: \(duration)s")

        return SyncResult(
            success: result.success,
            syncedCount: result.syncedCount,
            failedCount: result.failedCount,
            batchSize: batchSize,
            error: result.error,
            duration: duration
        )
    }

    /// Trigger sync across all known threads
    func syncAllThreads() async {
        do {
            let threads = try await databaseManager.fetchThreads()

            guard threads.isEmpty == false else {
                print("ℹ️ No threads available for initial sync")
                return
            }

            for thread in threads {
                _ = await triggerSync(threadId: thread.id)
            }
        } catch {
            print("❌ Failed to fetch threads for bulk sync: \(error.localizedDescription)")
        }
    }

    /// Calculate retry delay with exponential backoff
    func calculateRetryDelay(attemptNumber: Int) -> TimeInterval {
        let delay = baseRetryDelay * pow(2.0, Double(attemptNumber))
        return min(delay, maxRetryDelay)
    }

    // MARK: - Private Methods

    private var isMonitoringConnectivity: Bool {
        get { _isMonitoringConnectivity }
        set { _isMonitoringConnectivity = newValue }
    }

    /// Monitor connectivity and trigger sync when online
    private func monitorConnectivity() async {
        print("👁️ Monitoring connectivity...")

        var wasConnected = false

        while !Task.isCancelled && isMonitoringConnectivity {
            let isConnected = await checkConnectivity()

            if isConnected && !wasConnected {
                print("🌐 Connection restored - triggering sync for all threads...")
                await syncAllThreads()
            }

            wasConnected = isConnected

            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }

        print("👁️ Connectivity monitoring stopped")
    }

    /// Evaluate current connectivity status via Phoenix manager
    nonisolated private func checkConnectivity() async -> Bool {
        await phoenixManager.isNetworkAvailable()
    }

    /// Perform sync operation with retry logic
    private func performSync(threadId: UUID, attemptNumber: Int) async -> SyncResult {
        do {
            guard let _ = try await databaseManager.fetchThread(id: threadId) else {
                print("⚠️ Thread not found locally for sync: \(threadId.uuidString)")
                return SyncResult(
                    success: false,
                    syncedCount: 0,
                    failedCount: 0,
                    batchSize: batchSize,
                    error: "Thread not found",
                    duration: 0
                )
            }

            let summary = try await cdcManager.syncThread(threadId)

            let totalSynced = summary.pulledCount + summary.pushedCount
            
            return SyncResult(
                success: true,
                syncedCount: totalSynced,
                failedCount: 0,
                batchSize: batchSize,
                error: nil,
                duration: 0
            )
        } catch {
            print("❌ Sync failed for thread: \(threadId.uuidString) - \(error.localizedDescription)")

            if attemptNumber < maxRetryAttempts {
                let delay = calculateRetryDelay(attemptNumber: attemptNumber)
                print("🔄 Retrying thread \(threadId.uuidString) in \(delay) seconds (attempt \(attemptNumber + 2))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return await performSync(threadId: threadId, attemptNumber: attemptNumber + 1)
            } else {
                print("❌ Max retry attempts reached for thread: \(threadId.uuidString)")
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

    // MARK: - Cleanup

    deinit {
        monitoringTask?.cancel()
        for (_, task) in syncTasks {
            task.cancel()
        }
    }
}
