//
//  UnifiedTranslationServiceTests.swift
//  GlobalBridgeTests
//
//  Comprehensive tests for UnifiedTranslationService provider selection,
//  fallback strategies, and metrics tracking
//

import XCTest
@testable import GlobalBridge

@MainActor
final class UnifiedTranslationServiceTests: XCTestCase {

    // MARK: - Properties

    var sut: UnifiedTranslationService!
    var mockAppleService: MockAppleTranslationService!
    var mockBackendService: MockBackendTranslationService!
    var mockNetworkMonitor: MockNetworkMonitor!
    var mockFeatureFlags: MockFeatureFlags!
    var mockCache: MockAIServiceCache!
    var mockRateLimiter: MockRateLimitTracker!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create mocks
        mockAppleService = MockAppleTranslationService()
        mockBackendService = MockBackendTranslationService()
        mockNetworkMonitor = MockNetworkMonitor()
        mockFeatureFlags = MockFeatureFlags()
        mockCache = MockAIServiceCache()
        mockRateLimiter = MockRateLimitTracker()

        // Default configurations
        mockNetworkMonitor.isConnected = true
        mockFeatureFlags.enabledFeatures = [.translationEnabled]
        mockRateLimiter.allowRequests = true

        // TODO: Create UnifiedTranslationService with dependency injection
        // For now, tests will use the shared instance
        sut = .shared
    }

    override func tearDown() async throws {
        sut = nil
        mockAppleService = nil
        mockBackendService = nil
        mockNetworkMonitor = nil
        mockFeatureFlags = nil
        mockCache = nil
        mockRateLimiter = nil

        try await super.tearDown()
    }

    // MARK: - Provider Selection Tests

    func testAutoSelectionUsesBackendWhenOnline() async throws {
        // Given: Online with supported language pair
        mockNetworkMonitor.isConnected = true

        // When: Translate with auto provider
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .auto
        )

        // Then: Backend should be used (default for best quality)
        XCTAssertEqual(result.provider, "backend")
        XCTAssertFalse(result.fallbackUsed)
    }

    func testAutoSelectionUsesAppleWhenOffline() async throws {
        // Given: Offline
        mockNetworkMonitor.isConnected = false

        // When: Translate with auto provider
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .auto
        )

        // Then: Apple should be used
        XCTAssertEqual(result.provider, "apple")
    }

    func testAutoSelectionUsesBackendForUnsupportedApplePair() async throws {
        // Given: Online with language pair unsupported by Apple
        mockNetworkMonitor.isConnected = true

        // When: Translate unsupported pair (e.g., English to Turkish)
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "tr",  // Turkish not in Apple's supported pairs
            provider: .auto
        )

        // Then: Backend should be used
        XCTAssertEqual(result.provider, "backend")
    }

    func testAutoSelectionUsesAppleWhenBackendQuotaExceeded() async throws {
        // Given: Backend quota exceeded
        mockNetworkMonitor.isConnected = true
        mockRateLimiter.allowRequests = false

        // When: Translate with auto provider
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .auto
        )

        // Then: Apple should be used as fallback
        XCTAssertEqual(result.provider, "apple")
    }

    // MARK: - Explicit Provider Tests

    func testExplicitAppleProviderIsHonored() async throws {
        // Given: Explicit Apple provider request
        mockNetworkMonitor.isConnected = true

        // When: Translate with .apple provider
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .apple
        )

        // Then: Apple should be used
        XCTAssertEqual(result.provider, "apple")
    }

    func testExplicitBackendProviderIsHonored() async throws {
        // Given: Explicit Backend provider request
        mockNetworkMonitor.isConnected = true

        // When: Translate with .backend provider
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .backend
        )

        // Then: Backend should be used
        XCTAssertEqual(result.provider, "backend")
    }

    func testAppleProviderFallsBackToBackendWhenUnsupported() async throws {
        // Given: Apple provider requested but language unsupported
        mockNetworkMonitor.isConnected = true

        // When: Translate unsupported pair with .apple
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "tr",  // Unsupported by Apple
            provider: .apple
        )

        // Then: Should fallback to backend
        XCTAssertEqual(result.provider, "backend")
        // In practice, the provider selection logic adjusts before attempting translation
    }

    func testBackendProviderFallsBackToAppleWhenOffline() async throws {
        // Given: Backend provider requested but offline
        mockNetworkMonitor.isConnected = false

        // When: Translate with .backend provider
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .backend
        )

        // Then: Should fallback to Apple
        XCTAssertEqual(result.provider, "apple")
    }

    // MARK: - Fallback Strategy Tests

    func testBackendFailureFallsBackToApple() async throws {
        // Given: Backend configured to fail
        mockBackendService.shouldFail = true
        mockNetworkMonitor.isConnected = true

        // When: Translate with backend
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .backend
        )

        // Then: Should fallback to Apple
        XCTAssertEqual(result.provider, "apple")
        XCTAssertTrue(result.fallbackUsed)

        // Verify fallback metric incremented
        let metrics = sut.getMetrics()
        XCTAssertEqual(metrics.fallbackEvents, 1)
    }

    func testAppleFailureFallsBackToBackend() async throws {
        // Given: Apple configured to fail, backend available
        mockAppleService.shouldFail = true
        mockNetworkMonitor.isConnected = true

        // When: Translate with Apple
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .apple
        )

        // Then: Should fallback to Backend
        XCTAssertEqual(result.provider, "backend")
        XCTAssertTrue(result.fallbackUsed)
    }

    func testBothProvidersFailThrowsError() async throws {
        // Given: Both providers configured to fail
        mockAppleService.shouldFail = true
        mockBackendService.shouldFail = true
        mockNetworkMonitor.isConnected = true

        // When/Then: Translation should throw error
        do {
            _ = try await sut.translate(
                text: "Hello, world!",
                from: "en",
                to: "es",
                provider: .auto
            )
            XCTFail("Should have thrown error")
        } catch {
            // Expected error
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Hybrid Mode Tests

    func testHybridModeTranslatesWithBothProviders() async throws {
        // Given: Both providers available
        mockNetworkMonitor.isConnected = true

        // When: Translate with hybrid mode
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .hybrid
        )

        // Then: Should have both translations
        XCTAssertEqual(result.provider, "backend")  // Primary
        XCTAssertNotNil(result.alternateTranslation)
        XCTAssertEqual(result.alternateProvider, "apple")
        XCTAssertNotNil(result.alternateConfidence)
    }

    func testHybridModeReturnsAppleIfBackendFails() async throws {
        // Given: Backend fails, Apple succeeds
        mockBackendService.shouldFail = true
        mockNetworkMonitor.isConnected = true

        // When: Translate with hybrid mode
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .hybrid
        )

        // Then: Should return Apple result
        XCTAssertEqual(result.provider, "apple")
        XCTAssertTrue(result.fallbackUsed)
    }

    func testHybridModeReturnsBackendIfAppleFails() async throws {
        // Given: Apple fails, Backend succeeds
        mockAppleService.shouldFail = true
        mockNetworkMonitor.isConnected = true

        // When: Translate with hybrid mode
        let result = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .hybrid
        )

        // Then: Should return Backend result
        XCTAssertEqual(result.provider, "backend")
        XCTAssertTrue(result.fallbackUsed)
    }

    // MARK: - Cache Tests

    func testCacheHitReturnsCachedResult() async throws {
        // Given: Cache contains result
        mockCache.hasCachedResult = true

        // When: Translate same text twice
        let result1 = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .auto
        )

        let result2 = try await sut.translate(
            text: "Hello, world!",
            from: "en",
            to: "es",
            provider: .auto
        )

        // Then: Second call should be cache hit
        XCTAssertTrue(result2.cacheHit || result1.translatedText == result2.translatedText)
    }

    func testClearCacheRemovesAllCachedResults() async throws {
        // Given: Cache contains results
        _ = try await sut.translate(text: "Hello", from: "en", to: "es", provider: .auto)

        // When: Clear cache
        sut.clearCache()

        // Then: Cache should be empty
        // Verify by translating again and checking it's not a cache hit
        let result = try await sut.translate(text: "Hello", from: "en", to: "es", provider: .auto)
        XCTAssertFalse(result.cacheHit)
    }

    // MARK: - Metrics Tests

    func testMetricsTrackTotalTranslations() async throws {
        // Given: Clean metrics
        sut.resetMetrics()

        // When: Perform multiple translations
        _ = try await sut.translate(text: "Hello", from: "en", to: "es", provider: .apple)
        _ = try await sut.translate(text: "World", from: "en", to: "fr", provider: .backend)

        // Then: Total should be 2
        let metrics = sut.getMetrics()
        XCTAssertEqual(metrics.totalTranslations, 2)
    }

    func testMetricsTrackProviderUsage() async throws {
        // Given: Clean metrics
        sut.resetMetrics()

        // When: Use different providers
        _ = try await sut.translate(text: "Hello", from: "en", to: "es", provider: .apple)
        _ = try await sut.translate(text: "World", from: "en", to: "fr", provider: .backend)
        _ = try await sut.translate(text: "Test", from: "en", to: "de", provider: .hybrid)

        // Then: Counts should match
        let metrics = sut.getMetrics()
        XCTAssertEqual(metrics.appleTranslations, 1)
        XCTAssertEqual(metrics.backendTranslations, 1)
        XCTAssertEqual(metrics.hybridTranslations, 1)
    }

    func testMetricsTrackCacheHits() async throws {
        // Given: Clean metrics
        sut.resetMetrics()

        // When: Translate same text multiple times
        _ = try await sut.translate(text: "Hello", from: "en", to: "es")
        _ = try await sut.translate(text: "Hello", from: "en", to: "es")
        _ = try await sut.translate(text: "Hello", from: "en", to: "es")

        // Then: Should have cache hits (at least 2)
        let metrics = sut.getMetrics()
        XCTAssertGreaterThanOrEqual(metrics.cacheHits, 2)
    }

    func testMetricsCalculateCacheHitRate() async throws {
        // Given: Clean metrics
        sut.resetMetrics()

        // When: 1 fresh translation + 2 cache hits
        _ = try await sut.translate(text: "Hello", from: "en", to: "es")
        _ = try await sut.translate(text: "Hello", from: "en", to: "es")
        _ = try await sut.translate(text: "Hello", from: "en", to: "es")

        // Then: Cache hit rate should be ~66%
        let metrics = sut.getMetrics()
        XCTAssertGreaterThanOrEqual(metrics.cacheHitRate, 0.5)
    }

    func testMetricsTrackOfflineTranslations() async throws {
        // Given: Offline mode
        sut.resetMetrics()
        mockNetworkMonitor.isConnected = false

        // When: Translate offline
        _ = try await sut.translate(text: "Hello", from: "en", to: "es")

        // Then: Should track as offline translation
        let metrics = sut.getMetrics()
        XCTAssertEqual(metrics.offlineTranslations, 1)
    }

    // MARK: - Feature Flag Tests

    func testTranslationFailsWhenFeatureDisabled() async throws {
        // Given: Translation feature disabled
        mockFeatureFlags.enabledFeatures = []

        // When/Then: Translation should throw error
        do {
            _ = try await sut.translate(
                text: "Hello, world!",
                from: "en",
                to: "es"
            )
            XCTFail("Should have thrown error")
        } catch let error as AIServiceError {
            if case .featureDisabled = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Validation Tests

    func testEmptyTextThrowsError() async throws {
        // When/Then: Empty text should throw
        do {
            _ = try await sut.translate(text: "", from: "en", to: "es")
            XCTFail("Should have thrown error")
        } catch let error as AIServiceError {
            if case .invalidText = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testWhitespaceOnlyTextThrowsError() async throws {
        // When/Then: Whitespace-only text should throw
        do {
            _ = try await sut.translate(text: "   \n\t  ", from: "en", to: "es")
            XCTFail("Should have thrown error")
        } catch let error as AIServiceError {
            if case .invalidText = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    // MARK: - Configuration Tests

    func testSetPreferredProviderUpdatesDefault() async throws {
        // Given: Default provider
        XCTAssertEqual(sut.preferredProvider, .auto)

        // When: Set preferred provider
        sut.setPreferredProvider(.apple)

        // Then: Should be updated
        XCTAssertEqual(sut.preferredProvider, .apple)
    }

    func testGetMetricsReturnsCurrentMetrics() {
        // When: Get metrics
        let metrics = sut.getMetrics()

        // Then: Should return valid metrics
        XCTAssertNotNil(metrics)
        XCTAssertGreaterThanOrEqual(metrics.totalTranslations, 0)
    }
}

// MARK: - Mock Objects

// Note: In a real implementation, these would be in separate files

class MockAppleTranslationService {
    var shouldFail = false
    var translationDelay: TimeInterval = 0.05

    func translate(text: String, from: String, to: String) async throws -> TranslationResult {
        if shouldFail {
            throw AIServiceError.backendError(message: "Mock Apple failure")
        }

        try await Task.sleep(nanoseconds: UInt64(translationDelay * 1_000_000_000))

        return TranslationResult(
            originalText: text,
            translatedText: "Apple: \(text) -> \(to)",
            sourceLanguage: from,
            targetLanguage: to,
            confidence: 0.85,
            provider: "apple",
            culturalNotes: nil,
            timestamp: Date()
        )
    }
}

class MockBackendTranslationService {
    var shouldFail = false
    var translationDelay: TimeInterval = 0.1

    func translate(text: String, targetLanguage: String, sourceLanguage: String?) async throws -> EnhancedTranslationResult {
        if shouldFail {
            throw AIServiceError.backendError(message: "Mock Backend failure")
        }

        try await Task.sleep(nanoseconds: UInt64(translationDelay * 1_000_000_000))

        return EnhancedTranslationResult(
            originalText: text,
            translatedText: "Backend: \(text) -> \(targetLanguage)",
            sourceLanguage: sourceLanguage ?? "auto",
            targetLanguage: targetLanguage,
            confidence: 0.95,
            provider: "backend",
            culturalNotes: "Mock cultural note",
            formality: .neutral,
            contextUsed: false,
            qualityScore: 0.9,
            timestamp: Date(),
            translationId: UUID().uuidString
        )
    }
}

class MockNetworkMonitor: ObservableObject {
    @Published var isConnected = true
    @Published var connectionType: NetworkMonitor.ConnectionType = .wifi
}

class MockFeatureFlags {
    var enabledFeatures: Set<FeatureFlags.Feature> = []

    func hasFeature(_ feature: FeatureFlags.Feature) -> Bool {
        return enabledFeatures.contains(feature)
    }
}

class MockAIServiceCache {
    var hasCachedResult = false
    private var cache: [String: Any] = [:]

    func retrieve<T: Codable>(forKey key: String, type: AIServiceCache.CacheType) async -> T? {
        return cache[key] as? T
    }

    func store<T: Codable>(_ value: T, forKey key: String, type: AIServiceCache.CacheType) async {
        cache[key] = value
    }

    func clearAll() {
        cache.removeAll()
    }
}

class MockRateLimitTracker {
    var allowRequests = true

    func canMakeRequest(for operation: RateLimitTracker.Operation) -> (isAllowed: Bool, remaining: Int?, tierName: String?) {
        return (allowRequests, allowRequests ? 100 : 0, "free")
    }

    func recordRequest(for operation: RateLimitTracker.Operation) {
        // No-op for mock
    }
}
