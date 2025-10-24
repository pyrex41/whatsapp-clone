# iOS Frontend - API Integration Requirements

**Date:** 2025-10-24
**Source:** `docs/API_DOCUMENTATION.md`
**iOS PRD:** `.taskmaster/docs/ios-ai-frontend-prd-updated.md`

---

## Overview

This document analyzes the backend API specification and identifies required changes/additions for the iOS frontend implementation.

---

## 1. Authentication Changes Required

### 1.1 Dual Authentication Support

**Current State:** iOS only implements Auth0 OAuth flow
**API Provides:** Both OAuth and traditional username/password auth

**Required Implementation:**

```swift
// Add support for traditional authentication
extension AuthManager {
    /// Sign up with username and password (alternative to OAuth)
    func signUp(
        username: String,
        phoneNumber: String,
        password: String,
        displayName: String?,
        publicKey: String?
    ) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/api/auth/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "username": username,
            "phone_number": phoneNumber,
            "password": password,
            "display_name": displayName as Any,
            "public_key": publicKey as Any
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        // Handle response...
    }

    /// Login with username/phone and password
    func login(
        identifier: String,  // username OR phone_number
        password: String
    ) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/api/auth/login")!
        // Implementation...
    }

    /// Refresh access token using refresh token
    func refreshTokenViaAPI() async throws -> TokenPair {
        let url = URL(string: "\(baseURL)/api/auth/refresh")!
        guard let refreshToken = self.refreshToken else {
            throw AuthError.noRefreshToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Store new tokens
        self.accessToken = response.data.access
        self.refreshToken = response.data.refresh

        return TokenPair(access: response.data.access, refresh: response.data.refresh)
    }
}

struct AuthResponse: Codable {
    let data: AuthData
}

struct AuthData: Codable {
    let user: User
    let tokens: TokenPair
}

struct TokenPair: Codable {
    let access: String
    let refresh: String
}
```

**Decision Required:**
- Should iOS support both OAuth and traditional auth?
- Or stick with OAuth only and ignore REST auth endpoints?

**Recommendation:** Support both for flexibility. Users may prefer traditional signup.

---

### 1.2 Public Key Management (E2EE)

**Current State:** Not fully implemented
**API Provides:** Public key storage and retrieval endpoints

**Required Implementation:**

```swift
extension AuthManager {
    /// Update E2EE public key
    func updatePublicKey(_ publicKey: String) async throws {
        let url = URL(string: "\(baseURL)/api/auth/public-key")!
        let token = try await getAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["public_key": publicKey]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        // Handle response...
    }

    /// Get another user's public key for E2EE
    func getPublicKey(userId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/api/auth/public-key/\(userId)")!
        let token = try await getAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw AuthError.publicKeyNotFound
        }

        let result = try JSONDecoder().decode(PublicKeyResponse.self, from: data)
        return result.data.publicKey
    }
}

struct PublicKeyResponse: Codable {
    let data: PublicKeyData

    struct PublicKeyData: Codable {
        let userId: String
        let publicKey: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case publicKey = "public_key"
        }
    }
}
```

---

### 1.3 Password Management

**New Endpoints:**

```swift
extension AuthManager {
    /// Change password
    func changePassword(currentPassword: String, newPassword: String) async throws {
        let url = URL(string: "\(baseURL)/api/auth/password")!
        let token = try await getAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "current_password": currentPassword,
            "new_password": newPassword
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        // Handle response...
    }

    /// Logout (invalidate tokens)
    func logout() async throws {
        let url = URL(string: "\(baseURL)/api/auth/logout")!
        let token = try await getAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try await URLSession.shared.data(for: request)

        // Clear local credentials
        self.accessToken = nil
        self.refreshToken = nil
        self.isAuthenticated = false
    }
}
```

---

## 2. New WebSocket Channel: User Channel

**Current State:** Only `thread:{thread_id}` channel implemented
**API Provides:** `user:{user_id}` channel with extensive functionality

**Required Implementation:**

```swift
// MARK: - User Channel Manager
@MainActor
class UserChannelManager: ObservableObject {
    private var userChannel: Channel?
    private let phoenixManager: PhoenixChannelManager

    @Published var threads: [Thread] = []
    @Published var contacts: [Contact] = []

    init(phoenixManager: PhoenixChannelManager) {
        self.phoenixManager = phoenixManager
    }

    func joinUserChannel(userId: String) async throws {
        let topic = "user:\(userId)"

        userChannel = try await phoenixManager.joinChannel(topic: topic)

        // Set up event listeners
        setupEventListeners()

        // Bootstrap data on join
        try await bootstrap()
    }

    private func setupEventListeners() {
        // Listen for new threads created
        userChannel?.on("thread_created") { [weak self] payload in
            guard let self = self else { return }

            if let threadData = payload["thread"] as? [String: Any],
               let thread = try? JSONDecoder().decode(Thread.self, from: JSONSerialization.data(withJSONObject: threadData)) {
                Task { @MainActor in
                    self.threads.append(thread)
                }
            }
        }
    }

    // MARK: - Bootstrap
    func bootstrap() async throws -> BootstrapData {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("bootstrap", payload: [:])
                .receive("ok") { payload in
                    if let data = try? JSONDecoder().decode(BootstrapData.self, from: JSONSerialization.data(withJSONObject: payload)) {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: ChannelError.invalidResponse)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    // MARK: - Thread Management
    func createThread(title: String, participantIds: [String]) async throws -> Thread {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        let payload: [String: Any] = [
            "title": title,
            "participant_ids": participantIds
        ]

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("create_thread", payload: payload)
                .receive("ok") { response in
                    if let threadData = response["thread"] as? [String: Any],
                       let thread = try? JSONDecoder().decode(Thread.self, from: JSONSerialization.data(withJSONObject: threadData)) {
                        continuation.resume(returning: thread)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    func createDirectMessage(otherUserId: String) async throws -> Thread {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        let payload = ["other_user_id": otherUserId]

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("create_dm", payload: payload)
                .receive("ok") { response in
                    if let threadData = response["thread"] as? [String: Any],
                       let thread = try? JSONDecoder().decode(Thread.self, from: JSONSerialization.data(withJSONObject: threadData)) {
                        continuation.resume(returning: thread)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    // MARK: - Contact Management
    func getContacts() async throws -> [Contact] {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("get_contacts", payload: [:])
                .receive("ok") { response in
                    if let contactsData = response["contacts"] as? [[String: Any]] {
                        let contacts = contactsData.compactMap { contactDict -> Contact? in
                            try? JSONDecoder().decode(Contact.self, from: JSONSerialization.data(withJSONObject: contactDict))
                        }
                        continuation.resume(returning: contacts)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    func addContact(contactUserId: String, displayName: String) async throws -> Contact {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        let payload: [String: String] = [
            "contact_user_id": contactUserId,
            "display_name": displayName
        ]

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("add_contact", payload: payload)
                .receive("ok") { response in
                    if let contactData = response["contact"] as? [String: Any],
                       let contact = try? JSONDecoder().decode(Contact.self, from: JSONSerialization.data(withJSONObject: contactData)) {
                        continuation.resume(returning: contact)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    func removeContact(contactId: String) async throws {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        let payload = ["contact_id": contactId]

        try await withCheckedThrowingContinuation { continuation in
            channel.push("remove_contact", payload: payload)
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    // MARK: - User Search
    func searchUsers(query: String) async throws -> [User] {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        let payload = ["query": query]

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("search_users", payload: payload)
                .receive("ok") { response in
                    if let usersData = response["users"] as? [[String: Any]] {
                        let users = usersData.compactMap { userDict -> User? in
                            try? JSONDecoder().decode(User.self, from: JSONSerialization.data(withJSONObject: userDict))
                        }
                        continuation.resume(returning: users)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    func searchContacts(query: String) async throws -> [Contact] {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        let payload = ["query": query]

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("search_contacts", payload: payload)
                .receive("ok") { response in
                    if let contactsData = response["contacts"] as? [[String: Any]] {
                        let contacts = contactsData.compactMap { contactDict -> Contact? in
                            try? JSONDecoder().decode(Contact.self, from: JSONSerialization.data(withJSONObject: contactDict))
                        }
                        continuation.resume(returning: contacts)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    // MARK: - Contact CDC Sync
    func syncContacts(since: String?) async throws -> ContactSyncResult {
        guard let channel = userChannel else {
            throw ChannelError.notJoined
        }

        var payload: [String: String] = [:]
        if let since = since {
            payload["since"] = since
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("sync_contacts", payload: payload)
                .receive("ok") { response in
                    if let changes = response["changes"] as? [[String: Any]],
                       let cursor = response["cursor"] as? String {
                        let syncResult = ContactSyncResult(
                            changes: changes.compactMap { try? JSONDecoder().decode(CDCLog.self, from: JSONSerialization.data(withJSONObject: $0)) },
                            cursor: cursor
                        )
                        continuation.resume(returning: syncResult)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }
}

// MARK: - Supporting Types
struct BootstrapData: Codable {
    let threads: [Thread]
    let contacts: [Contact]
    let user: User
}

struct Contact: Codable, Identifiable {
    let id: String
    let userId: String
    let contactUserId: String
    let displayName: String?
    let insertedAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case contactUserId = "contact_user_id"
        case displayName = "display_name"
        case insertedAt = "inserted_at"
        case updatedAt = "updated_at"
    }
}

struct ContactSyncResult {
    let changes: [CDCLog]
    let cursor: String
}
```

---

## 3. Enhanced Thread Channel Events

**Missing Events to Implement:**

### 3.1 Read Receipts

```swift
extension ThreadChannelManager {
    /// Mark message as read
    func markAsRead(messageId: String) async throws {
        guard let channel = threadChannel else {
            throw ChannelError.notJoined
        }

        let payload = ["message_id": messageId]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.push("mark_read", payload: payload)
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    /// Get read receipts for a message
    func getReadReceipts(messageId: String) async throws -> [ReadReceipt] {
        guard let channel = threadChannel else {
            throw ChannelError.notJoined
        }

        let payload = ["message_id": messageId]

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("get_read_receipts", payload: payload)
                .receive("ok") { response in
                    if let receiptsData = response["receipts"] as? [[String: Any]] {
                        let receipts = receiptsData.compactMap { receiptDict -> ReadReceipt? in
                            try? JSONDecoder().decode(ReadReceipt.self, from: JSONSerialization.data(withJSONObject: receiptDict))
                        }
                        continuation.resume(returning: receipts)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    /// Listen for read receipts
    private func setupReadReceiptListener() {
        threadChannel?.on("message_read") { [weak self] payload in
            guard let self = self else { return }

            if let messageId = payload["message_id"] as? String,
               let userId = payload["user_id"] as? String,
               let readAtString = payload["read_at"] as? String,
               let readAt = ISO8601DateFormatter().date(from: readAtString) {

                let receipt = ReadReceipt(
                    messageId: messageId,
                    userId: userId,
                    readAt: readAt
                )

                Task { @MainActor in
                    // Update UI with read receipt
                    self.handleReadReceipt(receipt)
                }
            }
        }
    }
}

struct ReadReceipt: Codable {
    let messageId: String
    let userId: String
    let readAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case userId = "user_id"
        case readAt = "read_at"
    }
}
```

### 3.2 Message Editing & Deletion

```swift
extension ThreadChannelManager {
    /// Edit a message
    func editMessage(
        messageId: String,
        newContent: String,
        encryptedContent: String? = nil
    ) async throws -> Message {
        guard let channel = threadChannel else {
            throw ChannelError.notJoined
        }

        var payload: [String: Any] = [
            "message_id": messageId,
            "content": newContent
        ]

        if let encrypted = encryptedContent {
            payload["encrypted_content"] = encrypted
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.push("edit_message", payload: payload)
                .receive("ok") { response in
                    if let messageData = response["message"] as? [String: Any],
                       let message = try? JSONDecoder().decode(Message.self, from: JSONSerialization.data(withJSONObject: messageData)) {
                        continuation.resume(returning: message)
                    }
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    /// Delete a message
    func deleteMessage(messageId: String) async throws {
        guard let channel = threadChannel else {
            throw ChannelError.notJoined
        }

        let payload = ["message_id": messageId]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            channel.push("delete_message", payload: payload)
                .receive("ok") { _ in
                    continuation.resume()
                }
                .receive("error") { error in
                    continuation.resume(throwing: ChannelError.requestFailed(error))
                }
        }
    }

    /// Listen for message edits
    private func setupEditListener() {
        threadChannel?.on("message_edited") { [weak self] payload in
            guard let self = self else { return }

            if let messageData = payload["message"] as? [String: Any],
               let message = try? JSONDecoder().decode(Message.self, from: JSONSerialization.data(withJSONObject: messageData)) {

                Task { @MainActor in
                    self.handleMessageEdited(message)
                }
            }
        }
    }

    /// Listen for message deletions
    private func setupDeleteListener() {
        threadChannel?.on("message_deleted") { [weak self] payload in
            guard let self = self else { return }

            if let messageId = payload["message_id"] as? String {
                Task { @MainActor in
                    self.handleMessageDeleted(messageId: messageId)
                }
            }
        }
    }
}
```

---

## 4. Bootstrap Endpoint

**New REST Endpoint:**

```swift
class BootstrapService {
    private let baseURL: String

    /// Get initial app data (user + threads) in one request
    func bootstrap(limit: Int = 20, offset: Int = 0) async throws -> BootstrapResponse {
        let url = URL(string: "\(baseURL)/api/bootstrap?limit=\(limit)&offset=\(offset)")!
        let token = await AuthManager.shared.getAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BootstrapResponse.self, from: data)
    }
}

struct BootstrapResponse: Codable {
    let data: BootstrapData

    struct BootstrapData: Codable {
        let user: User
        let threads: [Thread]
        let pagination: Pagination
        let bridges: [Bridge]
        let csrfToken: String

        enum CodingKeys: String, CodingKey {
            case user, threads, pagination, bridges
            case csrfToken = "csrf_token"
        }
    }

    struct Pagination: Codable {
        let limit: Int
        let offset: Int
        let hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case limit, offset
            case hasMore = "has_more"
        }
    }

    struct Bridge: Codable {
        // Define bridge structure
    }
}
```

**Usage:**

```swift
// On app launch after authentication
let bootstrapData = try await BootstrapService().bootstrap()

// Populate initial UI
self.currentUser = bootstrapData.data.user
self.threads = bootstrapData.data.threads
self.hasMoreThreads = bootstrapData.data.pagination.hasMore
```

---

## 5. Rate Limiting

**✅ Decision:** Auto-retry silently on 429 responses. Backend will remove tier-based rate limits.

**Current State:** Basic 429 error handling
**Simplified Implementation:** Simple auto-retry without UI complexity

**Implementation:**

```swift
// Simplified rate limit handling
extension AIService {
    func translate(text: String, targetLanguage: String, sourceLanguage: String?) async throws -> TranslationResult {
        let url = URL(string: "\(baseURL)/api/v1/ai/translate")!
        let token = await AuthManager.shared.getAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "text": text,
            "target_language": targetLanguage,
            "source_language": sourceLanguage ?? "auto"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Simple 429 handling with auto-retry
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
            // Parse X-RateLimit-Reset header if available
            if let resetStr = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset"),
               let resetTimestamp = TimeInterval(resetStr) {
                let resetDate = Date(timeIntervalSince1970: resetTimestamp)
                let waitTime = resetDate.timeIntervalSinceNow

                if waitTime > 0 {
                    try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                    // Retry once
                    return try await translate(text: text, targetLanguage: targetLanguage, sourceLanguage: sourceLanguage)
                }
            } else {
                // Default wait: 60 seconds
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return try await translate(text: text, targetLanguage: targetLanguage, sourceLanguage: sourceLanguage)
            }
        }

        return try JSONDecoder().decode(TranslationResult.self, from: data)
    }
}
```

**Note:** No UI components needed. Rate limiting is handled silently with auto-retry. Backend will remove tier-based rate limits.

---

## 6. ~~CDC Sync via REST~~ (NOT NEEDED)

**❌ Decision:** WebSocket-only approach is sufficient. REST CDC endpoints will remain unused as primary sync method.

**Rationale:** Current WebSocket-only CDC sync works well and adding REST fallback adds unnecessary complexity.

---

## 7. Feature Flag Updates

**✅ Decision:** Sync feature flags from backend on every app launch.

**Implementation:** Fetch from `/api/v1/features` on app launch with local cache fallback for offline.

**New Endpoints:**

```swift
class FeatureFlagService {
    private let baseURL: String

    /// Get all features for current user
    func getAllFeatures() async throws -> FeatureResponse {
        let url = URL(string: "\(baseURL)/api/v1/features")!
        let token = await AuthManager.shared.getAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(FeatureResponse.self, from: data)
    }

    /// Check specific feature
    func checkFeature(_ feature: String) async throws -> FeatureCheckResponse {
        let url = URL(string: "\(baseURL)/api/v1/features/\(feature)")!
        let token = await AuthManager.shared.getAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(FeatureCheckResponse.self, from: data)
    }

    /// Update user tier (testing only)
    func updateTier(_ tier: UserTier) async throws -> TierUpdateResponse {
        let url = URL(string: "\(baseURL)/api/v1/features/tier")!
        let token = await AuthManager.shared.getAccessToken()

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["tier": tier.rawValue]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TierUpdateResponse.self, from: data)
    }
}

struct FeatureResponse: Codable {
    let data: FeatureData

    struct FeatureData: Codable {
        let tier: String
        let features: Features
        let limits: Limits
    }

    struct Features: Codable {
        let aiTranslation: Bool
        let aiToneAnalysis: Bool
        let semanticSearch: Bool
        let threadSummarization: Bool
        let taskExtraction: Bool
        let advancedRateLimits: Bool

        enum CodingKeys: String, CodingKey {
            case aiTranslation = "ai_translation"
            case aiToneAnalysis = "ai_tone_analysis"
            case semanticSearch = "semantic_search"
            case threadSummarization = "thread_summarization"
            case taskExtraction = "task_extraction"
            case advancedRateLimits = "advanced_rate_limits"
        }
    }

    struct Limits: Codable {
        let maxThreads: Int
        let maxMessagesPerThread: Int
        let aiRequestsPerDay: Int

        enum CodingKeys: String, CodingKey {
            case maxThreads = "max_threads"
            case maxMessagesPerThread = "max_messages_per_thread"
            case aiRequestsPerDay = "ai_requests_per_day"
        }
    }
}

struct FeatureCheckResponse: Codable {
    let data: FeatureCheckData

    struct FeatureCheckData: Codable {
        let feature: String
        let hasAccess: Bool
        let tier: String

        enum CodingKeys: String, CodingKey {
            case feature
            case hasAccess = "has_access"
            case tier
        }
    }
}

struct TierUpdateResponse: Codable {
    let data: TierUpdateData

    struct TierUpdateData: Codable {
        let tier: String
        let features: FeatureResponse.FeatureData.Features
        let message: String
    }
}
```

**Update FeatureFlags.swift:**

```swift
extension FeatureFlags {
    /// Sync features from backend
    func syncFromBackend() async throws {
        let response = try await FeatureFlagService().getAllFeatures()

        // Update local feature flags
        self.currentTier = UserTier(rawValue: response.data.tier) ?? .free

        // Store limits
        self.maxThreads = response.data.limits.maxThreads
        self.maxMessagesPerThread = response.data.limits.maxMessagesPerThread
        self.aiRequestsPerDay = response.data.limits.aiRequestsPerDay

        // Cache features locally
        UserDefaults.standard.set(response.data.tier, forKey: "user_tier")
        // Cache other features...
    }
}
```

---

## 8. Threads List Endpoint

**New REST Endpoint:**

```swift
class ThreadService {
    private let baseURL: String

    /// List all threads for current user
    func listThreads() async throws -> [Thread] {
        let url = URL(string: "\(baseURL)/api/v1/threads")!
        let token = await AuthManager.shared.getAccessToken()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token!)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ThreadsResponse.self, from: data)
        return response.data.threads
    }
}

struct ThreadsResponse: Codable {
    let data: ThreadsData

    struct ThreadsData: Codable {
        let threads: [Thread]
    }
}
```

---

## 9. Summary of Required Changes

### ✅ Decisions Made (2025-10-24)

**Authentication:** OAuth-only (no change needed)
**CDC Sync:** WebSocket-only (no REST fallback needed)
**Rate Limiting:** Auto-retry silently (backend will remove tier-based limits)
**Feature Flags:** Sync every app launch
**User Channel:** Implement now (next sprint)

---

### Priority 1: Approved Changes (5.5-7.5 days)

1. **✅ User Channel Implementation** - APPROVED
   - Contact management
   - Thread creation
   - User search
   - Bootstrap via channel
   - **Effort:** 3-4 days
   - **Status:** Implement next sprint

2. **✅ Read Receipts** - APPROVED
   - Mark as read
   - Get receipts
   - Listen for receipt events
   - **Effort:** 1-2 days

3. **✅ Rate Limit Handling** - SIMPLIFIED
   - Simple auto-retry on 429
   - No UI needed (silent)
   - Backend removing tier-based limits
   - **Effort:** 0.5 days (reduced from 1 day)

4. **✅ Message Edit/Delete** - APPROVED
   - Edit message flow
   - Delete message flow
   - Listen for edit/delete events
   - **Effort:** 1 day

### Priority 2: Approved Enhancements (1 day)

5. **🟡 Bootstrap Endpoint**
   - Replace multiple calls with single bootstrap
   - **Effort:** 0.5 days
   - **Status:** Pending approval

6. **✅ Feature Flags Sync** - APPROVED
   - Sync from backend on every app launch
   - Cache locally for offline fallback
   - **Effort:** 0.5 days

7. **❌ ~~CDC REST Fallback~~** - NOT NEEDED
   - Decision: WebSocket-only is sufficient
   - **Effort Saved:** 1 day

### Priority 3: Deferred/Cancelled Features

8. **❌ ~~Traditional Auth~~** - NOT NEEDED
   - Decision: OAuth-only approach
   - **Effort Saved:** 1-2 days

9. **❌ ~~Password Management~~** - NOT NEEDED
   - Decision: Not needed for OAuth
   - **Effort Saved:** 0.5 days

10. **🔄 Public Key Management** - DEFERRED
    - E2EE key setup UI
    - Deferred to E2EE implementation phase
    - **Effort:** 1 day (when needed)

---

## 10. Implementation Roadmap

**Week 1:**
- User Channel implementation
- Contact management UI
- Bootstrap endpoint integration

**Week 2:**
- Read receipts
- Message edit/delete
- Rate limit handling

**Week 3:**
- CDC REST fallback
- Feature flags sync
- Testing and polish

---

## 11. Testing Checklist

### Authentication
- [ ] OAuth login flow
- [ ] Token refresh
- [ ] Logout
- [ ] Get current user
- [ ] Traditional signup/login (if implemented)

### User Channel
- [ ] Join user channel
- [ ] Bootstrap data
- [ ] Create thread
- [ ] Create DM
- [ ] Search users
- [ ] Get contacts
- [ ] Add contact
- [ ] Remove contact
- [ ] Search contacts
- [ ] Sync contacts (CDC)

### Thread Channel
- [ ] Join thread channel
- [ ] Send message
- [ ] Fetch message history
- [ ] Edit message
- [ ] Delete message
- [ ] Mark as read
- [ ] Get read receipts
- [ ] Typing indicator
- [ ] Presence tracking
- [ ] CDC pull/push via WebSocket

### REST Endpoints
- [ ] Bootstrap endpoint
- [ ] List threads
- [ ] AI translation
- [ ] AI summarization
- [ ] Semantic search
- [ ] Task extraction
- [ ] Vector health check
- [ ] CDC pull/push via REST
- [ ] Get all features
- [ ] Check specific feature
- [ ] Update tier

### Rate Limiting
- [ ] Parse rate limit headers
- [ ] Handle 429 responses
- [ ] Show rate limit UI
- [ ] Auto-retry after reset

### Error Handling
- [ ] 400 Bad Request
- [ ] 401 Unauthorized
- [ ] 403 Forbidden
- [ ] 404 Not Found
- [ ] 422 Validation errors
- [ ] 429 Rate limit
- [ ] 500 Server error
- [ ] Network errors
- [ ] WebSocket disconnections

---

## ✅ Decisions Made (2025-10-24)

All questions have been resolved:

1. **Authentication Strategy:** ✅ OAuth-only (no change needed)
2. **User Channel Priority:** ✅ Implement now (next sprint)
3. **CDC Strategy:** ✅ WebSocket-only (no REST fallback)
4. **Rate Limiting:** ✅ Auto-retry silently (backend removing tier-based limits)
5. **Feature Flags:** ✅ Sync every app launch with offline cache
6. **E2EE:** 🔄 Deferred to E2EE implementation phase

**Backend Action Required:** Remove tier-based rate limits (see `docs/backend-action-items.md`)

---

**Document Owner:** iOS Team Lead
**Last Updated:** 2025-10-24
**Next Review:** After Priority 1 implementation
