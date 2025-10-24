//
//  TranslationComparisonViewTests.swift
//  GlobalBridgeTests
//
//  Comprehensive unit tests for TranslationComparisonView
//

import XCTest
import SwiftUI
@testable import GlobalBridge

@MainActor
final class TranslationComparisonViewTests: XCTestCase {

    // MARK: - Translation Comparison Tests

    func testTranslationComparisonInitialization() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            alternateTranslation: "Hola",
            alternateProvider: "apple"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.originalText, "Hello")
        XCTAssertEqual(comparison.primaryTranslation, "Hola")
        XCTAssertEqual(comparison.primaryProvider, "backend")
        XCTAssertEqual(comparison.alternateTranslation, "Hola")
        XCTAssertEqual(comparison.alternateProvider, "apple")
        XCTAssertTrue(comparison.hasComparison)
    }

    func testTranslationComparisonWithoutAlternate() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "apple",
            alternateTranslation: nil,
            alternateProvider: nil
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertFalse(comparison.hasComparison)
        XCTAssertNil(comparison.alternateTranslation)
        XCTAssertNil(comparison.alternateProvider)
    }

    func testIdenticalTranslations() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Gracias",
            provider: "backend",
            alternateTranslation: "gracias",  // Same but different case
            alternateProvider: "apple"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertTrue(comparison.isIdentical)
    }

    func testDifferentTranslations() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola, ¿cómo estás?",
            provider: "backend",
            alternateTranslation: "Hola, ¿qué tal?",
            alternateProvider: "apple"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertFalse(comparison.isIdentical)
    }

    func testTranslationComparisonWithCulturalNotes() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Buenos días",
            provider: "backend",
            culturalNotes: "Common morning greeting",
            alternateTranslation: "Buen día",
            alternateProvider: "apple"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.primaryCulturalNotes, "Common morning greeting")
    }

    // MARK: - Translation Preference Tests

    func testTranslationPreferenceEnum() {
        // Test all preference cases
        XCTAssertEqual(TranslationPreference.primary.rawValue, "primary")
        XCTAssertEqual(TranslationPreference.alternate.rawValue, "alternate")
        XCTAssertEqual(TranslationPreference.both.rawValue, "both")
        XCTAssertEqual(TranslationPreference.neither.rawValue, "neither")
    }

    func testTranslationPreferenceCodable() throws {
        // Given
        let preference = TranslationPreference.primary

        // When
        let encoded = try JSONEncoder().encode(preference)
        let decoded = try JSONDecoder().decode(TranslationPreference.self, from: encoded)

        // Then
        XCTAssertEqual(preference, decoded)
    }

    // MARK: - View State Tests

    func testViewInitialization() {
        // Given
        let comparison = createMockComparison()
        var voteCalled = false
        var feedbackCalled = false

        // When
        let view = TranslationComparisonView(
            comparison: comparison,
            onVote: { _ in voteCalled = true },
            onFeedback: { _ in feedbackCalled = true }
        )

        // Then
        XCTAssertNotNil(view)
        XCTAssertFalse(voteCalled)
        XCTAssertFalse(feedbackCalled)
    }

    func testViewWithoutCallbacks() {
        // Given
        let comparison = createMockComparison()

        // When
        let view = TranslationComparisonView(comparison: comparison)

        // Then
        XCTAssertNotNil(view)
    }

    // MARK: - Confidence Level Tests

    func testHighConfidence() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            confidence: 0.95
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertGreaterThanOrEqual(comparison.primaryConfidence, 0.9)
    }

    func testMediumConfidence() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            confidence: 0.75
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertGreaterThanOrEqual(comparison.primaryConfidence, 0.7)
        XCTAssertLessThan(comparison.primaryConfidence, 0.9)
    }

    func testLowConfidence() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            confidence: 0.55
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertLessThan(comparison.primaryConfidence, 0.7)
    }

    // MARK: - Performance Metrics Tests

    func testLatencyTracking() {
        // Given
        let latencyMs = 245

        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            latencyMs: latencyMs
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.latencyMs, latencyMs)
    }

    func testFastTranslation() {
        // Given (under 100ms is excellent)
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "apple",
            latencyMs: 85
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertLessThan(comparison.latencyMs, 100)
    }

    func testSlowTranslation() {
        // Given (over 500ms is slow)
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            latencyMs: 650
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertGreaterThan(comparison.latencyMs, 500)
    }

    // MARK: - Language Pair Tests

    func testEnglishToSpanish() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            sourceLanguage: "en",
            targetLanguage: "es"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.sourceLanguage, "en")
        XCTAssertEqual(comparison.targetLanguage, "es")
    }

    func testSpanishToEnglish() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hello",
            provider: "backend",
            sourceLanguage: "es",
            targetLanguage: "en"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.sourceLanguage, "es")
        XCTAssertEqual(comparison.targetLanguage, "en")
    }

    func testFrenchToGerman() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Guten Tag",
            provider: "backend",
            sourceLanguage: "fr",
            targetLanguage: "de"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.sourceLanguage, "fr")
        XCTAssertEqual(comparison.targetLanguage, "de")
    }

    // MARK: - Provider Tests

    func testAppleProvider() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "apple"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.primaryProvider, "apple")
    }

    func testBackendProvider() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.primaryProvider, "backend")
    }

    func testHybridMode() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola, ¿cómo estás?",
            provider: "backend",
            alternateTranslation: "Hola, ¿cómo está usted?",
            alternateProvider: "apple"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertTrue(comparison.hasComparison)
        XCTAssertEqual(comparison.primaryProvider, "backend")
        XCTAssertEqual(comparison.alternateProvider, "apple")
    }

    // MARK: - Edge Case Tests

    func testEmptyTranslation() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "",
            provider: "backend"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertTrue(comparison.primaryTranslation.isEmpty)
    }

    func testVeryLongTranslation() {
        // Given
        let longText = String(repeating: "Hola mundo. ", count: 100)
        let result = createMockUnifiedResult(
            translatedText: longText,
            provider: "backend"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertGreaterThan(comparison.primaryTranslation.count, 1000)
    }

    func testSpecialCharacters() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "¡Hola! ¿Cómo estás? 😊",
            provider: "backend"
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertTrue(comparison.primaryTranslation.contains("¡"))
        XCTAssertTrue(comparison.primaryTranslation.contains("¿"))
        XCTAssertTrue(comparison.primaryTranslation.contains("😊"))
    }

    func testZeroConfidence() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            confidence: 0.0
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.primaryConfidence, 0.0)
    }

    func testPerfectConfidence() {
        // Given
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            confidence: 1.0
        )

        // When
        let comparison = TranslationComparison(from: result)

        // Then
        XCTAssertEqual(comparison.primaryConfidence, 1.0)
    }

    // MARK: - Equatable Tests

    func testEquatable() {
        // Given
        let result1 = createMockUnifiedResult(translatedText: "Hola", provider: "backend")
        let result2 = createMockUnifiedResult(translatedText: "Hola", provider: "backend")

        // When
        let comparison1 = TranslationComparison(from: result1)
        let comparison2 = TranslationComparison(from: result2)

        // Then
        // Note: They won't be equal due to different UUIDs and timestamps
        // but they should have equal content
        XCTAssertEqual(comparison1.primaryTranslation, comparison2.primaryTranslation)
        XCTAssertEqual(comparison1.primaryProvider, comparison2.primaryProvider)
    }

    // MARK: - Helper Methods

    private func createMockUnifiedResult(
        translatedText: String,
        provider: String,
        confidence: Double = 0.9,
        culturalNotes: String? = nil,
        alternateTranslation: String? = nil,
        alternateProvider: String? = nil,
        alternateConfidence: Double? = nil,
        latencyMs: Int = 200,
        sourceLanguage: String = "en",
        targetLanguage: String = "es"
    ) -> UnifiedTranslationResult {
        return UnifiedTranslationResult(
            originalText: "Hello",
            translatedText: translatedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            confidence: confidence,
            provider: provider,
            culturalNotes: culturalNotes,
            timestamp: Date(),
            alternateTranslation: alternateTranslation,
            alternateProvider: alternateProvider,
            alternateConfidence: alternateConfidence,
            latencyMs: latencyMs,
            cacheHit: false,
            fallbackUsed: false
        )
    }

    private func createMockComparison() -> TranslationComparison {
        let result = createMockUnifiedResult(
            translatedText: "Hola",
            provider: "backend",
            alternateTranslation: "Hola",
            alternateProvider: "apple"
        )
        return TranslationComparison(from: result)
    }
}
