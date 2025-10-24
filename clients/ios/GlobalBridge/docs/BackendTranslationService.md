# BackendTranslationService Documentation

## Overview

`BackendTranslationService` is an advanced translation service that provides cloud-based AI translation with context awareness, cultural intelligence, and quality tracking. It wraps the core `AIService` with enhanced features for production-grade translation capabilities.

## Features

### Core Capabilities
- ✅ **Context-Aware Translation**: Uses conversation history for accurate translations
- ✅ **Cultural Intelligence**: Provides cultural notes and idiom explanations
- ✅ **Formality Detection**: Automatically detects and preserves formality level
- ✅ **Batch Translation**: Efficiently translate multiple texts concurrently
- ✅ **Translation History**: Tracks translations for learning and analytics
- ✅ **Quality Feedback**: Allows users to rate and improve translations
- ✅ **Smart Caching**: Context-aware caching for optimal performance
- ✅ **Rate Limiting**: Tier-based quota management
- ✅ **100+ Languages**: Supports all languages provided by backend AI

### Advantages
- **Higher Accuracy**: Backend AI models provide better accuracy than on-device translation
- **Cultural Context**: Includes cultural notes for idioms, slang, and cultural references
- **Continuous Learning**: Quality feedback improves future translations
- **Formality Awareness**: Understands and preserves formal vs informal tone
- **Context Understanding**: Uses conversation context for disambiguation

### Limitations
- **Internet Required**: Requires active network connection
- **API Quota**: Counts against user's AI feature quota
- **Privacy Consideration**: Text is sent to backend servers
- **Latency**: Network latency affects response time (~200-500ms)

## Architecture

```
┌─────────────────────────────────────────────────────┐
│         BackendTranslationService                   │
│  (Context-aware, Cultural Intelligence)             │
└────────────────┬────────────────────────────────────┘
                 │
                 ├── AIService (HTTP layer)
                 ├── AIServiceCache (Multi-tier caching)
                 ├── RateLimitTracker (Quota management)
                 └── FeatureFlags (Tier checking)
```

## Installation

The service is included in the GlobalBridge iOS client. No additional installation required.

## Usage Examples

### Basic Translation

```swift
import GlobalBridge

@MainActor
func translateMessage() async {
    let service = BackendTranslationService.shared

    do {
        let result = try await service.translate(
            text: "Hello, how are you?",
            targetLanguage: "es"
        )

        print("Original: \(result.originalText)")
        print("Translated: \(result.translatedText)")
        print("Confidence: \(result.confidence)")
        print("Quality: \(result.qualityDescription)")

        // Output:
        // Original: Hello, how are you?
        // Translated: Hola, ¿cómo estás?
        // Confidence: 0.95
        // Quality: Excellent
    } catch {
        print("Translation error: \(error)")
    }
}
```

### Translation with Explicit Source Language

```swift
@MainActor
func translateFromFrench() async {
    let service = BackendTranslationService.shared

    do {
        let result = try await service.translate(
            text: "Bonjour tout le monde",
            targetLanguage: "en",
            sourceLanguage: "fr"
        )

        print("Translated: \(result.translatedText)")
        // Output: Hello everyone
    } catch {
        print("Error: \(error)")
    }
}
```

### Context-Aware Translation

```swift
@MainActor
func translateWithContext() async {
    let service = BackendTranslationService.shared

    // Conversation context
    let context = [
        "Are you hungry?",
        "Let's go to the restaurant",
        "What do you want to eat?"
    ]

    do {
        // The word "table" could mean furniture or restaurant table
        // Context helps disambiguate
        let result = try await service.translate(
            text: "I need a table for two",
            targetLanguage: "es",
            context: context
        )

        print("Translated: \(result.translatedText)")
        // Output: Necesito una mesa para dos (restaurant table, not furniture)

        if result.contextUsed {
            print("Translation used conversation context for accuracy")
        }
    } catch {
        print("Error: \(error)")
    }
}
```

### Translation with Thread Context

```swift
@MainActor
func translateInThread(messageText: String, threadId: UUID) async {
    let service = BackendTranslationService.shared

    do {
        // Automatically fetches recent messages from thread for context
        let result = try await service.translateWithThreadContext(
            text: messageText,
            targetLanguage: "es",
            threadId: threadId
        )

        print("Thread-aware translation: \(result.translatedText)")
        print("Context was used: \(result.contextUsed)")
    } catch {
        print("Error: \(error)")
    }
}
```

### Cultural Notes and Idioms

```swift
@MainActor
func translateIdiom() async {
    let service = BackendTranslationService.shared

    do {
        let result = try await service.translate(
            text: "Break a leg at your performance!",
            targetLanguage: "es"
        )

        print("Translated: \(result.translatedText)")
        // Output: ¡Buena suerte en tu actuación!

        if let culturalNotes = result.culturalNotes {
            print("Cultural context: \(culturalNotes)")
            // Output: Cultural note: Theater idiom wishing good luck
        }
    } catch {
        print("Error: \(error)")
    }
}
```

### Formality Detection

```swift
@MainActor
func detectFormality() async {
    let service = BackendTranslationService.shared

    // Formal text
    do {
        let formalResult = try await service.translate(
            text: "Could you please assist me with this matter?",
            targetLanguage: "es"
        )

        print("Formality: \(formalResult.formality?.rawValue ?? "unknown")")
        // Output: formal
        print("Translation: \(formalResult.translatedText)")
        // Output: ¿Podría usted asistirme con este asunto? (formal "usted")
    } catch {
        print("Error: \(error)")
    }

    // Informal text
    do {
        let informalResult = try await service.translate(
            text: "Hey, wanna grab lunch?",
            targetLanguage: "es"
        )

        print("Formality: \(informalResult.formality?.rawValue ?? "unknown")")
        // Output: informal
        print("Translation: \(informalResult.translatedText)")
        // Output: Oye, ¿quieres almorzar? (informal "tú")
    } catch {
        print("Error: \(error)")
    }
}
```

### Explicit Formality Level

```swift
@MainActor
func translateWithFormalityLevel() async {
    let service = BackendTranslationService.shared

    do {
        // Force formal translation regardless of input
        let result = try await service.translate(
            text: "How can I help?",
            targetLanguage: "es",
            formality: .formal
        )

        print("Translated: \(result.translatedText)")
        // Output: ¿Cómo puedo ayudarle? (formal)
    } catch {
        print("Error: \(error)")
    }
}
```

### Batch Translation

```swift
@MainActor
func batchTranslate() async {
    let service = BackendTranslationService.shared

    let messages = [
        "Hello",
        "How are you?",
        "See you tomorrow!",
        "Thanks for your help",
        "Have a great day"
    ]

    do {
        let results = try await service.batchTranslate(
            texts: messages,
            targetLanguage: "fr"
        )

        for (index, result) in results.enumerated() {
            print("\(messages[index]) → \(result.translatedText)")
        }

        // Output:
        // Hello → Bonjour
        // How are you? → Comment allez-vous?
        // See you tomorrow! → À demain!
        // Thanks for your help → Merci pour votre aide
        // Have a great day → Passez une bonne journée

        print("Batch translated \(results.count) messages")
    } catch {
        print("Batch translation error: \(error)")
    }
}
```

### Translation History

```swift
@MainActor
func viewTranslationHistory() async {
    let service = BackendTranslationService.shared

    // Perform some translations...
    try? await service.translate(text: "Hello", targetLanguage: "es")
    try? await service.translate(text: "Goodbye", targetLanguage: "fr")

    // View history
    let history = service.getTranslationHistory(limit: 10)

    for entry in history {
        print("[\(entry.timestamp)] \(entry.originalText) → \(entry.translatedText)")
        print("  \(entry.sourceLanguage) → \(entry.targetLanguage)")
        print("  Confidence: \(entry.confidence)")
        print()
    }

    // Clear history if needed
    // service.clearTranslationHistory()
}
```

### Quality Feedback

```swift
@MainActor
func submitFeedback(translation: EnhancedTranslationResult) async {
    let service = BackendTranslationService.shared

    // User found translation excellent
    await service.submitQualityFeedback(
        translationId: translation.translationId,
        rating: 5
    )

    // User found issues with translation
    await service.submitQualityFeedback(
        translationId: translation.translationId,
        rating: 2,
        issues: [.awkwardPhrasing, .missingContext],
        suggestedTranslation: "Better translation here"
    )

    print("Feedback submitted for improvement")
}
```

### Translation Statistics

```swift
@MainActor
func viewStatistics() async {
    let service = BackendTranslationService.shared

    let stats = service.getStatistics()

    print("📊 Translation Statistics")
    print("Total translations: \(stats.totalTranslations)")
    print("Average confidence: \(String(format: "%.1f%%", stats.averageConfidence * 100))")
    print("Average rating: \(String(format: "%.1f/5", stats.averageRating))")
    print("Feedback count: \(stats.feedbackCount)")
    print()
    print("Language pairs:")
    for (pair, count) in stats.languagePairs.sorted(by: { $0.value > $1.value }) {
        print("  \(pair): \(count) translations")
    }
}
```

### Error Handling

```swift
@MainActor
func handleTranslationErrors() async {
    let service = BackendTranslationService.shared

    do {
        let result = try await service.translate(
            text: "Hello",
            targetLanguage: "es"
        )
        print("Success: \(result.translatedText)")
    } catch AIServiceError.rateLimitExceeded(let retryAfter, let remaining, let tier) {
        if let remaining = remaining, remaining == 0 {
            print("Quota exceeded. Upgrade to \(tier ?? "Pro") for more.")
        }
        if let retry = retryAfter {
            print("Try again at: \(retry)")
        }
    } catch AIServiceError.featureDisabled(let feature) {
        print("Feature disabled: \(feature)")
    } catch AIServiceError.networkError(let error) {
        print("Network error: \(error.localizedDescription)")
    } catch AIServiceError.invalidText {
        print("Cannot translate empty text")
    } catch {
        print("Unexpected error: \(error)")
    }
}
```

### Quality Score Checking

```swift
@MainActor
func checkTranslationQuality() async {
    let service = BackendTranslationService.shared

    do {
        let result = try await service.translate(
            text: "The quick brown fox jumps over the lazy dog",
            targetLanguage: "es"
        )

        print("Quality score: \(result.qualityScore)")
        print("Quality: \(result.qualityDescription)")
        print("Is high quality: \(result.isHighQuality)")
        print("Confidence: \(result.confidence)")

        if !result.isHighQuality {
            print("⚠️ Translation may need review")
        }
    } catch {
        print("Error: \(error)")
    }
}
```

### SwiftUI Integration

```swift
import SwiftUI

struct TranslationView: View {
    @State private var inputText: String = ""
    @State private var targetLanguage: String = "es"
    @State private var translationResult: EnhancedTranslationResult?
    @State private var isTranslating: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter text to translate", text: $inputText)
                .textFieldStyle(.roundedBorder)

            Picker("Target Language", selection: $targetLanguage) {
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Japanese").tag("ja")
            }
            .pickerStyle(.segmented)

            Button("Translate") {
                Task {
                    await translateText()
                }
            }
            .disabled(inputText.isEmpty || isTranslating)

            if isTranslating {
                ProgressView("Translating...")
            }

            if let result = translationResult {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Translation:")
                        .font(.headline)

                    Text(result.translatedText)
                        .font(.body)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)

                    HStack {
                        Text("Confidence:")
                        Text("\(Int(result.confidence * 100))%")
                            .fontWeight(.bold)
                    }

                    HStack {
                        Text("Quality:")
                        Text(result.qualityDescription)
                            .fontWeight(.bold)
                            .foregroundColor(result.isHighQuality ? .green : .orange)
                    }

                    if let formality = result.formality {
                        HStack {
                            Text("Formality:")
                            Text(formality.rawValue)
                                .fontWeight(.bold)
                        }
                    }

                    if let notes = result.culturalNotes {
                        VStack(alignment: .leading) {
                            Text("Cultural Notes:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(notes)
                                .font(.caption)
                                .italic()
                        }
                        .padding(.top, 5)
                    }
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    private func translateText() async {
        isTranslating = true
        errorMessage = nil

        do {
            let service = BackendTranslationService.shared
            let result = try await service.translate(
                text: inputText,
                targetLanguage: targetLanguage
            )
            translationResult = result
        } catch {
            errorMessage = error.localizedDescription
        }

        isTranslating = false
    }
}
```

## API Reference

### Core Methods

#### `translate(text:targetLanguage:sourceLanguage:context:formality:)`
Translate text with full context awareness and cultural intelligence.

**Parameters:**
- `text: String` - Text to translate
- `targetLanguage: String` - Target language code (ISO 639-1)
- `sourceLanguage: String?` - Optional source language (auto-detected if nil)
- `context: [String]?` - Optional conversation context
- `formality: FormalityLevel?` - Optional desired formality level

**Returns:** `EnhancedTranslationResult`

**Throws:** `AIServiceError`

#### `batchTranslate(texts:targetLanguage:sourceLanguage:preserveOrder:)`
Translate multiple texts efficiently.

**Parameters:**
- `texts: [String]` - Array of texts to translate
- `targetLanguage: String` - Target language for all texts
- `sourceLanguage: String?` - Optional source language
- `preserveOrder: Bool` - Whether to maintain input order (default: true)

**Returns:** `[EnhancedTranslationResult]`

**Throws:** `AIServiceError`

#### `translateWithThreadContext(text:targetLanguage:threadId:sourceLanguage:)`
Translate with full thread context.

**Parameters:**
- `text: String` - Text to translate
- `targetLanguage: String` - Target language
- `threadId: UUID` - Thread ID to fetch context from
- `sourceLanguage: String?` - Optional source language

**Returns:** `EnhancedTranslationResult`

**Throws:** `AIServiceError`

#### `submitQualityFeedback(translationId:rating:issues:suggestedTranslation:)`
Submit quality feedback for a translation.

**Parameters:**
- `translationId: String` - Unique ID of the translation
- `rating: Int` - Quality rating (1-5)
- `issues: [TranslationIssue]?` - Specific issues found
- `suggestedTranslation: String?` - User's suggested improvement

#### `getTranslationHistory(limit:)`
Get recent translation history.

**Parameters:**
- `limit: Int` - Maximum number of entries (default: 20)

**Returns:** `[TranslationHistoryEntry]`

#### `getStatistics()`
Get translation statistics for analytics.

**Returns:** `TranslationStatistics`

### Data Models

#### `EnhancedTranslationResult`
Enhanced translation result with cultural intelligence.

**Properties:**
- `originalText: String` - Original input text
- `translatedText: String` - Translated output text
- `sourceLanguage: String` - Detected/specified source language
- `targetLanguage: String` - Target language
- `confidence: Double` - Translation confidence (0.0-1.0)
- `provider: String?` - AI provider used
- `culturalNotes: String?` - Cultural context notes
- `formality: FormalityLevel?` - Detected formality level
- `contextUsed: Bool` - Whether conversation context was used
- `qualityScore: Double` - Overall quality score (0.0-1.0)
- `timestamp: Date` - Translation timestamp
- `translationId: String` - Unique translation ID

**Computed Properties:**
- `isHighQuality: Bool` - Whether quality score > 0.8
- `qualityDescription: String` - Human-readable quality ("Excellent", "Good", etc.)
- `age: TimeInterval` - Age in seconds
- `isFresh: Bool` - Whether less than 5 minutes old

#### `FormalityLevel`
Formality level for translations.

**Cases:**
- `formal` - Formal language (business, professional)
- `neutral` - Neutral tone (standard communication)
- `informal` - Informal language (friends, casual)

#### `TranslationIssue`
Specific translation issues for feedback.

**Cases:**
- `wrongMeaning` - Incorrect meaning
- `awkwardPhrasing` - Awkward or unnatural phrasing
- `missingContext` - Context not properly considered
- `incorrectFormality` - Wrong formality level
- `culturallyInappropriate` - Culturally inappropriate translation

## Performance Considerations

### Caching
The service implements intelligent caching:
- **Context-aware cache keys**: Different contexts create different cache entries
- **24-hour TTL**: Translation cache expires after 24 hours
- **Memory + Disk**: Two-tier caching for optimal performance

### Rate Limiting
Respects user tier quotas:
- **Free tier**: 100 translations/day
- **Pro tier**: 1,000 translations/day
- **Enterprise tier**: Unlimited

### Batch Optimization
- For 3+ texts, uses concurrent translation
- Maintains order by default (slight performance cost)
- Set `preserveOrder: false` for maximum speed

### Network Optimization
- Request timeout: 30 seconds
- Automatic retry on network errors
- Exponential backoff on rate limits

## Best Practices

### 1. Use Context When Available
```swift
// ❌ Without context - ambiguous
let result = try await service.translate(text: "bank", targetLanguage: "es")

// ✅ With context - accurate
let result = try await service.translate(
    text: "bank",
    targetLanguage: "es",
    context: ["river", "water", "fishing"]
)
```

### 2. Batch Multiple Translations
```swift
// ❌ Sequential translations
for text in messages {
    let result = try await service.translate(text: text, targetLanguage: "es")
    results.append(result)
}

// ✅ Batch translation
let results = try await service.batchTranslate(texts: messages, targetLanguage: "es")
```

### 3. Check Quality Score
```swift
let result = try await service.translate(text: text, targetLanguage: "es")

if !result.isHighQuality {
    // Show warning or request user confirmation
    showQualityWarning(result.qualityDescription)
}
```

### 4. Handle Errors Gracefully
```swift
do {
    let result = try await service.translate(text: text, targetLanguage: "es")
    // Use result
} catch AIServiceError.rateLimitExceeded {
    // Show upgrade prompt
    showUpgradePrompt()
} catch {
    // Fall back to Apple Translation
    let fallbackResult = await appleTranslationService.translate(text: text, to: "es")
}
```

### 5. Collect Quality Feedback
```swift
// Show feedback UI after translation
let result = try await service.translate(text: text, targetLanguage: "es")

// Let user rate translation
await service.submitQualityFeedback(
    translationId: result.translationId,
    rating: userRating
)
```

## Comparison with Apple Translation

| Feature | BackendTranslationService | AppleTranslationService |
|---------|---------------------------|-------------------------|
| Languages | 100+ | 12 |
| Accuracy | Higher (AI models) | Good (on-device) |
| Context awareness | ✅ Yes | ❌ No |
| Cultural notes | ✅ Yes | ❌ No |
| Formality detection | ✅ Yes | ❌ No |
| Internet required | ✅ Yes | ❌ No |
| Privacy | Sent to server | On-device only |
| Speed | 200-500ms | 50-100ms |
| Cost | Uses quota | Free |
| Offline support | ❌ No | ✅ Yes |

## Troubleshooting

### Translation Returns Low Quality Score
- **Cause**: Short text, ambiguous meaning, or rare language pair
- **Solution**: Provide more context or check cultural notes

### Rate Limit Exceeded
- **Cause**: User exceeded quota for their tier
- **Solution**: Wait for quota reset or upgrade tier

### Network Error
- **Cause**: No internet connection or server issues
- **Solution**: Check connectivity, fall back to Apple Translation

### Feature Disabled
- **Cause**: Feature flags disabled for user's tier
- **Solution**: Check FeatureFlags and show upgrade prompt

## Future Enhancements

- [ ] Streaming translation for long texts
- [ ] Voice tone preservation
- [ ] Domain-specific translations (medical, legal, technical)
- [ ] Translation memory integration
- [ ] A/B testing with multiple providers
- [ ] Real-time translation with WebSocket
- [ ] Offline translation fallback cache
- [ ] Translation glossary support

## Support

For issues or questions:
- Check error codes in `AIServiceError`
- Review translation history for patterns
- Submit quality feedback for improvements
- Contact backend team for API issues

## License

© 2024 GlobalBridge. All rights reserved.
