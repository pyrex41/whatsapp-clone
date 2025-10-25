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

    init(baseURL: URL = URL(string: "https://api.globalbridge.com")!,
         session: URLSession = .shared,
         authManager: AuthManager = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.authManager = authManager
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
            .eraseToAnyPublisher()
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