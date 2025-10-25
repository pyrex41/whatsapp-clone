//
//  ToneAnalysisResult.swift
//  GlobalBridge
//
//  Model for tone analysis API responses
//  Maps to backend POST /api/v1/ai/analyze_tone response
//

import Foundation

/// Result from emotional tone analysis of text
struct ToneAnalysisResult: Codable, Equatable {
    /// Primary emotional tone detected (e.g., "happy", "sad", "angry", "neutral")
    let tone: String

    /// Confidence score for the detected tone (0.0 to 1.0)
    let confidence: Double

    /// Additional emotions detected with lower confidence
    let emotions: [String]?

    /// Language code of the analyzed text
    let language: String

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case tone
        case confidence
        case emotions
        case language
    }

    // MARK: - Initialization

    init(
        tone: String,
        confidence: Double,
        emotions: [String]? = nil,
        language: String = "en"
    ) {
        self.tone = tone
        self.confidence = confidence
        self.emotions = emotions
        self.language = language
    }
}

// MARK: - Helper Extensions

extension ToneAnalysisResult {
    /// Whether the tone detection is highly confident (>0.8)
    var isHighConfidence: Bool {
        confidence > 0.8
    }

    /// Whether the tone detection is moderately confident (>0.5)
    var isModerateConfidence: Bool {
        confidence > 0.5
    }

    /// Confidence percentage (0-100)
    var confidencePercentage: Int {
        Int(confidence * 100)
    }

    /// Whether the detected tone is positive
    var isPositiveTone: Bool {
        ["happy", "excited", "cheerful", "joyful", "satisfied", "pleased"].contains(tone.lowercased())
    }

    /// Whether the detected tone is negative
    var isNegativeTone: Bool {
        ["sad", "angry", "frustrated", "annoyed", "disappointed", "upset"].contains(tone.lowercased())
    }

    /// Whether the detected tone is neutral
    var isNeutralTone: Bool {
        ["neutral", "calm", "factual", "professional"].contains(tone.lowercased())
    }
}

// MARK: - Display Helpers

extension ToneAnalysisResult {
    /// Color indicator for tone (for UI display)
    var toneColor: String {
        if isPositiveTone {
            return "green"
        } else if isNegativeTone {
            return "red"
        } else {
            return "gray"
        }
    }

    /// Icon name for tone (SF Symbols)
    var toneIcon: String {
        if isPositiveTone {
            return "face.smiling"
        } else if isNegativeTone {
            return "face.frowning"
        } else {
            return "face.neutral"
        }
    }

    /// Formatted confidence text (e.g., "85% confident")
    var confidenceText: String {
        "\(confidencePercentage)% confident"
    }

    /// Summary text combining tone and confidence
    var summary: String {
        "\(tone.capitalized) (\(confidencePercentage)% confidence)"
    }
}

// MARK: - Mock Data

#if DEBUG
extension ToneAnalysisResult {
    static let mockPositive = ToneAnalysisResult(
        tone: "happy",
        confidence: 0.92,
        emotions: ["excited", "cheerful"],
        language: "en"
    )

    static let mockNegative = ToneAnalysisResult(
        tone: "frustrated",
        confidence: 0.78,
        emotions: ["annoyed", "angry"],
        language: "en"
    )

    static let mockNeutral = ToneAnalysisResult(
        tone: "neutral",
        confidence: 0.65,
        emotions: ["calm", "professional"],
        language: "en"
    )
}
#endif
