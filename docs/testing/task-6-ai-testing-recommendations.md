# Task #6: AI Service - Testing Recommendations

**Date:** October 24, 2025
**Based on:** Task #5 Feature Flags Testing Success
**Project:** WhatsApp-clone iOS with Phoenix LiveView Backend

---

## Executive Summary

Based on the comprehensive testing approach from Task #5 (230+ test cases, 92% coverage), this document provides actionable recommendations for testing the AI Service implementation in Task #6.

---

## Test Suite Structure

### Recommended Test Files

```
clients/ios/GlobalBridge/Tests/AIService/
├── AIServiceTests.swift              (50+ cases) - Core service logic
├── AITranslationTests.swift          (40+ cases) - Translation feature
├── AISummarizationTests.swift        (40+ cases) - Thread summarization
├── AISemanticSearchTests.swift       (40+ cases) - Semantic search
├── AINetworkTests.swift              (50+ cases) - API integration
├── AIOfflineTests.swift              (60+ cases) - Caching & offline
├── AIUIComponentTests.swift          (50+ cases) - UI components
└── Mocks/
    ├── MockAIService.swift
    ├── MockURLProtocol.swift (reuse from Task #5)
    └── MockAuthManager.swift (reuse from Task #5)

Total: ~330+ test cases
```

---

## Reusable Patterns from Task #5

### 1. Network Mocking with URLProtocol

```swift
// Reuse MockURLProtocol from FeatureFlagsServiceTests
class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler not set")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

**Usage in AI Service:**
```swift
func testTranslateMessageSuccess() async throws {
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)
        let json = """
        {
            "data": {
                "translated_text": "Hola mundo",
                "source_language": "en",
                "target_language": "es",
                "tokens_used": 15
            }
        }
        """
        return (response, json.data(using: .utf8))
    }

    let result = try await aiService.translate(text: "Hello world", to: "es")
    XCTAssertEqual(result.translatedText, "Hola mundo")
}
```

---

### 2. Caching and Offline Tests

```swift
// Reuse caching patterns from FeatureFlagsOfflineTests
func testTranslationCachePersistence() {
    // Given - Cache translation
    let cacheKey = "translation_cache_en_es_hello_world"
    let cacheJSON = """
    {
        "translated_text": "Hola mundo",
        "source_language": "en",
        "target_language": "es",
        "cached_at": "2025-10-24T14:00:00Z"
    }
    """
    UserDefaults.standard.set(cacheJSON.data(using: .utf8), forKey: cacheKey)

    // When - Load from cache
    let cached = aiService.loadTranslationFromCache(text: "Hello world", to: "es")

    // Then
    XCTAssertEqual(cached?.translatedText, "Hola mundo")
}

func testOfflineTranslationFallback() async {
    // Given - No network, cache exists
    MockURLProtocol.requestHandler = { _ in
        throw NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
    }

    // When - Attempt translation
    do {
        let result = try await aiService.translate(text: "Hello", to: "es")
        XCTFail("Should fall back to cache or throw error")
    } catch {
        // Then - Should use cached translation if available
        XCTAssertNotNil(error)
    }
}
```

---

### 3. Thread Safety Tests

```swift
// Reuse concurrent access patterns from FeatureFlagsTests
func testConcurrentTranslationRequests() async {
    let iterations = 50

    await withTaskGroup(of: String?.self) { group in
        for i in 0..<iterations {
            group.addTask {
                do {
                    let result = try await self.aiService.translate(
                        text: "Message \(i)",
                        to: "es"
                    )
                    return result.translatedText
                } catch {
                    return nil
                }
            }
        }

        var results: [String?] = []
        for await result in group {
            results.append(result)
        }

        XCTAssertEqual(results.count, iterations)
    }
}
```

---

### 4. Performance Benchmarks

```swift
// Reuse performance measurement from FeatureFlagsTests
func testTranslationPerformance() async {
    measure {
        Task {
            do {
                _ = try await aiService.translate(text: "Hello world", to: "es")
            } catch {
                XCTFail("Translation failed: \(error)")
            }
        }
    }
}

func testTranslationLargeTextPerformance() async {
    // Given - 500-word message
    let longText = String(repeating: "Hello world. ", count: 50) // ~500 words

    // When/Then - Should complete in <3s
    let start = Date()
    let result = try? await aiService.translate(text: longText, to: "es")
    let duration = Date().timeIntervalSince(start)

    XCTAssertNotNil(result)
    XCTAssertLessThan(duration, 3.0, "Translation should complete in <3s")
}
```

---

## AI-Specific Test Cases

### 1. Translation Service Tests

```swift
// Translation success cases
testTranslateTextSuccess()
testTranslateMultipleLanguages() // en→es, en→fr, en→de, etc.
testTranslateEmptyText()
testTranslateLongText() // 500+ words
testTranslateSpecialCharacters() // Emojis, symbols
testTranslateHTMLContent()
testTranslateMarkdown()

// Translation error cases
testTranslateUnsupportedLanguage()
testTranslateRateLimitExceeded()
testTranslateQuotaExceeded()
testTranslateNetworkFailure()
testTranslateInvalidAPIKey()

// Translation caching
testTranslationCache Hit()
testTranslationCacheMiss()
testTranslationCacheExpiry() // 24-hour TTL
testTranslationCacheEviction() // LRU policy

// Translation token counting
testTokenCountingForShortText()
testTokenCountingForLongText()
testRemainingTokensCalculation()
testTokenQuotaEnforcement()
```

---

### 2. Summarization Service Tests

```swift
// Summarization success cases
testSummarizeThreadSuccess()
testSummarizeEmptyThread()
testSummarizeSingleMessage()
testSummarizeMultipleMessages() // 10, 50, 100 messages
testSummarizeDifferentLengths() // Short/medium/long summaries
testSummarizeWithImages() // Skip image messages
testSummarizeWithLinks()

// Summarization error cases
testSummarizeRateLimitExceeded()
testSummarizeNetworkFailure()
testSummarizeInvalidThread()

// Summarization performance
testSummarize50MessagesPerformance() // <5s target
testSummarize100MessagesPerformance() // <10s target

// Summarization caching
testSummarizationCacheHit()
testSummarizationCacheMiss()
testSummarizationCacheInvalidation() // New messages
```

---

### 3. Semantic Search Tests

```swift
// Search success cases
testSemanticSearchSuccess()
testSemanticSearchEmptyQuery()
testSemanticSearchNoResults()
testSemanticSearchMultipleResults()
testSemanticSearchRanking() // Relevance scoring
testSemanticSearchAcrossThreads()
testSemanticSearchWithFilters() // Date, user, thread

// Search error cases
testSemanticSearchRateLimitExceeded()
testSemanticSearchNetworkFailure()
testSemanticSearchInvalidQuery()

// Search performance
testSemanticSearch1000MessagesPerformance() // <2s target
testSemanticSearch10000MessagesPerformance() // <5s target

// Search caching
testSemanticSearchQueryCache()
testSemanticSearchEmbeddingCache()
testSemanticSearchCacheInvalidation()
```

---

## Integration with Feature Flags

### Test Feature Flag Integration

```swift
func testTranslationRequiresFeatureFlag() async {
    // Given - Translation feature disabled
    FeatureFlags.shared.clearCache() // Default to free tier

    // When - Attempt translation
    do {
        _ = try await aiService.translate(text: "Hello", to: "es")
        XCTFail("Should require feature flag")
    } catch AIService.AIServiceError.featureNotAvailable {
        // Then - Should throw feature not available error
        XCTAssertTrue(true)
    } catch {
        XCTFail("Wrong error type")
    }
}

func testTranslationWithProTier() async {
    // Given - Pro tier with translation enabled
    let cacheJSON = """
    {
        "tier": "pro",
        "features": {"translation_enabled": true},
        "limits": null,
        "translation_limit": 500
    }
    """
    UserDefaults.standard.set(cacheJSON.data(using: .utf8), forKey: "cached_features")

    // When - Attempt translation
    let result = try? await aiService.translate(text: "Hello", to: "es")

    // Then - Should succeed
    XCTAssertNotNil(result)
}

func testTranslationQuotaEnforcement() async {
    // Given - 500 translation limit
    let cacheJSON = """
    {
        "tier": "pro",
        "features": {"translation_enabled": true},
        "limits": null,
        "translation_limit": 500
    }
    """
    UserDefaults.standard.set(cacheJSON.data(using: .utf8), forKey: "cached_features")

    // Track usage
    aiService.translationUsage = 499

    // When - Translate (should succeed)
    let result1 = try? await aiService.translate(text: "Hello", to: "es")
    XCTAssertNotNil(result1)

    // When - Translate again (should fail - quota exceeded)
    do {
        _ = try await aiService.translate(text: "World", to: "es")
        XCTFail("Should exceed quota")
    } catch AIService.AIServiceError.quotaExceeded {
        XCTAssertTrue(true)
    } catch {
        XCTFail("Wrong error type")
    }
}
```

---

## Streaming Response Tests

### Test OpenAI/Claude Streaming

```swift
func testStreamingTranslation() async throws {
    // Given - Mock streaming response
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, ...)

        // Simulate SSE streaming
        let chunks = [
            "data: {\"delta\": \"Ho\"}\\n\\n",
            "data: {\"delta\": \"la \"}\\n\\n",
            "data: {\"delta\": \"mundo\"}\\n\\n",
            "data: [DONE]\\n\\n"
        ]
        let streamData = chunks.joined().data(using: .utf8)

        return (response, streamData)
    }

    // When - Stream translation
    var chunks: [String] = []
    for try await chunk in aiService.streamTranslation(text: "Hello world", to: "es") {
        chunks.append(chunk)
    }

    // Then - Should receive all chunks
    XCTAssertEqual(chunks, ["Ho", "la ", "mundo"])
}

func testStreamingErrorHandling() async throws {
    // Given - Streaming fails midway
    MockURLProtocol.requestHandler = { request in
        throw NSError(domain: "StreamError", code: 1, userInfo: nil)
    }

    // When/Then - Should handle error gracefully
    do {
        for try await _ in aiService.streamTranslation(text: "Hello", to: "es") {
            XCTFail("Should throw error")
        }
    } catch {
        XCTAssertNotNil(error)
    }
}
```

---

## Mock AI Service

### Create Reusable Mock

```swift
class MockAIService: AIServiceProtocol {
    var shouldSucceed = true
    var mockTranslation: TranslationResult?
    var mockSummary: SummaryResult?
    var mockSearchResults: [SearchResult] = []
    var tokensUsed = 0
    var callCount = 0

    func translate(text: String, to language: String) async throws -> TranslationResult {
        callCount += 1

        guard shouldSucceed else {
            throw AIServiceError.networkError(NSError())
        }

        guard let result = mockTranslation else {
            return TranslationResult(
                translatedText: "Mock translation",
                sourceLanguage: "en",
                targetLanguage: language,
                tokensUsed: 10
            )
        }

        return result
    }

    func summarize(thread: Thread) async throws -> SummaryResult {
        callCount += 1

        guard shouldSucceed else {
            throw AIServiceError.networkError(NSError())
        }

        return mockSummary ?? SummaryResult(
            summary: "Mock summary",
            messageCount: thread.messages.count,
            tokensUsed: 50
        )
    }

    func search(query: String, in threads: [Thread]) async throws -> [SearchResult] {
        callCount += 1

        guard shouldSucceed else {
            throw AIServiceError.networkError(NSError())
        }

        return mockSearchResults
    }
}
```

**Usage:**
```swift
func testViewModelWithMockAI() async {
    // Given
    let mockAI = MockAIService()
    mockAI.mockTranslation = TranslationResult(
        translatedText: "Hola mundo",
        sourceLanguage: "en",
        targetLanguage: "es",
        tokensUsed: 15
    )

    let viewModel = ChatViewModel(aiService: mockAI)

    // When
    await viewModel.translateMessage("Hello world", to: "es")

    // Then
    XCTAssertEqual(viewModel.translatedText, "Hola mundo")
    XCTAssertEqual(mockAI.callCount, 1)
}
```

---

## Performance Targets

### Key Metrics

| Operation | Target | Test Method |
|-----------|--------|-------------|
| Translation (short) | <1s | `testTranslateShortTextPerformance()` |
| Translation (500 words) | <3s | `testTranslateLongTextPerformance()` |
| Summarization (50 msgs) | <5s | `testSummarize50MessagesPerformance()` |
| Summarization (100 msgs) | <10s | `testSummarize100MessagesPerformance()` |
| Semantic search (1K msgs) | <2s | `testSemanticSearch1000MessagesPerformance()` |
| Semantic search (10K msgs) | <5s | `testSemanticSearch10000MessagesPerformance()` |
| Cache load | <100ms | `testCacheLoadPerformance()` |
| Token counting | <10ms | `testTokenCountingPerformance()` |

---

## Error Handling Test Matrix

### All Error Scenarios

| Error Type | HTTP Status | Test Case |
|-----------|-------------|-----------|
| Unauthorized | 401 | `testAIServiceUnauthorized()` |
| Forbidden | 403 | `testAIServiceForbidden()` |
| Rate Limited | 429 | `testAIServiceRateLimited()` |
| Quota Exceeded | 402/custom | `testAIServiceQuotaExceeded()` |
| Invalid Request | 400 | `testAIServiceInvalidRequest()` |
| Server Error | 500 | `testAIServiceServerError()` |
| Timeout | - | `testAIServiceTimeout()` |
| No Internet | - | `testAIServiceNoInternet()` |
| Invalid Response | - | `testAIServiceInvalidResponse()` |
| Feature Disabled | - | `testAIServiceFeatureDisabled()` |

---

## Coverage Targets

### Component Coverage Goals

| Component | Target Coverage | Priority |
|-----------|----------------|----------|
| AI Service Core | 95%+ | P0 |
| Translation | 95%+ | P0 |
| Summarization | 95%+ | P0 |
| Semantic Search | 90%+ | P0 |
| Network Layer | 90%+ | P0 |
| Cache Layer | 90%+ | P0 |
| UI Components | 85%+ | P1 |
| Feature Integration | 90%+ | P0 |
| **Overall Target** | **92%+** | - |

---

## CI/CD Integration

### Recommended Pipeline

```yaml
# .github/workflows/ios-tests.yml
name: iOS Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.0'

      - name: Run Tests
        run: |
          cd clients/ios/GlobalBridge
          xcodebuild test \
            -scheme GlobalBridge \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
            -enableCodeCoverage YES \
            -resultBundlePath TestResults

      - name: Generate Coverage Report
        run: |
          xcrun xccov view --report TestResults.xcresult > coverage.txt
          cat coverage.txt

      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: coverage.txt
```

---

## Success Criteria for Task #6

### Must Have (P0)
- [ ] AI Service core tests (50+ cases)
- [ ] Translation tests (40+ cases)
- [ ] Summarization tests (40+ cases)
- [ ] Semantic search tests (40+ cases)
- [ ] Network layer tests (50+ cases)
- [ ] Offline/cache tests (60+ cases)
- [ ] All tests passing
- [ ] 92%+ code coverage
- [ ] Performance targets met

### Should Have (P1)
- [ ] UI component tests (50+ cases)
- [ ] Streaming tests
- [ ] Feature flag integration tests
- [ ] Mock objects created
- [ ] Documentation complete

### Nice to Have (P2)
- [ ] Snapshot tests
- [ ] CI/CD pipeline
- [ ] Integration tests with real backend
- [ ] Load testing (concurrent requests)

---

## Timeline Estimate

### Test Development
- **AI Service Core:** 2 hours
- **Translation:** 2 hours
- **Summarization:** 2 hours
- **Semantic Search:** 2 hours
- **Network/Offline:** 2 hours
- **UI Components:** 2 hours
- **Integration & Fixes:** 2 hours

**Total:** ~14 hours (2 working days)

---

## Conclusion

Following the testing patterns from Task #5 will ensure comprehensive coverage for the AI Service. The key is to:

1. **Reuse proven patterns** (URLProtocol mocking, caching, thread safety)
2. **Test AI-specific behaviors** (streaming, token counting, quota enforcement)
3. **Maintain high coverage** (92%+ target)
4. **Measure performance** (meet latency targets)
5. **Document thoroughly** (like this report)

With this approach, Task #6 testing should achieve the same quality and coverage as Task #5.

---

**Document Version:** 1.0
**Last Updated:** October 24, 2025, 2:15 PM
**Ready for Task #6 Implementation:** ✅
