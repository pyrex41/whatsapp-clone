//
//  BackendTranslationServiceTests.swift
//  GlobalBridgeTests
//
//  Comprehensive unit tests for BackendTranslationService
//  Tests context-aware translation, cultural notes, formality detection,
//  batch translation, history tracking, and quality feedback
//

import XCTest
@testable import GlobalBridge

@MainActor
final class BackendTranslationServiceTests: XCTestCase {

    // MARK: - Properties

    var service: BackendTranslationService!
    var mockAIService: MockAIService!
    var mockCache: MockAIServiceCache!
    var mockRateLimiter: MockRateLimitTracker!
    var mockFeatureFlags: MockFeatureFlags!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Initialize mocks
        mockAIService = MockAIService()
        mockCache = MockAIServiceCache()
        mockRateLimiter = MockRateLimitTracker()
        mockFeatureFlags = MockFeatureFlags()

        // Reset state
        mockAIService.reset()
        mockCache.reset()
        mockRateLimiter.reset()
        mockFeatureFlags.reset()
    }

    override func tearDown() async throws {
        service = nil
        mockAIService = nil
        mockCache = nil
        mockRateLimiter = nil
        mockFeatureFlags = nil

        try await super.tearDown()
    }

    // MARK: - Basic Translation Tests

    func testBasicTranslation() async throws {
        // Given
        let text = "Hello, how are you?"
        let target = "es"
        let expectedTranslation = "Hola, ¿cómo estás?"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: expectedTranslation,
            detectedLanguage: "en",
            confidence: 0.95
        )

        // When
        let result = try await service.translate(
            text: text,
            targetLanguage: target
        )

        // Then
        XCTAssertEqual(result.originalText, text)
        XCTAssertEqual(result.translatedText, expectedTranslation)
        XCTAssertEqual(result.sourceLanguage, "en")
        XCTAssertEqual(result.targetLanguage, target)
        XCTAssertEqual(result.confidence, 0.95)
        XCTAssertTrue(result.qualityScore > 0.0)
    }

    func testTranslationWithSourceLanguage() async throws {
        // Given
        let text = "Bonjour"
        let source = "fr"
        let target = "en"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Hello",
            detectedLanguage: "fr",
            confidence: 0.98
        )

        // When
        let result = try await service.translate(
            text: text,
            targetLanguage: target,
            sourceLanguage: source
        )

        // Then
        XCTAssertEqual(result.sourceLanguage, source)
        XCTAssertEqual(result.confidence, 0.98)
    }

    func testEmptyTextThrowsError() async {
        // Given
        let text = "   "
        let target = "es"

        // When/Then
        do {
            _ = try await service.translate(text: text, targetLanguage: target)
            XCTFail("Should throw invalidText error")
        } catch AIServiceError.invalidText {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Context-Aware Translation Tests

    func testTranslationWithContext() async throws {
        // Given
        let text = "I need a table"
        let target = "es"
        let context = [
            "Are you hungry?",
            "Let's go to the restaurant"
        ]

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Necesito una mesa",
            detectedLanguage: "en",
            confidence: 0.96
        )

        // When
        let result = try await service.translate(
            text: text,
            targetLanguage: target,
            context: context
        )

        // Then
        XCTAssertTrue(result.contextUsed)
        XCTAssertEqual(result.translatedText, "Necesito una mesa")
    }

    func testContextAffectsCacheKey() async throws {
        // Given
        let text = "bank"
        let target = "es"
        let context1 = ["river", "water"]
        let context2 = ["money", "account"]

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "orilla",
            detectedLanguage: "en",
            confidence: 0.90
        )

        // When
        let result1 = try await service.translate(text: text, targetLanguage: target, context: context1)

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "banco",
            detectedLanguage: "en",
            confidence: 0.90
        )

        let result2 = try await service.translate(text: text, targetLanguage: target, context: context2)

        // Then
        XCTAssertNotEqual(result1.translatedText, result2.translatedText)
        XCTAssertEqual(mockAIService.translateCallCount, 2, "Should not use cache with different context")
    }

    // MARK: - Cultural Notes Tests

    func testCulturalNotesForIdioms() async throws {
        // Given
        let text = "Break a leg!"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "¡Buena suerte!",
            detectedLanguage: "en",
            confidence: 0.92
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertNotNil(result.culturalNotes)
        XCTAssertTrue(result.culturalNotes?.contains("idiom") ?? false)
    }

    func testCulturalNotesForCommonPhrase() async throws {
        // Given
        let text = "It's a piece of cake"
        let target = "fr"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "C'est du gâteau",
            detectedLanguage: "en",
            confidence: 0.88
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertNotNil(result.culturalNotes)
        XCTAssertTrue(result.culturalNotes?.lowercased().contains("easy") ?? false)
    }

    // MARK: - Formality Detection Tests

    func testFormalityDetectionFormal() async throws {
        // Given
        let text = "Could you please assist me with this matter?"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "¿Podría usted asistirme con este asunto?",
            detectedLanguage: "en",
            confidence: 0.94
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertEqual(result.formality, .formal)
    }

    func testFormalityDetectionInformal() async throws {
        // Given
        let text = "Hey, gonna grab lunch?"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Oye, ¿vamos a almorzar?",
            detectedLanguage: "en",
            confidence: 0.91
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertEqual(result.formality, .informal)
    }

    func testExplicitFormalityOverride() async throws {
        // Given
        let text = "Hello"
        let target = "es"
        let explicitFormality = FormalityLevel.formal

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Buenos días",
            detectedLanguage: "en",
            confidence: 0.95
        )

        // When
        let result = try await service.translate(
            text: text,
            targetLanguage: target,
            formality: explicitFormality
        )

        // Then
        XCTAssertEqual(result.formality, .formal)
    }

    // MARK: - Batch Translation Tests

    func testBatchTranslation() async throws {
        // Given
        let texts = [
            "Hello",
            "Goodbye",
            "Thank you"
        ]
        let target = "es"

        mockAIService.mockTranslationResults = [
            TranslationResult(translatedText: "Hola", detectedLanguage: "en", confidence: 0.95),
            TranslationResult(translatedText: "Adiós", detectedLanguage: "en", confidence: 0.96),
            TranslationResult(translatedText: "Gracias", detectedLanguage: "en", confidence: 0.97)
        ]

        // When
        let results = try await service.batchTranslate(
            texts: texts,
            targetLanguage: target
        )

        // Then
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].translatedText, "Hola")
        XCTAssertEqual(results[1].translatedText, "Adiós")
        XCTAssertEqual(results[2].translatedText, "Gracias")
    }

    func testBatchTranslationEmptyArray() async throws {
        // Given
        let texts: [String] = []
        let target = "es"

        // When
        let results = try await service.batchTranslate(texts: texts, targetLanguage: target)

        // Then
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(mockAIService.translateCallCount, 0)
    }

    func testBatchTranslationFiltersEmptyTexts() async throws {
        // Given
        let texts = [
            "Hello",
            "   ",
            "Goodbye",
            ""
        ]
        let target = "es"

        mockAIService.mockTranslationResults = [
            TranslationResult(translatedText: "Hola", detectedLanguage: "en", confidence: 0.95),
            TranslationResult(translatedText: "Adiós", detectedLanguage: "en", confidence: 0.96)
        ]

        // When
        let results = try await service.batchTranslate(texts: texts, targetLanguage: target)

        // Then
        XCTAssertEqual(results.count, 2, "Should filter out empty texts")
    }

    func testBatchTranslationOrderPreservation() async throws {
        // Given
        let texts = ["One", "Two", "Three", "Four", "Five"]
        let target = "es"

        mockAIService.mockTranslationResults = texts.map {
            TranslationResult(translatedText: $0 + "_translated", detectedLanguage: "en", confidence: 0.95)
        }

        // When
        let results = try await service.batchTranslate(
            texts: texts,
            targetLanguage: target,
            preserveOrder: true
        )

        // Then
        XCTAssertEqual(results.count, 5)
        for (index, result) in results.enumerated() {
            XCTAssertEqual(result.originalText, texts[index])
        }
    }

    // MARK: - Caching Tests

    func testTranslationUsesCache() async throws {
        // Given
        let text = "Hello"
        let target = "es"

        let cachedResult = EnhancedTranslationResult(
            originalText: text,
            translatedText: "Hola (cached)",
            sourceLanguage: "en",
            targetLanguage: target,
            confidence: 0.95,
            provider: "cache",
            culturalNotes: nil,
            formality: .neutral,
            contextUsed: false,
            qualityScore: 0.90,
            timestamp: Date(),
            translationId: "test-123"
        )

        await mockCache.store(cachedResult, forKey: "test_cache_key", type: .translation)

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertEqual(result.translatedText, "Hola (cached)")
        XCTAssertEqual(mockAIService.translateCallCount, 0, "Should not call AI service when cached")
    }

    func testTranslationStoresInCache() async throws {
        // Given
        let text = "Hello"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Hola",
            detectedLanguage: "en",
            confidence: 0.95
        )

        // When
        _ = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertTrue(mockCache.storeCallCount > 0, "Should store result in cache")
    }

    // MARK: - Rate Limiting Tests

    func testRateLimitingBlocks() async {
        // Given
        let text = "Hello"
        let target = "es"

        mockRateLimiter.mockCanMakeRequest = (isAllowed: false, remaining: 0, tierName: "Free")

        // When/Then
        do {
            _ = try await service.translate(text: text, targetLanguage: target)
            XCTFail("Should throw rate limit error")
        } catch AIServiceError.rateLimitExceeded {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testRateLimitingAllows() async throws {
        // Given
        let text = "Hello"
        let target = "es"

        mockRateLimiter.mockCanMakeRequest = (isAllowed: true, remaining: 10, tierName: "Pro")

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Hola",
            detectedLanguage: "en",
            confidence: 0.95
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(mockRateLimiter.recordRequestCallCount, 1)
    }

    // MARK: - Translation History Tests

    func testTranslationHistory() async throws {
        // Given
        let text1 = "Hello"
        let text2 = "Goodbye"
        let target = "es"

        mockAIService.mockTranslationResults = [
            TranslationResult(translatedText: "Hola", detectedLanguage: "en", confidence: 0.95),
            TranslationResult(translatedText: "Adiós", detectedLanguage: "en", confidence: 0.96)
        ]

        // When
        _ = try await service.translate(text: text1, targetLanguage: target)
        _ = try await service.translate(text: text2, targetLanguage: target)

        let history = service.getTranslationHistory()

        // Then
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].originalText, text2, "Most recent should be first")
        XCTAssertEqual(history[1].originalText, text1)
    }

    func testTranslationHistoryLimit() async throws {
        // Given
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Translation",
            detectedLanguage: "en",
            confidence: 0.95
        )

        // When - Translate 150 texts (more than maxHistorySize of 100)
        for i in 0..<150 {
            _ = try await service.translate(text: "Text \(i)", targetLanguage: target)
        }

        let history = service.getTranslationHistory()

        // Then
        XCTAssertLessThanOrEqual(history.count, 100, "History should be capped at 100")
    }

    func testClearTranslationHistory() async throws {
        // Given
        let text = "Hello"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Hola",
            detectedLanguage: "en",
            confidence: 0.95
        )

        _ = try await service.translate(text: text, targetLanguage: target)
        XCTAssertFalse(service.getTranslationHistory().isEmpty)

        // When
        service.clearTranslationHistory()

        // Then
        XCTAssertTrue(service.getTranslationHistory().isEmpty)
    }

    // MARK: - Quality Feedback Tests

    func testSubmitQualityFeedback() async throws {
        // Given
        let translationId = "test-123"
        let rating = 4
        let issues: [TranslationIssue] = [.awkwardPhrasing]
        let suggestion = "Better translation here"

        // When
        await service.submitQualityFeedback(
            translationId: translationId,
            rating: rating,
            issues: issues,
            suggestedTranslation: suggestion
        )

        // Then - No direct way to verify, but should not crash
        // In real implementation, would verify backend call
    }

    // MARK: - Statistics Tests

    func testStatistics() async throws {
        // Given
        let target = "es"

        mockAIService.mockTranslationResults = [
            TranslationResult(translatedText: "Hola", detectedLanguage: "en", confidence: 0.90),
            TranslationResult(translatedText: "Adiós", detectedLanguage: "en", confidence: 0.95),
            TranslationResult(translatedText: "Gracias", detectedLanguage: "en", confidence: 0.85)
        ]

        // When
        _ = try await service.translate(text: "Hello", targetLanguage: target)
        _ = try await service.translate(text: "Goodbye", targetLanguage: target)
        _ = try await service.translate(text: "Thanks", targetLanguage: target)

        let stats = service.getStatistics()

        // Then
        XCTAssertEqual(stats.totalTranslations, 3)
        XCTAssertEqual(stats.averageConfidence, 0.90, accuracy: 0.01)
        XCTAssertTrue(stats.languagePairs.keys.contains("en->es"))
    }

    // MARK: - Quality Score Tests

    func testQualityScoreCalculation() async throws {
        // Given
        let text = "Hello, how are you?"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Hola, ¿cómo estás?",
            detectedLanguage: "en",
            confidence: 0.95
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertGreaterThan(result.qualityScore, 0.0)
        XCTAssertLessThanOrEqual(result.qualityScore, 1.0)
        XCTAssertTrue(result.isHighQuality)
    }

    func testQualityScoreLowForShortText() async throws {
        // Given
        let text = "Hi"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "Hola",
            detectedLanguage: "en",
            confidence: 0.95
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertLessThan(result.qualityScore, 0.95, "Short texts should have slightly lower quality score")
    }

    // MARK: - Feature Flag Tests

    func testFeatureDisabled() async {
        // Given
        let text = "Hello"
        let target = "es"

        mockFeatureFlags.setFeatureEnabled(.aiTranslation, enabled: false)

        // When/Then
        do {
            _ = try await service.translate(text: text, targetLanguage: target)
            XCTFail("Should throw feature disabled error")
        } catch AIServiceError.featureDisabled {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Edge Cases

    func testVeryLongText() async throws {
        // Given
        let text = String(repeating: "This is a long sentence. ", count: 100)
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: String(repeating: "Esta es una oración larga. ", count: 100),
            detectedLanguage: "en",
            confidence: 0.88
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertNotNil(result)
        XCTAssertFalse(result.translatedText.isEmpty)
    }

    func testSpecialCharacters() async throws {
        // Given
        let text = "Hello! 👋 How are you? 😊"
        let target = "es"

        mockAIService.mockTranslationResult = TranslationResult(
            translatedText: "¡Hola! 👋 ¿Cómo estás? 😊",
            detectedLanguage: "en",
            confidence: 0.93
        )

        // When
        let result = try await service.translate(text: text, targetLanguage: target)

        // Then
        XCTAssertTrue(result.translatedText.contains("👋"))
        XCTAssertTrue(result.translatedText.contains("😊"))
    }
}

// MARK: - Mock Objects

// Mock implementations would be in a separate file in production

@MainActor
final class MockAIService {
    var translateCallCount = 0
    var mockTranslationResult: TranslationResult?
    var mockTranslationResults: [TranslationResult] = []
    private var resultIndex = 0

    func translate(text: String, targetLanguage: String, sourceLanguage: String?) async throws -> TranslationResult {
        translateCallCount += 1

        if !mockTranslationResults.isEmpty {
            defer { resultIndex += 1 }
            return mockTranslationResults[min(resultIndex, mockTranslationResults.count - 1)]
        }

        guard let result = mockTranslationResult else {
            throw AIServiceError.invalidResponse
        }

        return result
    }

    func reset() {
        translateCallCount = 0
        mockTranslationResult = nil
        mockTranslationResults = []
        resultIndex = 0
    }
}

@MainActor
final class MockAIServiceCache {
    var storeCallCount = 0
    var retrieveCallCount = 0
    private var storage: [String: Any] = [:]

    func store<T: Codable>(_ item: T, forKey key: String, type: AIServiceCache.CacheType) async {
        storeCallCount += 1
        storage[key] = item
    }

    func retrieve<T: Codable>(forKey key: String, type: AIServiceCache.CacheType) async -> T? {
        retrieveCallCount += 1
        return storage[key] as? T
    }

    func reset() {
        storeCallCount = 0
        retrieveCallCount = 0
        storage.removeAll()
    }
}

@MainActor
final class MockRateLimitTracker {
    var recordRequestCallCount = 0
    var mockCanMakeRequest: (isAllowed: Bool, remaining: Int?, tierName: String?) = (true, 100, "Pro")

    func canMakeRequest(for feature: RateLimitTracker.AIFeature) -> (isAllowed: Bool, remaining: Int?, tierName: String?, errorMessage: String?) {
        return (mockCanMakeRequest.isAllowed, mockCanMakeRequest.remaining, mockCanMakeRequest.tierName, nil)
    }

    func recordRequest(for feature: RateLimitTracker.AIFeature) {
        recordRequestCallCount += 1
    }

    func reset() {
        recordRequestCallCount = 0
        mockCanMakeRequest = (true, 100, "Pro")
    }
}

@MainActor
final class MockFeatureFlags {
    private var enabledFeatures: Set<String> = ["aiTranslation"]

    func isFeatureEnabled(_ feature: FeatureFlags.Feature) -> Bool {
        switch feature {
        case .aiTranslation:
            return enabledFeatures.contains("aiTranslation")
        default:
            return true
        }
    }

    func setFeatureEnabled(_ feature: FeatureFlags.Feature, enabled: Bool) {
        let key = "aiTranslation"
        if enabled {
            enabledFeatures.insert(key)
        } else {
            enabledFeatures.remove(key)
        }
    }

    func reset() {
        enabledFeatures = ["aiTranslation"]
    }
}
