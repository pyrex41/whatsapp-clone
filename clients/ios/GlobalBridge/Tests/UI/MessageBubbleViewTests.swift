//
//  MessageBubbleViewTests.swift
//  GlobalBridgeTests
//
//  Unit tests for MessageBubbleView and MessageBubbleViewModel
//

import XCTest
@testable import GlobalBridge

@MainActor
final class MessageBubbleViewTests: XCTestCase {

    // MARK: - ViewModel Tests

    func testViewModelInitialization() {
        let message = createTestMessage()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: UnifiedTranslationService.shared
        )

        XCTAssertNil(viewModel.translation)
        XCTAssertFalse(viewModel.isTranslating)
        XCTAssertNil(viewModel.translationError)
        XCTAssertFalse(viewModel.hasTranslation)
    }

    func testTranslationToUserLanguage() async {
        let message = createTestMessage()
        let mockService = MockUnifiedTranslationService()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        await viewModel.translateToUserLanguage()

        XCTAssertNotNil(viewModel.translation)
        XCTAssertTrue(viewModel.hasTranslation)
        XCTAssertFalse(viewModel.isTranslating)
        XCTAssertNil(viewModel.translationError)
    }

    func testTranslationWithSpecificLanguage() async {
        let message = createTestMessage()
        let mockService = MockUnifiedTranslationService()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        await viewModel.translate(to: "es", from: "en")

        XCTAssertNotNil(viewModel.translation)
        XCTAssertEqual(viewModel.translation?.targetLanguage, "es")
        XCTAssertEqual(viewModel.translation?.sourceLanguage, "en")
    }

    func testTranslationError() async {
        let message = createTestMessage()
        let mockService = MockUnifiedTranslationService(shouldFail: true)
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        await viewModel.translateToUserLanguage()

        XCTAssertNil(viewModel.translation)
        XCTAssertNotNil(viewModel.translationError)
        XCTAssertFalse(viewModel.isTranslating)
    }

    func testRetryTranslation() async {
        let message = createTestMessage()
        let mockService = MockUnifiedTranslationService()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        // First attempt fails
        let failingService = MockUnifiedTranslationService(shouldFail: true)
        let failingViewModel = MessageBubbleViewModel(
            message: message,
            translationService: failingService
        )

        await failingViewModel.translateToUserLanguage()
        XCTAssertNil(failingViewModel.translation)

        // Retry should work with working service
        await viewModel.retryTranslation()
        XCTAssertNotNil(viewModel.translation)
    }

    func testClearTranslation() async {
        let message = createTestMessage()
        let mockService = MockUnifiedTranslationService()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        await viewModel.translateToUserLanguage()
        XCTAssertNotNil(viewModel.translation)

        viewModel.clearTranslation()
        XCTAssertNil(viewModel.translation)
        XCTAssertNil(viewModel.translationError)
    }

    func testNonTextMessageTranslation() async {
        let message = Message(
            threadId: UUID(),
            senderId: "user1",
            content: "image.jpg",
            messageType: .image
        )

        let mockService = MockUnifiedTranslationService()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        await viewModel.translateToUserLanguage()

        XCTAssertNil(viewModel.translation)
        XCTAssertNotNil(viewModel.translationError)
    }

    func testAvailableProviders() async {
        let message = createTestMessage()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: UnifiedTranslationService.shared
        )

        let providers = await viewModel.availableProviders()

        XCTAssertFalse(providers.isEmpty)
        XCTAssertTrue(providers.contains(.backend))
    }

    func testReportBadTranslation() async {
        let message = createTestMessage()
        let mockService = MockUnifiedTranslationService()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        await viewModel.translateToUserLanguage()
        XCTAssertNotNil(viewModel.translation)

        // Should not crash when reporting
        await viewModel.reportBadTranslation()
    }

    // MARK: - TranslationProvider Tests

    func testTranslationProviderDisplayNames() {
        XCTAssertEqual(TranslationProvider.apple.displayName, "On-Device (Private)")
        XCTAssertEqual(TranslationProvider.backend.displayName, "Cloud AI (More Languages)")
        XCTAssertEqual(TranslationProvider.auto.displayName, "Automatic")
    }

    func testTranslationProviderIcons() {
        XCTAssertEqual(TranslationProvider.apple.icon, "apple.logo")
        XCTAssertEqual(TranslationProvider.backend.icon, "cloud.fill")
        XCTAssertEqual(TranslationProvider.auto.icon, "arrow.triangle.2.circlepath")
    }

    func testTranslationProviderDescriptions() {
        XCTAssertFalse(TranslationProvider.apple.description.isEmpty)
        XCTAssertFalse(TranslationProvider.backend.description.isEmpty)
        XCTAssertFalse(TranslationProvider.auto.description.isEmpty)
    }

    // MARK: - Helper Methods

    private func createTestMessage() -> Message {
        Message(
            threadId: UUID(),
            senderId: "user1",
            content: "Hello, how are you?",
            messageType: .text,
            status: .sent
        )
    }
}

// MARK: - Mock Translation Service

@MainActor
private class MockUnifiedTranslationService: UnifiedTranslationService {
    let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    override func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        provider: TranslationProvider
    ) async throws -> TranslationResult {
        if shouldFail {
            throw AIServiceError.quotaExceeded(limit: 100, used: 100)
        }

        return TranslationResult(
            originalText: text,
            translatedText: "Translated: \(text)",
            sourceLanguage: sourceLanguage == "auto" ? "en" : sourceLanguage,
            targetLanguage: targetLanguage,
            confidence: 0.95,
            provider: provider.rawValue,
            culturalNotes: "Test cultural notes"
        )
    }

    override func supportsLanguagePair(from: String, to: String, provider: TranslationProvider) -> Bool {
        return true
    }
}

// MARK: - Performance Tests

extension MessageBubbleViewTests {
    func testTranslationPerformance() {
        let message = createTestMessage()
        let mockService = MockUnifiedTranslationService()
        let viewModel = MessageBubbleViewModel(
            message: message,
            translationService: mockService
        )

        measure {
            Task {
                await viewModel.translateToUserLanguage()
            }
        }
    }

    func testMultipleTranslationsPerformance() {
        let messages = (0..<10).map { _ in createTestMessage() }
        let mockService = MockUnifiedTranslationService()

        measure {
            Task {
                for message in messages {
                    let viewModel = MessageBubbleViewModel(
                        message: message,
                        translationService: mockService
                    )
                    await viewModel.translateToUserLanguage()
                }
            }
        }
    }
}
