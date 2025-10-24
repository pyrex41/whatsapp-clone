//
//  UnifiedTranslationService.swift
//  GlobalBridge
//
//  Unified translation orchestration layer that intelligently selects between
//  Apple Translation (on-device, privacy-first) and Backend Translation (cloud-based, advanced).
//
//  Features:
//  - Intelligent provider selection based on network, language support, and quotas
//  - Hybrid mode for quality comparison
//  - Automatic fallback on provider failures
//  - Feature flag integration for tier-based access
//  - Comprehensive metrics logging
//  - Offline-first strategy with Apple Translation
//  - Rate limiting awareness
//
//  This is the PRIMARY translation service for all UI components.
//

import Foundation
import Combine

/// Translation provider options
enum TranslationProvider: String, Codable {
    case apple = "apple"           // On-device, privacy-first
    case backend = "backend"       // Cloud-based, advanced features
    case hybrid = "hybrid"         // Both (for comparison)
    case auto = "auto"            // Smart selection
}

/// Result from unified translation including provider info
struct UnifiedTranslationResult: Codable, Equatable {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let confidence: Double
    let provider: String
    let culturalNotes: String?
    let timestamp: Date

    // Hybrid mode: alternate result
    let alternateTranslation: String?
    let alternateProvider: String?
    let alternateConfidence: Double?

    // Metadata
    let latencyMs: Int
    let cacheHit: Bool
    let fallbackUsed: Bool

    enum CodingKeys: String, CodingKey {
        case originalText = "original_text"
        case translatedText = "translated_text"
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
        case confidence
        case provider
        case culturalNotes = "cultural_notes"
        case timestamp
        case alternateTranslation = "alternate_translation"
        case alternateProvider = "alternate_provider"
        case alternateConfidence = "alternate_confidence"
        case latencyMs = "latency_ms"
        case cacheHit = "cache_hit"
        case fallbackUsed = "fallback_used"
    }

    /// Convert to basic TranslationResult for compatibility
    func toTranslationResult() -> TranslationResult {
        TranslationResult(
            originalText: originalText,
            translatedText: translatedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            confidence: confidence,
            provider: provider,
            culturalNotes: culturalNotes,
            timestamp: timestamp
        )
    }
}

/// Translation metrics for analytics
struct TranslationMetrics: Codable {
    let totalTranslations: Int
    let appleTranslations: Int
    let backendTranslations: Int
    let hybridTranslations: Int
    let cacheHits: Int
    let fallbackEvents: Int
    let averageLatencyMs: Double
    let errorCount: Int
    let offlineTranslations: Int

    var cacheHitRate: Double {
        guard totalTranslations > 0 else { return 0.0 }
        return Double(cacheHits) / Double(totalTranslations)
    }

    var fallbackRate: Double {
        guard totalTranslations > 0 else { return 0.0 }
        return Double(fallbackEvents) / Double(totalTranslations)
    }
}

/// Unified translation service that orchestrates between Apple and Backend providers
@MainActor
final class UnifiedTranslationService: ObservableObject {

    // MARK: - Singleton

    static let shared = UnifiedTranslationService()

    // MARK: - Published Properties

    /// Current preferred provider
    @Published private(set) var preferredProvider: TranslationProvider = .auto

    /// Translation metrics
    @Published private(set) var metrics: TranslationMetrics

    // MARK: - Private Properties

    private let appleService: AppleTranslationService
    private let backendService: BackendTranslationService
    private let cache: AIServiceCache
    private let rateLimiter: RateLimitTracker
    private let featureFlags: FeatureFlags
    private let networkMonitor: NetworkMonitor

    /// Metrics tracking
    private var totalTranslations = 0
    private var appleTranslations = 0
    private var backendTranslations = 0
    private var hybridTranslations = 0
    private var cacheHits = 0
    private var fallbackEvents = 0
    private var totalLatencyMs: Int64 = 0
    private var errorCount = 0
    private var offlineTranslations = 0

    // MARK: - Initialization

    private init(
        appleService: AppleTranslationService = AppleTranslationService(),
        backendService: BackendTranslationService = .shared,
        cache: AIServiceCache = .shared,
        rateLimiter: RateLimitTracker = .shared,
        featureFlags: FeatureFlags = .shared,
        networkMonitor: NetworkMonitor = .shared
    ) {
        self.appleService = appleService
        self.backendService = backendService
        self.cache = cache
        self.rateLimiter = rateLimiter
        self.featureFlags = featureFlags
        self.networkMonitor = networkMonitor

        self.metrics = TranslationMetrics(
            totalTranslations: 0,
            appleTranslations: 0,
            backendTranslations: 0,
            hybridTranslations: 0,
            cacheHits: 0,
            fallbackEvents: 0,
            averageLatencyMs: 0.0,
            errorCount: 0,
            offlineTranslations: 0
        )

        print("✅ [UNIFIED_TRANSLATE] Initialized unified translation service")
    }

    // MARK: - Core Translation Method (Conforms to AIServiceProtocol pattern)

    /// Translate text with intelligent provider selection
    ///
    /// - Parameters:
    ///   - text: Text to translate
    ///   - sourceLanguage: Source language code (ISO 639-1) or "auto"
    ///   - targetLanguage: Target language code (ISO 639-1)
    ///   - provider: Provider preference (.auto for smart selection)
    /// - Returns: Unified translation result with metadata
    func translate(
        text: String,
        from sourceLanguage: String = "auto",
        to targetLanguage: String,
        provider: TranslationProvider = .auto
    ) async throws -> UnifiedTranslationResult {

        let startTime = Date()

        // Validate input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIServiceError.invalidText
        }

        // Check feature availability
        guard featureFlags.hasFeature(.translationEnabled) else {
            throw AIServiceError.featureDisabled(feature: "Translation")
        }

        // Generate cache key
        let cacheKey = generateCacheKey(
            text: text,
            source: sourceLanguage,
            target: targetLanguage,
            provider: provider
        )

        // Check cache first
        if let cached: UnifiedTranslationResult = await cache.retrieve(forKey: cacheKey, type: .translation) {
            print("💾 [UNIFIED_TRANSLATE] Cache hit")
            recordCacheHit()
            return cached
        }

        // Determine which provider to use
        let selectedProvider = selectProvider(
            requestedProvider: provider,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )

        print("🎯 [UNIFIED_TRANSLATE] Selected provider: \(selectedProvider.rawValue)")

        // Perform translation based on selected provider
        let result: UnifiedTranslationResult

        switch selectedProvider {
        case .apple:
            result = try await translateWithApple(
                text: text,
                from: sourceLanguage,
                to: targetLanguage,
                startTime: startTime
            )

        case .backend:
            result = try await translateWithBackend(
                text: text,
                from: sourceLanguage,
                to: targetLanguage,
                startTime: startTime
            )

        case .hybrid:
            result = try await translateWithHybrid(
                text: text,
                from: sourceLanguage,
                to: targetLanguage,
                startTime: startTime
            )

        case .auto:
            // This shouldn't happen (selectProvider resolves .auto)
            // but handle it defensively
            result = try await translateWithBackend(
                text: text,
                from: sourceLanguage,
                to: targetLanguage,
                startTime: startTime
            )
        }

        // Cache result
        await cache.store(result, forKey: cacheKey, type: .translation)

        // Update metrics
        recordTranslation(provider: selectedProvider, latencyMs: result.latencyMs)

        return result
    }

    // MARK: - Provider Selection Logic

    /// Intelligently select the best provider based on context
    private func selectProvider(
        requestedProvider: TranslationProvider,
        sourceLanguage: String,
        targetLanguage: String
    ) -> TranslationProvider {

        // If user explicitly requested a provider, honor it (unless impossible)
        if requestedProvider != .auto {
            // Validate the request can be fulfilled
            switch requestedProvider {
            case .apple:
                let pairKey = "\(sourceLanguage)_\(targetLanguage)"
                if !AppleTranslationService.supportedLanguagePairs.contains(pairKey) {
                    print("⚠️ [UNIFIED_TRANSLATE] Apple doesn't support \(pairKey), falling back to backend")
                    return .backend
                }
            case .backend:
                if !networkMonitor.isConnected {
                    print("⚠️ [UNIFIED_TRANSLATE] Offline, falling back to Apple")
                    return .apple
                }
            case .hybrid, .auto:
                break
            }
            return requestedProvider
        }

        // AUTO SELECTION LOGIC

        // Rule 1: If offline → Apple Translation (only option)
        if !networkMonitor.isConnected {
            print("📵 [UNIFIED_TRANSLATE] Offline detected, using Apple Translation")
            return .apple
        }

        // Rule 2: Check if language pair is supported by Apple
        let normalizedSource = sourceLanguage == "auto" ? "en" : sourceLanguage.components(separatedBy: "-").first ?? sourceLanguage
        let normalizedTarget = targetLanguage.components(separatedBy: "-").first ?? targetLanguage
        let pairKey = "\(normalizedSource)_\(normalizedTarget)"

        let appleSupported = AppleTranslationService.supportedLanguagePairs.contains(pairKey)

        if !appleSupported {
            print("ℹ️ [UNIFIED_TRANSLATE] Language pair not supported by Apple, using backend")
            return .backend
        }

        // Rule 3: Check rate limits for backend
        let rateLimitCheck = rateLimiter.canMakeRequest(for: .translation)
        if !rateLimitCheck.isAllowed {
            print("⚠️ [UNIFIED_TRANSLATE] Backend quota exceeded, falling back to Apple")
            return .apple
        }

        // Rule 4: Default to Backend (better quality for complex text)
        print("✅ [UNIFIED_TRANSLATE] Using backend (default for best quality)")
        return .backend
    }

    // MARK: - Provider-Specific Translation Methods

    private func translateWithApple(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        startTime: Date
    ) async throws -> UnifiedTranslationResult {

        do {
            let result = try await appleService.translate(
                text: text,
                from: sourceLanguage,
                to: targetLanguage
            )

            let latency = Int(Date().timeIntervalSince(startTime) * 1000)

            return UnifiedTranslationResult(
                originalText: result.originalText,
                translatedText: result.translatedText,
                sourceLanguage: result.sourceLanguage,
                targetLanguage: result.targetLanguage,
                confidence: result.confidence ?? 0.85,
                provider: "apple",
                culturalNotes: result.culturalNotes,
                timestamp: result.timestamp,
                alternateTranslation: nil,
                alternateProvider: nil,
                alternateConfidence: nil,
                latencyMs: latency,
                cacheHit: false,
                fallbackUsed: false
            )

        } catch {
            print("❌ [UNIFIED_TRANSLATE] Apple translation failed: \(error)")

            // Try backend as fallback if online
            if networkMonitor.isConnected {
                print("🔄 [UNIFIED_TRANSLATE] Falling back to backend")
                recordFallback()
                return try await translateWithBackend(
                    text: text,
                    from: sourceLanguage,
                    to: targetLanguage,
                    startTime: startTime,
                    fallbackUsed: true
                )
            }

            throw error
        }
    }

    private func translateWithBackend(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        startTime: Date,
        fallbackUsed: Bool = false
    ) async throws -> UnifiedTranslationResult {

        do {
            let result = try await backendService.translate(
                text: text,
                targetLanguage: targetLanguage,
                sourceLanguage: sourceLanguage == "auto" ? nil : sourceLanguage
            )

            let latency = Int(Date().timeIntervalSince(startTime) * 1000)

            return UnifiedTranslationResult(
                originalText: result.originalText,
                translatedText: result.translatedText,
                sourceLanguage: result.sourceLanguage,
                targetLanguage: result.targetLanguage,
                confidence: result.confidence,
                provider: "backend",
                culturalNotes: result.culturalNotes,
                timestamp: result.timestamp,
                alternateTranslation: nil,
                alternateProvider: nil,
                alternateConfidence: nil,
                latencyMs: latency,
                cacheHit: false,
                fallbackUsed: fallbackUsed
            )

        } catch {
            print("❌ [UNIFIED_TRANSLATE] Backend translation failed: \(error)")

            // Try Apple as fallback if not already a fallback
            if !fallbackUsed {
                print("🔄 [UNIFIED_TRANSLATE] Falling back to Apple")
                recordFallback()
                return try await translateWithApple(
                    text: text,
                    from: sourceLanguage,
                    to: targetLanguage,
                    startTime: startTime
                )
            }

            throw error
        }
    }

    private func translateWithHybrid(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String,
        startTime: Date
    ) async throws -> UnifiedTranslationResult {

        // Translate with both providers concurrently
        async let appleTask = appleService.translate(
            text: text,
            from: sourceLanguage,
            to: targetLanguage
        )

        async let backendTask = backendService.translate(
            text: text,
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage == "auto" ? nil : sourceLanguage
        )

        do {
            // Wait for both results
            let (appleResult, backendResult) = try await (appleTask, backendTask)

            let latency = Int(Date().timeIntervalSince(startTime) * 1000)

            // Primary result is backend (typically higher quality)
            return UnifiedTranslationResult(
                originalText: backendResult.originalText,
                translatedText: backendResult.translatedText,
                sourceLanguage: backendResult.sourceLanguage,
                targetLanguage: backendResult.targetLanguage,
                confidence: backendResult.confidence,
                provider: "backend",
                culturalNotes: backendResult.culturalNotes,
                timestamp: backendResult.timestamp,
                alternateTranslation: appleResult.translatedText,
                alternateProvider: "apple",
                alternateConfidence: appleResult.confidence,
                latencyMs: latency,
                cacheHit: false,
                fallbackUsed: false
            )

        } catch {
            print("❌ [UNIFIED_TRANSLATE] Hybrid translation failed: \(error)")

            // If both fail, throw the error
            // If only one failed, return the successful one
            if let appleResult = try? await appleTask {
                let latency = Int(Date().timeIntervalSince(startTime) * 1000)
                return UnifiedTranslationResult(
                    originalText: appleResult.originalText,
                    translatedText: appleResult.translatedText,
                    sourceLanguage: appleResult.sourceLanguage,
                    targetLanguage: appleResult.targetLanguage,
                    confidence: appleResult.confidence ?? 0.85,
                    provider: "apple",
                    culturalNotes: appleResult.culturalNotes,
                    timestamp: appleResult.timestamp,
                    alternateTranslation: nil,
                    alternateProvider: nil,
                    alternateConfidence: nil,
                    latencyMs: latency,
                    cacheHit: false,
                    fallbackUsed: true
                )
            }

            if let backendResult = try? await backendTask {
                let latency = Int(Date().timeIntervalSince(startTime) * 1000)
                return UnifiedTranslationResult(
                    originalText: backendResult.originalText,
                    translatedText: backendResult.translatedText,
                    sourceLanguage: backendResult.sourceLanguage,
                    targetLanguage: backendResult.targetLanguage,
                    confidence: backendResult.confidence,
                    provider: "backend",
                    culturalNotes: backendResult.culturalNotes,
                    timestamp: backendResult.timestamp,
                    alternateTranslation: nil,
                    alternateProvider: nil,
                    alternateConfidence: nil,
                    latencyMs: latency,
                    cacheHit: false,
                    fallbackUsed: true
                )
            }

            throw error
        }
    }

    // MARK: - Public Configuration Methods

    /// Set preferred translation provider
    func setPreferredProvider(_ provider: TranslationProvider) {
        preferredProvider = provider
        print("⚙️ [UNIFIED_TRANSLATE] Preferred provider set to: \(provider.rawValue)")
    }

    /// Get current translation metrics
    func getMetrics() -> TranslationMetrics {
        return metrics
    }

    /// Clear translation cache
    func clearCache() {
        cache.clearAll()
        print("🗑️ [UNIFIED_TRANSLATE] Cache cleared")
    }

    // MARK: - Metrics Recording

    private func recordTranslation(provider: TranslationProvider, latencyMs: Int) {
        totalTranslations += 1
        totalLatencyMs += Int64(latencyMs)

        switch provider {
        case .apple:
            appleTranslations += 1
            if !networkMonitor.isConnected {
                offlineTranslations += 1
            }
        case .backend:
            backendTranslations += 1
        case .hybrid:
            hybridTranslations += 1
        case .auto:
            break
        }

        updateMetrics()
    }

    private func recordCacheHit() {
        cacheHits += 1
        totalTranslations += 1
        updateMetrics()
    }

    private func recordFallback() {
        fallbackEvents += 1
    }

    private func recordError() {
        errorCount += 1
        updateMetrics()
    }

    private func updateMetrics() {
        let avgLatency = totalTranslations > 0 ?
            Double(totalLatencyMs) / Double(totalTranslations) : 0.0

        metrics = TranslationMetrics(
            totalTranslations: totalTranslations,
            appleTranslations: appleTranslations,
            backendTranslations: backendTranslations,
            hybridTranslations: hybridTranslations,
            cacheHits: cacheHits,
            fallbackEvents: fallbackEvents,
            averageLatencyMs: avgLatency,
            errorCount: errorCount,
            offlineTranslations: offlineTranslations
        )
    }

    // MARK: - Cache Key Generation

    private func generateCacheKey(
        text: String,
        source: String,
        target: String,
        provider: TranslationProvider
    ) -> String {
        let components = [text, source, target, provider.rawValue]
        let combined = components.joined(separator: "_")
        return combined.data(using: .utf8)?.base64EncodedString() ?? combined
    }
}

// MARK: - AIServiceProtocol Conformance

extension UnifiedTranslationService: AIServiceProtocol {

    /// AIServiceProtocol translation method (forwards to unified translate)
    func translate(
        text: String,
        from sourceLanguage: String,
        to targetLanguage: String
    ) async throws -> TranslationResult {
        let result = try await translate(
            text: text,
            from: sourceLanguage,
            to: targetLanguage,
            provider: preferredProvider
        )
        return result.toTranslationResult()
    }

    // MARK: - Unsupported AIServiceProtocol Methods (Use Backend Service)

    func summarizeThread(threadId: UUID, maxLength: Int?) async throws -> ThreadSummary {
        throw AIServiceError.featureDisabled(feature: "Use AIService for thread summarization")
    }

    func searchSemantic(
        query: String,
        in threadId: UUID?,
        limit: Int,
        recencyBias: Bool,
        translate: Bool
    ) async throws -> [SearchResult] {
        throw AIServiceError.featureDisabled(feature: "Use AIService for semantic search")
    }

    func extractTasks(from threadId: UUID, query: String?) async throws -> [ExtractedTask] {
        throw AIServiceError.featureDisabled(feature: "Use AIService for task extraction")
    }

    func checkVectorHealth(for threadId: UUID) async throws -> VectorHealthStatus {
        throw AIServiceError.featureDisabled(feature: "Use AIService for vector health checks")
    }
}

// MARK: - Testing Support

#if DEBUG
extension UnifiedTranslationService {
    /// Reset metrics (for testing)
    func resetMetrics() {
        totalTranslations = 0
        appleTranslations = 0
        backendTranslations = 0
        hybridTranslations = 0
        cacheHits = 0
        fallbackEvents = 0
        totalLatencyMs = 0
        errorCount = 0
        offlineTranslations = 0
        updateMetrics()
        print("🧪 [UNIFIED_TRANSLATE] Metrics reset (DEBUG only)")
    }
}
#endif
