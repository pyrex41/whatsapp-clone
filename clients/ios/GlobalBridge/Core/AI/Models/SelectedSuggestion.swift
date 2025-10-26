//
//  SelectedSuggestion.swift
//  GlobalBridge
//
//  Task 21: Suggestion Modification Tracking
//  Tracks a selected suggestion and its original content for modification detection
//

import Foundation

/// Represents a suggestion that was selected by the user
struct SelectedSuggestion: Equatable {
    let suggestion: SmartReplySuggestion
    let originalContent: String
    let selectionTime: Date
    let timeToResponseMs: Int

    init(suggestion: SmartReplySuggestion, timeToResponseMs: Int) {
        self.suggestion = suggestion
        self.originalContent = suggestion.content
        self.selectionTime = Date()
        self.timeToResponseMs = timeToResponseMs
    }

    /// Detects if the content was modified compared to the original suggestion
    /// - Parameter currentContent: The current message content
    /// - Returns: Tuple of (wasModified, modifiedContent)
    func detectModification(in currentContent: String) -> (wasModified: Bool, modifiedContent: String?) {
        // Trim whitespace for comparison
        let trimmedOriginal = originalContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCurrent = currentContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if content was modified
        if trimmedOriginal == trimmedCurrent {
            print("✅ [MODIFICATION_TRACKING] No modification detected for suggestion: \(suggestion.id)")
            return (false, nil)
        } else {
            let changePercent = calculateChangePercentage(from: trimmedOriginal, to: trimmedCurrent)
            print("✏️  [MODIFICATION_TRACKING] Modification detected for suggestion: \(suggestion.id)")
            print("    Original length: \(trimmedOriginal.count), Modified length: \(trimmedCurrent.count)")
            print("    Change percentage: \(String(format: "%.1f", changePercent))%")
            return (true, currentContent)
        }
    }

    /// Calculates the percentage of content that changed
    private func calculateChangePercentage(from original: String, to modified: String) -> Double {
        guard !original.isEmpty else { return 100.0 }

        let maxLength = max(original.count, modified.count)
        let minLength = min(original.count, modified.count)

        // Simple length-based difference
        let lengthDiff = abs(original.count - modified.count)

        // Character-level comparison for common portion
        var differences = 0
        for i in 0..<minLength {
            let originalIndex = original.index(original.startIndex, offsetBy: i)
            let modifiedIndex = modified.index(modified.startIndex, offsetBy: i)
            if original[originalIndex] != modified[modifiedIndex] {
                differences += 1
            }
        }

        let totalDifferences = differences + lengthDiff
        return (Double(totalDifferences) / Double(maxLength)) * 100.0
    }

    /// Creates feedback based on whether the suggestion was accepted or modified
    /// - Parameters:
    ///   - finalContent: The final message content that was sent
    ///   - accepted: Whether the suggestion was accepted (true) or rejected (false)
    /// - Returns: SuggestionFeedback object
    func createFeedback(finalContent: String, accepted: Bool) -> SuggestionFeedback {
        let (wasModified, modifiedContent) = detectModification(in: finalContent)

        print("📊 [MODIFICATION_TRACKING] Creating feedback:")
        print("    Suggestion ID: \(suggestion.id)")
        print("    Accepted: \(accepted)")
        print("    Modified: \(wasModified)")
        print("    Time to response: \(timeToResponseMs)ms")

        return SuggestionFeedback(
            suggestionId: suggestion.id,
            accepted: accepted,
            modifiedContent: wasModified ? modifiedContent : nil,
            rejectionReason: nil,
            timeToResponseMs: timeToResponseMs,
            timestamp: Date()
        )
    }
}
