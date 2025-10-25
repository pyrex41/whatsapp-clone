//
//  SuggestionFeedback.swift
//  GlobalBridge
//
//  Created on 2025-10-25.
//

import Foundation

/// Represents user feedback on a smart reply suggestion
struct SuggestionFeedback: Codable, Equatable {
    let suggestionId: UUID
    let accepted: Bool
    let modifiedContent: String? // Content if user modified the suggestion
    let rejectionReason: String? // Reason if user rejected the suggestion
    let timeToResponseMs: Int? // Time taken to accept/reject in milliseconds
    let timestamp: Date

    init(suggestionId: UUID, accepted: Bool,
         modifiedContent: String? = nil, rejectionReason: String? = nil,
         timeToResponseMs: Int? = nil, timestamp: Date = Date()) {
        self.suggestionId = suggestionId
        self.accepted = accepted
        self.modifiedContent = modifiedContent
        self.rejectionReason = rejectionReason
        self.timeToResponseMs = timeToResponseMs
        self.timestamp = timestamp
    }
}
