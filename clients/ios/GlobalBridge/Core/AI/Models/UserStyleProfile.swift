//
//  UserStyleProfile.swift
//  GlobalBridge
//
//  Created on 2025-10-25.
//

import Foundation

/// Represents a user's messaging style profile derived from historical message analysis
struct UserStyleProfile: Codable, Equatable {
    let userId: UUID
    let formalityLevel: Double // 0.0-1.0 (0 = casual, 1 = formal)
    let emojiFrequency: Double // Average emojis per message
    let avgSentenceLength: Double // Average number of words per sentence
    let messagesAnalyzed: Int
    let confidenceScore: Double // 0.0-1.0
    let lastUpdatedAt: Date

    /// Indicates if the profile has high confidence (>= 0.8)
    var isHighConfidence: Bool {
        confidenceScore >= 0.8
    }

    init(userId: UUID, formalityLevel: Double, emojiFrequency: Double,
         avgSentenceLength: Double, messagesAnalyzed: Int,
         confidenceScore: Double, lastUpdatedAt: Date = Date()) {
        self.userId = userId
        self.formalityLevel = formalityLevel
        self.emojiFrequency = emojiFrequency
        self.avgSentenceLength = avgSentenceLength
        self.messagesAnalyzed = messagesAnalyzed
        self.confidenceScore = confidenceScore
        self.lastUpdatedAt = lastUpdatedAt
    }
}
