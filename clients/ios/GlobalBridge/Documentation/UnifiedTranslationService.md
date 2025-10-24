# UnifiedTranslationService Documentation

## Overview

`UnifiedTranslationService` is the primary translation orchestration layer for the GlobalBridge iOS app. It intelligently selects between Apple Translation (on-device, privacy-first) and Backend Translation (cloud-based, advanced features) based on network conditions, language support, feature flags, and rate limits.

**Location:** `Core/Services/AI/UnifiedTranslationService.swift`

## Features

### ✅ Intelligent Provider Selection
- **Auto Mode**: Automatically selects the best provider based on:
  - Network connectivity (offline → Apple)
  - Language pair support (unsupported by Apple → Backend)
  - Rate limit quotas (quota exceeded → Apple fallback)
  - Default preference (Backend for better quality)

### ✅ Multiple Translation Providers
- **Apple Translation**: On-device, privacy-first, offline-capable, 12+ language pairs
- **Backend Translation**: Cloud-based, advanced features, cultural notes, 100+ languages
- **Hybrid Mode**: Translates with both providers simultaneously for comparison
- **Auto Selection**: Smart selection based on context

### ✅ Robust Fallback Strategy
```
Primary → Fallback → Error
Backend → Apple (if online) → Throw error
Apple → Backend (if online) → Throw error
Hybrid → Return partial results → Throw if both fail
```

### ✅ Feature Flag Integration
- Checks `FeatureFlags.translationEnabled` before translation
- Respects tier-based quotas and limits
- Graceful degradation when features disabled

### ✅ Comprehensive Metrics
- Total translations count
- Provider usage breakdown (Apple/Backend/Hybrid)
- Cache hit rate tracking
- Fallback event monitoring
- Average latency tracking
- Error count tracking
- Offline translation tracking

### ✅ Smart Caching
- Results cached by text + language pair + provider
- Cache-first strategy for performance
- Manual cache clearing available
- Cache hit tracking in metrics

## Architecture

### Provider Selection Flow

```
┌─────────────────────────────────────────┐
│ UnifiedTranslationService.translate()   │
└─────────────────┬───────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │ selectProvider │
         └────────┬───────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌────────┐   ┌──────────┐  ┌─────────┐
│ Apple  │   │ Backend  │  │ Hybrid  │
└────────┘   └──────────┘  └─────────┘
    │             │             │
    └─────────────┼─────────────┘
                  │
                  ▼
         ┌────────────────┐
         │ Cache & Return │
         └────────────────┘
```

### Auto-Selection Rules (in priority order)

1. **Offline?** → Use Apple Translation
2. **Language unsupported by Apple?** → Use Backend Translation
3. **Backend quota exceeded?** → Use Apple Translation
4. **Default** → Use Backend Translation (better quality)

## Usage

### Basic Translation

```swift
import GlobalBridge

let service = UnifiedTranslationService.shared

// Auto-selection (recommended)
let result = try await service.translate(
    text: "Hello, world!",
    from: "en",
    to: "es",
    provider: .auto
)

print(result.translatedText)  // "¡Hola, mundo!"
print(result.provider)         // "backend" or "apple"
print(result.confidence)       // 0.95
```

### Explicit Provider Selection

```swift
// Force Apple Translation (on-device)
let appleResult = try await service.translate(
    text: "Hello, world!",
    from: "en",
    to: "es",
    provider: .apple
)

// Force Backend Translation (cloud)
let backendResult = try await service.translate(
    text: "Hello, world!",
    from: "en",
    to: "es",
    provider: .backend
)
```

### Hybrid Mode (Quality Comparison)

```swift
// Translate with both providers
let hybridResult = try await service.translate(
    text: "Hello, world!",
    from: "en",
    to: "es",
    provider: .hybrid
)

// Primary result (Backend)
print(hybridResult.translatedText)        // Backend translation
print(hybridResult.provider)              // "backend"

// Alternate result (Apple)
print(hybridResult.alternateTranslation)  // Apple translation
print(hybridResult.alternateProvider)     // "apple"
print(hybridResult.alternateConfidence)   // 0.85
```

### Metrics Tracking

```swift
// Get translation metrics
let metrics = service.getMetrics()

print("Total: \(metrics.totalTranslations)")
print("Apple: \(metrics.appleTranslations)")
print("Backend: \(metrics.backendTranslations)")
print("Cache Hit Rate: \(metrics.cacheHitRate * 100)%")
print("Average Latency: \(metrics.averageLatencyMs)ms")
print("Fallback Events: \(metrics.fallbackEvents)")
```

### Configuration

```swift
// Set preferred provider (used when .auto is specified)
service.setPreferredProvider(.apple)

// Clear translation cache
service.clearCache()
```

## SwiftUI Integration

### Basic View

```swift
struct TranslationView: View {
    @StateObject private var service = UnifiedTranslationService.shared
    @State private var inputText = ""
    @State private var result: UnifiedTranslationResult?

    var body: some View {
        VStack {
            TextField("Enter text", text: $inputText)

            Button("Translate") {
                Task {
                    result = try? await service.translate(
                        text: inputText,
                        from: "en",
                        to: "es"
                    )
                }
            }

            if let result = result {
                Text(result.translatedText)
                Text("Provider: \(result.provider)")
                    .font(.caption)
            }
        }
    }
}
```

### Observing Metrics

```swift
struct MetricsView: View {
    @ObservedObject var service = UnifiedTranslationService.shared

    var body: some View {
        VStack {
            Text("Translations: \(service.metrics.totalTranslations)")
            Text("Cache Hit Rate: \(service.metrics.cacheHitRate, format: .percent)")
            Text("Avg Latency: \(service.metrics.averageLatencyMs, format: .number)ms")
        }
    }
}
```

## Error Handling

```swift
do {
    let result = try await service.translate(
        text: "Hello",
        from: "en",
        to: "es"
    )
    print(result.translatedText)

} catch AIServiceError.featureDisabled(let feature) {
    // Feature not available for user's tier
    print("Feature disabled: \(feature)")

} catch AIServiceError.networkError(let error) {
    // Network issue (offline, timeout, etc.)
    print("Network error: \(error)")

} catch AIServiceError.rateLimitExceeded(let retryAfter, _, _) {
    // Quota exceeded
    if let retry = retryAfter {
        print("Retry after \(retry)")
    }

} catch AIServiceError.invalidText {
    // Empty or invalid text
    print("Invalid input text")

} catch {
    // Other errors
    print("Translation failed: \(error)")
}
```

## Best Practices

### 1. Use Auto Selection
```swift
// ✅ Good: Let the service decide
try await service.translate(text: text, from: "en", to: "es", provider: .auto)

// ❌ Avoid: Hard-coding provider unless necessary
try await service.translate(text: text, from: "en", to: "es", provider: .backend)
```

### 2. Handle Errors Gracefully
```swift
// ✅ Good: Handle specific error cases
do {
    let result = try await service.translate(...)
} catch AIServiceError.featureDisabled {
    // Show upgrade prompt
} catch AIServiceError.networkError {
    // Show offline message
} catch {
    // Generic error handling
}
```

### 3. Cache Results When Appropriate
```swift
// Cache is automatic - but consider clearing on memory warnings
func handleMemoryWarning() {
    service.clearCache()
}
```

### 4. Monitor Metrics for Analytics
```swift
// Track metrics for user behavior analysis
let metrics = service.getMetrics()
Analytics.log("translation_cache_hit_rate", metrics.cacheHitRate)
Analytics.log("translation_avg_latency", metrics.averageLatencyMs)
```

### 5. Use Hybrid Mode Sparingly
```swift
// Hybrid mode uses 2x resources
// Only use when:
// - Comparing provider quality
// - User explicitly requests comparison
// - A/B testing translation providers

let result = try await service.translate(
    text: longDocument,
    from: "en",
    to: "es",
    provider: .hybrid
)
```

## Testing

### Unit Tests

```swift
import XCTest
@testable import GlobalBridge

@MainActor
class UnifiedTranslationTests: XCTestCase {
    var sut: UnifiedTranslationService!

    override func setUp() async throws {
        sut = .shared
    }

    func testAutoSelectionUsesBackendWhenOnline() async throws {
        let result = try await sut.translate(
            text: "Hello",
            from: "en",
            to: "es",
            provider: .auto
        )

        XCTAssertEqual(result.provider, "backend")
    }
}
```

### Mock for Testing

```swift
// Use dependency injection for testing
protocol TranslationServiceProtocol {
    func translate(
        text: String,
        from: String,
        to: String,
        provider: TranslationProvider
    ) async throws -> UnifiedTranslationResult
}

// In production
let service: TranslationServiceProtocol = UnifiedTranslationService.shared

// In tests
let service: TranslationServiceProtocol = MockTranslationService()
```

## Performance Considerations

### Latency Benchmarks

| Provider | Average Latency | Notes |
|----------|----------------|-------|
| Apple (cached model) | 50-100ms | Instant after model download |
| Apple (first use) | 2-5s | One-time model download |
| Backend | 200-500ms | Depends on network speed |
| Hybrid | 200-500ms | Concurrent, takes as long as slowest |

### Memory Usage

- **Apple Translation**: ~50MB per active language pair model
- **Backend Translation**: Minimal (~5MB for networking)
- **Cache**: ~1MB per 100 cached translations

### Optimization Tips

1. **Pre-download models**: Call `AppleTranslationService.downloadModel()` during onboarding
2. **Batch translations**: For multiple texts, use individual calls but manage concurrency
3. **Clear cache on memory warnings**: Implement memory warning handlers
4. **Prefer Apple offline**: Saves network bandwidth and backend quota

## Roadmap

### Future Enhancements

- [ ] Batch translation API
- [ ] Streaming translation for long texts
- [ ] Translation quality feedback system
- [ ] User preference learning
- [ ] Language detection improvements
- [ ] Context-aware translations
- [ ] Translation history persistence

## Related Documentation

- [AppleTranslationService.md](./AppleTranslationService.md) - On-device translation
- [BackendTranslationService.md](./BackendTranslationService.md) - Cloud translation
- [FeatureFlags.md](./FeatureFlags.md) - Tier-based feature gating
- [AIServiceCache.md](./AIServiceCache.md) - Caching strategy
- [RateLimitTracker.md](./RateLimitTracker.md) - Quota management

## Support

For issues or questions:
- GitHub Issues: [globalbridge-ios/issues](https://github.com/org/globalbridge-ios/issues)
- Internal Slack: #ios-translation-support
- Documentation: [Full API Docs](https://docs.globalbridge.io/ios/translation)
