# Translation Services Testing Delegation Plan
**Version:** 1.0
**Date:** 2025-10-24
**Project:** WhatsApp-clone iOS GlobalBridge
**Target:** Tasks #7-10 Comprehensive Testing (340+ Test Cases)

---

## Executive Summary

This document outlines the comprehensive testing strategy for the Translation Services system in the GlobalBridge iOS app. Building on the success of Tasks #5 & #6 (510+ tests successfully delegated), we're coordinating testing for the complete translation chain: Apple Translation Framework, Backend AI Translation, Unified Translation Service, and Message Bubble UI.

**Key Metrics:**
- **Total Test Cases:** 340+ comprehensive tests
- **Target Code Coverage:** 90%+ for services, 85%+ for UI
- **Timeline:** 6-8 business days (parallel execution)
- **Delegation:** 4 parallel workstreams via Zen MCP
- **Quality Gate:** 100% API endpoint coverage + zero accessibility violations

---

## 1. Current State Analysis

### 1.1 Existing Test Infrastructure

**Strengths from Tasks #5 & #6:**
```swift
// Located: /clients/ios/GlobalBridge/Tests/

✅ AIServiceCacheTests.swift (175 lines, 12 test methods)
   - Memory cache validation
   - Disk persistence testing
   - Cache metrics tracking
   - TTL expiry verification

✅ FeatureFlagsTests.swift (multiple test suites)
   - Tier-based feature access
   - Feature flag persistence
   - Offline feature management
   - Usage quota tracking

✅ Integration test patterns established
   - OfflineSyncIntegrationTests.swift
   - Phoenix channel integration tests
   - CDC sync validation
```

**Key Patterns to Reuse:**
1. **Actor-based async testing** with XCTest async/await
2. **Mock infrastructure** (already have AIServiceCache mocks)
3. **Feature flag integration** in tests
4. **Offline/online scenario testing**
5. **Performance assertion patterns**

### 1.2 Translation Architecture Context

**Services Under Test:**

```swift
// Task #7: AppleTranslationService
- Location: /clients/ios/GlobalBridge/Core/Services/Translation/
- Dependencies: Translation framework (iOS 17.4+), FeatureFlags
- Key Features: On-device translation, language availability, batch translation

// Task #8: BackendTranslationService
- Location: /clients/ios/GlobalBridge/Core/Services/AI/
- Dependencies: AIService, AuthManager, AIServiceCache
- Key Features: Context-aware translation, cultural notes, rate limiting

// Task #9: UnifiedTranslationService
- Location: /clients/ios/GlobalBridge/Core/Services/Translation/
- Dependencies: AppleTranslationService, BackendTranslationService, FeatureFlags
- Key Features: Provider selection, hybrid mode, offline strategy

// Task #10: Message Bubble UI
- Location: /clients/ios/GlobalBridge/Views/Messages/
- Dependencies: UnifiedTranslationService, Message models
- Key Features: Translation toggle, provider badges, loading states
```

---

## 2. Mock Infrastructure Design

### 2.1 Core Mocks Required

**File:** `/clients/ios/GlobalBridge/Tests/Mocks/Translation/MockTranslationSession.swift`

```swift
import Translation

/// Mock for Apple's TranslationSession
class MockTranslationSession {
    var shouldSucceed = true
    var translationDelay: TimeInterval = 0.1
    var mockTranslations: [String: String] = [:]
    var translateCallCount = 0
    var batchTranslateCallCount = 0

    func translate(_ text: String) async throws -> MockTranslationResponse {
        translateCallCount += 1
        try await Task.sleep(nanoseconds: UInt64(translationDelay * 1_000_000_000))

        guard shouldSucceed else {
            throw TranslationError.sessionFailed
        }

        let translated = mockTranslations[text] ?? "TRANSLATED: \(text)"
        return MockTranslationResponse(sourceText: text, targetText: translated)
    }

    func translations(from requests: [MockTranslationRequest]) async throws -> [MockTranslationResponse] {
        batchTranslateCallCount += 1
        return try await withThrowingTaskGroup(of: MockTranslationResponse.self) { group in
            for request in requests {
                group.addTask {
                    try await self.translate(request.sourceText)
                }
            }

            var results: [MockTranslationResponse] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
}

struct MockTranslationRequest {
    let sourceText: String
}

struct MockTranslationResponse {
    let sourceText: String
    let targetText: String
}
```

**File:** `/clients/ios/GlobalBridge/Tests/Mocks/AI/MockAIService.swift`

```swift
@testable import GlobalBridge

/// Mock for backend AI translation service
actor MockAIService: AIServiceProtocol {
    var shouldSucceed = true
    var translationDelay: TimeInterval = 0.5
    var mockTranslations: [String: TranslationResult] = [:]
    var rateLimitReached = false
    var callCount = 0

    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult {
        callCount += 1
        try await Task.sleep(nanoseconds: UInt64(translationDelay * 1_000_000_000))

        if rateLimitReached {
            throw AIServiceError.rateLimitExceeded(retryAfter: 60)
        }

        guard shouldSucceed else {
            throw AIServiceError.translationFailed
        }

        let key = "\(text)_\(targetLanguage)"
        if let cached = mockTranslations[key] {
            return cached
        }

        return TranslationResult(
            translatedText: "BACKEND: \(text)",
            detectedLanguage: sourceLanguage == "auto" ? "es" : sourceLanguage,
            confidence: 0.95,
            culturalNotes: ["Test cultural note"],
            formalityLevel: "neutral"
        )
    }

    // Implement other AIServiceProtocol methods as no-ops or minimal mocks
    func summarizeThread(threadId: UUID, maxLength: Int?) async throws -> ThreadSummary {
        fatalError("Not implemented in mock")
    }

    func searchSemantic(query: String, in threadId: UUID?, limit: Int, recencyBias: Bool, translate: Bool) async throws -> [SearchResult] {
        fatalError("Not implemented in mock")
    }

    func extractTasks(from threadId: UUID, query: String?) async throws -> [ExtractedTask] {
        fatalError("Not implemented in mock")
    }

    func checkVectorHealth(for threadId: UUID) async throws -> VectorHealthStatus {
        fatalError("Not implemented in mock")
    }
}
```

**File:** `/clients/ios/GlobalBridge/Tests/Mocks/FeatureFlags/MockFeatureFlags.swift`

```swift
@testable import GlobalBridge

/// Mock for FeatureFlags manager
@MainActor
class MockFeatureFlags {
    var translationProvider: TranslationProvider = .apple
    var aiTranslationEnabled = true
    var hybridModeEnabled = false
    var currentTier: UserTier = .pro

    enum TranslationProvider {
        case apple
        case backend
        case hybrid
    }

    enum UserTier {
        case free
        case pro
        case enterprise
    }

    func getTranslationProvider() -> TranslationProvider {
        return translationProvider
    }

    func hasFeature(_ feature: String) -> Bool {
        switch feature {
        case "ai_translation":
            return aiTranslationEnabled
        case "hybrid_translation":
            return hybridModeEnabled
        default:
            return false
        }
    }

    func getTier() -> UserTier {
        return currentTier
    }

    func getDailyTranslationLimit() -> Int? {
        switch currentTier {
        case .free: return 10
        case .pro: return 100
        case .enterprise: return nil  // Unlimited
        }
    }
}
```

**File:** `/clients/ios/GlobalBridge/Tests/Mocks/AI/MockRateLimitTracker.swift`

```swift
/// Mock for rate limit tracking
actor MockRateLimitTracker {
    var translationsUsedToday = 0
    var limit: Int? = 100
    var shouldBlock = false

    func recordTranslation() async throws {
        translationsUsedToday += 1

        if shouldBlock {
            throw RateLimitError.quotaExceeded(resetAt: Date().addingTimeInterval(3600))
        }

        if let limit = limit, translationsUsedToday > limit {
            throw RateLimitError.quotaExceeded(resetAt: Date().addingTimeInterval(3600))
        }
    }

    func getRemainingQuota() -> Int? {
        guard let limit = limit else { return nil }
        return max(0, limit - translationsUsedToday)
    }

    func reset() {
        translationsUsedToday = 0
    }
}

enum RateLimitError: Error {
    case quotaExceeded(resetAt: Date)
}
```

### 2.2 Mock Organization

```
/clients/ios/GlobalBridge/Tests/
├── Mocks/
│   ├── Translation/
│   │   ├── MockTranslationSession.swift          (Apple framework mock)
│   │   ├── MockLanguageAvailability.swift        (Language support mock)
│   │   └── MockTranslationConfiguration.swift    (Session config mock)
│   ├── AI/
│   │   ├── MockAIService.swift                   (Backend service mock)
│   │   ├── MockRateLimitTracker.swift            (Quota management mock)
│   │   └── MockTranslationCache.swift            (Cache mock - if needed)
│   └── FeatureFlags/
│       └── MockFeatureFlags.swift                (Feature flag mock)
```

---

## 3. Task #7: Apple Translation Framework Tests (80+ Cases)

### 3.1 Test Scope

**File:** `/clients/ios/GlobalBridge/Tests/Services/Translation/AppleTranslationServiceTests.swift`

**Categories:**
1. **Language Availability (20 cases)** - Lines 1-250
2. **Basic Translation (15 cases)** - Lines 251-450
3. **Batch Translation (10 cases)** - Lines 451-600
4. **Session Management (10 cases)** - Lines 601-750
5. **Error Handling (15 cases)** - Lines 751-950
6. **Offline Support (10 cases)** - Lines 951-1100

### 3.2 Detailed Test Cases

#### 3.2.1 Language Availability Tests (20 cases)

```swift
import XCTest
@testable import GlobalBridge

@MainActor
final class AppleTranslationServiceTests: XCTestCase {

    var service: AppleTranslationService!
    var mockSession: MockTranslationSession!

    override func setUp() async throws {
        try await super.setUp()
        mockSession = MockTranslationSession()
        service = AppleTranslationService(session: mockSession)
    }

    override func tearDown() async throws {
        service = nil
        mockSession = nil
        try await super.tearDown()
    }

    // MARK: - Language Availability Tests

    func testCheckAvailability_SupportedLanguagePair() async throws {
        // Test: en-US → es-ES should be supported
        let status = await service.checkAvailability(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "es")
        )

        XCTAssertTrue(
            status == .installed || status == .supported,
            "English to Spanish should be supported"
        )
    }

    func testCheckAvailability_UnsupportedLanguagePair() async throws {
        // Test: Obscure language pair should not be supported
        let status = await service.checkAvailability(
            source: Locale.Language(identifier: "tlh"),  // Klingon (not real)
            target: Locale.Language(identifier: "es")
        )

        XCTAssertEqual(status, .unsupported, "Klingon should not be supported")
    }

    func testCheckAvailability_RequiresDownload() async throws {
        // Test: Language available but not downloaded yet
        mockSession.mockLanguageStatus = .supported

        let status = await service.checkAvailability(
            source: Locale.Language(identifier: "ar"),
            target: Locale.Language(identifier: "ja")
        )

        XCTAssertEqual(status, .supported, "Arabic-Japanese may need download")
    }

    func testCheckAvailability_AlreadyInstalled() async throws {
        // Test: Previously downloaded language
        mockSession.mockLanguageStatus = .installed

        let status = await service.checkAvailability(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "fr")
        )

        XCTAssertEqual(status, .installed, "Common pair should be installed")
    }

    func testCheckAvailability_AllCommonLanguages() async throws {
        // Test: Top 10 language pairs availability
        let languages = ["en", "es", "fr", "de", "ja", "ko", "zh", "ar", "ru", "pt"]
        var supportedCount = 0

        for source in languages {
            for target in languages where source != target {
                let status = await service.checkAvailability(
                    source: Locale.Language(identifier: source),
                    target: Locale.Language(identifier: target)
                )

                if status == .installed || status == .supported {
                    supportedCount += 1
                }
            }
        }

        // Expect at least 70% of common pairs to be supported
        XCTAssertGreaterThan(
            Double(supportedCount) / Double(languages.count * (languages.count - 1)),
            0.7,
            "Most common language pairs should be supported"
        )
    }

    // ... 15 more language availability tests:
    // - testCheckAvailability_SameSourceAndTarget (should fail)
    // - testCheckAvailability_EmptyLanguageCode (should fail)
    // - testCheckAvailability_InvalidLanguageCode (should fail)
    // - testCheckAvailability_RegionalVariants (en-US vs en-GB)
    // - testCheckAvailability_LanguageDownloadProgress (if API supports)
    // - testCheckAvailability_MultipleSimultaneousChecks (concurrency)
    // - testCheckAvailability_CachingBehavior (repeated checks)
    // - testCheckAvailability_NetworkOffline (should still work for installed)
    // - testCheckAvailability_LowStorageSpace (may affect downloads)
    // - testCheckAvailability_iOSVersionCompatibility (iOS 17.4+)
    // - testCheckAvailability_LanguagePackageSize (estimate if available)
    // - testCheckAvailability_AllAvailableLanguages (enumerate all)
    // - testCheckAvailability_LanguageUpdateAvailable (newer version)
    // - testCheckAvailability_BetaLanguageSupport (experimental)
    // - testCheckAvailability_PerformanceWithManyChecks (stress test)
}
```

#### 3.2.2 Basic Translation Tests (15 cases)

```swift
// MARK: - Basic Translation Tests

func testTranslate_SimpleEnglishToSpanish() async throws {
    // Test: Basic translation
    let result = try await service.translate(
        text: "Hello, world!",
        from: "en",
        to: "es"
    )

    XCTAssertFalse(result.isEmpty, "Translation should not be empty")
    XCTAssertNotEqual(result, "Hello, world!", "Translation should be different from source")
}

func testTranslate_LongText() async throws {
    // Test: Long paragraph translation
    let longText = String(repeating: "This is a test sentence. ", count: 50)

    let result = try await service.translate(
        text: longText,
        from: "en",
        to: "fr"
    )

    XCTAssertFalse(result.isEmpty)
    XCTAssertGreaterThan(result.count, 100, "Long text translation should be substantial")
}

func testTranslate_SpecialCharacters() async throws {
    // Test: Text with emojis and special characters
    let text = "Hello! 😊 How are you? €100 • Check marks ✓"

    let result = try await service.translate(
        text: text,
        from: "en",
        to: "de"
    )

    XCTAssertTrue(result.contains("😊"), "Emojis should be preserved")
    XCTAssertFalse(result.isEmpty)
}

func testTranslate_Numbers() async throws {
    // Test: Text with numbers
    let text = "I have 42 apples and 3.14 oranges"

    let result = try await service.translate(
        text: text,
        from: "en",
        to: "es"
    )

    XCTAssertTrue(result.contains("42"), "Numbers should be preserved")
    XCTAssertTrue(result.contains("3.14"), "Decimals should be preserved")
}

func testTranslate_URLs() async throws {
    // Test: Text containing URLs
    let text = "Visit https://example.com for more info"

    let result = try await service.translate(
        text: text,
        from: "en",
        to: "ja"
    )

    XCTAssertTrue(result.contains("https://example.com"), "URLs should be preserved")
}

// ... 10 more basic translation tests:
// - testTranslate_EmptyString (should handle gracefully)
// - testTranslate_SingleWord
// - testTranslate_SingleCharacter
// - testTranslate_WhitespaceOnly (should handle gracefully)
// - testTranslate_CodeSnippet (preserve syntax)
// - testTranslate_MixedLanguages (multiple languages in source)
// - testTranslate_Punctuation (preserve punctuation)
// - testTranslate_LineBreaks (preserve formatting)
// - testTranslate_HTMLTags (if supported, preserve tags)
// - testTranslate_MarkdownFormatting (preserve markdown)
```

#### 3.2.3 Performance & Latency Tests (10 cases)

```swift
// MARK: - Performance Tests

func testTranslate_Latency_ShortText() async throws {
    // Test: Translation should complete quickly for short text
    let startTime = Date()

    _ = try await service.translate(
        text: "Hello",
        from: "en",
        to: "es"
    )

    let elapsed = Date().timeIntervalSince(startTime)
    XCTAssertLessThan(elapsed, 0.1, "Short translation should be < 100ms")
}

func testTranslate_Latency_LongText() async throws {
    // Test: Long text translation latency
    let longText = String(repeating: "Test sentence. ", count: 100)
    let startTime = Date()

    _ = try await service.translate(
        text: longText,
        from: "en",
        to: "fr"
    )

    let elapsed = Date().timeIntervalSince(startTime)
    XCTAssertLessThan(elapsed, 2.0, "Long translation should be < 2 seconds")
}

func testTranslate_ConcurrentRequests() async throws {
    // Test: Handle multiple concurrent translations
    let texts = (1...10).map { "Test sentence \($0)" }

    let startTime = Date()

    try await withThrowingTaskGroup(of: String.self) { group in
        for text in texts {
            group.addTask {
                try await self.service.translate(text: text, from: "en", to: "es")
            }
        }

        var results: [String] = []
        for try await result in group {
            results.append(result)
        }

        XCTAssertEqual(results.count, 10, "All translations should complete")
    }

    let elapsed = Date().timeIntervalSince(startTime)
    XCTAssertLessThan(elapsed, 3.0, "10 concurrent translations should be < 3 seconds")
}
```

### 3.3 Testing Delegation for Task #7

**Delegation Package:**

**Developer Profile:** iOS Translation Framework Specialist
- **Skills:** Swift, Translation framework, XCTest, async/await testing
- **Experience:** iOS 17+ APIs, on-device ML frameworks
- **Deliverables:** 80+ comprehensive test cases, 90%+ code coverage

**Delegation via Zen MCP:**

```swift
// Use mcp__zen__codereview or mcp__zen__testgen to coordinate delegation
{
  "task": "Apple Translation Framework Testing",
  "service_path": "/clients/ios/GlobalBridge/Core/Services/Translation/AppleTranslationService.swift",
  "test_path": "/clients/ios/GlobalBridge/Tests/Services/Translation/AppleTranslationServiceTests.swift",
  "target_cases": 80,
  "categories": [
    "Language availability (20 cases)",
    "Basic translation (15 cases)",
    "Batch translation (10 cases)",
    "Session management (10 cases)",
    "Error handling (15 cases)",
    "Offline support (10 cases)"
  ],
  "mock_infrastructure": ["MockTranslationSession", "MockLanguageAvailability"],
  "performance_targets": {
    "short_text_latency": "< 100ms",
    "long_text_latency": "< 2s",
    "code_coverage": "> 90%"
  },
  "timeline": "2 business days"
}
```

---

## 4. Task #8: Backend Translation Service Tests (70+ Cases)

### 4.1 Test Scope

**File:** `/clients/ios/GlobalBridge/Tests/Services/AI/BackendTranslationServiceTests.swift`

**Categories:**
1. **API Request Formation (15 cases)** - Lines 1-300
2. **Response Parsing (15 cases)** - Lines 301-600
3. **Cultural Notes Handling (10 cases)** - Lines 601-800
4. **Rate Limiting (10 cases)** - Lines 801-1000
5. **Authentication (10 cases)** - Lines 1001-1200
6. **Error Handling (10 cases)** - Lines 1201-1400

### 4.2 Detailed Test Cases

#### 4.2.1 API Integration Tests (15 cases)

```swift
import XCTest
@testable import GlobalBridge

@MainActor
final class BackendTranslationServiceTests: XCTestCase {

    var service: BackendTranslationService!
    var mockAIService: MockAIService!
    var mockCache: AIServiceCache!
    var mockAuth: MockAuthManager!

    override func setUp() async throws {
        try await super.setUp()
        mockAIService = MockAIService()
        mockCache = AIServiceCache.shared
        mockAuth = MockAuthManager()

        service = BackendTranslationService(
            aiService: mockAIService,
            cache: mockCache,
            authManager: mockAuth
        )

        await mockCache.clearAll()
    }

    override func tearDown() async throws {
        await mockCache.clearAll()
        service = nil
        mockAIService = nil
        mockAuth = nil
        try await super.tearDown()
    }

    // MARK: - API Request Tests

    func testTranslate_RequestFormat() async throws {
        // Test: Verify correct request payload
        let text = "Hello, world!"
        let target = "es"

        _ = try await service.translate(
            text: text,
            targetLanguage: target,
            sourceLanguage: "en"
        )

        let callCount = await mockAIService.callCount
        XCTAssertEqual(callCount, 1, "Should make exactly one API call")

        // Verify request parameters were passed correctly
        let lastRequest = await mockAIService.lastRequest
        XCTAssertEqual(lastRequest?.text, text)
        XCTAssertEqual(lastRequest?.targetLanguage, target)
        XCTAssertEqual(lastRequest?.sourceLanguage, "en")
    }

    func testTranslate_AutoLanguageDetection() async throws {
        // Test: sourceLanguage = "auto" should trigger detection
        _ = try await service.translate(
            text: "Hola, mundo!",
            targetLanguage: "en",
            sourceLanguage: "auto"
        )

        let lastRequest = await mockAIService.lastRequest
        XCTAssertEqual(lastRequest?.sourceLanguage, "auto")
    }

    func testTranslate_AuthenticationHeader() async throws {
        // Test: JWT token included in request
        mockAuth.mockAccessToken = "test-jwt-token"

        _ = try await service.translate(
            text: "Test",
            targetLanguage: "es"
        )

        let authHeader = await mockAIService.lastAuthHeader
        XCTAssertEqual(authHeader, "Bearer test-jwt-token")
    }

    func testTranslate_ContentTypeHeader() async throws {
        // Test: Content-Type header is application/json
        _ = try await service.translate(
            text: "Test",
            targetLanguage: "fr"
        )

        let contentType = await mockAIService.lastContentType
        XCTAssertEqual(contentType, "application/json")
    }

    // ... 11 more API request tests
}
```

#### 4.2.2 Context-Aware Translation Tests (15 cases)

```swift
// MARK: - Context-Aware Translation Tests

func testTranslate_WithCulturalNotes() async throws {
    // Test: Backend returns cultural context
    mockAIService.mockTranslations = [
        "Hola_en": TranslationResult(
            translatedText: "Hello",
            detectedLanguage: "es",
            confidence: 0.98,
            culturalNotes: [
                "In Spain, 'Hola' is informal. Use 'Buenos días' for formal contexts.",
                "Latin American usage may vary by region."
            ],
            formalityLevel: "informal"
        )
    ]

    let result = try await service.translate(
        text: "Hola",
        targetLanguage: "en"
    )

    XCTAssertEqual(result.culturalNotes.count, 2)
    XCTAssertTrue(result.culturalNotes[0].contains("informal"))
}

func testTranslate_FormalityDetection() async throws {
    // Test: Formality level detection (formal vs informal)
    let formalText = "Would you be so kind as to assist me?"

    let result = try await service.translate(
        text: formalText,
        targetLanguage: "es"
    )

    XCTAssertEqual(result.formalityLevel, "formal")
}

func testTranslate_SlangDetection() async throws {
    // Test: Detect and handle slang/colloquialisms
    let slangText = "That's sick, bro!"

    let result = try await service.translate(
        text: slangText,
        targetLanguage: "es"
    )

    XCTAssertNotNil(result.culturalNotes)
    XCTAssertTrue(
        result.culturalNotes?.contains(where: { $0.contains("slang") }) ?? false,
        "Should note slang usage"
    )
}

// ... 12 more context-aware tests
```

#### 4.2.3 Rate Limiting Tests (10 cases)

```swift
// MARK: - Rate Limiting Tests

func testTranslate_RateLimitExceeded() async throws {
    // Test: Handle 429 rate limit response
    await mockAIService.setRateLimitReached(true)

    do {
        _ = try await service.translate(
            text: "Test",
            targetLanguage: "es"
        )
        XCTFail("Should throw rate limit error")
    } catch AIServiceError.rateLimitExceeded(let retryAfter) {
        XCTAssertGreaterThan(retryAfter, 0, "Should provide retry-after time")
    } catch {
        XCTFail("Wrong error type: \(error)")
    }
}

func testTranslate_DailyQuotaTracking() async throws {
    // Test: Track daily translation quota usage
    let tracker = MockRateLimitTracker()
    service.rateLimitTracker = tracker

    // Use up quota
    for i in 1...10 {
        _ = try await service.translate(
            text: "Test \(i)",
            targetLanguage: "es"
        )
    }

    let used = await tracker.translationsUsedToday
    XCTAssertEqual(used, 10, "Should track 10 translations")
}

func testTranslate_QuotaExhaustion() async throws {
    // Test: Fail when daily quota exhausted
    let tracker = MockRateLimitTracker()
    tracker.limit = 5
    tracker.translationsUsedToday = 5
    service.rateLimitTracker = tracker

    do {
        _ = try await service.translate(
            text: "Test",
            targetLanguage: "es"
        )
        XCTFail("Should throw quota exceeded error")
    } catch RateLimitError.quotaExceeded {
        // Expected
    }
}

// ... 7 more rate limiting tests
```

### 4.3 Testing Delegation for Task #8

**Developer Profile:** iOS Backend Integration Specialist
- **Skills:** Swift networking, URLSession, async/await, API integration
- **Experience:** REST API testing, JWT authentication, error handling
- **Deliverables:** 70+ comprehensive test cases, 90%+ code coverage

---

## 5. Task #9: Unified Translation Service Tests (90+ Cases)

### 5.1 Test Scope

**File:** `/clients/ios/GlobalBridge/Tests/Services/Translation/UnifiedTranslationServiceTests.swift`

**Categories:**
1. **Provider Selection Logic (20 cases)** - Lines 1-400
2. **Feature Flag Integration (15 cases)** - Lines 401-700
3. **Hybrid Mode (20 cases)** - Lines 701-1100
4. **Fallback Logic (15 cases)** - Lines 1101-1400
5. **Metrics Logging (10 cases)** - Lines 1401-1600
6. **Offline Strategy (10 cases)** - Lines 1601-1800

### 5.2 Detailed Test Cases

#### 5.2.1 Provider Selection Tests (20 cases)

```swift
import XCTest
@testable import GlobalBridge

@MainActor
final class UnifiedTranslationServiceTests: XCTestCase {

    var service: UnifiedTranslationService!
    var mockAppleService: MockAppleTranslationService!
    var mockBackendService: MockBackendTranslationService!
    var mockFeatureFlags: MockFeatureFlags!
    var mockCache: AIServiceCache!

    override func setUp() async throws {
        try await super.setUp()

        mockAppleService = MockAppleTranslationService()
        mockBackendService = MockBackendTranslationService()
        mockFeatureFlags = MockFeatureFlags()
        mockCache = AIServiceCache.shared

        service = UnifiedTranslationService(
            appleService: mockAppleService,
            backendService: mockBackendService,
            featureFlags: mockFeatureFlags,
            cache: mockCache
        )

        await mockCache.clearAll()
    }

    override func tearDown() async throws {
        await mockCache.clearAll()
        service = nil
        mockAppleService = nil
        mockBackendService = nil
        mockFeatureFlags = nil
        try await super.tearDown()
    }

    // MARK: - Provider Selection Tests

    func testProviderSelection_AppleOnly() async throws {
        // Test: Use Apple Translation when feature flag is set
        mockFeatureFlags.translationProvider = .apple

        _ = try await service.translate(
            text: "Hello",
            targetLanguage: "es"
        )

        XCTAssertEqual(mockAppleService.callCount, 1, "Should use Apple service")
        XCTAssertEqual(mockBackendService.callCount, 0, "Should not use backend")
    }

    func testProviderSelection_BackendOnly() async throws {
        // Test: Use backend when feature flag is set
        mockFeatureFlags.translationProvider = .backend

        _ = try await service.translate(
            text: "Hello",
            targetLanguage: "es"
        )

        XCTAssertEqual(mockAppleService.callCount, 0, "Should not use Apple")
        XCTAssertEqual(mockBackendService.callCount, 1, "Should use backend")
    }

    func testProviderSelection_HybridMode() async throws {
        // Test: Use both providers in hybrid mode
        mockFeatureFlags.translationProvider = .hybrid

        let result = try await service.translate(
            text: "Hello",
            targetLanguage: "es"
        )

        XCTAssertEqual(mockAppleService.callCount, 1, "Should use Apple")
        XCTAssertEqual(mockBackendService.callCount, 1, "Should use backend")

        // Result should contain both translations
        XCTAssertNotNil(result.appleTranslation)
        XCTAssertNotNil(result.backendTranslation)
    }

    func testProviderSelection_TierBasedDefault() async throws {
        // Test: Free tier defaults to Apple (on-device, no API cost)
        mockFeatureFlags.currentTier = .free
        mockFeatureFlags.translationProvider = .apple  // Default for free

        _ = try await service.translate(
            text: "Test",
            targetLanguage: "fr"
        )

        XCTAssertEqual(mockAppleService.callCount, 1)
    }

    func testProviderSelection_ProTierCanChoose() async throws {
        // Test: Pro tier can choose provider
        mockFeatureFlags.currentTier = .pro
        mockFeatureFlags.translationProvider = .backend

        _ = try await service.translate(
            text: "Test",
            targetLanguage: "de"
        )

        XCTAssertEqual(mockBackendService.callCount, 1)
    }

    // ... 15 more provider selection tests:
    // - testProviderSelection_EnterpriseTierHybrid
    // - testProviderSelection_RuntimeSwitch (change during app lifecycle)
    // - testProviderSelection_LanguagePairUnavailableOnApple (fallback to backend)
    // - testProviderSelection_OfflineForceApple (see offline tests)
    // - testProviderSelection_UserPreference (if stored)
    // - testProviderSelection_ABTesting (random selection for comparison)
    // - testProviderSelection_QualityComparisonMode
    // - testProviderSelection_CostOptimization (prefer on-device)
    // - testProviderSelection_SpeedOptimization (fastest provider)
    // - testProviderSelection_MultipleConcurrentRequests (same provider)
    // - testProviderSelection_ProviderHealthCheck (switch if one fails)
    // - testProviderSelection_FeatureFlagUpdateMidSession
    // - testProviderSelection_InvalidProvider (handle gracefully)
    // - testProviderSelection_DefaultFallback (if flags fail to load)
    // - testProviderSelection_PerLanguageProvider (optimize per language)
}
```

#### 5.2.2 Hybrid Mode Tests (20 cases)

```swift
// MARK: - Hybrid Mode Tests

func testHybridMode_BothTranslationsReturned() async throws {
    // Test: Both translations included in result
    mockFeatureFlags.translationProvider = .hybrid

    let result = try await service.translate(
        text: "Hello, world!",
        targetLanguage: "es"
    )

    XCTAssertNotNil(result.appleTranslation, "Should have Apple translation")
    XCTAssertNotNil(result.backendTranslation, "Should have backend translation")
    XCTAssertNotEqual(result.appleTranslation, result.backendTranslation, "Translations may differ")
}

func testHybridMode_ComparisonMetrics() async throws {
    // Test: Log metrics comparing both providers
    mockFeatureFlags.translationProvider = .hybrid

    let result = try await service.translate(
        text: "The quick brown fox jumps over the lazy dog",
        targetLanguage: "fr"
    )

    XCTAssertNotNil(result.metrics)
    XCTAssertNotNil(result.metrics?.appleLatency)
    XCTAssertNotNil(result.metrics?.backendLatency)
    XCTAssertNotNil(result.metrics?.qualityScore)  // If available
}

func testHybridMode_ParallelExecution() async throws {
    // Test: Both translations execute concurrently, not sequentially
    mockAppleService.translationDelay = 1.0
    mockBackendService.translationDelay = 1.0
    mockFeatureFlags.translationProvider = .hybrid

    let startTime = Date()

    _ = try await service.translate(
        text: "Test parallel execution",
        targetLanguage: "es"
    )

    let elapsed = Date().timeIntervalSince(startTime)

    // Should be ~1 second (parallel), not ~2 seconds (sequential)
    XCTAssertLessThan(elapsed, 1.5, "Translations should run in parallel")
}

func testHybridMode_OneProviderFails() async throws {
    // Test: Continue if one provider fails
    mockFeatureFlags.translationProvider = .hybrid
    mockAppleService.shouldSucceed = false  // Apple fails

    let result = try await service.translate(
        text: "Test failure handling",
        targetLanguage: "ja"
    )

    XCTAssertNil(result.appleTranslation, "Apple should fail")
    XCTAssertNotNil(result.backendTranslation, "Backend should succeed")
    XCTAssertTrue(result.hasPartialFailure, "Should flag partial failure")
}

func testHybridMode_BothProvidersFail() async throws {
    // Test: Throw error if both providers fail
    mockFeatureFlags.translationProvider = .hybrid
    mockAppleService.shouldSucceed = false
    mockBackendService.shouldSucceed = false

    do {
        _ = try await service.translate(
            text: "Test total failure",
            targetLanguage: "ko"
        )
        XCTFail("Should throw error when both providers fail")
    } catch TranslationError.allProvidersFailed {
        // Expected
    }
}

// ... 15 more hybrid mode tests
```

#### 5.2.3 Fallback Logic Tests (15 cases)

```swift
// MARK: - Fallback Logic Tests

func testFallback_AppleToBackend() async throws {
    // Test: Fallback to backend if Apple fails
    mockFeatureFlags.translationProvider = .apple
    mockAppleService.shouldSucceed = false

    let result = try await service.translate(
        text: "Test fallback",
        targetLanguage: "zh"
    )

    XCTAssertEqual(mockBackendService.callCount, 1, "Should fallback to backend")
    XCTAssertNotNil(result.translation)
    XCTAssertTrue(result.usedFallback, "Should flag fallback usage")
}

func testFallback_BackendToApple() async throws {
    // Test: Fallback to Apple if backend fails
    mockFeatureFlags.translationProvider = .backend
    mockBackendService.shouldSucceed = false

    let result = try await service.translate(
        text: "Test reverse fallback",
        targetLanguage: "ar"
    )

    XCTAssertEqual(mockAppleService.callCount, 1, "Should fallback to Apple")
    XCTAssertNotNil(result.translation)
}

func testFallback_NoFallbackIfBothUnavailable() async throws {
    // Test: Error if no fallback available
    mockFeatureFlags.translationProvider = .apple
    mockAppleService.shouldSucceed = false
    mockBackendService.shouldSucceed = false

    do {
        _ = try await service.translate(
            text: "Test no fallback",
            targetLanguage: "ru"
        )
        XCTFail("Should throw error")
    } catch TranslationError.noProviderAvailable {
        // Expected
    }
}

// ... 12 more fallback tests
```

#### 5.2.4 Offline Strategy Tests (10 cases)

```swift
// MARK: - Offline Strategy Tests

func testOffline_ForceAppleTranslation() async throws {
    // Test: Use Apple (on-device) when offline
    mockFeatureFlags.translationProvider = .backend  // Prefer backend normally
    service.isOffline = true  // Simulate offline

    let result = try await service.translate(
        text: "Offline test",
        targetLanguage: "it"
    )

    XCTAssertEqual(mockAppleService.callCount, 1, "Should use Apple offline")
    XCTAssertEqual(mockBackendService.callCount, 0, "Should not attempt backend")
    XCTAssertTrue(result.wasOffline, "Should flag offline mode")
}

func testOffline_CacheFirst() async throws {
    // Test: Check cache before attempting translation
    let text = "Cached translation test"
    let cachedResult = TranslationResult(
        translatedText: "CACHED: Prueba de traducción en caché",
        detectedLanguage: "en",
        confidence: 1.0,
        culturalNotes: [],
        formalityLevel: "neutral"
    )

    await mockCache.store(cachedResult, forKey: "\(text)_es", type: .translation)
    service.isOffline = true

    let result = try await service.translate(
        text: text,
        targetLanguage: "es"
    )

    XCTAssertEqual(result.translation, cachedResult.translatedText)
    XCTAssertEqual(mockAppleService.callCount, 0, "Should not call provider")
    XCTAssertTrue(result.fromCache, "Should flag cache hit")
}

func testOffline_NoAppleLanguageSupport() async throws {
    // Test: Fail gracefully if language not available offline
    service.isOffline = true
    mockAppleService.isLanguageAvailable = false

    do {
        _ = try await service.translate(
            text: "Unsupported offline",
            targetLanguage: "tlh"  // Klingon - unsupported
        )
        XCTFail("Should throw unsupported language error")
    } catch TranslationError.languageNotAvailableOffline {
        // Expected
    }
}

// ... 7 more offline tests
```

### 5.3 Testing Delegation for Task #9

**Developer Profile:** iOS Senior Architecture Specialist
- **Skills:** Swift, architecture patterns, feature flags, dependency injection
- **Experience:** Complex service orchestration, testing strategies
- **Deliverables:** 90+ comprehensive test cases, 90%+ code coverage

---

## 6. Task #10: Message Bubble UI Tests (100+ Cases)

### 6.1 Test Scope

**File:** `/clients/ios/GlobalBridge/Tests/Views/Messages/MessageBubbleTranslationUITests.swift`

**Categories:**
1. **Translation Toggle Button (20 cases)** - Lines 1-400
2. **Show/Hide Translated Text (15 cases)** - Lines 401-700
3. **Provider Badge Display (10 cases)** - Lines 701-900
4. **Loading States (15 cases)** - Lines 901-1200
5. **Error States (15 cases)** - Lines 1201-1500
6. **Accessibility (15 cases)** - Lines 1501-1800
7. **Dark Mode (10 cases)** - Lines 1801-2000

### 6.2 Detailed Test Cases

#### 6.2.1 Translation Toggle Button Tests (20 cases)

```swift
import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class MessageBubbleTranslationUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Translation Toggle Button Tests

    func testToggleButton_Exists() throws {
        // Test: Translation button appears on message bubbles
        let messageBubble = app.otherElements["message-bubble-1"]
        XCTAssertTrue(messageBubble.exists, "Message bubble should exist")

        let translateButton = messageBubble.buttons["translate-button"]
        XCTAssertTrue(translateButton.exists, "Translate button should exist")
    }

    func testToggleButton_IconCorrect() throws {
        // Test: Button shows correct SF Symbol icon
        let translateButton = app.buttons["translate-button"].firstMatch
        XCTAssertTrue(translateButton.exists)

        let icon = translateButton.images["globe.badge.chevron.backward"]
        XCTAssertTrue(icon.exists, "Should show translation icon")
    }

    func testToggleButton_TapToTranslate() throws {
        // Test: Tapping button triggers translation
        let translateButton = app.buttons["translate-button"].firstMatch
        translateButton.tap()

        // Wait for translation to appear
        let translatedText = app.staticTexts["translated-text"]
        let exists = translatedText.waitForExistence(timeout: 2.0)
        XCTAssertTrue(exists, "Translated text should appear")
    }

    func testToggleButton_TapToHide() throws {
        // Test: Tapping again hides translation
        let translateButton = app.buttons["translate-button"].firstMatch
        translateButton.tap()

        // Wait for translation
        let translatedText = app.staticTexts["translated-text"]
        _ = translatedText.waitForExistence(timeout: 2.0)

        // Tap again to hide
        translateButton.tap()

        XCTAssertFalse(translatedText.exists, "Translation should be hidden")
    }

    func testToggleButton_StateIndicator() throws {
        // Test: Button shows active state when translation shown
        let translateButton = app.buttons["translate-button"].firstMatch

        // Before translation
        XCTAssertFalse(translateButton.isSelected, "Should not be selected initially")

        translateButton.tap()

        // After translation
        XCTAssertTrue(translateButton.isSelected, "Should be selected after translation")
    }

    // ... 15 more toggle button tests:
    // - testToggleButton_DisabledWhenOffline
    // - testToggleButton_DisabledForOwnMessages (optional)
    // - testToggleButton_HapticsOnTap (if implemented)
    // - testToggleButton_AnimationOnToggle
    // - testToggleButton_PositionInBubble (top-right corner)
    // - testToggleButton_SizeAndHitArea (at least 44x44pt)
    // - testToggleButton_ColorScheme (light vs dark mode)
    // - testToggleButton_DisabledForUnsupportedLanguages
    // - testToggleButton_TooltipOnLongPress (if implemented)
    // - testToggleButton_MultipleTapsRapidly (debounce)
    // - testToggleButton_StatePersistedOnScroll
    // - testToggleButton_ContextMenuIntegration
    // - testToggleButton_SwipeActions (alternative UI)
    // - testToggleButton_KeyboardNavigation (if supported)
    // - testToggleButton_LoadingSpinnerWhileTranslating
}
```

#### 6.2.2 Show/Hide Translated Text Tests (15 cases)

```swift
// MARK: - Show/Hide Translated Text Tests

func testTranslatedText_AppearsBelow() throws {
    // Test: Translation appears below original message
    let messageBubble = app.otherElements["message-bubble-1"]
    let originalText = messageBubble.staticTexts["original-message"]
    let originalFrame = originalText.frame

    // Translate
    messageBubble.buttons["translate-button"].tap()

    let translatedText = messageBubble.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    let translatedFrame = translatedText.frame
    XCTAssertGreaterThan(
        translatedFrame.minY,
        originalFrame.maxY,
        "Translation should appear below original"
    )
}

func testTranslatedText_StylingDifferent() throws {
    // Test: Translation has different styling (smaller, secondary color)
    let messageBubble = app.otherElements["message-bubble-1"]
    messageBubble.buttons["translate-button"].tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    // Font size should be smaller (caption vs body)
    // Color should be secondary (gray vs primary)
    // This is visual testing - may need snapshot testing
}

func testTranslatedText_AnimatesIn() throws {
    // Test: Translation animates smoothly when appearing
    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 0.3)  // Should appear quickly

    // Check animation completed (no assertions available, visual test)
}

func testTranslatedText_AnimatesOut() throws {
    // Test: Translation animates smoothly when hiding
    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    translateButton.tap()

    // Should disappear with animation
    let exists = translatedText.waitForExistence(timeout: 0.3)
    XCTAssertFalse(exists, "Should disappear")
}

// ... 11 more show/hide tests
```

#### 6.2.3 Provider Badge Tests (10 cases)

```swift
// MARK: - Provider Badge Tests

func testProviderBadge_AppleShown() throws {
    // Test: Apple Translation badge displayed
    let messageBubble = app.otherElements["message-bubble-1"]
    messageBubble.buttons["translate-button"].tap()

    let badge = messageBubble.images["provider-badge-apple"]
    _ = badge.waitForExistence(timeout: 2.0)
    XCTAssertTrue(badge.exists, "Apple badge should appear")
}

func testProviderBadge_BackendShown() throws {
    // Test: Backend AI badge displayed
    // Set feature flag to use backend
    app.launchArguments.append("--use-backend-translation")
    app.launch()

    let messageBubble = app.otherElements["message-bubble-1"]
    messageBubble.buttons["translate-button"].tap()

    let badge = messageBubble.images["provider-badge-backend"]
    _ = badge.waitForExistence(timeout: 2.0)
    XCTAssertTrue(badge.exists, "Backend badge should appear")
}

func testProviderBadge_HybridShowsBoth() throws {
    // Test: Hybrid mode shows both badges
    app.launchArguments.append("--use-hybrid-translation")
    app.launch()

    let messageBubble = app.otherElements["message-bubble-1"]
    messageBubble.buttons["translate-button"].tap()

    let appleBadge = messageBubble.images["provider-badge-apple"]
    let backendBadge = messageBubble.images["provider-badge-backend"]

    _ = appleBadge.waitForExistence(timeout: 2.0)
    _ = backendBadge.waitForExistence(timeout: 2.0)

    XCTAssertTrue(appleBadge.exists, "Apple badge should appear")
    XCTAssertTrue(backendBadge.exists, "Backend badge should appear")
}

// ... 7 more provider badge tests
```

#### 6.2.4 Loading States Tests (15 cases)

```swift
// MARK: - Loading States Tests

func testLoadingState_SpinnerShown() throws {
    // Test: Loading spinner appears while translating
    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let spinner = app.activityIndicators["translation-loading"]
    let exists = spinner.waitForExistence(timeout: 0.5)
    XCTAssertTrue(exists, "Loading spinner should appear")
}

func testLoadingState_ButtonDisabled() throws {
    // Test: Button disabled during translation
    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    // Try to tap again immediately
    translateButton.tap()

    // Should not trigger second translation
    let spinners = app.activityIndicators.matching(identifier: "translation-loading")
    XCTAssertEqual(spinners.count, 1, "Should only have one loading spinner")
}

func testLoadingState_ProgressIndicator() throws {
    // Test: Progress indicator for long translations
    // Set up slow translation
    app.launchArguments.append("--slow-translation")
    app.launch()

    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let progress = app.progressIndicators["translation-progress"]
    _ = progress.waitForExistence(timeout: 1.0)
    XCTAssertTrue(progress.exists, "Progress indicator should appear")
}

// ... 12 more loading state tests
```

#### 6.2.5 Error States Tests (15 cases)

```swift
// MARK: - Error States Tests

func testErrorState_NetworkError() throws {
    // Test: Show error when network unavailable
    app.launchArguments.append("--simulate-network-error")
    app.launch()

    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let errorAlert = app.alerts["translation-error"]
    _ = errorAlert.waitForExistence(timeout: 2.0)
    XCTAssertTrue(errorAlert.exists, "Error alert should appear")

    let message = errorAlert.staticTexts["error-message"]
    XCTAssertTrue(message.label.contains("network"), "Should mention network error")
}

func testErrorState_RateLimitExceeded() throws {
    // Test: Show error when rate limit exceeded
    app.launchArguments.append("--simulate-rate-limit")
    app.launch()

    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let errorAlert = app.alerts["translation-error"]
    _ = errorAlert.waitForExistence(timeout: 2.0)

    let message = errorAlert.staticTexts["error-message"]
    XCTAssertTrue(message.label.contains("limit"), "Should mention rate limit")
}

func testErrorState_RetryButton() throws {
    // Test: Retry button in error state
    app.launchArguments.append("--simulate-network-error")
    app.launch()

    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let errorAlert = app.alerts["translation-error"]
    _ = errorAlert.waitForExistence(timeout: 2.0)

    let retryButton = errorAlert.buttons["Retry"]
    XCTAssertTrue(retryButton.exists, "Retry button should exist")

    retryButton.tap()

    // Should attempt translation again
    let spinner = app.activityIndicators["translation-loading"]
    let exists = spinner.waitForExistence(timeout: 0.5)
    XCTAssertTrue(exists, "Should retry translation")
}

// ... 12 more error state tests
```

#### 6.2.6 Accessibility Tests (15 cases)

```swift
// MARK: - Accessibility Tests

func testAccessibility_VoiceOverAnnouncement() throws {
    // Test: VoiceOver announces translation
    let translateButton = app.buttons["translate-button"].firstMatch

    XCTAssertNotNil(translateButton.label, "Button should have accessibility label")
    XCTAssertTrue(
        translateButton.label.contains("Translate"),
        "Label should describe action"
    )

    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    XCTAssertNotNil(translatedText.value, "Translation should have accessibility value")
}

func testAccessibility_DynamicType() throws {
    // Test: Translation text scales with Dynamic Type
    // This requires running test with different text size settings
    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    // Text should scale (visual test, hard to assert programmatically)
    XCTAssertTrue(translatedText.exists)
}

func testAccessibility_HighContrast() throws {
    // Test: UI works in high contrast mode
    // Enable high contrast in system settings
    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    // Colors should have sufficient contrast (visual test)
    XCTAssertTrue(translatedText.exists)
}

func testAccessibility_ReducedMotion() throws {
    // Test: Animations respect reduced motion preference
    // Enable reduced motion in system settings
    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]

    // Should appear instantly without animation
    let exists = translatedText.waitForExistence(timeout: 0.1)
    XCTAssertTrue(exists, "Should appear without animation")
}

func testAccessibility_ButtonMinimumSize() throws {
    // Test: Button meets 44x44pt minimum touch target
    let translateButton = app.buttons["translate-button"].firstMatch
    let frame = translateButton.frame

    XCTAssertGreaterThanOrEqual(frame.width, 44, "Button width should be >= 44pt")
    XCTAssertGreaterThanOrEqual(frame.height, 44, "Button height should be >= 44pt")
}

// ... 10 more accessibility tests:
// - testAccessibility_ColorBlindness (sufficient contrast)
// - testAccessibility_VoiceControl (voice commands work)
// - testAccessibility_SwitchControl (navigation)
// - testAccessibility_AssistiveTouch (gesture alternatives)
// - testAccessibility_HearingAid (no audio-only feedback)
// - testAccessibility_ClosedCaptions (if video involved)
// - testAccessibility_GuidedAccess (works in restricted mode)
// - testAccessibility_VoiceOverRotor (custom actions)
// - testAccessibility_Traits (button traits correct)
// - testAccessibility_HintText (helpful hints provided)
```

#### 6.2.7 Dark Mode Tests (10 cases)

```swift
// MARK: - Dark Mode Tests

func testDarkMode_ButtonAppearance() throws {
    // Test: Button looks correct in dark mode
    app.launchArguments.append("--dark-mode")
    app.launch()

    let translateButton = app.buttons["translate-button"].firstMatch
    XCTAssertTrue(translateButton.exists, "Button should exist in dark mode")

    // Visual test: Button should have appropriate dark mode styling
}

func testDarkMode_TranslatedTextReadable() throws {
    // Test: Translation readable in dark mode
    app.launchArguments.append("--dark-mode")
    app.launch()

    let translateButton = app.buttons["translate-button"].firstMatch
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    // Visual test: Text should have sufficient contrast
    XCTAssertTrue(translatedText.exists)
}

func testDarkMode_ProviderBadgeVisible() throws {
    // Test: Provider badge visible in dark mode
    app.launchArguments.append("--dark-mode")
    app.launch()

    let messageBubble = app.otherElements["message-bubble-1"]
    messageBubble.buttons["translate-button"].tap()

    let badge = messageBubble.images["provider-badge-apple"]
    _ = badge.waitForExistence(timeout: 2.0)

    // Visual test: Badge should be visible
    XCTAssertTrue(badge.exists)
}

// ... 7 more dark mode tests
```

### 6.3 Testing Delegation for Task #10

**Developer Profile:** iOS UI/UX Testing Specialist
- **Skills:** XCTest UI testing, SwiftUI, accessibility testing
- **Experience:** UI test automation, snapshot testing, visual regression
- **Deliverables:** 100+ UI test cases, accessibility compliance, visual tests

---

## 7. Integration Test Scenarios

### 7.1 End-to-End Translation Flow

**File:** `/clients/ios/GlobalBridge/Tests/Integration/TranslationFlowIntegrationTests.swift`

```swift
import XCTest
@testable import GlobalBridge

@MainActor
final class TranslationFlowIntegrationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI-Testing", "--reset-app-state"]
        app.launch()
    }

    // MARK: - End-to-End Scenarios

    func testEndToEnd_UserReceivesMessageAndTranslates() throws {
        // Scenario: User receives foreign language message, translates it, understands content

        // 1. Navigate to thread with foreign message
        let threadList = app.collectionViews["thread-list"]
        threadList.cells.firstMatch.tap()

        // 2. Verify message exists
        let messageBubble = app.otherElements["message-bubble-foreign"]
        XCTAssertTrue(messageBubble.exists, "Foreign message should exist")

        let originalText = messageBubble.staticTexts["original-message"].label
        XCTAssertFalse(originalText.isEmpty, "Original text should not be empty")

        // 3. Tap translate button
        let translateButton = messageBubble.buttons["translate-button"]
        translateButton.tap()

        // 4. Wait for translation
        let translatedText = messageBubble.staticTexts["translated-text"]
        let exists = translatedText.waitForExistence(timeout: 5.0)
        XCTAssertTrue(exists, "Translation should appear within 5 seconds")

        // 5. Verify translation differs from original
        XCTAssertNotEqual(translatedText.label, originalText, "Translation should differ")

        // 6. Verify provider badge shown
        let providerBadge = messageBubble.images.matching(NSPredicate(format: "identifier BEGINSWITH 'provider-badge'")).firstMatch
        XCTAssertTrue(providerBadge.exists, "Provider badge should appear")

        // 7. User can hide translation
        translateButton.tap()
        XCTAssertFalse(translatedText.exists, "Translation should hide")

        // 8. User can show translation again (cached, instant)
        let startTime = Date()
        translateButton.tap()
        _ = translatedText.waitForExistence(timeout: 1.0)
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertLessThan(elapsed, 0.5, "Cached translation should appear instantly")
    }

    func testEndToEnd_MultilingualConversation() throws {
        // Scenario: User has conversation in multiple languages, translates selectively

        // Navigate to multilingual thread
        let threadList = app.collectionViews["thread-list"]
        let multilingualThread = threadList.cells["thread-multilingual"]
        multilingualThread.tap()

        // Should see messages in multiple languages
        let spanishMessage = app.otherElements["message-spanish"]
        let frenchMessage = app.otherElements["message-french"]
        let germanMessage = app.otherElements["message-german"]

        XCTAssertTrue(spanishMessage.exists)
        XCTAssertTrue(frenchMessage.exists)
        XCTAssertTrue(germanMessage.exists)

        // Translate Spanish message
        spanishMessage.buttons["translate-button"].tap()
        let spanishTranslation = spanishMessage.staticTexts["translated-text"]
        _ = spanishTranslation.waitForExistence(timeout: 3.0)
        XCTAssertTrue(spanishTranslation.exists)

        // Translate French message
        frenchMessage.buttons["translate-button"].tap()
        let frenchTranslation = frenchMessage.staticTexts["translated-text"]
        _ = frenchTranslation.waitForExistence(timeout: 3.0)
        XCTAssertTrue(frenchTranslation.exists)

        // German message remains untranslated (user choice)
        XCTAssertFalse(germanMessage.staticTexts["translated-text"].exists)

        // Verify all translations visible simultaneously
        XCTAssertTrue(spanishTranslation.exists)
        XCTAssertTrue(frenchTranslation.exists)
    }

    func testEndToEnd_ProviderSwitch() throws {
        // Scenario: User switches translation provider mid-conversation

        // Start with Apple Translation
        app.launchArguments.append("--use-apple-translation")
        app.launch()

        let messageBubble = app.otherElements["message-bubble-1"]
        messageBubble.buttons["translate-button"].tap()

        let appleBadge = messageBubble.images["provider-badge-apple"]
        _ = appleBadge.waitForExistence(timeout: 2.0)
        XCTAssertTrue(appleBadge.exists)

        // Switch to backend (simulate in settings)
        app.navigationBars.buttons["Settings"].tap()
        let settingsTable = app.tables["settings"]
        settingsTable.cells["translation-provider"].tap()
        settingsTable.cells["provider-backend"].tap()
        app.navigationBars.buttons["Back"].tap()

        // Translate another message
        let messageBubble2 = app.otherElements["message-bubble-2"]
        messageBubble2.buttons["translate-button"].tap()

        let backendBadge = messageBubble2.images["provider-badge-backend"]
        _ = backendBadge.waitForExistence(timeout: 2.0)
        XCTAssertTrue(backendBadge.exists, "Should use backend provider")
    }

    func testEndToEnd_OfflineToOnlineTransition() throws {
        // Scenario: User goes offline, translations use Apple, then online again

        // Start online, use backend
        app.launchArguments.append("--use-backend-translation")
        app.launch()

        let messageBubble1 = app.otherElements["message-bubble-1"]
        messageBubble1.buttons["translate-button"].tap()

        let backendBadge1 = messageBubble1.images["provider-badge-backend"]
        _ = backendBadge1.waitForExistence(timeout: 2.0)
        XCTAssertTrue(backendBadge1.exists)

        // Simulate offline
        app.launchArguments.append("--offline-mode")
        app.terminate()
        app.launch()

        // Translate while offline (should use Apple)
        let messageBubble2 = app.otherElements["message-bubble-2"]
        messageBubble2.buttons["translate-button"].tap()

        let appleBadge = messageBubble2.images["provider-badge-apple"]
        _ = appleBadge.waitForExistence(timeout: 2.0)
        XCTAssertTrue(appleBadge.exists, "Should fallback to Apple offline")

        // Go back online
        app.launchArguments.removeAll { $0 == "--offline-mode" }
        app.terminate()
        app.launch()

        // Translate should use backend again
        let messageBubble3 = app.otherElements["message-bubble-3"]
        messageBubble3.buttons["translate-button"].tap()

        let backendBadge2 = messageBubble3.images["provider-badge-backend"]
        _ = backendBadge2.waitForExistence(timeout: 2.0)
        XCTAssertTrue(backendBadge2.exists, "Should use backend when online")
    }

    // ... More integration scenarios:
    // - testEndToEnd_QuotaExhaustion (reach daily limit, show upgrade prompt)
    // - testEndToEnd_HybridComparison (view both translations side-by-side)
    // - testEndToEnd_CulturalNotesDisplay (see cultural context)
    // - testEndToEnd_PerformanceUnderLoad (translate many messages rapidly)
    // - testEndToEnd_DeepLink (translate specific message from notification)
}
```

### 7.2 Provider Switching Integration

**Scenario:** User preferences change translation provider dynamically

**Test Coverage:**
- Switch from Apple → Backend mid-conversation
- Switch from Backend → Hybrid mode
- Feature flag updates from backend
- User tier upgrade (Free → Pro enables backend)
- A/B test group assignment

### 7.3 Offline-Online Transitions

**Scenario:** Network connectivity changes during active translation

**Test Coverage:**
- Online → Offline mid-translation (fallback to Apple)
- Offline → Online (switch back to preferred provider)
- Cached translations used offline
- Queue backend translations for when online
- Partial connectivity (slow network)

### 7.4 Multi-Language Conversations

**Scenario:** Thread with messages in 5+ languages

**Test Coverage:**
- Detect and translate each language correctly
- Show multiple translations simultaneously
- Cache performance with many translations
- Language auto-detection accuracy
- UI responsiveness with many visible translations

---

## 8. Performance Benchmarks

### 8.1 Translation Latency Targets

**Apple Translation Framework:**
```swift
// Short text (< 50 characters): < 100ms
func testPerformance_AppleShortText() throws {
    measure {
        let expectation = XCTestExpectation(description: "Translation completes")

        Task {
            let result = try? await appleService.translate(
                text: "Hello",
                from: "en",
                to: "es"
            )
            XCTAssertNotNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.1)
    }
}

// Long text (500+ characters): < 2s
func testPerformance_AppleLongText() throws {
    let longText = String(repeating: "Test sentence. ", count: 50)

    measure {
        let expectation = XCTestExpectation(description: "Translation completes")

        Task {
            let result = try? await appleService.translate(
                text: longText,
                from: "en",
                to: "es"
            )
            XCTAssertNotNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
```

**Backend Translation:**
```swift
// Short text: < 2s (network + processing)
func testPerformance_BackendShortText() throws {
    measure {
        let expectation = XCTestExpectation(description: "Translation completes")

        Task {
            let result = try? await backendService.translate(
                text: "Hello",
                targetLanguage: "es"
            )
            XCTAssertNotNil(result)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
```

### 8.2 Cache Hit Rate Targets

**Target: > 60% cache hit rate**

```swift
func testCacheHitRate_TypicalUsage() async throws {
    let cache = AIServiceCache.shared
    await cache.clearAll()

    // Simulate typical usage: 100 translation requests
    let texts = (1...10).map { "Common phrase \($0)" }

    // First pass: all cache misses
    for text in texts {
        for _ in 1...5 {  // Translate each 5 times
            _ = try? await service.translate(text: text, targetLanguage: "es")
        }
    }

    let metrics = cache.getMetrics()
    let hitRate = metrics.hitRate

    XCTAssertGreaterThan(hitRate, 0.6, "Cache hit rate should exceed 60%")
    print("Cache hit rate: \(hitRate * 100)%")
}
```

### 8.3 Memory Usage Targets

**Target: < 50MB for translation services**

```swift
func testMemoryUsage_TranslationServices() throws {
    // Measure memory before
    let memoryBefore = getMemoryUsage()

    // Perform 100 translations
    Task {
        for i in 1...100 {
            _ = try? await service.translate(
                text: "Test message \(i)",
                targetLanguage: "es"
            )
        }
    }

    // Measure memory after
    let memoryAfter = getMemoryUsage()
    let memoryIncrease = memoryAfter - memoryBefore

    XCTAssertLessThan(
        memoryIncrease,
        50 * 1024 * 1024,  // 50MB
        "Memory increase should be < 50MB"
    )
}

private func getMemoryUsage() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

    let kerr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }

    return kerr == KERN_SUCCESS ? info.resident_size : 0
}
```

### 8.4 Battery Impact Targets

**Target: < 2% battery per 100 translations (on-device)**

```swift
// Note: Battery testing requires manual device testing
// Automated test would use XCTMetric for energy diagnostics

func testBatteryImpact_OnDeviceTranslation() throws {
    let options = XCTMeasureOptions()
    options.iterationCount = 5

    measure(metrics: [XCTOSSignpostMetric.applicationLaunch], options: options) {
        // Perform translations
        Task {
            for i in 1...100 {
                _ = try? await appleService.translate(
                    text: "Test \(i)",
                    from: "en",
                    to: "es"
                )
            }
        }
    }

    // Analyze energy metrics in Xcode Instruments
}
```

### 8.5 UI Responsiveness Targets

**Target: 60 FPS during translation**

```swift
func testUIResponsiveness_DuringTranslation() throws {
    // Use Xcode UI Performance testing
    let app = XCUIApplication()
    app.launch()

    // Navigate to messages
    let threadList = app.collectionViews["thread-list"]
    threadList.cells.firstMatch.tap()

    // Start monitoring FPS
    let performanceMetrics = [XCTOSSignpostMetric.scrollDecelerationMetric]

    measure(metrics: performanceMetrics) {
        // Trigger translation while scrolling
        let messageBubble = app.otherElements["message-bubble-1"]
        messageBubble.buttons["translate-button"].tap()

        // Scroll list
        let messageList = app.collectionViews["message-list"]
        messageList.swipeUp()
        messageList.swipeDown()
    }

    // Should maintain 60 FPS (16.67ms per frame)
}
```

---

## 9. Accessibility Testing Checklist

### 9.1 VoiceOver Compliance

**Required:**
- [ ] All translation buttons have descriptive labels
- [ ] Translation state announced ("Showing translation", "Hiding translation")
- [ ] Translated text read in correct order
- [ ] Provider badges have meaningful descriptions
- [ ] Loading states announced
- [ ] Error states announced with actionable info
- [ ] VoiceOver rotor supports custom actions (translate, copy translation)

**Test Coverage:**
```swift
func testVoiceOver_TranslationAnnouncement() throws {
    // Enable VoiceOver simulation
    let translateButton = app.buttons["translate-button"]

    XCTAssertNotNil(translateButton.label)
    XCTAssertTrue(translateButton.label.contains("Translate"))

    translateButton.tap()

    // Verify accessibility announcement
    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    XCTAssertNotNil(translatedText.value)
    XCTAssertFalse(translatedText.value as! String isEmpty)
}
```

### 9.2 Dynamic Type Support

**Required:**
- [ ] Translation text scales with system font size
- [ ] UI layout adjusts for large text sizes
- [ ] No text truncation at accessibility sizes
- [ ] Buttons remain tappable at all sizes

**Test Coverage:**
```swift
func testDynamicType_TranslationScaling() throws {
    // Set preferred content size category
    UIApplication.shared.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge

    let translateButton = app.buttons["translate-button"]
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    // Text should be visible and not truncated
    XCTAssertTrue(translatedText.exists)
    XCTAssertFalse(translatedText.label.contains("..."), "Text should not be truncated")
}
```

### 9.3 Color Contrast Compliance

**WCAG 2.1 AA Standards:**
- [ ] Normal text: 4.5:1 contrast ratio minimum
- [ ] Large text (18pt+): 3:1 contrast ratio minimum
- [ ] UI components: 3:1 contrast ratio minimum
- [ ] High contrast mode supported

**Test Coverage:**
```swift
func testColorContrast_TranslationText() throws {
    // Visual regression test or manual audit
    let translateButton = app.buttons["translate-button"]
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)

    // Snapshot test for contrast validation
    // Or integrate with Color Contrast Analyzer API
    XCTAssertTrue(translatedText.exists)
}
```

### 9.4 Keyboard Navigation

**Required:**
- [ ] Tab order logical and predictable
- [ ] All interactive elements keyboard accessible
- [ ] Focus indicator visible
- [ ] Keyboard shortcuts documented

**Test Coverage:**
```swift
func testKeyboardNavigation_TranslateButton() throws {
    // Simulate keyboard navigation
    let translateButton = app.buttons["translate-button"]

    // Tab to button
    app.typeKey(.tab, modifierFlags: [])

    // Verify focus
    XCTAssertTrue(translateButton.hasFocus, "Button should receive focus")

    // Activate with Enter/Space
    app.typeKey(.enter, modifierFlags: [])

    let translatedText = app.staticTexts["translated-text"]
    _ = translatedText.waitForExistence(timeout: 2.0)
    XCTAssertTrue(translatedText.exists)
}
```

### 9.5 Reduced Motion Compliance

**Required:**
- [ ] Animations disabled when Reduce Motion enabled
- [ ] Alternative UI transitions provided
- [ ] No essential information conveyed by motion alone

**Test Coverage:**
```swift
func testReducedMotion_TranslationAppearance() throws {
    // Enable reduced motion
    UIAccessibility.isReduceMotionEnabled = true

    let translateButton = app.buttons["translate-button"]
    translateButton.tap()

    let translatedText = app.staticTexts["translated-text"]

    // Should appear instantly without animation
    let exists = translatedText.waitForExistence(timeout: 0.1)
    XCTAssertTrue(exists, "Translation should appear without animation")
}
```

---

## 10. Delegation Execution Plan

### 10.1 Parallel Workstreams

**Workstream 1: Apple Translation Testing (Developer A)**
- **Duration:** 2 business days
- **Deliverables:** 80+ test cases for AppleTranslationService
- **Dependencies:** MockTranslationSession completed
- **Skills:** iOS frameworks, on-device ML, XCTest

**Workstream 2: Backend Translation Testing (Developer B)**
- **Duration:** 2 business days
- **Deliverables:** 70+ test cases for BackendTranslationService
- **Dependencies:** MockAIService, MockAuthManager completed
- **Skills:** API integration, networking, async testing

**Workstream 3: Unified Service Testing (Developer C)**
- **Duration:** 3 business days
- **Deliverables:** 90+ test cases for UnifiedTranslationService
- **Dependencies:** Workstreams 1 & 2 completed
- **Skills:** Architecture testing, dependency injection, feature flags

**Workstream 4: UI Testing (Developer D)**
- **Duration:** 3 business days
- **Deliverables:** 100+ UI test cases, accessibility compliance
- **Dependencies:** Workstream 3 50% complete
- **Skills:** XCTest UI, accessibility, visual testing

### 10.2 Timeline Gantt Chart

```
Week 1:
Mon    Tue    Wed    Thu    Fri
[=====================================================]
│      │      │      │      │
├─ WS1: Apple Translation Tests ────┤
│      │      │      │      │
├─ WS2: Backend Translation Tests ──┤
│      │      │      │      │
├─ WS3: Unified Service Tests ──────────────────────┤
│      │      │      │      │
│      ├─ WS4: UI Tests ────────────────────────────┤
│      │      │      │      │
├─ Mock Infrastructure (Day 0-1) ───┤

Week 2:
Mon    Tue    Wed    Thu    Fri
[=====================================================]
│      │      │      │      │
├─ Integration Tests ───────┤
│      │      │      │      │
├─ Performance Benchmarks ──┤
│      │      │      │      │
├─ Accessibility Audit ─────┤
│      │      │      │      │
├─ Code Review & Refinement────────────┤
│      │      │      │      │
│      ├─ Documentation ───────────────┤
```

### 10.3 Delegation via Zen MCP

**Using mcp__zen__testgen Tool:**

```json
{
  "step": "Delegate comprehensive testing for Translation Services (Tasks 7-10)",
  "step_number": 1,
  "total_steps": 4,
  "next_step_required": true,
  "findings": "Identified 340+ test cases across 4 major workstreams. Mock infrastructure designed. Performance targets defined. Accessibility checklist created.",
  "model": "grok-code-fast-1",
  "relevant_files": [
    "/clients/ios/GlobalBridge/Core/Services/Translation/AppleTranslationService.swift",
    "/clients/ios/GlobalBridge/Core/Services/AI/BackendTranslationService.swift",
    "/clients/ios/GlobalBridge/Core/Services/Translation/UnifiedTranslationService.swift",
    "/clients/ios/GlobalBridge/Views/Messages/MessageBubbleView.swift"
  ],
  "confidence": "high",
  "target_cases": 340,
  "categories": [
    "Task #7: Apple Translation Framework (80 cases)",
    "Task #8: Backend Translation Service (70 cases)",
    "Task #9: Unified Translation Service (90 cases)",
    "Task #10: Message Bubble UI (100 cases)"
  ],
  "delegation_packages": [
    {
      "workstream": 1,
      "developer_profile": "iOS Translation Framework Specialist",
      "target": 80,
      "duration_days": 2,
      "deliverables": ["AppleTranslationServiceTests.swift", "MockTranslationSession.swift"]
    },
    {
      "workstream": 2,
      "developer_profile": "iOS Backend Integration Specialist",
      "target": 70,
      "duration_days": 2,
      "deliverables": ["BackendTranslationServiceTests.swift", "MockAIService.swift"]
    },
    {
      "workstream": 3,
      "developer_profile": "iOS Senior Architecture Specialist",
      "target": 90,
      "duration_days": 3,
      "deliverables": ["UnifiedTranslationServiceTests.swift", "Integration tests"]
    },
    {
      "workstream": 4,
      "developer_profile": "iOS UI/UX Testing Specialist",
      "target": 100,
      "duration_days": 3,
      "deliverables": ["MessageBubbleTranslationUITests.swift", "Accessibility audit"]
    }
  ]
}
```

### 10.4 Quality Gates

**Gate 1: Mock Infrastructure (Day 1)**
- [ ] All mock classes implemented
- [ ] Mock behaviors validated
- [ ] Integration with existing test infrastructure confirmed

**Gate 2: Service Tests (Day 3)**
- [ ] Apple Translation: 80+ tests, 90%+ coverage
- [ ] Backend Translation: 70+ tests, 90%+ coverage
- [ ] All tests passing

**Gate 3: Unified Service Tests (Day 6)**
- [ ] Unified Translation: 90+ tests, 90%+ coverage
- [ ] Integration scenarios validated
- [ ] Performance benchmarks met

**Gate 4: UI Tests & Accessibility (Day 8)**
- [ ] Message Bubble UI: 100+ tests, 85%+ coverage
- [ ] Accessibility checklist 100% complete
- [ ] Visual regression tests passing
- [ ] Zero accessibility violations

**Gate 5: Final Review (Day 10)**
- [ ] All 340+ tests passing
- [ ] Code review completed
- [ ] Documentation updated
- [ ] Ready for merge to main branch

---

## 11. Success Metrics & KPIs

### 11.1 Code Coverage Targets

- **Translation Services:** 90%+ line coverage
- **Message Bubble UI:** 85%+ line coverage
- **Integration Tests:** 100% critical path coverage

### 11.2 Performance Targets Met

- **Apple Translation Latency:** < 100ms (short text), < 2s (long text)
- **Backend Translation Latency:** < 2s (short text), < 5s (long text)
- **Cache Hit Rate:** > 60%
- **Memory Usage:** < 50MB increase
- **UI Responsiveness:** 60 FPS maintained

### 11.3 Accessibility Compliance

- **VoiceOver:** 100% compliance
- **Dynamic Type:** 100% compliance
- **Color Contrast:** WCAG 2.1 AA
- **Keyboard Navigation:** 100% support
- **Reduced Motion:** 100% compliance

### 11.4 Test Execution Metrics

- **Total Test Cases:** 340+
- **Automated Tests:** 320+ (94%)
- **Manual Tests:** 20 (6%) - visual/accessibility
- **Test Execution Time:** < 10 minutes (full suite)
- **Flaky Tests:** 0 (100% deterministic)

---

## 12. Risk Mitigation

### 12.1 Technical Risks

**Risk:** Apple Translation Framework API changes in iOS updates
- **Mitigation:** Abstract framework behind protocol, extensive mocking

**Risk:** Backend API rate limiting in tests
- **Mitigation:** Use mock services for unit tests, limit integration test frequency

**Risk:** Flaky UI tests due to timing issues
- **Mitigation:** Use explicit waits, avoid hardcoded delays, implement retry logic

### 12.2 Schedule Risks

**Risk:** Workstream 3 depends on 1 & 2 completion
- **Mitigation:** Start mock infrastructure early, enable parallel work on stubs

**Risk:** UI testing takes longer than expected
- **Mitigation:** Prioritize critical paths, defer nice-to-have visual tests

### 12.3 Resource Risks

**Risk:** Developer availability conflicts
- **Mitigation:** Pre-assign developers, ensure clear delegation packages

**Risk:** Test infrastructure bottlenecks
- **Mitigation:** Use parallel test execution, optimize slow tests

---

## 13. Recommendations for Tasks #11-15

Based on learnings from Tasks #7-10 translation testing:

**For Task #11 (Thread Summarization):**
- Reuse MockAIService infrastructure
- Similar caching strategy tests (60%+ hit rate target)
- Focus on content quality validation (summary accuracy)
- Test long threads (1000+ messages) performance

**For Task #12 (Semantic Search):**
- Test vector search accuracy (precision/recall metrics)
- Performance benchmarks for large message corpora
- Multilingual search validation
- Test search result ranking algorithms

**For Task #13 (Task Extraction):**
- NLP accuracy testing (assignee, deadline, priority detection)
- Test edge cases (ambiguous tasks, multiple tasks in one message)
- Integration with iOS Reminders/Calendar
- Privacy considerations (task data handling)

**For Task #14 (Cultural Context UI):**
- Similar UI testing approach to Task #10
- Focus on educational value (user comprehension tests)
- Test cultural sensitivity (avoid stereotypes)
- Multilingual cultural notes validation

**For Task #15 (AI Features Dashboard):**
- Metrics aggregation testing
- Usage analytics privacy compliance
- Performance impact monitoring
- A/B test result visualization

---

## 14. Appendix

### 14.1 Test File Locations

```
/clients/ios/GlobalBridge/
├── Tests/
│   ├── Mocks/
│   │   ├── Translation/
│   │   │   ├── MockTranslationSession.swift
│   │   │   ├── MockLanguageAvailability.swift
│   │   │   └── MockTranslationConfiguration.swift
│   │   ├── AI/
│   │   │   ├── MockAIService.swift
│   │   │   ├── MockRateLimitTracker.swift
│   │   │   └── MockTranslationCache.swift
│   │   └── FeatureFlags/
│   │       └── MockFeatureFlags.swift
│   ├── Services/
│   │   ├── Translation/
│   │   │   ├── AppleTranslationServiceTests.swift (80+ cases)
│   │   │   └── UnifiedTranslationServiceTests.swift (90+ cases)
│   │   └── AI/
│   │       └── BackendTranslationServiceTests.swift (70+ cases)
│   ├── Views/
│   │   └── Messages/
│   │       └── MessageBubbleTranslationUITests.swift (100+ cases)
│   └── Integration/
│       ├── TranslationFlowIntegrationTests.swift
│       ├── ProviderSwitchingTests.swift
│       └── OfflineOnlineTransitionTests.swift
```

### 14.2 Test Naming Conventions

**Pattern:** `test<Feature>_<Scenario>_<ExpectedOutcome>`

**Examples:**
- `testTranslate_ShortText_CompletesQuickly`
- `testProviderSelection_AppleOnly_UsesAppleService`
- `testHybridMode_BothTranslations_ReturnedInParallel`
- `testAccessibility_VoiceOver_AnnouncesTranslation`

### 14.3 XCTest Utilities

**Custom Assertions:**

```swift
extension XCTestCase {
    /// Assert translation latency is acceptable
    func assertTranslationLatency(
        _ elapsed: TimeInterval,
        target: TimeInterval,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertLessThan(
            elapsed,
            target,
            "Translation took \(elapsed)s, expected < \(target)s",
            file: file,
            line: line
        )
    }

    /// Assert cache hit rate meets target
    func assertCacheHitRate(
        _ metrics: CacheMetrics,
        target: Double,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(
            metrics.hitRate,
            target,
            "Cache hit rate \(metrics.hitRate) below target \(target)",
            file: file,
            line: line
        )
    }

    /// Assert accessibility compliance
    func assertAccessibilityCompliant(
        _ element: XCUIElement,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertNotNil(element.label, "Element missing accessibility label", file: file, line: line)
        XCTAssertFalse(element.label.isEmpty, "Accessibility label empty", file: file, line: line)
        XCTAssertTrue(element.isAccessibilityElement, "Element not accessible", file: file, line: line)
    }
}
```

### 14.4 CI/CD Integration

**GitHub Actions Workflow:**

```yaml
name: Translation Tests

on:
  pull_request:
    paths:
      - 'clients/ios/GlobalBridge/Core/Services/Translation/**'
      - 'clients/ios/GlobalBridge/Core/Services/AI/**'
      - 'clients/ios/GlobalBridge/Views/Messages/**'
      - 'clients/ios/GlobalBridge/Tests/**'

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '15.2'

      - name: Run Translation Tests
        run: |
          cd clients/ios
          xcodebuild test \
            -scheme GlobalBridge \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
            -only-testing:GlobalBridgeTests/AppleTranslationServiceTests \
            -only-testing:GlobalBridgeTests/BackendTranslationServiceTests \
            -only-testing:GlobalBridgeTests/UnifiedTranslationServiceTests \
            -only-testing:GlobalBridgeTests/MessageBubbleTranslationUITests \
            -resultBundlePath TestResults

      - name: Generate Code Coverage
        run: |
          xcrun xccov view --report --only-targets TestResults.xcresult > coverage.txt
          cat coverage.txt

      - name: Check Coverage Threshold
        run: |
          COVERAGE=$(grep "GlobalBridge" coverage.txt | awk '{print $4}' | sed 's/%//')
          if (( $(echo "$COVERAGE < 90" | bc -l) )); then
            echo "Code coverage $COVERAGE% below 90% threshold"
            exit 1
          fi

      - name: Upload Test Results
        uses: actions/upload-artifact@v3
        with:
          name: test-results
          path: TestResults.xcresult
```

---

## 15. Conclusion

This comprehensive testing delegation plan provides:

1. **Detailed Test Specifications:** 340+ test cases across 4 major workstreams
2. **Mock Infrastructure:** Complete mock ecosystem for isolated testing
3. **Integration Scenarios:** End-to-end flows validating complete translation system
4. **Performance Benchmarks:** Quantifiable targets for latency, cache hit rate, memory
5. **Accessibility Compliance:** WCAG 2.1 AA standards, VoiceOver, Dynamic Type
6. **Delegation Strategy:** 4 parallel workstreams with clear deliverables and timelines
7. **Quality Gates:** Phased checkpoints ensuring incremental validation
8. **Risk Mitigation:** Technical, schedule, and resource risk management

**Next Steps:**

1. **Approve Plan:** Review and approve delegation plan
2. **Assign Developers:** Confirm 4 specialist developers via Zen MCP
3. **Kickoff:** Day 0 - Mock infrastructure implementation
4. **Execute:** Days 1-8 - Parallel test development
5. **Review:** Days 9-10 - Code review, refinement, merge

**Expected Outcomes:**

- ✅ 340+ comprehensive test cases implemented
- ✅ 90%+ code coverage for translation services
- ✅ 85%+ UI test coverage for message bubbles
- ✅ Zero accessibility violations
- ✅ All performance benchmarks met
- ✅ Complete documentation and CI/CD integration
- ✅ Ready for production deployment

This plan positions the GlobalBridge iOS app for robust, reliable translation functionality with world-class quality assurance.

---

**Document Prepared By:** iOS Development Delegation Specialist
**Coordination:** Zen MCP Server + Grot Code Fast 1
**Date:** 2025-10-24
**Status:** Ready for Delegation
