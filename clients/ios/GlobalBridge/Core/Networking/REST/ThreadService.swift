//
//  ThreadService.swift
//  GlobalBridge
//
//  Fetches thread metadata from backend REST API for initial sync.
//

import Foundation

struct ThreadService {
    let baseURL: URL
    let session: URLSession
    let authManager: AuthManager

    /// Returns the appropriate backend URL based on environment
    static var defaultBaseURL: URL {
        // Check environment variable first
        if let backendEnv = ProcessInfo.processInfo.environment["BACKEND_ENV"],
           backendEnv.lowercased() == "production" {
            return URL(string: "https://globalbridge-backend.fly.dev")!
        }

        // Default to localhost for Debug, production for Release
        #if DEBUG
        return URL(string: "http://localhost:4000")!
        #else
        return URL(string: "https://globalbridge-backend.fly.dev")!
        #endif
    }

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        authManager: AuthManager = .shared
    ) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session
        self.authManager = authManager
    }

    /// Fetch threads for the current user from the backend.
    func fetchThreads() async throws -> [Thread] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/threads"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = await authManager.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let payload = try decoder.decode(ThreadIndexResponse.self, from: data)
        return payload.data.map { $0.toDomainModel() }
    }
}

// MARK: - DTOs

private struct ThreadIndexResponse: Decodable {
    let data: [ThreadDTO]
}

private struct ThreadDTO: Decodable {
    let id: UUID
    let title: String?
    let threadType: Thread.ThreadType
    let databaseShardId: String
    let isArchived: Bool
    let isMuted: Bool
    let lastMessageAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case threadType = "thread_type"
        case databaseShardId = "database_shard_id"
        case isArchived = "is_archived"
        case isMuted = "is_muted"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toDomainModel() -> Thread {
        Thread(
            id: id,
            threadType: threadType,
            title: title,
            lastMessageAt: lastMessageAt,
            isArchived: isArchived,
            isMuted: isMuted,
            databaseShardId: databaseShardId,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
