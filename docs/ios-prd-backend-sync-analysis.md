# iOS AI Frontend PRD - Backend Sync Analysis

**Date:** 2025-10-24
**Purpose:** Compare iOS Frontend PRD assumptions with actual backend implementation
**Status:** Analysis Complete - Updates Required

---

## Executive Summary

The backend implementation has been completed with significant AI infrastructure in place. The iOS Frontend PRD needs several updates to align with the actual backend API endpoints, data models, and capabilities. This document identifies critical gaps and required PRD updates.

**Key Findings:**
- ✅ **Core AI Endpoints Implemented**: Translation, summarization, semantic search, task extraction
- ⚠️ **Missing Features**: Tone analysis (placeholder only), cultural context tools (partial implementation)
- 🔄 **API Differences**: Authentication flow, WebSocket events, CDC sync mechanism differ from PRD
- 📊 **Additional Features**: Feature flags system, rate limiting, vec health checks not in PRD

---

## 1. Authentication & Authorization

### ✅ What's Implemented

**Endpoints:**
```
POST /api/auth/signup
POST /api/auth/login
POST /api/auth/refresh
GET  /api/auth/me
POST /api/auth/logout
PUT  /api/auth/password
PUT  /api/auth/public-key
GET  /api/auth/public-key/:user_id
GET  /api/auth/:provider (OAuth - Auth0)
GET  /api/auth/:provider/callback
```

**Authentication Flow:**
- JWT-based authentication using Guardian library
- Refresh token rotation
- OAuth 2.0 support (Auth0)
- E2EE public key management
- Rate limiting: 5 requests/minute on auth endpoints

### ⚠️ PRD Gaps

**Section 2.1 - iOS App Architecture:**
- PRD assumes simple "HTTPS / WebSocket" communication
- **Update needed**: Document JWT Bearer token authentication
- **Add**: Token refresh strategy for iOS (automatic refresh before expiry)
- **Add**: Keychain storage requirements for tokens
- **Add**: OAuth flow for Auth0 integration

**Recommended Update:**
```swift
// Add to Section 2.2 - Authentication Service Layer
protocol AuthServiceProtocol {
    func signup(username: String, phoneNumber: String, password: String) async throws -> AuthTokens
    func login(identifier: String, password: String) async throws -> AuthTokens
    func refreshTokens(refreshToken: String) async throws -> AuthTokens
    func logout() async throws
    func updatePublicKey(_ key: String) async throws
    func getPublicKey(for userId: String) async throws -> String
}

struct AuthTokens: Codable {
    let access: String
    let refresh: String
    let expiresAt: Date
}
```

---

## 2. WebSocket / Phoenix Channel Implementation

### ✅ What's Implemented

**Channel:** `thread:#{thread_id}`

**Events (Client → Server):**
```
"new_message" - Send new message
"fetch_messages" - Get historical messages
"edit_message" - Edit existing message
"delete_message" - Delete message
"typing" - Typing indicator
"mark_read" - Mark message as read
"get_read_receipts" - Get read receipts for message
"cdc:pull" - Pull CDC changes
"cdc:push" - Push CDC changes
```

**Events (Server → Client):**
```
"new_message" - Broadcast new message
"message_edited" - Message was edited
"message_deleted" - Message was deleted
"user_typing" - User typing status
"message_read" - Read receipt
"presence_state" - Presence tracking
"presence_diff" - Presence changes
```

**Critical Implementation Details:**
- Messages broadcast immediately BEFORE database persistence (< 100ms latency)
- Async database write using Task.Supervisor
- Presence tracking for online/offline status
- Auto-stop typing after 3 seconds
- Client message deduplication via `client_message_id`

### ⚠️ PRD Gaps

**Section 2.1 - Architecture Diagram:**
- PRD shows generic "HTTPS / WebSocket" connection
- **Missing**: Phoenix Channel join authorization
- **Missing**: Presence tracking system
- **Missing**: CDC pull/push mechanism over WebSocket

**Recommended Update:**
Add new section **"2.4 Phoenix Channel Architecture"**:

```swift
// MARK: - Phoenix Channel Integration
class PhoenixChannelManager {
    private var socket: Socket?
    private var channels: [String: Channel] = [:]

    func connect(token: String) async throws {
        let params = ["token": token]
        socket = Socket("wss://api.globalbridge.com/socket/websocket", params: params)
        try await socket?.connect()
    }

    func joinThread(threadId: String) async throws -> Channel {
        guard let socket = socket else { throw ChannelError.notConnected }

        let channel = socket.channel("thread:\(threadId)")

        // Handle server events
        channel.on("new_message") { [weak self] message in
            self?.handleNewMessage(message)
        }

        channel.on("presence_state") { [weak self] state in
            self?.handlePresenceState(state)
        }

        channel.on("presence_diff") { [weak self] diff in
            self?.handlePresenceDiff(diff)
        }

        try await channel.join()
        channels[threadId] = channel
        return channel
    }

    func sendMessage(threadId: String, content: String, clientMessageId: String) async throws {
        guard let channel = channels[threadId] else {
            throw ChannelError.notJoined
        }

        let payload: [String: Any] = [
            "content": content,
            "content_type": "text",
            "client_message_id": clientMessageId,
            "client_created_at": ISO8601DateFormatter().string(from: Date())
        ]

        try await channel.push("new_message", payload)
    }
}
```

---

## 3. AI Service Endpoints

### ✅ What's Implemented

**Base Path:** `/api/v1/ai`

**Endpoints:**
```
POST /api/v1/ai/translate
POST /api/v1/ai/analyze_tone (⚠️ PLACEHOLDER ONLY)
POST /api/v1/ai/summarize_thread
POST /api/v1/ai/search_semantic
POST /api/v1/ai/extract_tasks
POST /api/v1/ai/vec_health
```

**Rate Limiting:**
- Per-user AI rate limiting via `RateLimitAI` plug
- Different limits based on user tier (Free/Pro/Enterprise)

**Request/Response Formats:**

#### Translation
```
POST /api/v1/ai/translate
Request:
{
  "text": "Hello world",
  "target_language": "es",
  "source_language": "en"  // optional, defaults to "auto"
}

Response:
{
  "success": true,
  "translation": "Hola mundo",
  "source_language": "en",
  "target_language": "es"
}
```

#### Thread Summarization
```
POST /api/v1/ai/summarize_thread
Request:
{
  "thread_id": "uuid",
  "max_length": 200  // optional, defaults to 200
}

Response:
{
  "success": true,
  "summary": "Meeting recap: John agreed to deliver mockups by Friday...",
  "thread_id": "uuid",
  "max_length": 200
}
```

#### Semantic Search
```
POST /api/v1/ai/search_semantic
Request:
{
  "query": "project deadline",
  "thread_id": "uuid",  // optional
  "limit": 10,  // optional, defaults to 10
  "recency_bias": true,  // optional, defaults to true
  "translate": false  // optional, defaults to false
}

Response:
{
  "success": true,
  "query": "project deadline",
  "results": [
    {
      "message_id": "uuid",
      "content": "The deadline is next Friday",
      "sender_id": "uuid",
      "created_at": "2025-10-24T12:00:00Z",
      "relevance_score": 0.92
    }
  ],
  "total_results": 5,
  "thread_id": "uuid"
}
```

#### Task Extraction
```
POST /api/v1/ai/extract_tasks
Request:
{
  "thread_id": "uuid",
  "query": "tasks, deadlines, decisions"  // optional
}

Response:
{
  "success": true,
  "extraction": {
    "tasks": [
      {
        "description": "Complete mockups",
        "assignee": "John",
        "deadline": "2025-10-25T17:00:00Z",
        "priority": "high",
        "status": "pending"
      }
    ],
    "decisions": [
      {
        "decision": "Use React for frontend",
        "made_by": "Sarah",
        "timestamp": "2025-10-20T14:00:00Z"
      }
    ]
  },
  "thread_id": "uuid",
  "query": "tasks, deadlines, decisions"
}
```

#### Vec Health Check
```
POST /api/v1/ai/vec_health
Request:
{
  "thread_id": "uuid"
}

Response:
{
  "success": true,
  "thread_id": "uuid",
  "shard_id": "shard-abc-123",
  "vec_extension_available": true,
  "embeddings_table_exists": true,
  "embeddings_count": 1234
}
```

### ⚠️ PRD Gaps & Required Updates

**Section 2.2 - AIServiceProtocol:**

The PRD defines a simplified protocol. **Update to match actual backend:**

```swift
protocol AIServiceProtocol {
    // ✅ Implemented
    func translate(text: String, targetLanguage: String, sourceLanguage: String?) async throws -> TranslationResult

    // ❌ NOT IMPLEMENTED - Only placeholder
    // Remove or mark as "Coming Soon"
    func analyzeTone(text: String, context: CulturalContext) async throws -> ToneAnalysis

    // ✅ Implemented - UPDATE signature
    func summarizeThread(threadId: String, maxLength: Int?) async throws -> ThreadSummary

    // ✅ Implemented - UPDATE signature
    func searchSemantic(query: String, threadId: String?, limit: Int?, recencyBias: Bool?, translate: Bool?) async throws -> [SearchResult]

    // ✅ Implemented - UPDATE signature
    func extractTasks(threadId: String, query: String?) async throws -> TaskExtractionResult

    // ➕ ADD NEW - Not in PRD
    func checkVecHealth(threadId: String) async throws -> VecHealthStatus
}

// ➕ ADD NEW MODELS
struct TranslationResult: Codable {
    let success: Bool
    let translation: String
    let sourceLanguage: String
    let targetLanguage: String
}

struct ThreadSummary: Codable {
    let success: Bool
    let summary: String
    let threadId: String
    let maxLength: Int
}

struct SearchResult: Codable {
    let messageId: String
    let content: String
    let senderId: String
    let createdAt: Date
    let relevanceScore: Double
}

struct TaskExtractionResult: Codable {
    let success: Bool
    let extraction: ExtractionData
    let threadId: String
    let query: String
}

struct ExtractionData: Codable {
    let tasks: [ExtractedTask]
    let decisions: [ExtractedDecision]
}

struct ExtractedTask: Codable {
    let description: String
    let assignee: String?
    let deadline: Date?
    let priority: String?
    let status: String?
}

struct ExtractedDecision: Codable {
    let decision: String
    let madeBy: String?
    let timestamp: Date?
}

struct VecHealthStatus: Codable {
    let success: Bool
    let threadId: String
    let shardId: String
    let vecExtensionAvailable: Bool
    let embeddingsTableExists: Bool
    let embeddingsCount: Int
}
```

**Section 4 - AI Features Implementation:**
- **Remove or mark as "Future Feature"**: Tone Analysis (analyze_tone endpoint only returns placeholder)
- **Add**: Vec Health monitoring UI for debugging/diagnostics
- **Update**: All AI feature request/response formats to match backend

---

## 4. Feature Flags System

### ✅ What's Implemented

**Endpoints:**
```
GET /api/v1/features
GET /api/v1/features/:feature
PUT /api/v1/features/tier
```

**Feature Tiers:**
- `free`: Basic messaging, limited AI
- `pro`: Advanced AI features, higher limits
- `enterprise`: All features, highest limits

**Tier Limits:**
```elixir
# Free Tier
translations_per_day: 10
threads_per_user: 5
messages_per_thread: 500
ai_search_enabled: false
task_extraction_enabled: false
offline_translation: false

# Pro Tier
translations_per_day: 100
threads_per_user: 50
messages_per_thread: 10_000
ai_search_enabled: true
task_extraction_enabled: true
offline_translation: true

# Enterprise Tier
translations_per_day: :unlimited
threads_per_user: :unlimited
messages_per_thread: :unlimited
ai_search_enabled: true
task_extraction_enabled: true
offline_translation: true
```

### ⚠️ PRD Gaps

**Section 2.1 - Missing Feature Flags:**
- PRD mentions "Progressive Feature Disclosure based on user tier" but doesn't detail the system
- **Add new section 2.5 - Feature Flags Architecture**

```swift
// MARK: - Feature Flags Service
class FeatureFlagsService {
    private var cachedFeatures: UserFeatures?
    private let apiClient: APIClient

    struct UserFeatures: Codable {
        let tier: String
        let features: [String: Bool]
        let limits: TierLimits
    }

    struct TierLimits: Codable {
        let translationsPerDay: Int?  // nil for unlimited
        let threadsPerUser: Int?
        let messagesPerThread: Int?
        let aiSearchEnabled: Bool
        let taskExtractionEnabled: Bool
        let offlineTranslation: Bool
    }

    func fetchFeatures() async throws -> UserFeatures {
        let response = try await apiClient.get("/api/v1/features")
        let features = try JSONDecoder().decode(UserFeatures.self, from: response.data)
        cachedFeatures = features
        return features
    }

    func hasFeature(_ feature: String) -> Bool {
        cachedFeatures?.features[feature] ?? false
    }

    func checkLimit(_ limit: String) -> Int? {
        // Return nil for unlimited, or the limit value
        switch limit {
        case "translations":
            return cachedFeatures?.limits.translationsPerDay
        default:
            return nil
        }
    }

    func upgradeTier(to tier: String) async throws {
        let payload = ["tier": tier]
        _ = try await apiClient.put("/api/v1/features/tier", body: payload)
        try await fetchFeatures()  // Refresh
    }
}
```

**UI Updates Needed:**
- Add tier badge in settings UI
- Show feature availability inline (e.g., "Pro feature" badges)
- Display usage limits and quotas (e.g., "7/10 translations today")
- Add upgrade flow for tier changes

---

## 5. CDC Sync Mechanism

### ✅ What's Implemented

**REST Endpoints:**
```
POST /api/v1/sync/pull
POST /api/v1/sync/push
```

**WebSocket Events:**
```
"cdc:pull" - Pull CDC changes over WebSocket
"cdc:push" - Push CDC changes over WebSocket
```

**Pull Request:**
```json
{
  "thread_id": "uuid",
  "since": "2025-10-24T10:00:00Z"  // ISO8601 timestamp
}
```

**Pull Response:**
```json
{
  "changes": [
    {
      "log_id": 123,
      "thread_id": "uuid",
      "table_name": "messages",
      "operation": "INSERT",
      "record_id": "msg-uuid",
      "changed_fields": {
        "id": "msg-uuid",
        "content": "Hello",
        "sender_id": "user-uuid",
        "created_at": "2025-10-24T10:15:00Z"
      },
      "timestamp": "2025-10-24T10:15:00Z"
    }
  ],
  "next_cursor": "2025-10-24T10:20:00Z"
}
```

**Push Request:**
```json
{
  "thread_id": "uuid",
  "changes": [
    {
      "table_name": "messages",
      "operation": "INSERT",
      "record_id": "msg-uuid",
      "changed_fields": {
        "id": "msg-uuid",
        "content": "Hello from iOS",
        "sender_id": "user-uuid",
        "client_created_at": "2025-10-24T10:30:00Z"
      }
    }
  ]
}
```

**Push Response:**
```json
{
  "applied": 1,
  "failed": 0,
  "results": [
    {
      "success": true,
      "record_id": "msg-uuid"
    }
  ]
}
```

### ⚠️ PRD Gaps

**CDC Sync Not Documented:**
- PRD doesn't mention CDC (Change Data Capture) sync at all
- **Add new major section: "7. Offline Sync & CDC Architecture"**

```markdown
## 7. Offline Sync & CDC Architecture

### 7.1 CDC Overview

GlobalBridge uses Change Data Capture (CDC) for offline-first sync:
- SQLite database on iOS stores all thread data locally
- CDC logs track changes on both client and server
- Bidirectional sync: pull server changes, push local changes
- Conflict resolution via last-write-wins with server timestamp

### 7.2 iOS CDC Implementation

**Database Schema:**
```sql
CREATE TABLE cdc_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,  -- INSERT, UPDATE, DELETE
    record_id TEXT NOT NULL,
    changed_fields TEXT NOT NULL,  -- JSON
    timestamp TEXT NOT NULL,
    synced INTEGER DEFAULT 0
);

CREATE INDEX idx_cdc_logs_synced ON cdc_logs(synced, timestamp);
```

**Sync Service:**
```swift
class CDCSyncService {
    private let apiClient: APIClient
    private let database: Database

    // Pull changes from server
    func syncPull(threadId: String) async throws {
        let lastCursor = getLastSyncCursor(threadId)

        let response = try await apiClient.post("/api/v1/sync/pull", body: [
            "thread_id": threadId,
            "since": lastCursor?.iso8601 ?? ""
        ])

        for change in response.changes {
            try applyChange(change)
        }

        saveLastSyncCursor(threadId, cursor: response.nextCursor)
    }

    // Push local changes to server
    func syncPush(threadId: String) async throws {
        let unsyncedChanges = getUnsyncedChanges(threadId)

        guard !unsyncedChanges.isEmpty else { return }

        let response = try await apiClient.post("/api/v1/sync/push", body: [
            "thread_id": threadId,
            "changes": unsyncedChanges.map { $0.toJSON() }
        ])

        markChangesSynced(response.results)
    }

    // Full sync: pull then push
    func syncThread(threadId: String) async throws {
        try await syncPull(threadId)
        try await syncPush(threadId)
    }
}
```

### 7.3 Sync Strategy

**Periodic Sync:**
- Sync every 30 seconds when app is active
- Sync on app foreground
- Sync on network reconnection

**Real-time Sync:**
- Use WebSocket events for real-time updates
- Fall back to CDC pull if WebSocket disconnected
- Prefer WebSocket for immediate delivery

**Conflict Resolution:**
- Last-write-wins based on server timestamp
- Client cannot override server changes
- Server always has authority
```

---

## 6. Rate Limiting & Cost Controls

### ✅ What's Implemented

**Global API Rate Limit:**
- 100 requests per minute per IP address

**Auth Endpoints:**
- 5 requests per minute per IP address

**AI Endpoints (Per User, Per Tier):**
```elixir
# Free Tier
10 requests per day

# Pro Tier
100 requests per day

# Enterprise Tier
Unlimited (but still monitored)
```

**Backend Infrastructure:**
- Uses Hammer (https://github.com/ExHammer/hammer) for rate limiting
- Redis-backed for distributed rate limiting
- 429 status code with "Retry-After" header

### ⚠️ PRD Gaps

**Section 5.1 - Performance Targets:**
- PRD mentions performance targets but no rate limiting
- **Add**: Client-side rate limit handling
- **Add**: Quota UI (e.g., "7/10 AI requests today")

```swift
// MARK: - Rate Limit Handling
class RateLimitHandler {
    struct RateLimit {
        let limit: Int
        let remaining: Int
        let resetAt: Date
    }

    private var quotas: [String: RateLimit] = [:]

    func handleResponse(_ response: HTTPURLResponse) {
        if response.statusCode == 429 {
            // Too Many Requests
            if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
               let seconds = Int(retryAfter) {
                let resetAt = Date().addingTimeInterval(TimeInterval(seconds))
                // Show user-friendly message with countdown
                showRateLimitError(resetAt: resetAt)
            }
        }

        // Parse rate limit headers
        if let limit = response.value(forHTTPHeaderField: "X-RateLimit-Limit"),
           let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let resetTimestamp = response.value(forHTTPHeaderField: "X-RateLimit-Reset") {
            // Store quota info
            updateQuota(limit: Int(limit) ?? 0,
                       remaining: Int(remaining) ?? 0,
                       resetAt: Date(timeIntervalSince1970: Double(resetTimestamp) ?? 0))
        }
    }

    func showRateLimitError(resetAt: Date) {
        // Show banner: "Rate limit exceeded. Try again in 5 minutes."
    }
}
```

---

## 7. Message Schema Updates

### ✅ What's Implemented

**Message Fields:**
```swift
struct Message {
    let id: UUID
    let threadId: UUID
    let senderId: UUID
    let content: String
    let contentType: String  // "text", "image", "video", "audio", "file", "location"
    let mediaUrl: String?
    let mediaSize: Int?
    let mediaMimeType: String?
    let isEncrypted: Bool
    let encryptionKeyId: String?
    let replyToId: UUID?
    let isDeleted: Bool
    let deletedAt: Date?
    let editedAt: Date?
    let clientCreatedAt: Date?  // Client timestamp
    let insertedAt: Date        // Server timestamp
    let updatedAt: Date         // Server timestamp
}
```

### ⚠️ PRD Gaps

**Section 3.2 - MessageBubbleView:**
- PRD doesn't include all message fields
- **Add**: Media message support (images, videos, audio, files)
- **Add**: Reply-to functionality
- **Add**: Deleted message state
- **Add**: Edited indicator

**Recommended Update:**
```swift
struct MessageBubbleView: View {
    let message: Message
    @State private var showTranslation = false
    @State private var translation: TranslationResult?
    @State private var showReplyPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Show reply preview if replying to another message
            if let replyToId = message.replyToId {
                ReplyPreviewView(messageId: replyToId)
                    .padding(.bottom, 4)
            }

            // Message content based on type
            Group {
                switch message.contentType {
                case "text":
                    textMessageView
                case "image":
                    imageMessageView
                case "video":
                    videoMessageView
                case "audio":
                    audioMessageView
                case "file":
                    fileMessageView
                default:
                    unknownMessageView
                }
            }

            // Message metadata
            HStack(spacing: 8) {
                if message.editedAt != nil {
                    Text("(edited)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(message.insertedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if message.isEncrypted {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            // AI indicators (translation, tasks, cultural notes)
            aiIndicatorsView
        }
        .opacity(message.isDeleted ? 0.5 : 1.0)
        .contextMenu {
            if !message.isDeleted {
                Button("Reply") { showReplySheet() }
                Button("Translate") { showTranslation.toggle() }

                if message.senderId == currentUserId {
                    Button("Edit") { editMessage() }
                    Button("Delete", role: .destructive) { deleteMessage() }
                }
            }
        }
    }

    private var textMessageView: some View {
        Text(message.isDeleted ? "This message was deleted" : message.content)
            .padding(12)
            .background(message.isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
            .foregroundColor(message.isFromCurrentUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var imageMessageView: some View {
        AsyncImage(url: URL(string: message.mediaUrl ?? "")) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 250)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } placeholder: {
            ProgressView()
        }
    }
}
```

---

## 8. Bootstrap Endpoint

### ✅ What's Implemented

**Endpoint:**
```
GET /api/bootstrap
```

**Purpose:** Fetch initial data for the client on app launch

**Response (Assumed):**
```json
{
  "user": {
    "id": "uuid",
    "username": "john_doe",
    "display_name": "John Doe",
    "phone_number": "+1234567890",
    "avatar_url": "https://...",
    "tier": "pro",
    "public_key": "..."
  },
  "threads": [
    {
      "id": "uuid",
      "title": "Project Discussion",
      "last_message_at": "2025-10-24T12:00:00Z",
      "unread_count": 3
    }
  ],
  "features": {
    "tier": "pro",
    "features": {
      "ai_translation": true,
      "ai_search": true,
      "task_extraction": true
    },
    "limits": {
      "translations_per_day": 100,
      "threads_per_user": 50
    }
  }
}
```

### ⚠️ PRD Gaps

**Missing Bootstrap Flow:**
- PRD doesn't document initial app launch data loading
- **Add new section 2.6 - Bootstrap Flow**

```swift
// MARK: - Bootstrap Service
class BootstrapService {
    private let apiClient: APIClient

    struct BootstrapData: Codable {
        let user: User
        let threads: [ThreadSummary]
        let features: UserFeatures
    }

    func bootstrap() async throws -> BootstrapData {
        let response = try await apiClient.get("/api/bootstrap")
        return try JSONDecoder().decode(BootstrapData.self, from: response.data)
    }
}

// App launch flow
class AppCoordinator: ObservableObject {
    @Published var isBootstrapping = true
    @Published var bootstrapData: BootstrapData?

    func initialize() async {
        do {
            // 1. Load stored auth tokens
            guard let tokens = try KeychainManager.loadTokens() else {
                showLoginScreen()
                return
            }

            // 2. Refresh token if needed
            if tokens.isExpiringSoon {
                let newTokens = try await authService.refreshTokens(tokens.refresh)
                try KeychainManager.saveTokens(newTokens)
            }

            // 3. Fetch bootstrap data
            bootstrapData = try await bootstrapService.bootstrap()

            // 4. Initialize local database
            try await databaseManager.initialize()

            // 5. Sync threads
            for thread in bootstrapData.threads {
                try await syncService.syncThread(thread.id)
            }

            isBootstrapping = false
        } catch {
            handleBootstrapError(error)
        }
    }
}
```

---

## 9. Backend AI Architecture Details

### ✅ What's Implemented

**AI Infrastructure:**
- **Agens Framework**: Multi-agent AI orchestration
- **RAG (Retrieval-Augmented Generation)**: For summarization and task extraction
- **SQLite-vec**: Vector embeddings for semantic search (using `sqlite-vec` extension)
- **OpenAI API**: For embeddings and LLM calls
- **Cost Optimization**: Caching, budget monitoring, cost tracking

**AI Agents:**
```
LanguageDetectionAgent - Detect source language
TranslatorAgent - Translate text
SummarizerAgent - Generate thread summaries
RAGRetrieverAgent - Retrieve relevant context for queries
```

**AI Jobs (Background Processing):**
```
TranslationJob - Execute translation requests
SummarizationJob - Generate summaries with RAG
BatchEmbedJob - Generate embeddings in batches
GenerateEmbeddingJob - Generate single embedding
CleanupCacheJob - Clean old cache entries
```

**Cost Controls:**
```
BudgetMonitor - Track spending per user/tier
CostOptimizer - Select optimal AI models
CostTracker - Log AI usage and costs
TranslationCache - Cache translations to reduce API calls
```

### ⚠️ PRD Gaps

**Section 2.3 - Local AI Processing Strategy:**
- PRD focuses heavily on CoreML local processing
- **Reality**: Backend does all AI processing (no local models)
- **Update needed**: Remove or de-emphasize local CoreML models
- **Update needed**: Focus on caching strategy instead

**Recommended Changes:**
1. **Remove or mark as "Future Enhancement"**: CoreML integration (not currently implemented)
2. **Update Section 5.2 - Offline-First Architecture**:
   - Emphasize **caching** over local models
   - Document that AI features require internet
   - Only language detection can work offline (using iOS NLLanguageRecognizer)

```swift
// UPDATED: Simplified Offline Strategy
class OfflineAIManager {
    private let cache: CacheManager

    // Language detection works offline
    func detectLanguage(text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    // Translation - uses cache when offline
    func translate(text: String, to targetLang: String) async throws -> String {
        // Check cache first
        if let cached = cache.getCachedTranslation(text, targetLang) {
            return cached
        }

        // If offline, throw error
        guard networkMonitor.isOnline else {
            throw AIError.offline("Translation requires internet connection")
        }

        // Call backend API
        let result = try await aiService.translate(text: text, targetLanguage: targetLang)

        // Cache result
        cache.cacheTranslation(text, targetLang, result.translation)

        return result.translation
    }
}
```

---

## 10. Critical PRD Updates Summary

### 🚨 High Priority Updates

1. **Authentication Flow** (Section 2.2)
   - Add JWT token management
   - Add refresh token strategy
   - Add OAuth 2.0 (Auth0) support

2. **Phoenix Channel Integration** (Section 2.4 - NEW)
   - Document WebSocket connection
   - Document channel join/authorization
   - Document all channel events (client ↔ server)

3. **AI Service API** (Section 2.2, Section 4)
   - Update all request/response formats
   - Remove tone analysis or mark as placeholder
   - Add vec health check endpoint
   - Update error handling

4. **CDC Sync Architecture** (Section 7 - NEW)
   - Document CDC pull/push mechanism
   - Add sync service implementation
   - Add conflict resolution strategy

5. **Feature Flags** (Section 2.5 - NEW)
   - Document tier system (Free/Pro/Enterprise)
   - Add feature flag service
   - Add UI for tier limits/quotas

6. **Message Schema** (Section 3.2)
   - Add media message types
   - Add reply-to functionality
   - Add edit/delete functionality
   - Add E2EE fields

7. **Local AI Models** (Section 2.3, 5.2)
   - Remove CoreML implementation details
   - Emphasize caching strategy
   - Document offline limitations

8. **Rate Limiting** (Section 5.1 - UPDATE)
   - Add rate limit handling
   - Add quota UI components
   - Add retry strategies

### ⚙️ Medium Priority Updates

9. **Bootstrap Flow** (Section 2.6 - NEW)
   - Add app launch sequence
   - Document initial data loading

10. **Error Handling** (Throughout)
    - Add standard error response formats
    - Add offline error handling
    - Add rate limit error UI

### 📝 Low Priority Updates

11. **Siri Integration** (Section 5.3)
    - Already marked as deferred ✅
    - Keep as future enhancement

12. **Voice Transcription** (Section 5.3)
    - Already marked as deferred ✅
    - Keep as future enhancement

---

## 11. Implementation Checklist for iOS Team

### Phase 1: Core Infrastructure (Week 1-2)

- [ ] Implement JWT authentication with token refresh
- [ ] Set up Phoenix Socket/Channel manager
- [ ] Implement CDC sync service (pull/push)
- [ ] Create feature flags service
- [ ] Set up rate limit handling

### Phase 2: Messaging Core (Week 3-4)

- [ ] Implement WebSocket message sending/receiving
- [ ] Add CDC sync for messages
- [ ] Support media messages (images, videos, audio)
- [ ] Add reply-to functionality
- [ ] Implement edit/delete messages

### Phase 3: AI Features (Week 5-6)

- [ ] Translation service integration
- [ ] Thread summarization UI
- [ ] Semantic search interface
- [ ] Task extraction UI
- [ ] Caching layer for AI responses

### Phase 4: Polish & Optimization (Week 7-8)

- [ ] Offline mode improvements
- [ ] Presence tracking UI
- [ ] Read receipts
- [ ] Typing indicators
- [ ] Performance optimization

### Phase 5: Testing & Launch (Week 9-10)

- [ ] Integration testing
- [ ] Performance testing
- [ ] User acceptance testing
- [ ] App Store submission

---

## 12. API Documentation Gaps

### Missing API Docs

The backend implementation is complete but lacks comprehensive API documentation. The iOS team will need:

1. **OpenAPI/Swagger Spec**: Auto-generated API documentation
2. **Postman Collection**: For testing API endpoints
3. **WebSocket Event Catalog**: Complete list of channel events with examples
4. **Error Code Reference**: Standard error codes and messages
5. **Rate Limit Headers**: Documentation of rate limit response headers

### Recommended Actions

1. Add Swagger/OpenAPI generation to backend (using ex_doc or similar)
2. Create Postman workspace with all endpoints
3. Document all Phoenix Channel events in a markdown file
4. Create error code enum that both backend and iOS can reference

---

## Conclusion

The backend implementation is robust and production-ready, but the iOS Frontend PRD needs significant updates to reflect the actual API surface. The most critical gaps are:

1. ✅ **Authentication**: JWT-based auth with refresh tokens
2. ✅ **WebSocket Events**: Phoenix Channel integration
3. ✅ **CDC Sync**: Offline sync mechanism
4. ✅ **Feature Flags**: Tier-based feature access
5. ⚠️ **AI Processing**: All done on backend, not locally

**Next Steps:**
1. Update iOS PRD with changes outlined in this document
2. Generate comprehensive API documentation
3. Create iOS SDK/client library based on updated PRD
4. Begin Phase 1 implementation

---

**Document Version:** 1.0
**Last Updated:** 2025-10-24
**Review Status:** Ready for iOS Team Review
