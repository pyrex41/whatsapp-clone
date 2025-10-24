# AIService - Comprehensive AI Features for GlobalBridge

## Overview

The `AIService` class provides a complete HTTP networking layer for AI-powered features in the GlobalBridge iOS app. It integrates seamlessly with Auth0 authentication and the FeatureFlags system to provide tier-based access control.

## Features

### ✅ Implemented Capabilities

1. **Translation** - Translate text between languages with automatic source detection
2. **Thread Summarization** - Generate concise summaries of conversation threads
3. **Semantic Search** - Find messages using natural language queries
4. **Task Extraction** - Extract actionable items, deadlines, and decisions
5. **Tone Analysis** - Analyze emotional tone and sentiment of text

### 🔐 Security & Authentication

- **Auth0 Integration** - Automatic JWT token management
- **Token Refresh** - Seamless token renewal on expiry
- **Bearer Authentication** - All requests include `Authorization: Bearer <token>`
- **401 Handling** - Proper unauthorized response handling

### 🎯 Feature Flag Integration

- **Tier Checking** - Validates feature access before making requests
- **Quota Management** - Respects translation limits and other tier restrictions
- **Graceful Degradation** - Clear error messages when features unavailable

### 🔄 Robust Error Handling

- **Network Errors** - Automatic retry with exponential backoff
- **Rate Limiting** - 429 response handling with retry-after logic
- **Server Errors** - Automatic retry for transient failures (5xx)
- **Client Errors** - Detailed error messages for validation failures (4xx)
- **Timeout Handling** - 30-second request timeout

### ⚡ Performance Features

- **Retry Logic** - Up to 3 automatic retries with exponential backoff
- **Connection Pooling** - Uses shared URLSession for efficiency
- **Async/Await** - Modern Swift concurrency for smooth UI
- **Observable** - `@Published` properties for SwiftUI reactivity

## Architecture

```
AIService (Singleton)
├── HTTP Layer (URLSession)
├── Authentication (AuthManager)
├── Feature Flags (FeatureFlags)
├── Retry Logic (Exponential Backoff)
└── Error Handling (Comprehensive)
```

## Usage Examples

### 1. Translation

```swift
import SwiftUI

struct TranslationView: View {
    @StateObject private var aiService = AIService.shared
    @State private var originalText = ""
    @State private var translatedText = ""

    var body: some View {
        VStack {
            TextField("Enter text", text: $originalText)

            Button("Translate to Spanish") {
                Task {
                    do {
                        let result = try await aiService.translate(
                            text: originalText,
                            sourceLanguage: "en",
                            targetLanguage: "es"
                        )
                        translatedText = result.translatedText
                    } catch let error as AIServiceError {
                        print("Translation failed: \(error.localizedDescription)")
                    }
                }
            }
            .disabled(aiService.isProcessing)

            Text(translatedText)

            if aiService.isProcessing {
                ProgressView()
            }
        }
    }
}
```

### 2. Thread Summarization

```swift
func summarizeConversation(threadId: String) async {
    do {
        let result = try await AIService.shared.summarizeThread(
            threadId: threadId,
            maxLength: 200
        )

        print("Summary: \(result.summary)")
        print("Thread: \(result.threadId)")
    } catch AIServiceError.featureDisabled(let feature) {
        // Handle feature not available for tier
        print("Please upgrade to use \(feature)")
    } catch {
        print("Summarization failed: \(error.localizedDescription)")
    }
}
```

### 3. Semantic Search

```swift
func searchMessages(query: String, in threadId: String?) async {
    do {
        let results = try await AIService.shared.searchSemantic(
            query: query,
            threadId: threadId,
            limit: 20,
            recencyBias: true
        )

        for result in results {
            print("Found: \(result.content)")
            print("Score: \(result.relevanceScore)")
            print("Message ID: \(result.messageId)")
        }
    } catch AIServiceError.rateLimitExceeded(let retryAfter) {
        // Handle rate limiting
        if let delay = retryAfter {
            print("Rate limited. Retry in \(Int(delay)) seconds")
        }
    } catch {
        print("Search failed: \(error.localizedDescription)")
    }
}
```

### 4. Task Extraction

```swift
func extractTasksFromThread(threadId: String) async {
    do {
        let result = try await AIService.shared.extractTasks(
            threadId: threadId,
            query: "tasks, deadlines, action items"
        )

        print("📋 Tasks: \(result.tasks)")
        print("📅 Deadlines: \(result.deadlines)")
        print("✅ Decisions: \(result.decisions)")
    } catch {
        print("Task extraction failed: \(error.localizedDescription)")
    }
}
```

### 5. Tone Analysis

```swift
func analyzeMessageTone(text: String) async {
    do {
        let result = try await AIService.shared.analyzeTone(
            text: text,
            language: "en"
        )

        print("Tone: \(result.tone)")
        print("Confidence: \(result.confidence)")
        print("Emotions: \(result.emotions.joined(separator: ", "))")
    } catch {
        print("Tone analysis failed: \(error.localizedDescription)")
    }
}
```

## Error Handling Best Practices

### Handle Specific Errors

```swift
do {
    let result = try await AIService.shared.translate(
        text: "Hello",
        targetLanguage: "es"
    )
    // Use result
} catch AIServiceError.notAuthenticated {
    // Navigate to login
    showLoginScreen()
} catch AIServiceError.featureDisabled(let feature) {
    // Show upgrade prompt
    showUpgradePrompt(for: feature)
} catch AIServiceError.rateLimitExceeded(let retryAfter) {
    // Show rate limit message
    if let delay = retryAfter {
        showMessage("Please wait \(Int(delay)) seconds")
    }
} catch AIServiceError.networkError {
    // Show offline message
    showOfflineMessage()
} catch {
    // Generic error handling
    showError(error.localizedDescription)
}
```

### Observe Processing State

```swift
struct AIFeatureView: View {
    @StateObject private var aiService = AIService.shared

    var body: some View {
        VStack {
            if aiService.isProcessing {
                ProgressView("Processing...")
            }

            // Your AI feature UI

            Text("Total requests: \(aiService.requestCount)")
        }
    }
}
```

## Configuration

### Environment Variables

The service automatically detects the environment:

```swift
// Debug builds use localhost
#if DEBUG
http://localhost:4000

// Release builds use production
#else
https://globalbridge-backend.fly.dev
#endif
```

Override with environment variable:
```bash
BACKEND_ENV=production
```

### Custom Configuration

```swift
// Custom URLSession (for testing)
let customSession = URLSession(configuration: .default)
let aiService = AIService(session: customSession)

// Custom base URL
let customURL = URL(string: "https://custom-backend.com")!
let aiService = AIService(baseURL: customURL)
```

## Testing

### Mock Service for Unit Tests

```swift
class MockAIService: AIService {
    var shouldFail = false
    var mockTranslation = "Hola mundo"

    override func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String
    ) async throws -> TranslationResult {
        if shouldFail {
            throw AIServiceError.networkError(NSError())
        }

        return TranslationResult(
            originalText: text,
            translatedText: mockTranslation,
            sourceLanguage: sourceLanguage ?? "auto",
            targetLanguage: targetLanguage,
            confidence: 0.95
        )
    }
}
```

### Integration Tests

```swift
func testTranslationFlow() async throws {
    let service = AIService.shared

    let result = try await service.translate(
        text: "Hello world",
        sourceLanguage: "en",
        targetLanguage: "es"
    )

    XCTAssertEqual(result.translatedText, "Hola mundo")
    XCTAssertEqual(result.targetLanguage, "es")
}
```

## API Endpoints

| Feature | Endpoint | Method |
|---------|----------|--------|
| Translation | `/api/v1/ai/translate` | POST |
| Summarization | `/api/v1/ai/summarize_thread` | POST |
| Semantic Search | `/api/v1/ai/search_semantic` | POST |
| Task Extraction | `/api/v1/ai/extract_tasks` | POST |
| Tone Analysis | `/api/v1/ai/analyze_tone` | POST |

## Rate Limiting

The service handles rate limiting automatically:

1. **Detection** - Identifies 429 responses
2. **Parse Headers** - Reads `X-RateLimit-Reset` and `Retry-After`
3. **Automatic Retry** - Waits and retries (up to 3 attempts)
4. **User Feedback** - Provides retry time in error message

Example rate limit headers:
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1704067200
Retry-After: 60
```

## Feature Flags

Before making AI requests, the service checks feature availability:

```swift
// Translation
guard featureFlags.hasFeature(.translationEnabled) else {
    throw AIServiceError.featureDisabled(feature: "translation")
}

// Summarization
guard featureFlags.hasFeature(.threadSummarization) else {
    throw AIServiceError.featureDisabled(feature: "thread_summarization")
}

// Semantic Search
guard featureFlags.hasFeature(.semanticSearch) else {
    throw AIServiceError.featureDisabled(feature: "semantic_search")
}
```

## Performance Considerations

### Request Timeout

Default: 30 seconds
```swift
private let requestTimeout: TimeInterval = 30.0
```

### Retry Strategy

- **Max Retries**: 3 attempts
- **Initial Delay**: 1 second
- **Strategy**: Exponential backoff (1s, 2s, 3s)
- **Applies To**: Network errors, 5xx responses, 429 rate limits

### Memory Management

- Singleton pattern prevents multiple instances
- No data caching (stateless service)
- Minimal memory footprint (~KB range)

## Logging

The service provides detailed logging for debugging:

```
🤖 [AI_SERVICE] Initialized with base URL: http://localhost:4000
🌐 [AI_SERVICE] Translating text (12 chars) from auto to es
📡 [AI_SERVICE] Response status: 200
✅ [AI_SERVICE] Translation successful
```

Log levels:
- 🤖 Initialization
- 🌐 Request start
- 📡 Response received
- ✅ Success
- ⚠️ Warning
- ❌ Error
- 🔄 Retry

## Security Best Practices

1. **Never Log Tokens** - Auth tokens are redacted in logs
2. **HTTPS Only** - Production uses secure connections
3. **Token Refresh** - Automatic renewal before expiry
4. **Secure Storage** - Tokens stored via AuthManager/Keychain
5. **Input Validation** - All inputs validated before sending

## Migration from Old Implementation

If you had a previous AI service:

```swift
// Old
let translation = oldService.translate(text: "Hello")

// New (async/await)
let result = try await AIService.shared.translate(
    text: "Hello",
    targetLanguage: "es"
)
let translation = result.translatedText
```

## Troubleshooting

### Issue: "Not authenticated"
**Solution**: Ensure user is logged in via AuthManager
```swift
await AuthManager.shared.login()
```

### Issue: "Feature disabled"
**Solution**: Check user's tier and feature flags
```swift
let hasTier = FeatureFlags.shared.hasFeature(.translationEnabled)
```

### Issue: "Rate limit exceeded"
**Solution**: Wait for retry-after period or upgrade tier
```swift
catch AIServiceError.rateLimitExceeded(let retryAfter) {
    // Wait for retry-after seconds
}
```

### Issue: "Network error"
**Solution**: Check internet connection and backend availability
```swift
// Backend health check
curl http://localhost:4000/api/health
```

## Future Enhancements

Potential additions:
- [ ] Response caching for repeated queries
- [ ] Batch translation support
- [ ] Streaming responses for long-running operations
- [ ] Offline queue for requests
- [ ] Analytics integration
- [ ] Custom retry strategies per endpoint

## Dependencies

- **Foundation** - Core networking (URLSession)
- **Combine** - Reactive properties (@Published)
- **AuthManager** - JWT token management
- **FeatureFlags** - Tier-based access control

## Support

For issues or questions:
1. Check backend API documentation: `/docs/API_DOCUMENTATION.md`
2. Review error messages (they're descriptive!)
3. Enable debug logging in Debug builds
4. Check backend health endpoint

---

**Version**: 1.0.0
**Last Updated**: 2025-10-24
**Author**: Task #6.2 - AI Service Implementation
