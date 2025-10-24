# Translation Comparison UI - Documentation

## Overview

The **TranslationComparisonView** provides a side-by-side comparison UI for hybrid translation mode, allowing users to compare Apple Translation (on-device) with Backend Translation (cloud-based) and provide quality feedback.

## Features

### Core Features
- ✅ Side-by-side translation comparison
- ✅ Visual quality indicators (color-coded confidence scores)
- ✅ Performance metrics display (latency in milliseconds)
- ✅ User voting system ("Pick Winner" buttons)
- ✅ Quality feedback mechanism
- ✅ Copy translation to clipboard
- ✅ Cultural notes comparison (expandable)
- ✅ Identical translation detection
- ✅ Smooth SwiftUI animations
- ✅ Full accessibility support
- ✅ Dark mode support

### Visual Design
- **Color-coded confidence indicators**:
  - 🟢 Green: Excellent (90%+ confidence)
  - 🟠 Orange: Good (70-89% confidence)
  - 🔴 Red: Fair (<70% confidence)

- **Provider icons**:
  - 🍎 Apple Translation: Apple logo
  - ☁️ Backend Translation: Cloud icon

- **Performance indicators**:
  - ⏱️ Latency display
  - ✓ Identical results badge
  - 🔄 Provider count

## Architecture

### Data Models

#### TranslationComparison
```swift
struct TranslationComparison: Identifiable, Equatable {
    let id: UUID
    let originalText: String
    let sourceLanguage: String
    let targetLanguage: String

    // Primary translation (usually backend)
    let primaryTranslation: String
    let primaryProvider: String
    let primaryConfidence: Double
    let primaryCulturalNotes: String?

    // Alternate translation (usually apple)
    let alternateTranslation: String?
    let alternateProvider: String?
    let alternateConfidence: Double?

    // Performance metrics
    let latencyMs: Int
    let timestamp: Date

    // User feedback
    var userPreference: TranslationPreference?
    var userFeedback: String?

    // Computed properties
    var hasComparison: Bool
    var isIdentical: Bool
}
```

#### TranslationPreference
```swift
enum TranslationPreference: String, Codable {
    case primary = "primary"        // Backend is better
    case alternate = "alternate"    // Apple is better
    case both = "both"              // Both are good
    case neither = "neither"        // Both are poor
}
```

### View Structure

```
TranslationComparisonView
├── Original Text Section
│   ├── Language label
│   └── Original text display
│
├── Performance Section
│   ├── Latency metric
│   ├── Provider count
│   └── Identical indicator (if applicable)
│
├── Comparison Section (if hybrid)
│   ├── Primary Translation Card
│   │   ├── Provider header
│   │   ├── Confidence indicator
│   │   ├── Translation text
│   │   └── Copy button
│   │
│   └── Alternate Translation Card
│       ├── Provider header
│       ├── Confidence indicator
│       ├── Translation text
│       └── Copy button
│
├── Voting Section
│   ├── "Primary" button
│   ├── "Alternate" button
│   ├── "Both Good" button
│   ├── "Neither" button
│   └── Confirmation message
│
├── Cultural Notes Section (if available)
│   ├── Primary notes (expandable)
│   └── Alternate notes (expandable)
│
└── Feedback Button
    └── Opens feedback sheet
```

## Usage

### Basic Usage

```swift
import SwiftUI

struct MyView: View {
    @State private var comparison: TranslationComparison?

    var body: some View {
        VStack {
            Button("Compare Translations") {
                Task {
                    await performComparison()
                }
            }

            if let comparison = comparison {
                TranslationComparisonView(
                    comparison: comparison,
                    onVote: { preference in
                        print("User voted: \(preference.rawValue)")
                    },
                    onFeedback: { feedback in
                        print("User feedback: \(feedback)")
                    }
                )
            }
        }
    }

    private func performComparison() async {
        do {
            // Request hybrid translation
            let result = try await UnifiedTranslationService.shared.translate(
                text: "Hello, how are you?",
                from: "en",
                to: "es",
                provider: .hybrid  // KEY: Use hybrid mode
            )

            // Create comparison
            comparison = TranslationComparison(from: result)
        } catch {
            print("Translation error: \(error)")
        }
    }
}
```

### Chat Integration

```swift
struct ChatView: View {
    @State private var showComparison = false
    @State private var comparison: TranslationComparison?

    var body: some View {
        VStack {
            // Message bubble
            MessageBubbleView(message: message)

            // Translation comparison button
            Button("Compare Quality") {
                Task {
                    await compareTranslations()
                }
            }
        }
        .sheet(isPresented: $showComparison) {
            if let comparison = comparison {
                NavigationView {
                    TranslationComparisonView(
                        comparison: comparison,
                        onVote: saveVote,
                        onFeedback: submitFeedback
                    )
                    .navigationTitle("Translation Quality")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showComparison = false
                            }
                        }
                    }
                }
            }
        }
    }

    private func compareTranslations() async {
        // Implementation...
    }
}
```

### Batch Comparison

```swift
struct BatchComparisonView: View {
    let messages: [String]
    @State private var comparisons: [TranslationComparison] = []

    var body: some View {
        List(comparisons) { comparison in
            NavigationLink(destination:
                TranslationComparisonView(comparison: comparison)
            ) {
                ComparisonRowView(comparison: comparison)
            }
        }
        .task {
            await loadComparisons()
        }
    }

    private func loadComparisons() async {
        for message in messages {
            if let comparison = await translateAndCompare(message) {
                comparisons.append(comparison)
            }
        }
    }
}
```

## API Reference

### TranslationComparisonView

```swift
struct TranslationComparisonView: View {
    init(
        comparison: TranslationComparison,
        onVote: ((TranslationPreference) -> Void)? = nil,
        onFeedback: ((String) -> Void)? = nil
    )
}
```

**Parameters:**
- `comparison`: The translation comparison data to display
- `onVote`: Optional callback when user votes on quality
- `onFeedback`: Optional callback when user submits feedback

### Callbacks

#### onVote
Called when user selects a preference:
```swift
onVote: { preference in
    switch preference {
    case .primary:
        print("Backend is better")
    case .alternate:
        print("Apple is better")
    case .both:
        print("Both are good")
    case .neither:
        print("Both are poor")
    }

    // Log to analytics
    AnalyticsService.log(
        event: "translation_vote",
        parameters: ["preference": preference.rawValue]
    )
}
```

#### onFeedback
Called when user submits text feedback:
```swift
onFeedback: { feedback in
    // Send to backend
    Task {
        try await FeedbackService.submit(
            type: "translation_quality",
            text: feedback
        )
    }
}
```

## Performance

### Metrics
- **Latency Display**: Shows total translation time in milliseconds
- **Concurrent Execution**: Hybrid mode runs both providers in parallel
- **Typical Performance**:
  - Apple Translation: 50-150ms
  - Backend Translation: 150-400ms
  - Hybrid Mode: 150-400ms (limited by slowest provider)

### Optimization Tips
1. **Cache Results**: Translation results are automatically cached
2. **Preload**: Request translations before showing comparison UI
3. **Lazy Loading**: Load cultural notes on demand (expandable)
4. **Efficient Rendering**: SwiftUI optimizations for smooth scrolling

## Accessibility

### VoiceOver Support
- All buttons have descriptive labels
- Confidence scores are announced
- Translation text is readable
- Provider names are announced

### Dynamic Type
- All text scales with user's preferred size
- Layouts adapt to larger text sizes

### Color Contrast
- Confidence indicators meet WCAG AA standards
- Dark mode support with appropriate contrasts

## Testing

### Unit Tests
Comprehensive test coverage (20+ test cases):

```swift
// Test identical translations
func testIdenticalTranslations() {
    let comparison = createComparison(
        primary: "Hola",
        alternate: "hola"  // Case-insensitive
    )
    XCTAssertTrue(comparison.isIdentical)
}

// Test confidence levels
func testHighConfidence() {
    let comparison = createComparison(confidence: 0.95)
    XCTAssertGreaterThanOrEqual(comparison.primaryConfidence, 0.9)
}

// Test language pairs
func testEnglishToSpanish() {
    let comparison = createComparison(
        source: "en",
        target: "es"
    )
    XCTAssertEqual(comparison.sourceLanguage, "en")
}
```

### UI Tests
```swift
// Test voting interaction
func testVotingInteraction() {
    let app = XCUIApplication()

    // Tap primary vote button
    app.buttons["Apple Translation"].tap()

    // Verify feedback appears
    XCTAssertTrue(app.staticTexts["Thank you for your feedback!"].exists)
}

// Test copy functionality
func testCopyTranslation() {
    let app = XCUIApplication()

    // Tap copy button
    app.buttons["Copy"].firstMatch.tap()

    // Verify confirmation
    XCTAssertTrue(app.staticTexts["Copied to clipboard!"].exists)
}
```

## Analytics Events

### Tracking User Behavior
```swift
// Vote events
AnalyticsService.log(
    event: "translation_vote",
    parameters: [
        "preference": preference.rawValue,
        "primary_provider": comparison.primaryProvider,
        "alternate_provider": comparison.alternateProvider ?? "none",
        "primary_confidence": comparison.primaryConfidence,
        "latency_ms": comparison.latencyMs
    ]
)

// Feedback events
AnalyticsService.log(
    event: "translation_feedback",
    parameters: [
        "feedback_length": feedback.count,
        "has_alternate": comparison.hasComparison,
        "is_identical": comparison.isIdentical
    ]
)

// Copy events
AnalyticsService.log(
    event: "translation_copy",
    parameters: [
        "provider": provider,
        "confidence": confidence
    ]
)
```

## Best Practices

### When to Use Comparison View
- ✅ User requests quality comparison
- ✅ Testing new translation features
- ✅ Gathering user feedback on quality
- ✅ Important/sensitive translations
- ❌ Every single translation (too expensive)
- ❌ Real-time chat (use auto-select mode)

### User Experience Guidelines
1. **Provide Context**: Explain why comparison is happening
2. **Make Voting Optional**: Don't force users to vote
3. **Respect Choices**: Save user preferences for future improvements
4. **Show Performance**: Display latency to set expectations
5. **Enable Copying**: Let users copy either translation

### Implementation Checklist
- [ ] Initialize UnifiedTranslationService
- [ ] Request hybrid translation mode
- [ ] Create TranslationComparison from result
- [ ] Implement onVote callback
- [ ] Implement onFeedback callback
- [ ] Log analytics events
- [ ] Test with various language pairs
- [ ] Test with long translations
- [ ] Test with identical results
- [ ] Verify accessibility

## Troubleshooting

### Common Issues

**Issue**: No alternate translation shown
```swift
// Solution: Ensure hybrid mode is requested
let result = try await service.translate(
    text: text,
    from: source,
    to: target,
    provider: .hybrid  // ← Must be .hybrid
)
```

**Issue**: Slow performance
```swift
// Solution: Cache translations
let cached = await cache.retrieve(forKey: key, type: .translation)
if let cached = cached {
    return TranslationComparison(from: cached)
}
```

**Issue**: Missing cultural notes
```swift
// Solution: Check provider capabilities
// Not all providers return cultural notes
if let notes = comparison.primaryCulturalNotes {
    // Display notes
} else {
    // Hide notes section
}
```

## Future Enhancements

### Planned Features
- [ ] Visual diff highlighting (word-level differences)
- [ ] Translation history tracking
- [ ] Quality trend analysis
- [ ] A/B testing framework integration
- [ ] Export comparison results
- [ ] Collaborative voting (multiple users)
- [ ] Machine learning quality prediction

### Potential Improvements
- Animated transitions between votes
- Haptic feedback on voting
- Swipe gestures for quick voting
- Inline editing of translations
- Share comparison with others
- Translation quality scores over time

## Resources

### Related Documentation
- [UnifiedTranslationService Guide](./unified-translation-service.md)
- [Translation Architecture](./translation-architecture.md)
- [Feature Flags System](./feature-flags.md)
- [Analytics Integration](./analytics.md)

### Code Examples
- Basic usage: `TranslationComparisonExamples.swift`
- Chat integration: `ChatTranslationComparisonExample`
- Batch processing: `BatchTranslationComparisonExample`
- Quality monitoring: `QualityMonitoringExample`

### External References
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [Accessibility Guidelines](https://developer.apple.com/accessibility/)
- [Translation Framework](https://developer.apple.com/documentation/translation)

---

## Quick Reference

### Initialization
```swift
let comparison = TranslationComparison(from: unifiedResult)
```

### Display
```swift
TranslationComparisonView(comparison: comparison)
```

### With Callbacks
```swift
TranslationComparisonView(
    comparison: comparison,
    onVote: { preference in /* ... */ },
    onFeedback: { feedback in /* ... */ }
)
```

### Check Capabilities
```swift
if comparison.hasComparison {
    // Show side-by-side
}

if comparison.isIdentical {
    // Show identical badge
}
```

---

**Version**: 1.0.0
**Last Updated**: 2024-10-24
**Status**: Production Ready ✅
