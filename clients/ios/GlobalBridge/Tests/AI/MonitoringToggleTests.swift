//
//  MonitoringToggleTests.swift
//  GlobalBridge
//
//  Task 26.5: Test Per-Thread Monitoring Toggle
//  Tests for toggle UI, reducer logic, AppState updates, and integration
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class MonitoringToggleTests: XCTestCase {

    // MARK: - Test Data

    let testThreadId = UUID()
    let testThreadIdString: String

    override init() {
        self.testThreadIdString = testThreadId.uuidString
        super.init()
    }

    // MARK: - Reducer Tests

    func testToggleMonitoringAddsThreadWhenNotMonitored() {
        // Given: A thread that is not monitored
        var state = AppState()
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString),
                      "Thread should not be monitored initially")

        // When: Toggle monitoring action is dispatched
        let action = AppAction.toggleMonitoring(threadId: testThreadIdString)
        _ = appReducer(state: &state, action: action)

        // Then: Thread is added to monitored set
        XCTAssertTrue(state.monitoredThreads.contains(testThreadIdString),
                     "Thread should be added to monitored set")
        XCTAssertEqual(state.monitoredThreads.count, 1,
                      "Monitored set should contain exactly one thread")
    }

    func testToggleMonitoringRemovesThreadWhenAlreadyMonitored() {
        // Given: A thread that is already monitored
        var state = AppState()
        state.monitoredThreads.insert(testThreadIdString)
        XCTAssertTrue(state.monitoredThreads.contains(testThreadIdString),
                     "Thread should be monitored initially")

        // When: Toggle monitoring action is dispatched
        let action = AppAction.toggleMonitoring(threadId: testThreadIdString)
        _ = appReducer(state: &state, action: action)

        // Then: Thread is removed from monitored set
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString),
                      "Thread should be removed from monitored set")
        XCTAssertEqual(state.monitoredThreads.count, 0,
                      "Monitored set should be empty")
    }

    func testToggleMonitoringIsIdempotent() {
        // Given: Empty monitored threads
        var state = AppState()

        // When: Toggle monitoring twice
        let action = AppAction.toggleMonitoring(threadId: testThreadIdString)
        _ = appReducer(state: &state, action: action)
        _ = appReducer(state: &state, action: action)

        // Then: Thread should not be monitored (toggled on, then off)
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString),
                      "Thread should be toggled back off")
        XCTAssertEqual(state.monitoredThreads.count, 0,
                      "Monitored set should be empty after two toggles")
    }

    func testToggleMonitoringDoesNotAffectOtherThreads() {
        // Given: Multiple threads, one monitored
        var state = AppState()
        let otherThreadId = UUID().uuidString
        state.monitoredThreads.insert(otherThreadId)

        // When: Toggle a different thread
        let action = AppAction.toggleMonitoring(threadId: testThreadIdString)
        _ = appReducer(state: &state, action: action)

        // Then: Both threads should be monitored
        XCTAssertTrue(state.monitoredThreads.contains(testThreadIdString),
                     "New thread should be monitored")
        XCTAssertTrue(state.monitoredThreads.contains(otherThreadId),
                     "Original thread should still be monitored")
        XCTAssertEqual(state.monitoredThreads.count, 2,
                      "Monitored set should contain both threads")
    }

    // MARK: - Start/Stop Monitoring Action Tests

    func testStartMonitoringAddsThread() {
        // Given: Empty monitored threads
        var state = AppState()

        // When: Start monitoring action is dispatched
        let action = AppAction.startMonitoring(threadId: testThreadIdString)
        _ = appReducer(state: &state, action: action)

        // Then: Thread is added to monitored set
        XCTAssertTrue(state.monitoredThreads.contains(testThreadIdString),
                     "Thread should be added to monitored set")
    }

    func testStopMonitoringRemovesThread() {
        // Given: A monitored thread
        var state = AppState()
        state.monitoredThreads.insert(testThreadIdString)

        // When: Stop monitoring action is dispatched
        let action = AppAction.stopMonitoring(threadId: testThreadIdString)
        _ = appReducer(state: &state, action: action)

        // Then: Thread is removed from monitored set
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString),
                      "Thread should be removed from monitored set")
    }

    // MARK: - AppState Persistence Tests

    func testMonitoredThreadsSetPersistsInState() {
        // Given: Multiple threads monitored
        var state = AppState()
        let thread1 = UUID().uuidString
        let thread2 = UUID().uuidString
        let thread3 = UUID().uuidString

        // When: Add multiple threads
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: thread1))
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: thread2))
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: thread3))

        // Then: All threads persist in state
        XCTAssertEqual(state.monitoredThreads.count, 3,
                      "All threads should be in monitored set")
        XCTAssertTrue(state.monitoredThreads.contains(thread1))
        XCTAssertTrue(state.monitoredThreads.contains(thread2))
        XCTAssertTrue(state.monitoredThreads.contains(thread3))
    }

    func testMonitoredThreadsSetIsMutable() {
        // Given: A monitored thread
        var state = AppState()
        state.monitoredThreads.insert(testThreadIdString)

        // When: Directly modify the set
        state.monitoredThreads.remove(testThreadIdString)

        // Then: Modification is reflected
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString),
                      "Direct modification should be reflected in state")
    }

    // MARK: - Integration Tests

    func testFullToggleFlow() {
        // Test the complete flow: not monitored -> monitored -> not monitored
        var state = AppState()

        // Initial state: not monitored
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString))

        // Toggle on
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: testThreadIdString))
        XCTAssertTrue(state.monitoredThreads.contains(testThreadIdString),
                     "Thread should be monitored after first toggle")

        // Toggle off
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: testThreadIdString))
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString),
                      "Thread should not be monitored after second toggle")
    }

    func testMultipleThreadsIndependentToggling() {
        // Test that multiple threads can be toggled independently
        var state = AppState()
        let thread1 = UUID().uuidString
        let thread2 = UUID().uuidString
        let thread3 = UUID().uuidString

        // Toggle thread1 on
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: thread1))
        XCTAssertTrue(state.monitoredThreads.contains(thread1))
        XCTAssertFalse(state.monitoredThreads.contains(thread2))
        XCTAssertFalse(state.monitoredThreads.contains(thread3))

        // Toggle thread2 on
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: thread2))
        XCTAssertTrue(state.monitoredThreads.contains(thread1))
        XCTAssertTrue(state.monitoredThreads.contains(thread2))
        XCTAssertFalse(state.monitoredThreads.contains(thread3))

        // Toggle thread1 off
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: thread1))
        XCTAssertFalse(state.monitoredThreads.contains(thread1))
        XCTAssertTrue(state.monitoredThreads.contains(thread2))
        XCTAssertFalse(state.monitoredThreads.contains(thread3))

        // Toggle thread3 on
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: thread3))
        XCTAssertFalse(state.monitoredThreads.contains(thread1))
        XCTAssertTrue(state.monitoredThreads.contains(thread2))
        XCTAssertTrue(state.monitoredThreads.contains(thread3))
    }

    // MARK: - Edge Cases

    func testToggleWithEmptyThreadId() {
        // Given: Empty thread ID
        var state = AppState()
        let emptyThreadId = ""

        // When: Toggle empty thread ID
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: emptyThreadId))

        // Then: Empty string is added to set (valid but unusual)
        XCTAssertTrue(state.monitoredThreads.contains(emptyThreadId),
                     "Empty thread ID should be allowed (edge case)")
    }

    func testToggleSameThreadMultipleTimes() {
        // Given: Empty state
        var state = AppState()

        // When: Toggle same thread 5 times
        for _ in 1...5 {
            _ = appReducer(state: &state, action: .toggleMonitoring(threadId: testThreadIdString))
        }

        // Then: Thread should not be monitored (5 toggles = on->off->on->off->on)
        // Wait, 5 toggles would be: off->on->off->on->off->on (starts at off)
        // 1: on, 2: off, 3: on, 4: off, 5: on
        XCTAssertTrue(state.monitoredThreads.contains(testThreadIdString),
                     "Thread should be monitored after odd number of toggles")

        // One more toggle to even it out
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: testThreadIdString))
        XCTAssertFalse(state.monitoredThreads.contains(testThreadIdString),
                      "Thread should not be monitored after even number of toggles")
    }

    // MARK: - UI State Binding Tests (Conceptual)

    func testMonitoringStateReflectsInUI() {
        // This is a conceptual test - actual UI testing would require ChatScreenTests
        // Here we verify the logic that the UI would use

        var state = AppState()
        let threadId = testThreadIdString

        // Simulate UI check: Is this thread monitored?
        var isMonitored = state.monitoredThreads.contains(threadId)
        XCTAssertFalse(isMonitored, "UI should show thread as not monitored")

        // Simulate user tapping toggle
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: threadId))

        // UI checks state again
        isMonitored = state.monitoredThreads.contains(threadId)
        XCTAssertTrue(isMonitored, "UI should show thread as monitored")

        // Simulate user tapping toggle again
        _ = appReducer(state: &state, action: .toggleMonitoring(threadId: threadId))

        // UI checks state again
        isMonitored = state.monitoredThreads.contains(threadId)
        XCTAssertFalse(isMonitored, "UI should show thread as not monitored again")
    }

    // MARK: - Performance Tests

    func testTogglePerformanceWithManyThreads() {
        // Test that toggle remains fast even with many monitored threads
        var state = AppState()

        // Add 100 threads
        for i in 1...100 {
            let threadId = "thread-\(i)"
            state.monitoredThreads.insert(threadId)
        }

        measure {
            // Toggle a specific thread 100 times
            for _ in 1...100 {
                _ = appReducer(state: &state, action: .toggleMonitoring(threadId: testThreadIdString))
            }
        }
    }
}
