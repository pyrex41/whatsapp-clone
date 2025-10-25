//
//  PushService.swift
//  GlobalBridge
//
//  Registers APNs device tokens with backend.
//

import Foundation
import Combine

struct PushService {
    let baseURL: URL
    let session: URLSession
    let authManager: AuthManager

    init(
        baseURL: URL = URL(string: "http://localhost:4000")!,
        session: URLSession = .shared,
        authManager: AuthManager = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.authManager = authManager
    }

    /// Register or update the device token for the current user
    func registerDeviceToken(
        token: String,
        userId: String,
        appVersion: String
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/push/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bearer = await authManager.getAccessToken() {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "platform": "ios",
            "device_token": token,
            "app_version": appVersion,
            "user_id": userId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            // Surface backend error body when possible
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw NSError(
                domain: "PushService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Device token register failed (\(http.statusCode)): \(body)"]
            )
        }
    }
}

