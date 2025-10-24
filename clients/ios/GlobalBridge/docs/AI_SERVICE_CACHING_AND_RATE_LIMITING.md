# AI Service Caching and Rate Limiting

**Version:** 1.0
**Last Updated:** 2025-10-24
**Status:** Production Ready

---

## Overview

The AI Service infrastructure provides intelligent caching and rate limiting for all AI-powered features in GlobalBridge Messenger. This system ensures optimal performance, cost efficiency, and a smooth user experience while respecting backend rate limits and tier-based quotas.

---

## Architecture

### Components

1. **AIService** - Main service interface for AI features
2. **AIServiceCache** - Multi-tier caching system (memory + disk)
3. **RateLimitTracker** - Quota tracking and rate limit enforcement
4. **FeatureFlags** - Tier-based feature access control

### Data Flow

```
User Request
    ↓
[AIService]
    ↓
[Check Rate Limit] → Denied? → Return Error
    ↓ Allowed
[Check Cache] → Hit? → Return Cached Result
    ↓ Miss
[Make Backend Request]
    ↓
[Process Response]
    ↓
[Update Rate Limit State]
    ↓
[Cache Result]
    ↓
Return to User
```

---

## AIServiceCache

### Features

- **Two-Tier Storage**: Memory (NSCache) + Disk (FileManager)
- **LRU Eviction**: Automatic memory management via NSCache
- **TTL-Based Expiry**: Different TTLs per cache type
- **Size Limits**: 20MB memory, 50MB disk (configurable)
- **Metrics Tracking**: Hit rate, memory/disk hits, misses
- **Memory Pressure Handling**: Automatic cleanup on memory warnings

### Cache Types and TTLs

| Cache Type    | TTL       | Reason                                    |
|---------------|-----------|-------------------------------------------|
| Translation   | 24 hours  | Translations are stable and reusable      |
| Summary       | 1 hour    | Summaries change with new messages        |
| Search        | 30 minutes| Search results can change frequently      |
| Tasks         | 2 hours   | Tasks are relatively stable               |

### Usage

```swift
// Store item in cache
await AIServiceCache.shared.store(
    translationResult,
    forKey: "hello_en_es",
    type: .translation
)

// Retrieve from cache
if let cached: TranslationResult = await AIServiceCache.shared.retrieve(
    forKey: "hello_en_es",
    type: .translation
) {
    // Use cached result
}

// Remove specific item
AIServiceCache.shared.remove(forKey: "hello_en_es", type: .translation)

// Clear all caches
await AIServiceCache.shared.clearAll()

// Get metrics
let metrics = AIServiceCache.shared.getMetrics()
print("Hit rate: \(metrics.hitRate * 100)%")
```

### Cache Key Generation

Cache keys are generated using base64 encoding of the request parameters to ensure:
- Unique keys for different requests
- Safe filenames for disk storage
- Collision avoidance

Example:
```swift
private func translationCacheKey(text: String, target: String, source: String?) -> String {
    let sourceKey = source ?? "auto"
    return "\(text)_\(sourceKey)_\(target)".data(using: .utf8)?.base64EncodedString() ?? text
}
```

### Cache Invalidation

- **Automatic**: Expired items are removed during retrieval
- **Manual**: Call `remove(forKey:type:)` to invalidate specific items
- **Type-based**: Call `clear(type:)` to clear all items of a type
- **Full clear**: Call `clearAll()` to remove everything

### Memory Management

The cache responds to memory warnings by clearing the in-memory cache:

```swift
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    ...
) { [weak self] _ in
    self?.memoryCache.removeAllObjects()
}
```

### Disk Cache Limits

When disk cache exceeds 50MB:
1. Get all cached files with modification dates
2. Sort by date (oldest first)
3. Remove oldest files until under limit
4. Log cleanup statistics

---

## RateLimitTracker

### Features

- **Tier-Aware Limits**: Different quotas for free/pro/enterprise
- **Per-Feature Tracking**: Separate quotas for each AI feature
- **Backend Rate Limit Parsing**: Respects `X-RateLimit-*` headers
- **Exponential Backoff**: Automatic retry logic for 429 responses
- **Daily Quota Reset**: Automatic reset at midnight UTC
- **Usage Metrics**: Real-time quota tracking for UI display

### Tier Limits

| Feature           | Free Tier | Pro Tier  | Enterprise  |
|-------------------|-----------|-----------|-------------|
| Translation       | Backend*  | Backend*  | Unlimited   |
| Summarization     | 10/day    | 100/day   | Unlimited   |
| Semantic Search   | 50/day    | 500/day   | Unlimited   |
| Task Extraction   | 20/day    | 200/day   | Unlimited   |

*Translation limits are provided by the backend API

### Usage

```swift
// Check if request is allowed
let check = RateLimitTracker.shared.canMakeRequest(for: .translation)

switch check {
case .allowed(let remaining, let resetDate):
    // Make request
    print("Remaining: \(remaining ?? -1)")

case .quotaExceeded(let limit, let used, let resetDate):
    // Show quota exceeded error
    print("Quota exceeded: \(used)/\(limit)")

case .rateLimited(let resetDate, let waitTime):
    // Wait until reset date
    print("Rate limited, retry at \(resetDate)")

case .backoff(let retryAfter, let attemptCount):
    // In exponential backoff
    print("Backoff attempt \(attemptCount), retry at \(retryAfter)")

case .denied(let reason):
    // Feature disabled or not authenticated
    print("Denied: \(reason)")
}

// Record successful request
RateLimitTracker.shared.recordRequest(for: .translation)

// Process backend rate limit headers
RateLimitTracker.shared.processRateLimitHeaders(
    ["X-RateLimit-Limit": "100", "X-RateLimit-Remaining": "87"],
    for: .translation
)

// Handle 429 response
RateLimitTracker.shared.handle429Response(for: .translation, retryAfter: 60)
```

### Backend Rate Limit Headers

The tracker parses standard rate limit headers:

```
X-RateLimit-Limit: 100          // Total allowed requests
X-RateLimit-Remaining: 87       // Remaining requests
X-RateLimit-Reset: 1640000000   // Unix timestamp for reset
```

### Exponential Backoff

When receiving 429 responses, the tracker implements exponential backoff:

- **Attempt 1**: Wait 2^1 = 2 seconds
- **Attempt 2**: Wait 2^2 = 4 seconds
- **Attempt 3**: Wait 2^3 = 8 seconds
- **Maximum**: Capped at 5 minutes

If `Retry-After` header is provided, it takes precedence.

### Quota Persistence

Quota usage is persisted to UserDefaults:
- Survives app restarts
- Resets daily at midnight UTC
- Cleared on logout

### Quota Summary for UI

```swift
let summary = RateLimitTracker.shared.getQuotaSummary()

for (feature, info) in summary {
    print("\(feature.displayName):")
    print("  Used: \(info.used)")
    print("  Limit: \(info.limit?.description ?? "Unlimited")")
    print("  Remaining: \(info.remaining?.description ?? "∞")")
    print("  Percentage: \(info.percentageUsed)%")
    print("  Near limit: \(info.isNearLimit)")
    print("  Exceeded: \(info.isExceeded)")
}
```

---

## AIService

### Features

The AIService provides four main AI-powered features:

1. **Translation**: Translate text with language detection
2. **Thread Summarization**: Generate conversation summaries
3. **Semantic Search**: Cross-language message search
4. **Task Extraction**: Extract actionable tasks from threads

### Translation

```swift
let result = try await AIService.shared.translate(
    text: "Hello, world!",
    targetLanguage: "es",
    sourceLanguage: "en"  // Optional, defaults to auto-detect
)

print("Translated: \(result.translatedText)")
print("Detected language: \(result.detectedLanguage ?? "unknown")")
print("Confidence: \(result.confidence ?? 0.0)")
```

**Caching**: Translations are cached for 24 hours (same text + language pair)

**Rate Limiting**: Respects backend translation limits (tier-based)

### Thread Summarization

```swift
let summary = try await AIService.shared.summarizeThread(
    threadId: "thread_123",
    invalidateCache: false  // Set true to force refresh
)

print("Summary: \(summary.summary)")
print("Key points: \(summary.keyPoints ?? [])")
print("Messages: \(summary.messageCount ?? 0)")
```

**Caching**: Summaries cached for 1 hour, invalidated manually when new messages arrive

**Rate Limiting**: 10/100/unlimited per day (free/pro/enterprise)

### Semantic Search

```swift
let results = try await AIService.shared.semanticSearch(
    query: "meeting tomorrow",
    threadId: "thread_123"  // Optional, search specific thread
)

for result in results {
    print("\(result.content) - Score: \(result.score)")
}
```

**Caching**: Search results cached for 30 minutes

**Rate Limiting**: 50/500/unlimited per day (free/pro/enterprise)

### Task Extraction

```swift
let tasks = try await AIService.shared.extractTasks(threadId: "thread_123")

for task in tasks {
    print("Task: \(task.description)")
    print("Assignee: \(task.assignee ?? "Unassigned")")
    print("Due: \(task.dueDate?.description ?? "No due date")")
    print("Priority: \(task.priority ?? "Normal")")
}
```

**Caching**: Not cached (tasks change frequently)

**Rate Limiting**: 20/200/unlimited per day (free/pro/enterprise)

### Error Handling

```swift
do {
    let result = try await AIService.shared.translate(...)
} catch AIServiceError.rateLimited(let message) {
    // Show rate limit error to user
    print("Rate limited: \(message)")
} catch AIServiceError.notAuthenticated {
    // Prompt user to log in
} catch AIServiceError.httpError(let statusCode) {
    // Handle HTTP errors
    print("HTTP error: \(statusCode)")
} catch {
    // Handle other errors
    print("Error: \(error)")
}
```

### Retry Logic

The AIService automatically retries 429 responses up to 3 times with exponential backoff:

```swift
if httpResponse.statusCode == 429 {
    rateLimiter.handle429Response(for: feature, retryAfter: retryAfter)

    if attempt < config.maxRetries {
        let backoffTime = retryAfter ?? pow(2.0, Double(attempt))
        try await Task.sleep(nanoseconds: UInt64(backoffTime * 1_000_000_000))
        return try await performTranslation(..., attempt: attempt + 1)
    }
}
```

---

## Integration with FeatureFlags

The rate limiting system integrates with the feature flags service to respect tier-based access:

```swift
// Check if feature is enabled for user's tier
guard featureFlags.hasFeature(.translationEnabled) else {
    return .denied(reason: .featureDisabled)
}

// Get tier-specific limits
let limit = getTierLimit(for: feature)

// For translation, use backend-provided limit
if feature == .translation {
    return featureFlags.getTranslationLimit()
}
```

---

## Performance Metrics

### Cache Performance

```swift
let metrics = AIService.shared.getCacheMetrics()

print("Total requests: \(metrics.totalRequests)")
print("Total hits: \(metrics.totalHits)")
print("Memory hits: \(metrics.memoryHits)")
print("Disk hits: \(metrics.diskHits)")
print("Misses: \(metrics.misses)")
print("Hit rate: \(metrics.hitRate * 100)%")
print("Memory hit rate: \(metrics.memoryHitRate * 100)%")
```

### Quota Metrics

```swift
let quotaSummary = AIService.shared.getQuotaSummary()

for (feature, summary) in quotaSummary {
    print("\(feature.displayName):")
    print("  Usage: \(summary.percentageUsed)%")
    print("  Near limit: \(summary.isNearLimit)")
    print("  Exceeded: \(summary.isExceeded)")
}
```

---

## Best Practices

### For App Developers

1. **Always check cache first** before making requests
2. **Handle rate limit errors gracefully** with user-friendly messages
3. **Invalidate caches when appropriate** (e.g., new messages in thread)
4. **Show quota usage in UI** to help users manage their limits
5. **Implement debouncing** for search queries to avoid excessive requests
6. **Use batch operations** where possible

### For Backend Integration

1. **Always include rate limit headers** in responses:
   - `X-RateLimit-Limit`
   - `X-RateLimit-Remaining`
   - `X-RateLimit-Reset`
2. **Provide Retry-After header** in 429 responses
3. **Keep tier limits consistent** between backend and iOS
4. **Log rate limit violations** for monitoring

### For Testing

1. **Test with different tiers** (free/pro/enterprise)
2. **Verify cache expiration** works correctly
3. **Simulate 429 responses** to test backoff logic
4. **Test quota reset** at midnight
5. **Verify cache persistence** across app restarts

---

## Troubleshooting

### Issue: Cache not working

**Check:**
- Is caching enabled in configuration?
- Are cache keys generated consistently?
- Is disk cache directory writable?

**Solution:**
```swift
let metrics = AIServiceCache.shared.getMetrics()
print("Hit rate: \(metrics.hitRate)") // Should be > 0 for repeated requests
```

### Issue: Rate limit exceeded unexpectedly

**Check:**
- Current quota usage: `RateLimitTracker.shared.getUsage(for: feature)`
- Tier limits: `RateLimitTracker.shared.getQuotaSummary()`
- Daily reset time

**Solution:**
```swift
// Reset quotas for testing
RateLimitTracker.shared.resetQuotas()

// Or clear all data
RateLimitTracker.shared.clearAll()
```

### Issue: 429 responses not handled

**Check:**
- Are rate limit headers being parsed?
- Is exponential backoff working?
- Are retry attempts being made?

**Solution:**
```swift
// Enable detailed logging
print("[AI_SERVICE] Processing 429 response")
rateLimiter.handle429Response(for: feature, retryAfter: retryAfter)
```

---

## Future Enhancements

### Planned Features

1. **Predictive prefetching**: Cache common translations proactively
2. **Smart cache warming**: Pre-load frequently accessed data
3. **Analytics dashboard**: Detailed usage statistics
4. **Offline mode improvements**: Better cache management when offline
5. **Background cache cleanup**: Scheduled maintenance tasks
6. **Cache compression**: Reduce disk space usage
7. **Cache sharing**: Share translations across users (privacy-safe)

### Performance Improvements

1. **Batch request API**: Send multiple requests in one call
2. **WebSocket streaming**: Real-time AI responses
3. **Edge caching**: CDN integration for common translations
4. **Client-side ML**: On-device translation for common phrases

---

## API Reference

### AIServiceCache

```swift
class AIServiceCache {
    static let shared: AIServiceCache

    func store<T: Codable>(_ item: T, forKey key: String, type: CacheType) async
    func retrieve<T: Codable>(forKey key: String, type: CacheType) async -> T?
    func remove(forKey key: String, type: CacheType)
    func clearAll() async
    func clear(type: CacheType) async
    func getMetrics() -> CacheMetrics
    func getDiskCacheSize() -> Int64
}

enum CacheType: String {
    case translation, summary, search, tasks
}

struct CacheMetrics {
    let memoryHits: Int
    let diskHits: Int
    let misses: Int
    let totalHits: Int
    let totalRequests: Int
    let hitRate: Double
    let memoryHitRate: Double
}
```

### RateLimitTracker

```swift
class RateLimitTracker {
    static let shared: RateLimitTracker

    func canMakeRequest(for feature: AIFeature) -> RateLimitCheckResult
    func recordRequest(for feature: AIFeature)
    func processRateLimitHeaders(_ headers: [String: String], for feature: AIFeature)
    func handle429Response(for feature: AIFeature, retryAfter: TimeInterval?)
    func getUsage(for feature: AIFeature) -> Int
    func getRemainingQuota(for feature: AIFeature) -> Int?
    func getQuotaSummary() -> [AIFeature: QuotaSummary]
    func resetQuotas()
    func clearAll()
}

enum AIFeature: String {
    case translation, summarization, search, taskExtraction
}

enum RateLimitCheckResult {
    case allowed(remaining: Int?, resetDate: Date)
    case quotaExceeded(limit: Int, used: Int, resetDate: Date)
    case rateLimited(resetDate: Date, waitTime: TimeInterval)
    case backoff(retryAfter: Date, attemptCount: Int)
    case denied(reason: DenialReason)
}

struct QuotaSummary {
    let feature: AIFeature
    let limit: Int?
    let used: Int
    let remaining: Int?
    let resetDate: Date
    let enabled: Bool
    let percentageUsed: Double
    let isNearLimit: Bool
    let isExceeded: Bool
}
```

### AIService

```swift
class AIService {
    static let shared: AIService

    func translate(text: String, targetLanguage: String, sourceLanguage: String?) async throws -> TranslationResult
    func summarizeThread(threadId: String, invalidateCache: Bool) async throws -> ThreadSummary
    func semanticSearch(query: String, threadId: String?) async throws -> [SearchResult]
    func extractTasks(threadId: String) async throws -> [ExtractedTask]

    func getQuotaSummary() -> [AIFeature: QuotaSummary]
    func getCacheMetrics() -> CacheMetrics
    func clearCaches() async
    func resetRateLimits()
}
```

---

**Document maintained by:** iOS Team
**Questions/Issues:** Contact #ios-dev on Slack
