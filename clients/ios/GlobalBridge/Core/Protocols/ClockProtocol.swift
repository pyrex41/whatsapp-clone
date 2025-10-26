//
//  ClockProtocol.swift
//  GlobalBridge
//
//  Task 31: E2E Test Smart Reply MVP
//  Protocol for injecting time dependencies to enable deterministic testing
//

import Foundation

/// Protocol for providing current time, enabling time-based testing
protocol ClockProtocol {
    /// Returns the current date and time
    func now() -> Date
}

/// Production implementation using system time
final class SystemClock: ClockProtocol {
    static let shared = SystemClock()

    private init() {}

    func now() -> Date {
        return Date()
    }
}

/// Test implementation with manually controlled time
final class MockClock: ClockProtocol {
    private var currentTime: Date

    init(startTime: Date = Date()) {
        self.currentTime = startTime
    }

    func now() -> Date {
        return currentTime
    }

    /// Advance the clock by a given time interval
    func advance(by interval: TimeInterval) {
        currentTime = currentTime.addingTimeInterval(interval)
    }

    /// Set the clock to a specific time
    func set(to date: Date) {
        currentTime = date
    }

    /// Reset the clock to current system time
    func reset() {
        currentTime = Date()
    }
}
