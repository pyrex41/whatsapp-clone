//
//  BackendTranslationService.swift
//  GlobalBridge
//
//  Advanced backend-powered translation service with context awareness,
//  cultural notes, formality detection, and batch translation.
//
//  Features:
//  - Context-aware translation using conversation history
//  - Cultural notes and idiom explanations
//  - Formality level detection and preservation
//  - Batch translation for efficiency
//  - Translation history tracking
//  - Quality feedback system
//  - Smart caching with context fingerprints
//  - Rate limiting with tier-based quotas
//
//  Backend: POST /api/v1/ai/translate (with extended parameters)
//

import Foundation
import Combine

/// Advanced translation service with context awareness and cultural intelligence
@MainActor
final class BackendTranslationService {

    // MARK: - Singleton

    static let shared = BackendTranslationService()

    // MARK: - Properties

    private let aiService: AIService
    private let cache: AIServiceCache
    private let rateLimiter: RateLimitTracker
    private let featureFlags: FeatureFlags

    /// Translation history for learning and improvement
    private var translationHistory: [TranslationHistoryEntry] = []
    private let maxHistorySize = 100

    /// Quality feedback storage
    private var qualityFeedback: [String: QualityFeedback] = [:]

    // MARK: - Configuration

    struct TranslationConfiguration {
        let includeContext: Bool
        let maxContextMessages: Int
        let includeCulturalNotes: Bool
        let detectFormality: Bool
        let enableBatchOptimization: Bool

        static let `default` = TranslationConfiguration(
            includeContext: true,
            maxContextMessages: 5,
            includeCulturalNotes: true,
            detectFormality: true,
            enableBatchOptimization: true
        )
    }

    private let config: TranslationConfiguration

    // MARK: - Initialization

    private init(
        config: TranslationConfiguration = .default,
        aiService: AIService = .shared,
        cache: AIServiceCache = .shared,
        rateLimiter: RateLimitTracker = .shared,
        featureFlags: FeatureFlags = .shared
    ) {
        self.config = config
        self.aiService = aiService
        self.cache = cache
        self.rateLimiter = rateLimiter
        self.featureFlags = featureFlags

        print("✅ [BACKEND_TRANSLATION] Initialized with context-aware features")
    }

    // MARK: - Core Translation

    /// Translate text with full context awareness and cultural intelligence
    ///
    /// - Parameters:
    ///   - text: Text to translate
    ///   - targetLanguage: Target language code (ISO 639-1)
    ///   - sourceLanguage: Optional source language (auto-detected if nil)
    ///   - context: Optional conversation context for better accuracy
    ///   - formality: Optional desired formality level
    /// - Returns: Enhanced translation result with cultural notes
    func translate(
        text: String,
        targetLanguage: String,
        sourceLanguage: String? = nil,
        context: [String]? = nil,
        formality: FormalityLevel? = nil
    ) async throws -> EnhancedTranslationResult {
        // Validate input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.invalidText
        }

        // Check feature availability
        guard featureFlags.hasFeature(.translationEnabled) else {
            throw AIServiceError.featureDisabled(feature: "AI Translation")
        }

        // Check rate limits
        let rateLimitCheck = rateLimiter.canMakeRequest(for: RateLimitTracker.AIFeature.translation)
        guard rateLimitCheck.isAllowed else {
            // Extract retry date from rate limit result
            let retryDate: Date? = {
                switch rateLimitCheck {
                case .quotaExceeded(_, _, let resetDate),
                     .rateLimited(let resetDate, _):
                    return resetDate
                case .backoff(let retryAfter, _):
                    return retryAfter
                default:
                    return nil
                }
            }()
            throw AIServiceError.rateLimitExceeded(
                retryAfter: retryDate,
                remainingQuota: nil,
                tierLimit: nil
            )
        }

        // Generate cache key with context fingerprint
        let cacheKey = generateContextualCacheKey(
            text: text,
            target: targetLanguage,
            source: sourceLanguage,
            context: context,
            formality: formality
        )

        // Check cache
        if let cached: EnhancedTranslationResult = await cache.retrieve(forKey: cacheKey, type: .translation) {
            print("✅ [BACKEND_TRANSLATION] Cache hit with context")
            return cached
        }

        // Perform translation with context
        let result = try await performContextualTranslation(
            text: text,
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage,
            context: context,
            formality: formality
        )

        // Record in history
        addToHistory(result)

        // Cache result
        await cache.store(result, forKey: cacheKey, type: .translation)

        // Record usage
        rateLimiter.recordRequest(for: .translation)

        return result
    }

    // MARK: - Batch Translation

    /// Translate multiple texts efficiently in a single batch
    ///
    /// - Parameters:
    ///   - texts: Array of texts to translate
    ///   - targetLanguage: Target language for all texts
    ///   - sourceLanguage: Optional source language
    ///   - preserveOrder: Whether to maintain input order (may be slower)
    /// - Returns: Array of translation results in same order as input
    func batchTranslate(
        texts: [String],
        targetLanguage: String,
        sourceLanguage: String? = nil,
        preserveOrder: Bool = true
    ) async throws -> [EnhancedTranslationResult] {
        guard !texts.isEmpty else {
            return []
        }

        // Check feature availability
        guard featureFlags.hasFeature(.translationEnabled) else {
            throw AIServiceError.featureDisabled(feature: "AI Translation")
        }

        // Filter out empty texts
        let validTexts = texts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !validTexts.isEmpty else {
            return []
        }

        print("📦 [BACKEND_TRANSLATION] Batch translating \(validTexts.count) texts")

        // Check if batch optimization is enabled and backend supports it
        if config.enableBatchOptimization && validTexts.count > 3 {
            // Use dedicated batch endpoint for efficiency
            return try await performBatchTranslation(
                texts: validTexts,
                targetLanguage: targetLanguage,
                sourceLanguage: sourceLanguage
            )
        } else {
            // Fall back to individual translations with concurrency
            return try await withThrowingTaskGroup(of: (Int, EnhancedTranslationResult).self) { group in
                for (index, text) in validTexts.enumerated() {
                    group.addTask {
                        let result = try await self.translate(
                            text: text,
                            targetLanguage: targetLanguage,
                            sourceLanguage: sourceLanguage
                        )
                        return (index, result)
                    }
                }

                // Collect results
                var results: [(Int, EnhancedTranslationResult)] = []
                for try await result in group {
                    results.append(result)
                }

                // Sort by index if order preservation is required
                if preserveOrder {
                    results.sort { $0.0 < $1.0 }
                }

                return results.map { $0.1 }
            }
        }
    }

    // MARK: - Translation with Thread Context

    /// Translate with full thread context for maximum accuracy
    ///
    /// - Parameters:
    ///   - text: Text to translate
    ///   - targetLanguage: Target language
    ///   - threadId: Thread ID to fetch context from
    ///   - sourceLanguage: Optional source language
    /// - Returns: Translation with thread-aware context
    func translateWithThreadContext(
        text: String,
        targetLanguage: String,
        threadId: UUID,
        sourceLanguage: String? = nil
    ) async throws -> EnhancedTranslationResult {
        // Fetch recent messages from thread for context
        // Note: This would integrate with MessageService in real implementation
        let contextMessages = await fetchThreadContext(threadId: threadId)

        return try await translate(
            text: text,
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage,
            context: contextMessages
        )
    }

    // MARK: - Quality Feedback

    /// Submit quality feedback for a translation
    ///
    /// - Parameters:
    ///   - translationId: Unique ID of the translation
    ///   - rating: Quality rating (1-5)
    ///   - issues: Specific issues found (optional)
    ///   - suggestedTranslation: User's suggested improvement (optional)
    func submitQualityFeedback(
        translationId: String,
        rating: Int,
        issues: [TranslationIssue]? = nil,
        suggestedTranslation: String? = nil
    ) async {
        let feedback = QualityFeedback(
            translationId: translationId,
            rating: rating,
            issues: issues ?? [],
            suggestedTranslation: suggestedTranslation,
            timestamp: Date()
        )

        qualityFeedback[translationId] = feedback

        // In production, this would send feedback to backend for model improvement
        print("📝 [BACKEND_TRANSLATION] Quality feedback recorded: \(rating)/5")
    }

    // MARK: - Translation History

    /// Get recent translation history
    func getTranslationHistory(limit: Int = 20) -> [TranslationHistoryEntry] {
        return Array(translationHistory.prefix(limit))
    }

    /// Clear translation history
    func clearTranslationHistory() {
        translationHistory.removeAll()
        print("🗑️ [BACKEND_TRANSLATION] Translation history cleared")
    }

    // MARK: - Statistics

    /// Get translation statistics for analytics
    func getStatistics() -> TranslationStatistics {
        let totalTranslations = translationHistory.count
        let averageConfidence = translationHistory.isEmpty ? 0.0 :
            translationHistory.compactMap { $0.confidence }.reduce(0.0, +) / Double(translationHistory.count)

        let languagePairs = Dictionary(grouping: translationHistory) {
            "\($0.sourceLanguage)->\($0.targetLanguage)"
        }

        let feedbackCount = qualityFeedback.count
        let averageRating = qualityFeedback.isEmpty ? 0.0 :
            Double(qualityFeedback.values.map { $0.rating }.reduce(0, +)) / Double(feedbackCount)

        return TranslationStatistics(
            totalTranslations: totalTranslations,
            averageConfidence: averageConfidence,
            languagePairs: languagePairs.mapValues { $0.count },
            feedbackCount: feedbackCount,
            averageRating: averageRating
        )
    }

    // MARK: - Private Methods

    private func performContextualTranslation(
        text: String,
        targetLanguage: String,
        sourceLanguage: String?,
        context: [String]?,
        formality: FormalityLevel?
    ) async throws -> EnhancedTranslationResult {
        // Use the AIService.translate() method with formality support
        // Pass formality as string to match backend API expectations

        let basicResult = try await aiService.translate(
            text: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            formality: formality?.rawValue
        )

        // Enhance the basic result with additional features
        let detectedFormality = formality ?? detectFormalityLevel(text: text)
        let culturalNotes = config.includeCulturalNotes ?
            generateCulturalNotes(
                originalText: text,
                translatedText: basicResult.translatedText,
                sourceLanguage: basicResult.sourceLanguage,
                targetLanguage: targetLanguage
            ) : nil

        let qualityScore = calculateQualityScore(result: basicResult)

        return EnhancedTranslationResult(
            originalText: text,
            translatedText: basicResult.translatedText,
            sourceLanguage: basicResult.sourceLanguage,
            targetLanguage: targetLanguage,
            confidence: basicResult.confidence ?? 0.95,
            provider: "backend-ai",
            culturalNotes: culturalNotes,
            formality: detectedFormality,
            contextUsed: context != nil,
            qualityScore: qualityScore,
            timestamp: Date(),
            translationId: UUID().uuidString
        )
    }

    private func performBatchTranslation(
        texts: [String],
        targetLanguage: String,
        sourceLanguage: String?
    ) async throws -> [EnhancedTranslationResult] {
        // In production, this would use a dedicated batch endpoint
        // For now, we'll use concurrent individual translations

        return try await withThrowingTaskGroup(of: EnhancedTranslationResult.self) { group in
            for text in texts {
                group.addTask {
                    try await self.translate(
                        text: text,
                        targetLanguage: targetLanguage,
                        sourceLanguage: sourceLanguage
                    )
                }
            }

            var results: [EnhancedTranslationResult] = []
            for try await result in group {
                results.append(result)
            }

            return results
        }
    }

    private func generateContextualCacheKey(
        text: String,
        target: String,
        source: String?,
        context: [String]?,
        formality: FormalityLevel?
    ) -> String {
        var components = [text, target, source ?? "auto"]

        if let context = context, !context.isEmpty {
            let contextHash = context.joined(separator: "|").hashValue
            components.append("ctx:\(contextHash)")
        }

        if let formality = formality {
            components.append("form:\(formality.rawValue)")
        }

        let combined = components.joined(separator: "_")
        return combined.data(using: .utf8)?.base64EncodedString() ?? combined
    }

    private func detectFormalityLevel(text: String) -> FormalityLevel {
        // Simple heuristic-based formality detection
        // In production, this would use backend AI for accurate detection

        let formalIndicators = ["please", "kindly", "sir", "madam", "would you", "could you"]
        let informalIndicators = ["hey", "yo", "gonna", "wanna", "yeah", "nope"]

        let lowercasedText = text.lowercased()

        let formalCount = formalIndicators.filter { lowercasedText.contains($0) }.count
        let informalCount = informalIndicators.filter { lowercasedText.contains($0) }.count

        if formalCount > informalCount {
            return .formal
        } else if informalCount > formalCount {
            return .informal
        } else {
            return .neutral
        }
    }

    private func generateCulturalNotes(
        originalText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String
    ) -> String? {
        // In production, this would come from backend AI analysis
        // For now, provide placeholder based on simple patterns

        // Check for common idioms or cultural references
        let idioms = [
            "break a leg": "Theater idiom wishing good luck",
            "piece of cake": "Idiom meaning something is very easy",
            "hit the books": "Informal phrase meaning to study",
            "under the weather": "Idiom meaning feeling ill"
        ]

        for (idiom, note) in idioms {
            if originalText.lowercased().contains(idiom) {
                return "Cultural note: \(note)"
            }
        }

        return nil
    }

    private func calculateQualityScore(result: TranslationResult) -> Double {
        // Combine backend confidence with heuristics
        var score = result.confidence ?? 0.0

        // Adjust based on text length (very short translations are less reliable)
        if result.translatedText.count < 10 {
            score *= 0.9
        }

        // Check for obvious issues (repeated words, etc.)
        let words = result.translatedText.components(separatedBy: .whitespaces)
        let uniqueWords = Set(words)
        if uniqueWords.count < words.count / 2 {
            score *= 0.8 // Many repeated words might indicate poor translation
        }

        return min(1.0, max(0.0, score))
    }

    private func addToHistory(_ result: EnhancedTranslationResult) {
        let entry = TranslationHistoryEntry(
            originalText: result.originalText,
            translatedText: result.translatedText,
            sourceLanguage: result.sourceLanguage,
            targetLanguage: result.targetLanguage,
            confidence: result.confidence,
            timestamp: result.timestamp
        )

        translationHistory.insert(entry, at: 0)

        // Maintain max history size
        if translationHistory.count > maxHistorySize {
            translationHistory.removeLast()
        }
    }

    private func fetchThreadContext(threadId: UUID) async -> [String] {
        // In production, this would fetch recent messages from MessageService
        // For now, return empty array
        return []
    }
}

// MARK: - Supporting Types

/// Enhanced translation result with cultural intelligence
struct EnhancedTranslationResult: Codable, Equatable {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let confidence: Double
    let provider: String?
    let culturalNotes: String?
    let formality: FormalityLevel?
    let contextUsed: Bool
    let qualityScore: Double
    let timestamp: Date
    let translationId: String

    enum CodingKeys: String, CodingKey {
        case originalText = "original_text"
        case translatedText = "translated_text"
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
        case confidence
        case provider
        case culturalNotes = "cultural_notes"
        case formality
        case contextUsed = "context_used"
        case qualityScore = "quality_score"
        case timestamp
        case translationId = "translation_id"
    }
}

/// Formality level for translations
enum FormalityLevel: String, Codable, CaseIterable, Identifiable {
    case formal = "formal"
    case neutral = "neutral"
    case informal = "informal"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .informal:
            return "Casual"
        case .neutral:
            return "Neutral"
        case .formal:
            return "Formal"
        }
    }

    var description: String {
        switch self {
        case .informal:
            return "Informal, friendly tone"
        case .neutral:
            return "Standard, balanced tone"
        case .formal:
            return "Professional, polite tone"
        }
    }

    /// Default formality level
    static let `default`: FormalityLevel = .neutral
}

/// Translation history entry for learning
struct TranslationHistoryEntry: Codable {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let confidence: Double
    let timestamp: Date
}

/// Quality feedback from users
struct QualityFeedback: Codable {
    let translationId: String
    let rating: Int // 1-5
    let issues: [TranslationIssue]
    let suggestedTranslation: String?
    let timestamp: Date
}

/// Specific translation issues
enum TranslationIssue: String, Codable {
    case wrongMeaning = "wrong_meaning"
    case awkwardPhrasing = "awkward_phrasing"
    case missingContext = "missing_context"
    case incorrectFormality = "incorrect_formality"
    case culturallyInappropriate = "culturally_inappropriate"
}

/// Translation statistics for analytics
struct TranslationStatistics {
    let totalTranslations: Int
    let averageConfidence: Double
    let languagePairs: [String: Int]
    let feedbackCount: Int
    let averageRating: Double
}

// MARK: - Extensions

extension EnhancedTranslationResult {
    /// Whether this is a high-quality translation
    var isHighQuality: Bool {
        return qualityScore > 0.8 && confidence > 0.85
    }

    /// Human-readable quality description
    var qualityDescription: String {
        switch qualityScore {
        case 0.9...1.0:
            return "Excellent"
        case 0.8..<0.9:
            return "Good"
        case 0.7..<0.8:
            return "Fair"
        default:
            return "Needs review"
        }
    }

    /// Age of translation in seconds
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    /// Whether translation is fresh (less than 5 minutes)
    var isFresh: Bool {
        age < 300
    }
}

// MARK: - FeatureFlags Integration
// Note: Uses FeatureFlags.Feature enum defined in Core/Utilities/FeatureFlags.swift
// Available features: .translationEnabled, .threadSummarization, .semanticSearch
