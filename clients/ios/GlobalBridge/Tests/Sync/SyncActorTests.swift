//
//  SyncActorTests.swift
//  GlobalBridge
//
//  Updated tests for SyncActor with CDC integration
//

import XCTest
@testable import GlobalBridge

@MainActor
final class SyncActorTests: XCTestCase {

    private var syncActor: SyncActor!
    private var databaseManager: DatabaseManager!
    private var phoenixManager: MockPhoenixManager!
    private var cdcManager: MockCDCManager!
    private var testThread: Thread!

    override func setUp() async throws {
        try await super.setUp()

        databaseManager = DatabaseManager.shared
        try await databaseManager.initialize()

        testThread = Thread(
            id: UUID(),
            threadType: .direct,
            title: "Test Thread",
            databaseShardId: "test-shard-\(UUID().uuidString)",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await databaseManager.createThread(testThread)

        phoenixManager = MockPhoenixManager()
        cdcManager = MockCDCManager()

        syncActor = SyncActor(
            phoenixManager: phoenixManager,
            databaseManager: databaseManager,
            cdcManager: cdcManager
        )
    }

    override func tearDown() async throws {
        await syncActor.stopMonitoring()
        try? await databaseManager.deleteThread(id: testThread.id)
        databaseManager.closeAllConnections()

        syncActor = nil
        phoenixManager = nil
        cdcManager = nil
        testThread = nil
        databaseManager = nil

        try await super.tearDown()
    }

    func testStartMonitoring_ShouldBeginWatchingConnectivity() async {
        await syncActor.startMonitoring()
        let isMonitoring = await syncActor.isMonitoring
        XCTAssertTrue(isMonitoring)
    }

    func testStopMonitoring_ShouldStopWatchingConnectivity() async {
        await syncActor.startMonitoring()
        await syncActor.stopMonitoring()
        let isMonitoring = await syncActor.isMonitoring
        XCTAssertFalse(isMonitoring)
    }

    func testTriggerSync_SuccessReturnsSummary() async {
        cdcManager.summaryToReturn = SyncSummary(pulledCount: 2, pushedCount: 1)

        let result = await syncActor.triggerSync(threadId: testThread.id)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.syncedCount, 3)
        XCTAssertNil(result.error)
        XCTAssertEqual(cdcManager.syncCallCount, 1)
        XCTAssertEqual(cdcManager.lastThreadID, testThread.id)
    }

    func testTriggerSync_WhenSyncFails_ShouldRetryAndReturnFailure() async {
        cdcManager.shouldThrow = true

        let result = await syncActor.triggerSync(threadId: testThread.id)

        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(cdcManager.syncCallCount, 6, "Should retry up to max attempts")
    }

    func testSyncAllThreads_ShouldInvokeSyncPerThread() async {
        let extraThread = Thread(
            id: UUID(),
            threadType: .group,
            title: "Extra",
            databaseShardId: "extra-shard-\(UUID().uuidString)",
            createdAt: Date(),
            updatedAt: Date()
        )
        try await databaseManager.createThread(extraThread)
        defer { try? await databaseManager.deleteThread(id: extraThread.id) }

        await syncActor.syncAllThreads()

        XCTAssertEqual(cdcManager.syncCallCount, 2)
        XCTAssertTrue([testThread.id, extraThread.id].contains(cdcManager.lastThreadID ?? UUID()))
    }
}

// MARK: - Test Doubles

final class MockPhoenixManager: PhoenixChannelManagerProtocol {
    var pulledLogs: [CDCLog] = []
    var pushedLogs: [[CDCLog]] = []
    var isConnected: Bool = true

    func pullCDCLogs(threadId: String, since: Date?) async throws -> [CDCLog] {
        pulledLogs
    }

    func pushCDCLogs(_ logs: [CDCLog], threadId: String) async throws {
        pushedLogs.append(logs)
    }

    func isNetworkAvailable() async -> Bool {
        isConnected
    }
}

final class MockCDCManager: CDCManaging {
    var summaryToReturn = SyncSummary(pulledCount: 0, pushedCount: 0)
    var shouldThrow = false
    private(set) var syncCallCount = 0
    private(set) var lastThreadID: UUID?

    func syncThread(_ threadId: UUID) async throws -> SyncSummary {
        syncCallCount += 1
        lastThreadID = threadId

        if shouldThrow {
            throw NSError(domain: "MockCDCManager", code: -1)
        }

        return summaryToReturn
    }
}
