//
//  ConversationMonitorService.swift
//  GlobalBridge
//
//  Manages real-time AI monitoring of conversations for proactive suggestions
//  Coordinates with PhoenixChannelManager for live broadcasts
//

import Foundation
import Combine

/// Service for managing AI conversation monitoring and real-time suggestions
@MainActor
final class ConversationMonitorService: ObservableObject {

    // MARK: - Singleton

    static let shared = ConversationMonitorService()

    // MARK: - Published Properties

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: AIServiceError?
    @Published private(set) var monitoredThreads: Set<UUID> = []

    // MARK: - Dependencies

    private let session: URLSession
    private let authManager: AuthManager
    private let baseURL: URL

    // MARK: - Configuration

    private let requestTimeout: TimeInterval = 30.0
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0

    // MARK: - Initialization

    init(
        session: URLSession = .shared,
        authManager: AuthManager = .shared,
        baseURL: URL? = nil
    ) {
        self.session = session
        self.authManager = authManager

        // Determine base URL based on environment
        if let providedURL = baseURL {
            self.baseURL = providedURL
        } else {
            #if DEBUG
            // Check for local development override
            if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"],
               backendEnv.lowercased() == "local" {
                self.baseURL = URL(string: "http://localhost:4000")!
            } else {
                self.baseURL = URL(string: "https://globalbridge-backend.fly.dev")!
            }
            #else
            self.baseURL = URL(string: "https://globalbridge-backend.fly.dev")!
            #endif
        }

        print("👁️  [CONVERSATION_MONITOR_SERVICE] Initialized with base URL: \(self.baseURL.absoluteString)")
    }

    // MARK: - Public Methods

    /// Start AI monitoring for a thread
    /// - Parameter threadId: Thread UUID to start monitoring
    /// - Throws: AIServiceError for various failure cases
    /// - Note: Notifies PhoenixChannelManager to subscribe to real-time broadcasts
    func startMonitoring(threadId: UUID) async throws {
        // Check if already monitoring
        if monitoredThreads.contains(threadId) {
            print("⚠️  [CONVERSATION_MONITOR_SERVICE] Thread already being monitored: \(threadId)")
            return
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/monitor/start")
        let requestBody: [String: Any] = [
            "thread_id": threadId.uuidString
        ]

        print("👁️  [CONVERSATION_MONITOR_SERVICE] Starting monitoring for thread: \(threadId)")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct MonitorResponse: Decodable {
            let success: Bool
            let monitoring: Bool
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(MonitorResponse.self, from: responseData)

        guard response.success && response.monitoring else {
            throw AIServiceError.backendError(message: "Failed to start monitoring")
        }

        // Add to monitored threads set
        _ = await MainActor.run {
            monitoredThreads.insert(threadId)
        }

        // Notify PhoenixChannelManager to subscribe to real-time broadcasts
        // The actual WebSocket subscription will be handled by PhoenixChannelManager
        NotificationCenter.default.post(
            name: NSNotification.Name("AIMonitoringStarted"),
            object: nil,
            userInfo: ["threadId": threadId]
        )

        print("✅ [CONVERSATION_MONITOR_SERVICE] Monitoring started for thread: \(threadId)")
    }

    /// Stop AI monitoring for a thread
    /// - Parameter threadId: Thread UUID to stop monitoring
    /// - Throws: AIServiceError for various failure cases
    /// - Note: Notifies PhoenixChannelManager to unsubscribe from real-time broadcasts
    func stopMonitoring(threadId: UUID) async throws {
        // Check if actually monitoring
        guard monitoredThreads.contains(threadId) else {
            print("⚠️  [CONVERSATION_MONITOR_SERVICE] Thread not being monitored: \(threadId)")
            return
        }

        await setProcessing(true)
        defer { Task { await setProcessing(false) } }

        let endpoint = baseURL.appendingPathComponent("api/v1/ai/monitor/stop")
        let requestBody: [String: Any] = [
            "thread_id": threadId.uuidString
        ]

        print("👁️  [CONVERSATION_MONITOR_SERVICE] Stopping monitoring for thread: \(threadId)")

        let responseData = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: requestBody
        )

        // Parse response
        struct MonitorResponse: Decodable {
            let success: Bool
            let monitoring: Bool
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(MonitorResponse.self, from: responseData)

        guard response.success && !response.monitoring else {
            throw AIServiceError.backendError(message: "Failed to stop monitoring")
        }

        // Remove from monitored threads set
        _ = await MainActor.run {
            monitoredThreads.remove(threadId)
        }

        // Notify PhoenixChannelManager to unsubscribe from real-time broadcasts
        NotificationCenter.default.post(
            name: NSNotification.Name("AIMonitoringStopped"),
            object: nil,
            userInfo: ["threadId": threadId]
        )

        print("✅ [CONVERSATION_MONITOR_SERVICE] Monitoring stopped for thread: \(threadId)")
    }

    /// Check if a thread is currently being monitored
    /// - Parameter threadId: Thread UUID to check
    /// - Returns: True if the thread is being monitored, false otherwise
    func isMonitoring(threadId: UUID) -> Bool {
        return monitoredThreads.contains(threadId)
    }

    /// Stop monitoring all threads
    /// - Throws: AIServiceError for various failure cases
    func stopAllMonitoring() async throws {
        let threadsToStop = Array(monitoredThreads)

        print("👁️  [CONVERSATION_MONITOR_SERVICE] Stopping monitoring for \(threadsToStop.count) threads")

        // Stop monitoring for each thread
        for threadId in threadsToStop {
            do {
                try await stopMonitoring(threadId: threadId)
            } catch {
                print("⚠️  [CONVERSATION_MONITOR_SERVICE] Failed to stop monitoring for thread: \(threadId) - \(error)")
                // Continue with other threads even if one fails
            }
        }

        print("✅ [CONVERSATION_MONITOR_SERVICE] All monitoring stopped")
    }

    // MARK: - Private HTTP Methods

    /// Perform HTTP request with authentication and retry logic
    private func performRequest(
        endpoint: URL,
        method: String,
        body: [String: Any]? = nil,
        attempt: Int = 1
    ) async throws -> Data {
        // Get authentication token
        guard let token = await authManager.getAccessToken() else {
            print("❌ [CONVERSATION_MONITOR_SERVICE] No authentication token available")
            throw AIServiceError.unauthorized
        }

        // Build request
        var request = URLRequest(url: endpoint, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add body if present
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw AIServiceError.decodingError(error)
            }
        }

        // Perform request
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }

            print("📡 [CONVERSATION_MONITOR_SERVICE] Response status: \(httpResponse.statusCode)")

            // Handle different status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success
                return data

            case 401:
                // Unauthorized - token may be expired
                print("⚠️  [CONVERSATION_MONITOR_SERVICE] Unauthorized (401) - attempting token refresh")
                throw AIServiceError.unauthorized

            case 403:
                // Forbidden - likely feature not available for tier
                throw AIServiceError.forbidden

            case 429:
                // Rate limit exceeded
                print("⚠️  [CONVERSATION_MONITOR_SERVICE] Rate limit exceeded (429)")

                // Parse rate limit headers
                let resetTime = parseRateLimitReset(from: httpResponse)

                // Retry after delay if we haven't exceeded max retries
                if attempt < maxRetries {
                    let delay = resetTime ?? retryDelay * Double(attempt)
                    print("🔄 [CONVERSATION_MONITOR_SERVICE] Retrying after \(delay) seconds (attempt \(attempt + 1)/\(maxRetries))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
                } else {
                    // Convert TimeInterval (seconds from now) to Date
                    let retryAfterDate = resetTime.map { Date().addingTimeInterval($0) }
                    throw AIServiceError.rateLimitExceeded(retryAfter: retryAfterDate, remainingQuota: nil, tierLimit: nil)
                }

            case 400...499:
                // Client error
                let errorMessage = parseErrorMessage(from: data)
                throw AIServiceError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)

            case 500...599:
                // Server error - retry with exponential backoff
                if attempt < maxRetries {
                    let delay = retryDelay * Double(attempt)
                    print("🔄 [CONVERSATION_MONITOR_SERVICE] Server error (\(httpResponse.statusCode)) - retrying after \(delay) seconds")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
                } else {
                    throw AIServiceError.backendError(message: "Server error")
                }

            default:
                throw AIServiceError.httpError(statusCode: httpResponse.statusCode, message: "Unexpected status code")
            }

        } catch let error as AIServiceError {
            // Re-throw AIService errors
            throw error
        } catch {
            // Network or other errors
            print("❌ [CONVERSATION_MONITOR_SERVICE] Network error: \(error.localizedDescription)")

            // Retry on network errors
            if attempt < maxRetries {
                let delay = retryDelay * Double(attempt)
                print("🔄 [CONVERSATION_MONITOR_SERVICE] Network error - retrying after \(delay) seconds")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequest(endpoint: endpoint, method: method, body: body, attempt: attempt + 1)
            } else {
                throw AIServiceError.networkError(error)
            }
        }
    }

    /// Parse rate limit reset time from response headers
    private func parseRateLimitReset(from response: HTTPURLResponse) -> TimeInterval? {
        // Check for X-RateLimit-Reset header (Unix timestamp)
        if let resetHeader = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = TimeInterval(resetHeader) {
            let resetDate = Date(timeIntervalSince1970: resetTimestamp)
            let delay = resetDate.timeIntervalSinceNow
            return max(0, delay)
        }

        // Check for Retry-After header (seconds)
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
           let delay = TimeInterval(retryAfter) {
            return delay
        }

        return nil
    }

    /// Parse error message from response data
    private func parseErrorMessage(from data: Data) -> String {
        struct ErrorResponse: Decodable {
            let message: String?
            let error: String?
        }

        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            return "Unknown error"
        }

        return response.message ?? response.error ?? "Unknown error"
    }

    // MARK: - State Management

    private func setProcessing(_ value: Bool) async {
        await MainActor.run {
            self.isProcessing = value
        }
    }

    /// Clear last error
    func clearError() {
        lastError = nil
    }
}
