# iOS AIServiceProtocol Design Documentation

**Task:** #6.1 - Define AIServiceProtocol
**Date:** 2025-10-24
**Status:** ✅ Complete

---

## Overview

This document describes the foundational AI service architecture for the GlobalBridge iOS application. The AIServiceProtocol provides a clean, testable interface for all AI-powered features including translation, thread summarization, semantic search, and task extraction.

---

## Architecture Summary

### Design Principles

1. **Protocol-Oriented Design**
   - Enables easy testing with mock implementations
   - Allows for future alternative implementations (local AI models, different providers)
   - Follows Swift best practices and iOS architecture patterns

2. **Async/Await Pattern**
   - Modern Swift concurrency for cleaner code
   - Avoids callback hell and completion handler complexity
   - Better error handling with structured concurrency

3. **Typed Errors**
   - Comprehensive AIServiceError enum with specific cases
   - Enables proper error handling and recovery strategies
   - Supports rate limiting retry logic with metadata

4. **Backend Contract Compliance**
   - All methods map directly to backend API endpoints
   - Request/response models match backend JSON schemas exactly
   - Snake_case backend fields automatically converted to camelCase Swift

---

## File Structure

```
/Core/AI/
├── Protocols/
│   └── AIServiceProtocol.swift          # Main protocol definition
├── Errors/
│   └── AIServiceError.swift             # Comprehensive error types
└── Models/
    ├── TranslationResult.swift          # Translation response model
    ├── ThreadSummary.swift              # Thread summarization model
    ├── SearchResult.swift               # Semantic search results
    ├── ExtractedTask.swift              # Task extraction model
    └── VectorHealthStatus.swift         # Vector DB health check
```

---

## Protocol Definition

### AIServiceProtocol

```swift
protocol AIServiceProtocol {
    // Translation
    func translate(text: String, from: String, to: String) async throws -> TranslationResult

    // Thread Summarization
    func summarizeThread(threadId: UUID, maxLength: Int?) async throws -> ThreadSummary

    // Semantic Search
    func searchSemantic(query: String, in: UUID?, limit: Int,
                       recencyBias: Bool, translate: Bool) async throws -> [SearchResult]

    // Task Extraction
    func extractTasks(from: UUID, query: String?) async throws -> [ExtractedTask]

    // Health Check
    func checkVectorHealth(for: UUID) async throws -> VectorHealthStatus
}
```

### Default Parameters

Convenience extensions provide sensible defaults:
- `translate()` - Auto-detects source language ("auto")
- `summarizeThread()` - Uses backend default max length
- `searchSemantic()` - Searches all threads, limit 10, recency bias enabled
- `extractTasks()` - No query filter (extracts all task types)

---

## Backend API Mapping

### 1. Translation
**Endpoint:** `POST /api/v1/ai/translate`

**Request:**
```json
{
  "text": "Hello world",
  "target_language": "es",
  "source_language": "en"  // optional, defaults to "auto"
}
```

**Response:**
```json
{
  "success": true,
  "translation": "Hola mundo",
  "source_language": "en",
  "target_language": "es",
  "confidence": 0.95,
  "provider": "openai",
  "cultural_notes": "Informal greeting"
}
```

**Swift Model:** `TranslationResult`
- Includes original text for context
- Timestamp for caching
- Confidence score for UI feedback

---

### 2. Thread Summarization
**Endpoint:** `POST /api/v1/ai/summarize_thread`

**Request:**
```json
{
  "thread_id": "uuid",
  "max_length": 200
}
```

**Response:**
```json
{
  "success": true,
  "summary": "Team discussed Q4 roadmap...",
  "thread_id": "uuid",
  "key_topics": ["roadmap", "deadlines", "resources"],
  "decisions": ["Launch delayed to Nov 15"],
  "action_items": [
    {
      "description": "Finalize mockups",
      "assignee": "john",
      "due_date": "2025-10-30",
      "priority": "high"
    }
  ],
  "participants": [
    {
      "user_id": "uuid",
      "username": "john",
      "display_name": "John Doe",
      "message_count": 12
    }
  ],
  "message_count": 45,
  "provider": "anthropic"
}
```

**Swift Model:** `ThreadSummary`
- Nested `ActionItem` and `Participant` types
- Priority and status enums
- Helper properties for filtering and display

---

### 3. Semantic Search
**Endpoint:** `POST /api/v1/ai/search_semantic`

**Request:**
```json
{
  "query": "project deadline",
  "thread_id": "uuid",  // optional
  "limit": 10,
  "recency_bias": true,
  "translate": false
}
```

**Response:**
```json
{
  "success": true,
  "results": [
    {
      "message_id": "uuid",
      "thread_id": "uuid",
      "content": "The project deadline is October 30th",
      "sender_id": "uuid",
      "sender_username": "jane",
      "sender_display_name": "Jane Smith",
      "timestamp": "2025-10-20T10:30:00Z",
      "relevance_score": 0.92,
      "snippet": "...project deadline is October 30th...",
      "translated": false
    }
  ],
  "total_results": 5,
  "thread_id": "uuid"
}
```

**Swift Model:** `SearchResult`
- Nested `MessageInfo` type
- Relevance percentage helpers
- Sorting and filtering extensions

---

### 4. Task Extraction
**Endpoint:** `POST /api/v1/ai/extract_tasks`

**Request:**
```json
{
  "thread_id": "uuid",
  "query": "tasks, deadlines, decisions"  // optional
}
```

**Response:**
```json
{
  "success": true,
  "extraction": {
    "tasks": [
      {
        "title": "Update documentation",
        "description": "Update API docs with new endpoints",
        "assignee": "john",
        "due_date": "2025-10-25",
        "priority": "medium",
        "task_type": "action",
        "confidence": 0.88,
        "related_message_ids": ["uuid1", "uuid2"],
        "tags": ["documentation", "api"]
      }
    ],
    "decisions": [...],
    "deadlines": [...]
  },
  "thread_id": "uuid"
}
```

**Swift Model:** `ExtractedTask`
- Priority, Status, TaskType enums
- Overdue/due-soon computed properties
- Grouping and sorting helpers

---

### 5. Vector Health Check
**Endpoint:** `POST /api/v1/ai/vec_health`

**Request:**
```json
{
  "thread_id": "uuid"
}
```

**Response:**
```json
{
  "success": true,
  "thread_id": "uuid",
  "shard_id": "shard-abc-123",
  "message_count": 150,
  "embedded_count": 147,
  "status": "healthy",
  "provider": "sqlite_vec",
  "last_update": "2025-10-24T12:00:00Z"
}
```

**Swift Model:** `VectorHealthStatus`
- HealthStatus enum (healthy, degraded, unhealthy, initializing, unavailable)
- Coverage percentage calculation
- Estimated completion time for pending embeddings

---

## Error Handling

### AIServiceError Enum

Comprehensive error cases with localized descriptions:

```swift
enum AIServiceError: LocalizedError {
    // Network
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String?)

    // Authentication
    case unauthorized
    case forbidden

    // Rate Limiting
    case rateLimitExceeded(retryAfter: Date?, remainingQuota: Int?, tierLimit: String?)
    case featureNotAvailable(feature: String, requiredTier: String)

    // Validation
    case invalidInput(reason: String)
    case threadNotFound(threadId: UUID)
    case invalidText
    case unsupportedLanguage(code: String)

    // Parsing
    case decodingError(Error)
    case backendError(message: String)

    // Vector Database
    case vectorDatabaseError(reason: String)
    case noEmbeddingsAvailable(threadId: UUID)

    // Feature Flags
    case featureDisabled(feature: String)

    // Unknown
    case unknown(Error)
}
```

### Error Metadata

Each error provides:
- **errorDescription**: User-friendly message
- **failureReason**: Why the error occurred
- **recoverySuggestion**: How to fix the issue

### Helper Properties

```swift
extension AIServiceError {
    var shouldRetry: Bool          // Auto-retry for network/5xx errors
    var requiresAuth: Bool         // Needs token refresh
    var isTierLimited: Bool        // Requires plan upgrade
}
```

### Rate Limit Handling

Rate limit errors include parsed headers:
- `X-RateLimit-Reset` → `retryAfter: Date?`
- `X-RateLimit-Remaining` → `remainingQuota: Int?`
- `X-RateLimit-Tier` → `tierLimit: String?`

---

## Model Features

### Common Patterns

All models include:
1. **Codable Conformance** - JSON serialization
2. **Equatable Conformance** - Value comparison
3. **Identifiable Conformance** - SwiftUI compatibility
4. **CodingKeys** - Snake_case ↔ camelCase conversion
5. **Backend DTOs** - Separate API response types
6. **Domain Models** - Clean Swift types for app logic
7. **Helper Extensions** - Computed properties and utilities
8. **Display Helpers** - UI-ready formatted strings

### Example: TranslationResult

```swift
struct TranslationResult: Codable, Equatable {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let confidence: Double?
    let provider: String?
    let culturalNotes: String?
    let timestamp: Date

    // Helpers
    var isHighConfidence: Bool { confidence ?? 0 > 0.8 }
    var hasCulturalNotes: Bool { !(culturalNotes?.isEmpty ?? true) }
    var isFresh: Bool { Date().timeIntervalSince(timestamp) < 300 }
    var cacheKey: String { /* ... */ }

    // Display
    var sourceLanguageName: String { /* ... */ }
    var targetLanguageName: String { /* ... */ }
    var confidencePercentage: String? { /* ... */ }
}
```

---

## Integration Requirements

### 1. Authentication
- All API calls require JWT tokens from AuthManager
- Use `AuthManager.shared.getAccessToken()`
- Handle 401 responses with token refresh
- Handle 403 responses with permission errors

### 2. Feature Flags
- Check `FeatureFlags` before API calls
- Gracefully degrade when features disabled
- Show upgrade prompts for tier-limited features

Example:
```swift
guard await featureFlags.isEnabled(.translation) else {
    throw AIServiceError.featureDisabled(feature: "Translation")
}

guard await featureFlags.hasAccess(to: .semanticSearch) else {
    throw AIServiceError.featureNotAvailable(
        feature: "Semantic Search",
        requiredTier: "Pro"
    )
}
```

### 3. Rate Limiting
- Parse `X-RateLimit-*` headers from responses
- Implement exponential backoff for retries
- Show user-friendly quota messages
- Provide upgrade prompts when appropriate

### 4. Caching
- TranslationResult: Cache by `cacheKey`
- ThreadSummary: Invalidate on new messages
- SearchResult: Cache with TTL
- ExtractedTask: Sync with local task storage

### 5. Error Recovery
- Network errors: Auto-retry with backoff
- 5xx errors: Retry up to 3 times
- 429 errors: Wait for `retryAfter` date
- 401 errors: Refresh token and retry once
- Vector errors: Show "initializing" state

---

## Testing Strategy

### Mock Implementation

```swift
class MockAIService: AIServiceProtocol {
    var shouldFail = false
    var mockTranslation: TranslationResult?
    var mockSummary: ThreadSummary?
    // ...

    func translate(...) async throws -> TranslationResult {
        if shouldFail { throw AIServiceError.networkError(...) }
        return mockTranslation ?? defaultTranslation
    }
}
```

### Test Cases

1. **Success Paths**
   - Each API call with valid inputs
   - Proper model parsing
   - Helper properties work correctly

2. **Error Paths**
   - Network failures
   - Invalid responses
   - Rate limiting
   - Authentication failures
   - Feature flag checks

3. **Edge Cases**
   - Empty strings
   - Missing optional fields
   - Invalid UUIDs
   - Malformed JSON
   - Concurrent requests

---

## Future Enhancements

### Planned Improvements

1. **Streaming Responses**
   - Large thread summaries
   - Progressive search results
   - Real-time translation

2. **Local AI Models**
   - On-device translation (Core ML)
   - Offline semantic search
   - Privacy-focused processing

3. **Caching Layer**
   - In-memory cache with LRU eviction
   - Persistent cache with SwiftData
   - Cache invalidation strategies

4. **Batch Operations**
   - Translate multiple messages
   - Summarize multiple threads
   - Bulk task extraction

5. **Performance Monitoring**
   - API latency tracking
   - Error rate monitoring
   - Usage analytics
   - Cache hit rates

---

## Implementation Checklist

### Task #6.1 Deliverables ✅

- [x] AIServiceProtocol.swift with all method signatures
- [x] AIServiceError enum with comprehensive error cases
- [x] TranslationResult model with backend mapping
- [x] ThreadSummary model with nested types
- [x] SearchResult model with relevance scoring
- [x] ExtractedTask model with priority/status
- [x] VectorHealthStatus model for health checks
- [x] API request/response DTOs for all endpoints
- [x] Helper extensions for all models
- [x] Display helpers for UI integration
- [x] Documentation of design decisions

### Next Steps (Task #6.2+)

- [ ] Implement AIService class conforming to protocol
- [ ] Add URLSession networking layer
- [ ] Integrate with AuthManager for JWT tokens
- [ ] Integrate with FeatureFlags service
- [ ] Implement caching strategy
- [ ] Add retry logic with exponential backoff
- [ ] Create unit tests for protocol and models
- [ ] Create integration tests with mock backend

---

## Key Design Decisions

### 1. Why Protocol-Oriented?
**Decision:** Use protocol instead of concrete class
**Rationale:** Enables testing with mocks, supports multiple implementations (cloud API, local models, test doubles)
**Trade-off:** Slightly more verbose, but vastly improves testability

### 2. Why Async/Await?
**Decision:** Use async/await instead of callbacks
**Rationale:** Modern Swift concurrency, cleaner code, better error handling
**Trade-off:** Requires iOS 15+, but project already targets iOS 15

### 3. Why Separate DTOs?
**Decision:** Separate API response DTOs from domain models
**Rationale:** Decouples API contract from app logic, easier to evolve independently
**Trade-off:** More code, but cleaner architecture and easier migrations

### 4. Why Comprehensive Errors?
**Decision:** Detailed error enum with metadata
**Rationale:** Enables proper error handling, retry logic, user feedback
**Trade-off:** Larger error type, but much better UX

### 5. Why Helper Extensions?
**Decision:** Rich computed properties on models
**Rationale:** Keeps view logic simple, reusable across app
**Trade-off:** Models are larger, but views are much cleaner

---

## Performance Considerations

### API Call Optimization

1. **Debouncing** - Translation should debounce user input (500ms)
2. **Batching** - Group multiple requests when possible
3. **Caching** - Cache frequently accessed data (translations, summaries)
4. **Prefetching** - Load summaries/health proactively
5. **Cancellation** - Cancel in-flight requests when view disappears

### Memory Management

1. **Lazy Loading** - Load search results paginated
2. **Image Caching** - Cache user avatars in search results
3. **Model Size** - Keep models lightweight (use UUIDs, not full objects)
4. **Cleanup** - Clear old cached data periodically

---

## Security Considerations

1. **Authentication** - All requests require valid JWT
2. **Rate Limiting** - Backend enforces per-user quotas
3. **Input Validation** - Validate all inputs client-side
4. **Sensitive Data** - Never log message content
5. **Error Messages** - Don't expose internal errors to users

---

## Conclusion

The AIServiceProtocol provides a robust, testable foundation for all AI features in the iOS app. The protocol-oriented design enables easy testing, the comprehensive error handling supports great UX, and the rich model types make UI integration straightforward.

**Next Task:** Implement concrete AIService class with networking layer (Task #6.2)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-24
**Task Status:** ✅ Complete
