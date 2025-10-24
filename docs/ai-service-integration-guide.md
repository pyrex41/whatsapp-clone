# AIService Integration Guide

## Quick Start

### 1. Import and Use

```swift
import SwiftUI

// AIService is ready to use immediately via singleton
let aiService = AIService.shared
```

### 2. Basic Translation Example

```swift
struct MessageTranslationButton: View {
    let message: Message
    @StateObject private var aiService = AIService.shared
    @State private var translation: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(message.content)

            if let translation = translation {
                Text(translation)
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }

            Button("Translate to Spanish") {
                Task {
                    do {
                        let result = try await aiService.translate(
                            text: message.content,
                            targetLanguage: "es"
                        )
                        translation = result.translatedText
                    } catch {
                        print("Translation failed: \(error.localizedDescription)")
                    }
                }
            }
            .disabled(aiService.isProcessing)
        }
    }
}
```

### 3. Thread Summary in ConversationView

```swift
struct ConversationView: View {
    let thread: Thread
    @StateObject private var aiService = AIService.shared
    @State private var summary: String?
    @State private var showSummary = false

    var body: some View {
        VStack {
            // Existing conversation UI

            if showSummary, let summary = summary {
                Text(summary)
                    .padding()
                    .background(Color.blue.opacity(0.1))
            }

            Button("Summarize Conversation") {
                Task {
                    do {
                        let result = try await aiService.summarizeThread(
                            threadId: thread.id,
                            maxLength: 200
                        )
                        summary = result.summary
                        showSummary = true
                    } catch AIServiceError.featureDisabled {
                        // Show upgrade prompt
                    } catch {
                        print("Summarization failed: \(error.localizedDescription)")
                    }
                }
            }
            .disabled(aiService.isProcessing)
        }
    }
}
```

### 4. Semantic Search in SearchView

```swift
struct MessageSearchView: View {
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @StateObject private var aiService = AIService.shared

    var body: some View {
        VStack {
            TextField("Search messages...", text: $query)
                .textFieldStyle(.roundedBorder)

            Button("Search") {
                Task {
                    do {
                        results = try await aiService.searchSemantic(
                            query: query,
                            limit: 20,
                            recencyBias: true
                        )
                    } catch {
                        print("Search failed: \(error.localizedDescription)")
                    }
                }
            }
            .disabled(aiService.isProcessing || query.isEmpty)

            if aiService.isProcessing {
                ProgressView()
            }

            List(results, id: \.messageId) { result in
                VStack(alignment: .leading) {
                    Text(result.content)
                    Text("Score: \(result.relevanceScore, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}
```

### 5. Task Extraction in ActionItemsView

```swift
struct ActionItemsView: View {
    let thread: Thread
    @StateObject private var aiService = AIService.shared
    @State private var tasks: TaskExtractionResult?

    var body: some View {
        VStack(alignment: .leading) {
            Button("Extract Action Items") {
                Task {
                    do {
                        tasks = try await aiService.extractTasks(
                            threadId: thread.id
                        )
                    } catch {
                        print("Extraction failed: \(error.localizedDescription)")
                    }
                }
            }
            .disabled(aiService.isProcessing)

            if let tasks = tasks {
                Section("Tasks") {
                    ForEach(tasks.tasks, id: \.self) { task in
                        Text("• \(task)")
                    }
                }

                Section("Deadlines") {
                    ForEach(tasks.deadlines, id: \.self) { deadline in
                        Text("📅 \(deadline)")
                    }
                }

                Section("Decisions") {
                    ForEach(tasks.decisions, id: \.self) { decision in
                        Text("✅ \(decision)")
                    }
                }
            }

            if aiService.isProcessing {
                ProgressView("Analyzing conversation...")
            }
        }
        .padding()
    }
}
```

## Error Handling Patterns

### 1. Comprehensive Error Handling

```swift
func translateMessage(_ text: String, to language: String) async {
    do {
        let result = try await AIService.shared.translate(
            text: text,
            targetLanguage: language
        )
        // Use result
        print("Translation: \(result.translatedText)")

    } catch AIServiceError.notAuthenticated {
        // User not logged in
        showLoginAlert()

    } catch AIServiceError.featureDisabled(let feature) {
        // Feature not available for tier
        showUpgradeAlert(for: feature)

    } catch AIServiceError.rateLimitExceeded(let retryAfter) {
        // Rate limited
        if let delay = retryAfter {
            showAlert("Please wait \(Int(delay)) seconds")
        } else {
            showAlert("Please try again later")
        }

    } catch AIServiceError.invalidInput(let reason) {
        // Invalid input
        showAlert("Invalid input: \(reason)")

    } catch AIServiceError.networkError {
        // Network issue
        showAlert("Network error. Please check your connection.")

    } catch {
        // Generic error
        showAlert("An error occurred: \(error.localizedDescription)")
    }
}
```

### 2. SwiftUI Alert Integration

```swift
struct TranslationView: View {
    @StateObject private var aiService = AIService.shared
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        // Your UI
        .alert("Error", isPresented: $showError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .task {
            do {
                _ = try await aiService.translate(
                    text: "Hello",
                    targetLanguage: "es"
                )
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}
```

## Observing State

### 1. Loading Indicator

```swift
struct AIFeatureView: View {
    @StateObject private var aiService = AIService.shared

    var body: some View {
        ZStack {
            // Your content

            if aiService.isProcessing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                ProgressView("Processing...")
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
            }
        }
    }
}
```

### 2. Request Counter (Analytics)

```swift
struct AnalyticsView: View {
    @StateObject private var aiService = AIService.shared

    var body: some View {
        VStack {
            Text("AI Requests: \(aiService.requestCount)")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Reset Counter") {
                aiService.resetRequestCount()
            }
        }
    }
}
```

## Feature Flag Integration

### 1. Check Before Showing UI

```swift
struct AIFeaturesMenu: View {
    @StateObject private var featureFlags = FeatureFlags.shared

    var body: some View {
        Menu("AI Features") {
            if featureFlags.hasFeature(.translationEnabled) {
                Button("Translate") { /* ... */ }
            }

            if featureFlags.hasFeature(.threadSummarization) {
                Button("Summarize") { /* ... */ }
            }

            if featureFlags.hasFeature(.semanticSearch) {
                Button("Semantic Search") { /* ... */ }
            }
        }
    }
}
```

### 2. Show Upgrade Prompt

```swift
struct UpgradePromptView: View {
    let feature: String

    var body: some View {
        VStack {
            Text("Upgrade Required")
                .font(.headline)

            Text("The '\(feature)' feature is not available on your current plan.")
                .padding()

            Button("Upgrade to Pro") {
                // Navigate to upgrade flow
            }
        }
    }
}
```

## Testing

### 1. Mock Service for Tests

```swift
class MockAIService: AIService {
    var shouldSucceed = true
    var mockTranslation = "Hola mundo"

    override func translate(
        text: String,
        sourceLanguage: String?,
        targetLanguage: String
    ) async throws -> TranslationResult {
        if !shouldSucceed {
            throw AIServiceError.networkError(NSError(domain: "", code: -1))
        }

        return TranslationResult(
            originalText: text,
            translatedText: mockTranslation,
            sourceLanguage: sourceLanguage ?? "auto",
            targetLanguage: targetLanguage,
            confidence: 0.95
        )
    }
}
```

### 2. Unit Test Example

```swift
import XCTest
@testable import GlobalBridge

class AIServiceTests: XCTestCase {
    func testTranslation() async throws {
        let service = MockAIService()
        service.shouldSucceed = true
        service.mockTranslation = "Bonjour"

        let result = try await service.translate(
            text: "Hello",
            targetLanguage: "fr"
        )

        XCTAssertEqual(result.translatedText, "Bonjour")
        XCTAssertEqual(result.targetLanguage, "fr")
    }

    func testTranslationFailure() async {
        let service = MockAIService()
        service.shouldSucceed = false

        do {
            _ = try await service.translate(
                text: "Hello",
                targetLanguage: "es"
            )
            XCTFail("Should have thrown error")
        } catch {
            // Expected
            XCTAssertTrue(error is AIServiceError)
        }
    }
}
```

## App Launch Integration

### 1. Initialize on App Start

```swift
@main
struct GlobalBridgeApp: App {
    init() {
        // AIService initializes automatically as singleton
        // No explicit setup needed

        // Optionally, you can access it to trigger initialization
        _ = AIService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 2. Fetch Feature Flags on Launch

```swift
@main
struct GlobalBridgeApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var featureFlags = FeatureFlags.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Wait for auth
                    await authManager.ensureSessionRestored()

                    // Fetch feature flags
                    if authManager.isAuthenticated {
                        try? await featureFlags.fetchFeatures()
                    }
                }
        }
    }
}
```

## Production Checklist

Before deploying AI features:

- [ ] Verify backend URL is correct for environment
- [ ] Test all AI methods with real backend
- [ ] Test error handling paths
- [ ] Test rate limiting behavior
- [ ] Verify Auth0 integration works
- [ ] Test feature flag restrictions
- [ ] Add analytics for AI usage
- [ ] Add user feedback mechanisms
- [ ] Test offline behavior
- [ ] Verify request timeouts are appropriate
- [ ] Add logging for debugging
- [ ] Test with different tier levels
- [ ] Verify all error messages are user-friendly

## Performance Tips

1. **Batch Operations**: If translating multiple messages, wait for one to complete before starting the next to avoid overwhelming the API.

2. **Cache Results**: Consider caching translations locally to avoid repeated requests:
   ```swift
   class TranslationCache {
       private var cache: [String: String] = [:]

       func translation(for text: String, language: String) -> String? {
           return cache["\(text)-\(language)"]
       }

       func cache(text: String, language: String, translation: String) {
           cache["\(text)-\(language)"] = translation
       }
   }
   ```

3. **Debounce User Input**: For search, debounce queries to avoid excessive API calls:
   ```swift
   @State private var searchTask: Task<Void, Never>?

   func search(_ query: String) {
       searchTask?.cancel()
       searchTask = Task {
           try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
           guard !Task.isCancelled else { return }

           // Perform search
           let results = try? await AIService.shared.searchSemantic(
               query: query,
               limit: 20
           )
       }
   }
   ```

4. **Background Processing**: For non-urgent operations, consider using background tasks:
   ```swift
   Task.detached(priority: .background) {
       let result = try? await AIService.shared.summarizeThread(
           threadId: threadId
       )
       // Update UI on main thread
       await MainActor.run {
           // Update state
       }
   }
   ```

## Troubleshooting

### Issue: Requests timing out

```swift
// Check backend connectivity
curl http://localhost:4000/api/health

// If backend is down, start it
cd globalbridge_backend
mix phx.server
```

### Issue: "Not authenticated" errors

```swift
// Verify user is logged in
if !AuthManager.shared.isAuthenticated {
    await AuthManager.shared.login()
}

// Check token is valid
let token = await AuthManager.shared.getAccessToken()
print("Token: \(token ?? "nil")")
```

### Issue: "Feature disabled" errors

```swift
// Check feature flags
let hasTranslation = FeatureFlags.shared.hasFeature(.translationEnabled)
print("Translation enabled: \(hasTranslation)")

// Fetch latest features
try? await FeatureFlags.shared.fetchFeatures()
```

### Issue: Rate limiting

```swift
// Wait for rate limit to reset
// The error message includes retry-after time

// Or upgrade user's tier to increase limits
```

## Next Steps

Now that AIService is implemented, you can:

1. Build translation UI in messages
2. Add summarization button to conversations
3. Implement semantic search feature
4. Create action items extraction view
5. Add tone indicators to messages
6. Integrate with notifications
7. Add analytics tracking
8. Implement usage quotas display

---

**Ready to use!** The AIService is production-ready and can be integrated into your app immediately.
