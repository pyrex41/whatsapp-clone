//
//  BridgeService.swift
//  GlobalBridge
//
//  Created by GlobalBridge on 10/24/25.
//  REST API client for bridge management
//

import Foundation
import Combine

/// Protocol for bridge API operations
protocol BridgeServiceProtocol {
    func getBridges() -> AnyPublisher<[Bridge], Error>
    func createBridge(type: String, phoneNumber: String) -> AnyPublisher<Bridge, Error>
    func updateBridgeStatus(id: String, isActive: Bool) -> AnyPublisher<Bridge, Error>
    func deleteBridge(id: String) -> AnyPublisher<Void, Error>
    func getBridgeForThread(threadId: String, bridgeType: String) -> AnyPublisher<Bridge?, Error>
}

/// REST API client for bridge management
class BridgeService: BridgeServiceProtocol {
    private let baseURL: URL
    private let session: URLSession
    private let authManager: AuthManager

    // Retry configuration
    private let maxRetries: Int
    private let initialRetryDelay: TimeInterval

    init(baseURL: URL = URL(string: "https://api.globalbridge.com")!,
         session: URLSession = .shared,
         authManager: AuthManager = .shared,
         maxRetries: Int = 3,
         initialRetryDelay: TimeInterval = 1.0) {
        self.baseURL = baseURL
        self.session = session
        self.authManager = authManager
        self.maxRetries = maxRetries
        self.initialRetryDelay = initialRetryDelay
    }

    func getBridges() -> AnyPublisher<[Bridge], Error> {
        guard let token = authManager.getAccessToken() else {
            return Fail(error: BridgeServiceError.unauthorized).eraseToAnyPublisher()
        }

        let url = baseURL.appendingPathComponent("v1/bridges")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return session.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: BridgeResponse.self, decoder: JSONDecoder())
            .map(\.bridges)
            .retryWithExponentialBackoff(maxRetries: maxRetries, initialDelay: initialRetryDelay)
            .eraseToAnyPublisher()
    }

    func createBridge(type: String, phoneNumber: String) -> AnyPublisher<Bridge, Error> {
        guard let token = authManager.getAccessToken() else {
            return Fail(error: BridgeServiceError.unauthorized).eraseToAnyPublisher()
        }

        let url = baseURL.appendingPathComponent("v1/bridges")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateBridgeRequest(bridgeType: type, phoneNumber: phoneNumber)
        request.httpBody = try? JSONEncoder().encode(body)

        return session.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: CreateBridgeResponse.self, decoder: JSONDecoder())
            .map(\.bridge)
            .retryWithExponentialBackoff(maxRetries: maxRetries, initialDelay: initialRetryDelay)
            .eraseToAnyPublisher()
    }

    func updateBridgeStatus(id: String, isActive: Bool) -> AnyPublisher<Bridge, Error> {
        guard let token = authManager.getAccessToken() else {
            return Fail(error: BridgeServiceError.unauthorized).eraseToAnyPublisher()
        }

        let url = baseURL.appendingPathComponent("v1/bridges/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = UpdateBridgeRequest(isActive: isActive)
        request.httpBody = try? JSONEncoder().encode(body)

        return session.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: UpdateBridgeResponse.self, decoder: JSONDecoder())
            .map(\.bridge)
            .retryWithExponentialBackoff(maxRetries: maxRetries, initialDelay: initialRetryDelay)
            .eraseToAnyPublisher()
    }

    func deleteBridge(id: String) -> AnyPublisher<Void, Error> {
        guard let token = authManager.getAccessToken() else {
            return Fail(error: BridgeServiceError.unauthorized).eraseToAnyPublisher()
        }

        let url = baseURL.appendingPathComponent("v1/bridges/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return session.dataTaskPublisher(for: request)
            .mapError { $0 as Error }
            .map { _ in () }
            .retryWithExponentialBackoff(maxRetries: maxRetries, initialDelay: initialRetryDelay)
            .eraseToAnyPublisher()
    }

    func getBridgeForThread(threadId: String, bridgeType: String) -> AnyPublisher<Bridge?, Error> {
        guard let token = authManager.getAccessToken() else {
            return Fail(error: BridgeServiceError.unauthorized).eraseToAnyPublisher()
        }

        let url = baseURL.appendingPathComponent("v1/bridges/\(threadId)/\(bridgeType)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return session.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: BridgeResponse.self, decoder: JSONDecoder())
            .map(\.bridge)
            .retryWithExponentialBackoff(maxRetries: maxRetries, initialDelay: initialRetryDelay)
            .eraseToAnyPublisher()
    }

    // MARK: - Private Helpers

    /// Checks if an error is retryable (network errors, timeouts, 5xx server errors)
    private func isRetryableError(_ error: Error) -> Bool {
        // Network errors are retryable
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        // HTTP 5xx errors are retryable (server errors)
        if let httpResponse = (error as NSError).userInfo["response"] as? HTTPURLResponse {
            return (500...599).contains(httpResponse.statusCode)
        }

        return false
    }
}

/// Mock implementation for testing
class MockBridgeService: BridgeServiceProtocol {
    var mockBridges: [Bridge] = []
    var shouldFail = false
    var delay: TimeInterval = 0

    func getBridges() -> AnyPublisher<[Bridge], Error> {
        if shouldFail {
            return Fail(error: BridgeServiceError.networkError).eraseToAnyPublisher()
        }

        return Just(mockBridges)
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func createBridge(type: String, phoneNumber: String) -> AnyPublisher<Bridge, Error> {
        if shouldFail {
            return Fail(error: BridgeServiceError.validationError).eraseToAnyPublisher()
        }

        let newBridge = Bridge(
            id: UUID().uuidString,
            userId: "test_user",
            bridgeType: Bridge.BridgeType(rawValue: type) ?? .telegram,
            phoneNumber: phoneNumber,
            status: .disconnected
        )

        mockBridges.append(newBridge)

        return Just(newBridge)
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func updateBridgeStatus(id: String, isActive: Bool) -> AnyPublisher<Bridge, Error> {
        if shouldFail {
            return Fail(error: BridgeServiceError.validationError).eraseToAnyPublisher()
        }

        guard let index = mockBridges.firstIndex(where: { $0.id == id }) else {
            return Fail(error: BridgeServiceError.notFound).eraseToAnyPublisher()
        }

        mockBridges[index].isActive = isActive

        return Just(mockBridges[index])
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func deleteBridge(id: String) -> AnyPublisher<Void, Error> {
        if shouldFail {
            return Fail(error: BridgeServiceError.notFound).eraseToAnyPublisher()
        }

        mockBridges.removeAll { $0.id == id }

        return Just(())
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }

    func getBridgeForThread(threadId: String, bridgeType: String) -> AnyPublisher<Bridge?, Error> {
        if shouldFail {
            return Fail(error: BridgeServiceError.notFound).eraseToAnyPublisher()
        }

        let bridge = mockBridges.first { $0.bridgeType.rawValue == bridgeType }

        return Just(bridge)
            .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}

// MARK: - Response Models

private struct BridgeResponse: Decodable {
    let bridges: [Bridge]
    let bridge: Bridge?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bridges = try container.decodeIfPresent([Bridge].self, forKey: .bridges) ?? []
        bridge = try container.decodeIfPresent(Bridge.self, forKey: .bridge)
    }

    private enum CodingKeys: String, CodingKey {
        case bridges, bridge
    }
}

private struct CreateBridgeResponse: Decodable {
    let bridge: Bridge
}

private struct UpdateBridgeRequest: Encodable {
    let isActive: Bool
}

private struct UpdateBridgeResponse: Decodable {
    let bridge: Bridge
}

// MARK: - Errors

enum BridgeServiceError: Error {
    case unauthorized
    case networkError
    case validationError
    case notFound
    case decodingError
}

// MARK: - Combine Extensions for Retry Logic

extension Publisher {
    /// Retries with exponential backoff for transient failures
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    ///   - initialDelay: Initial delay before first retry in seconds (default: 1.0)
    ///   - shouldRetry: Optional closure to determine if error is retryable (default: all errors)
    /// - Returns: Publisher with retry logic applied
    func retryWithExponentialBackoff(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 1.0,
        shouldRetry: ((Failure) -> Bool)? = nil
    ) -> AnyPublisher<Output, Failure> {
        var attempt = 0

        return self.catch { error -> AnyPublisher<Output, Failure> in
            attempt += 1

            // Check if we should retry
            let isRetryable = shouldRetry?(error) ?? true

            guard attempt < maxRetries && isRetryable else {
                // Max retries reached or error not retryable, fail
                return Fail(error: error).eraseToAnyPublisher()
            }

            // Calculate exponential backoff delay: initialDelay * 2^(attempt-1)
            // e.g., for initialDelay=1.0: 1s, 2s, 4s
            let delay = initialDelay * pow(2.0, Double(attempt - 1))

            // Log retry attempt (in production, use proper logging)
            #if DEBUG
            print("⚠️ Network request failed (attempt \(attempt)/\(maxRetries)), retrying in \(delay)s...")
            #endif

            // Wait for delay, then retry the original publisher
            return Just(())
                .delay(for: .seconds(delay), scheduler: DispatchQueue.main)
                .flatMap { _ in self }
                .retryWithExponentialBackoff(
                    maxRetries: maxRetries - attempt,
                    initialDelay: initialDelay,
                    shouldRetry: shouldRetry
                )
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
}