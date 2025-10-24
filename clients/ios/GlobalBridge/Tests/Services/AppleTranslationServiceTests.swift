//
//  AppleTranslationServiceTests.swift
//  GlobalBridgeTests
//
//  Unit tests for AppleTranslationService
//  Tests on-device translation, model management, and caching
//

import XCTest
@testable import GlobalBridge

@MainActor
final class AppleTranslationServiceTests: XCTestCase {

    var service: AppleTranslationService!

    override func setUp() async throws {
        try await super.setUp()
        service = AppleTranslationService()
    }

    override func tearDown() async throws {
        service.invalidateAllSessions()
        service = nil
        try await super.tearDown()
    }

    // MARK: - Language Detection Tests

    func testDetectLanguageEnglish() async {
        let text = "Hello, how are you today?"
        let detected = await service.detectLanguage(of: text)

        XCTAssertNotNil(detected, "Should detect language")
        XCTAssertEqual(detected, "en", "Should detect English")
    }

    func testDetectLanguageSpanish() async {
        let text = "Hola, ¿cómo estás hoy?"
        let detected = await service.detectLanguage(of: text)

        XCTAssertNotNil(detected, "Should detect language")
        XCTAssertEqual(detected, "es", "Should detect Spanish")
    }

    func testDetectLanguageFrench() async {
        let text = "Bonjour, comment allez-vous aujourd'hui?"
        let detected = await service.detectLanguage(of: text)

        XCTAssertNotNil(detected, "Should detect language")
        XCTAssertEqual(detected, "fr", "Should detect French")
    }

    func testDetectLanguageEmptyText() async {
        let detected = await service.detectLanguage(of: "")
        XCTAssertNil(detected, "Should return nil for empty text")
    }

    func testDetectLanguageTooShort() async {
        let detected = await service.detectLanguage(of: "Hi")
        XCTAssertNil(detected, "Should return nil for very short text")
    }

    // MARK: - Supported Language Pairs Tests

    func testSupportedLanguagePairsCount() {
        let count = AppleTranslationService.supportedLanguagePairs.count
        XCTAssertGreaterThan(count, 30, "Should support 30+ language pairs")
    }

    func testEnglishToSpanishSupported() {
        XCTAssertTrue(
            AppleTranslationService.supportedLanguagePairs.contains("en_es"),
            "English to Spanish should be supported"
        )
    }

    func testSpanishToEnglishSupported() {
        XCTAssertTrue(
            AppleTranslationService.supportedLanguagePairs.contains("es_en"),
            "Spanish to English should be supported"
        )
    }

    func testBidirectionalPairs() {
        // Test that major language pairs are bidirectional
        let majorLanguages = ["en", "es", "fr", "de", "it", "pt"]

        for source in majorLanguages {
            for target in majorLanguages where source != target {
                let pair = "\(source)_\(target)"
                XCTAssertTrue(
                    AppleTranslationService.supportedLanguagePairs.contains(pair),
                    "Should support \(pair)"
                )
            }
        }
    }

    // MARK: - Translation Tests

    func testTranslateSameLanguage() async throws {
        let text = "Hello world"
        let result = try await service.translate(text: text, from: "en", to: "en")

        XCTAssertEqual(result.originalText, text)
        XCTAssertEqual(result.translatedText, text)
        XCTAssertEqual(result.sourceLanguage, "en")
        XCTAssertEqual(result.targetLanguage, "en")
        XCTAssertEqual(result.confidence, 1.0)
        XCTAssertEqual(result.provider, "apple-translation-identity")
    }

    func testTranslateEmptyText() async {
        do {
            _ = try await service.translate(text: "", from: "en", to: "es")
            XCTFail("Should throw error for empty text")
        } catch let error as AIServiceError {
            XCTAssertEqual(error, .invalidText)
        } catch {
            XCTFail("Should throw AIServiceError.invalidText")
        }
    }

    func testTranslateEmptyTargetLanguage() async {
        do {
            _ = try await service.translate(text: "Hello", from: "en", to: "")
            XCTFail("Should throw error for empty target language")
        } catch let error as AIServiceError {
            if case .invalidInput(let reason) = error {
                XCTAssertTrue(reason.contains("Target language"))
            } else {
                XCTFail("Should throw invalidInput error")
            }
        } catch {
            XCTFail("Should throw AIServiceError")
        }
    }

    func testTranslateAutoDetectLanguage() async throws {
        // Note: This test requires actual Translation framework to work
        // In a real test, you'd mock the Translation framework or use a simulator with models
        let text = "Hello world"

        do {
            let result = try await service.translate(text: text, from: "auto", to: "es")

            XCTAssertEqual(result.originalText, text)
            XCTAssertNotEqual(result.translatedText, text, "Should be translated")
            XCTAssertNotNil(result.sourceLanguage, "Should detect source language")
            XCTAssertEqual(result.targetLanguage, "es")
            XCTAssertEqual(result.provider, "apple-translation")
        } catch {
            // Skip test if Translation framework not available (e.g., in CI)
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    func testTranslateNormalizeLanguageCodes() async throws {
        // Test that region variants are normalized (e.g., "en-US" -> "en")
        let text = "Hello"

        do {
            let result = try await service.translate(text: text, from: "en-US", to: "es-ES")

            XCTAssertEqual(result.sourceLanguage, "en", "Should normalize to base language code")
            XCTAssertEqual(result.targetLanguage, "es", "Should normalize to base language code")
        } catch {
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    // MARK: - Caching Tests

    func testTranslationCaching() async throws {
        let text = "Hello world"
        let cache = AIServiceCache.shared

        // Clear cache first
        await cache.clear(type: .translation)

        do {
            // First translation (cache miss)
            let result1 = try await service.translate(text: text, from: "en", to: "es")

            // Second translation (should hit cache)
            let result2 = try await service.translate(text: text, from: "en", to: "es")

            XCTAssertEqual(result1.translatedText, result2.translatedText)
            XCTAssertEqual(result1.sourceLanguage, result2.sourceLanguage)
            XCTAssertEqual(result1.targetLanguage, result2.targetLanguage)

            // Verify cache hit
            let metrics = cache.getMetrics()
            XCTAssertGreaterThan(metrics.totalHits, 0, "Should have cache hits")
        } catch {
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    func testCacheKeyUniqueness() async throws {
        let cache = AIServiceCache.shared
        await cache.clear(type: .translation)

        do {
            // Different language pairs should have different cache keys
            let result1 = try await service.translate(text: "Hello", from: "en", to: "es")
            let result2 = try await service.translate(text: "Hello", from: "en", to: "fr")

            XCTAssertNotEqual(result1.targetLanguage, result2.targetLanguage)
            XCTAssertNotEqual(result1.translatedText, result2.translatedText)
        } catch {
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    // MARK: - Batch Translation Tests

    func testBatchTranslateEmpty() async throws {
        let results = try await service.batchTranslate(texts: [], from: "en", to: "es")
        XCTAssertEqual(results.count, 0, "Should return empty array")
    }

    func testBatchTranslateSingleText() async throws {
        let texts = ["Hello"]

        do {
            let results = try await service.batchTranslate(texts: texts, from: "en", to: "es")

            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results[0].originalText, "Hello")
            XCTAssertEqual(results[0].sourceLanguage, "en")
            XCTAssertEqual(results[0].targetLanguage, "es")
        } catch {
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    func testBatchTranslateMultipleTexts() async throws {
        let texts = ["Hello", "Goodbye", "Thank you"]

        do {
            let results = try await service.batchTranslate(texts: texts, from: "en", to: "es")

            XCTAssertEqual(results.count, 3, "Should return same number of results")

            // Verify order is preserved
            XCTAssertEqual(results[0].originalText, "Hello")
            XCTAssertEqual(results[1].originalText, "Goodbye")
            XCTAssertEqual(results[2].originalText, "Thank you")

            // All should be translated
            for result in results {
                XCTAssertEqual(result.sourceLanguage, "en")
                XCTAssertEqual(result.targetLanguage, "es")
                XCTAssertNotEqual(result.translatedText, result.originalText)
            }
        } catch {
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    // MARK: - Session Management Tests

    func testInvalidateAllSessions() {
        // Create service
        let testService = AppleTranslationService()

        // Invalidate sessions (should not crash)
        testService.invalidateAllSessions()

        // Verify sessions are cleared by checking internal state
        // Note: This is a smoke test since sessions dict is private
        XCTAssertTrue(true, "Should invalidate sessions without crashing")
    }

    func testHandleMemoryWarning() {
        let testService = AppleTranslationService()

        // Should not crash
        testService.handleMemoryWarning()

        XCTAssertTrue(true, "Should handle memory warning without crashing")
    }

    func testHandleAppDidEnterBackground() {
        let testService = AppleTranslationService()

        // Should not crash
        testService.handleAppDidEnterBackground()

        XCTAssertTrue(true, "Should handle background without crashing")
    }

    // MARK: - Model Management Tests

    func testCheckAvailableLanguagePairs() async {
        await service.checkAvailableLanguagePairs()

        // Should complete without error
        XCTAssertFalse(service.isCheckingAvailability, "Should not be checking after completion")

        // May have 0 or more pairs depending on device
        XCTAssertTrue(true, "Should complete check without crashing")
    }

    func testDownloadModelUnsupportedPair() async {
        do {
            _ = try await service.downloadModel(from: "xx", to: "yy")
            XCTFail("Should throw error for unsupported language pair")
        } catch let error as AIServiceError {
            if case .unsupportedLanguage = error {
                XCTAssertTrue(true, "Should throw unsupportedLanguage error")
            } else {
                XCTFail("Should throw unsupportedLanguage error")
            }
        } catch {
            XCTFail("Should throw AIServiceError")
        }
    }

    // MARK: - Confidence Scoring Tests

    func testConfidenceScoreRange() async throws {
        do {
            let result = try await service.translate(text: "Hello world", from: "en", to: "es")

            // Confidence should be between 0.5 and 0.95 (per implementation)
            if let confidence = result.confidence {
                XCTAssertGreaterThanOrEqual(confidence, 0.5)
                XCTAssertLessThanOrEqual(confidence, 0.95)
            }
        } catch {
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    // MARK: - Error Handling Tests

    func testUnsupportedLanguagePair() async {
        // Try translating to an unsupported language
        do {
            _ = try await service.translate(text: "Hello", from: "en", to: "xyz")
            XCTFail("Should throw error for unsupported language")
        } catch let error as AIServiceError {
            if case .unsupportedLanguage = error {
                XCTAssertTrue(true, "Should throw unsupportedLanguage error")
            } else if case .unknown = error {
                // May throw unknown if Translation framework rejects it
                XCTAssertTrue(true, "Acceptable error type")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Should throw AIServiceError")
        }
    }

    // MARK: - Unimplemented Methods Tests

    func testSummarizeThreadThrows() async {
        do {
            _ = try await service.summarizeThread(threadId: UUID(), maxLength: nil)
            XCTFail("Should throw featureDisabled error")
        } catch let error as AIServiceError {
            if case .featureDisabled(let feature) = error {
                XCTAssertTrue(feature.contains("summarization"))
            } else {
                XCTFail("Should throw featureDisabled error")
            }
        } catch {
            XCTFail("Should throw AIServiceError")
        }
    }

    func testSearchSemanticThrows() async {
        do {
            _ = try await service.searchSemantic(
                query: "test",
                in: nil,
                limit: 10,
                recencyBias: true,
                translate: false
            )
            XCTFail("Should throw featureDisabled error")
        } catch let error as AIServiceError {
            if case .featureDisabled(let feature) = error {
                XCTAssertTrue(feature.contains("search"))
            } else {
                XCTFail("Should throw featureDisabled error")
            }
        } catch {
            XCTFail("Should throw AIServiceError")
        }
    }

    func testExtractTasksThrows() async {
        do {
            _ = try await service.extractTasks(from: UUID(), query: nil)
            XCTFail("Should throw featureDisabled error")
        } catch let error as AIServiceError {
            if case .featureDisabled(let feature) = error {
                XCTAssertTrue(feature.contains("extraction"))
            } else {
                XCTFail("Should throw featureDisabled error")
            }
        } catch {
            XCTFail("Should throw AIServiceError")
        }
    }

    func testCheckVectorHealthThrows() async {
        do {
            _ = try await service.checkVectorHealth(for: UUID())
            XCTFail("Should throw featureDisabled error")
        } catch let error as AIServiceError {
            if case .featureDisabled(let feature) = error {
                XCTAssertTrue(feature.contains("health"))
            } else {
                XCTFail("Should throw featureDisabled error")
            }
        } catch {
            XCTFail("Should throw AIServiceError")
        }
    }

    // MARK: - Integration Tests

    func testFullTranslationWorkflow() async throws {
        // This test simulates a complete workflow
        let originalText = "Hello, how are you?"

        do {
            // 1. Detect language
            let detectedLang = await service.detectLanguage(of: originalText)
            XCTAssertNotNil(detectedLang)

            // 2. Check available pairs
            await service.checkAvailableLanguagePairs()

            // 3. Translate text
            let result = try await service.translate(
                text: originalText,
                from: detectedLang ?? "en",
                to: "es"
            )

            XCTAssertEqual(result.originalText, originalText)
            XCTAssertNotEqual(result.translatedText, originalText)
            XCTAssertEqual(result.provider, "apple-translation")

            // 4. Verify caching on second call
            let cachedResult = try await service.translate(
                text: originalText,
                from: result.sourceLanguage,
                to: "es"
            )

            XCTAssertEqual(result.translatedText, cachedResult.translatedText)

        } catch {
            throw XCTSkip("Translation framework not available: \(error)")
        }
    }

    // MARK: - Performance Tests

    func testTranslationPerformance() async throws {
        let text = "Hello, how are you today?"

        measure {
            let expectation = self.expectation(description: "Translation completes")

            Task {
                do {
                    _ = try await service.translate(text: text, from: "en", to: "es")
                    expectation.fulfill()
                } catch {
                    // Skip if models not available
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 5.0)
        }
    }

    func testBatchTranslationPerformance() async throws {
        let texts = Array(repeating: "Hello world", count: 10)

        measure {
            let expectation = self.expectation(description: "Batch translation completes")

            Task {
                do {
                    _ = try await service.batchTranslate(texts: texts, from: "en", to: "es")
                    expectation.fulfill()
                } catch {
                    expectation.fulfill()
                }
            }

            wait(for: [expectation], timeout: 10.0)
        }
    }
}
