# Feature Flags Usage Guide

Quick reference for integrating the Feature Flags system into iOS UI components.

## Basic Usage

### Import
```swift
// Feature flags are automatically available through the singleton
// No import needed - already accessible throughout the app
```

### Check if Feature is Available
```swift
// Simple boolean check
if FeatureFlags.shared.hasFeature(.translationEnabled) {
    // Show translation button
    showTranslationButton()
}

if FeatureFlags.shared.hasFeature(.threadSummarization) {
    // Enable summarization feature
    enableThreadSummary()
}

if FeatureFlags.shared.hasFeature(.semanticSearch) {
    // Show semantic search option
    showSemanticSearchUI()
}
```

### Check Translation Quota
```swift
// Get current limit
if let limit = FeatureFlags.shared.getTranslationLimit() {
    let remaining = limit - currentTranslationCount
    statusLabel.text = "\(remaining) translations remaining"
} else {
    statusLabel.text = "Unlimited translations"
}

// Check if user can translate
if FeatureFlags.shared.hasTranslationCapacity(currentUsage: translationCount) {
    // Allow translation
    translateButton.isEnabled = true
} else {
    // Show upgrade prompt
    showUpgradePrompt()
}
```

### Get Current Tier
```swift
let tier = FeatureFlags.shared.getCurrentTier()

switch tier {
case .free:
    headerLabel.text = "Free Plan"
case .pro:
    headerLabel.text = "Pro Plan"
case .enterprise:
    headerLabel.text = "Enterprise Plan"
}
```

## App Launch Integration

### GlobalBridgeApp.swift
```swift
import SwiftUI

@main
struct GlobalBridgeApp: App {
    @StateObject private var authManager = AuthManager.shared

    init() {
        // Fetch features on app launch
        Task {
            await authManager.ensureSessionRestored()

            if authManager.isAuthenticated {
                do {
                    try await FeatureFlags.shared.fetchFeatures()
                    print("✅ Features loaded from backend")
                } catch {
                    print("⚠️  Using cached features: \(error)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}
```

## SwiftUI Integration

### Reactive UI Updates
```swift
import SwiftUI
import Combine

struct TranslationView: View {
    @State private var translationEnabled = false
    @State private var translationLimit: Int?
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack {
            if translationEnabled {
                TranslationButton()

                if let limit = translationLimit {
                    Text("\(limit) translations remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                UpgradePromptView()
            }
        }
        .onAppear {
            updateFeatures()
            observeFeatureChanges()
        }
    }

    private func updateFeatures() {
        translationEnabled = FeatureFlags.shared.hasFeature(.translationEnabled)
        translationLimit = FeatureFlags.shared.getTranslationLimit()
    }

    private func observeFeatureChanges() {
        NotificationCenter.default
            .publisher(for: .featureFlagsUpdated)
            .sink { _ in
                updateFeatures()
            }
            .store(in: &cancellables)
    }
}
```

### Conditional Feature Display
```swift
struct ChatView: View {
    var body: some View {
        VStack {
            MessageList()

            // Show thread summary only if feature is enabled
            if FeatureFlags.shared.hasFeature(.threadSummarization) {
                ThreadSummaryCard()
            }

            // Show semantic search only if enabled
            if FeatureFlags.shared.hasFeature(.semanticSearch) {
                SemanticSearchBar()
            }

            MessageInput()
        }
    }
}
```

## UIKit Integration

### ViewController Usage
```swift
import UIKit

class ChatViewController: UIViewController {
    private var translationButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup UI based on features
        setupTranslationButton()

        // Observe feature updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(featuresUpdated),
            name: .featureFlagsUpdated,
            object: nil
        )
    }

    private func setupTranslationButton() {
        let isEnabled = FeatureFlags.shared.hasFeature(.translationEnabled)
        translationButton.isHidden = !isEnabled

        if isEnabled, let limit = FeatureFlags.shared.getTranslationLimit() {
            translationButton.setTitle("Translate (\(limit) left)", for: .normal)
        }
    }

    @objc private func featuresUpdated() {
        DispatchQueue.main.async {
            self.setupTranslationButton()
        }
    }
}
```

## Usage Tracking

### Track Translation Usage
```swift
class TranslationManager {
    private var translationCount: Int {
        get { UserDefaults.standard.integer(forKey: "translation_count") }
        set { UserDefaults.standard.set(newValue, forKey: "translation_count") }
    }

    func canTranslate() -> Bool {
        return FeatureFlags.shared.hasTranslationCapacity(currentUsage: translationCount)
    }

    func performTranslation() async throws {
        guard canTranslate() else {
            throw TranslationError.quotaExceeded
        }

        // Perform actual translation
        // ...

        // Increment usage counter
        translationCount += 1
    }

    func resetUsageIfNeeded() {
        // Reset monthly on the 1st
        let calendar = Calendar.current
        if calendar.component(.day, from: Date()) == 1 {
            translationCount = 0
        }
    }
}
```

## Settings Screen Integration

### Tier Display
```swift
struct SettingsView: View {
    @State private var currentTier: FeatureFlags.UserTier = .free

    var body: some View {
        List {
            Section("Subscription") {
                HStack {
                    Text("Current Plan")
                    Spacer()
                    Text(currentTier.displayName)
                        .foregroundColor(.secondary)
                }

                if currentTier != .enterprise {
                    Button("Upgrade Plan") {
                        showUpgradeOptions()
                    }
                }
            }

            Section("Features") {
                FeatureRow(
                    name: "AI Translation",
                    isEnabled: FeatureFlags.shared.hasFeature(.translationEnabled),
                    limit: FeatureFlags.shared.getTranslationLimit()
                )

                FeatureRow(
                    name: "Thread Summarization",
                    isEnabled: FeatureFlags.shared.hasFeature(.threadSummarization)
                )

                FeatureRow(
                    name: "Semantic Search",
                    isEnabled: FeatureFlags.shared.hasFeature(.semanticSearch)
                )
            }
        }
        .onAppear {
            currentTier = FeatureFlags.shared.getCurrentTier()
        }
    }
}

struct FeatureRow: View {
    let name: String
    let isEnabled: Bool
    var limit: Int? = nil

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if isEnabled {
                if let limit = limit {
                    Text("\(limit) per month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.gray)
            }
        }
    }
}
```

## Error Handling

### Handling Fetch Errors
```swift
func refreshFeatures() async {
    do {
        try await FeatureFlags.shared.fetchFeatures()
        showSuccessMessage("Features updated")
    } catch FeatureFlags.FeatureFlagsError.notAuthenticated {
        // Prompt user to login
        showLoginPrompt()
    } catch FeatureFlags.FeatureFlagsError.serviceError(let serviceError) {
        // Handle specific service errors
        if case .unauthorized = serviceError {
            // Token expired, refresh auth
            await refreshAuthentication()
        } else if case .networkError = serviceError {
            // Network issue, use cached features
            showMessage("Using offline features")
        }
    } catch {
        // Unknown error
        showError("Failed to update features: \(error.localizedDescription)")
    }
}
```

## Background Sync

### Periodic Feature Refresh
```swift
class FeatureSyncManager {
    private var timer: Timer?

    func startPeriodicSync(interval: TimeInterval = 3600) { // 1 hour
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.syncFeatures()
        }
    }

    private func syncFeatures() {
        Task {
            do {
                try await FeatureFlags.shared.fetchFeatures()
                print("✅ Background feature sync successful")
            } catch {
                print("⚠️  Background sync failed: \(error)")
                // Cached features remain available
            }
        }
    }

    func stopSync() {
        timer?.invalidate()
        timer = nil
    }
}
```

## Testing Support

### Mock Features for Testing
```swift
// In your test setup
class FeatureFlagsTests: XCTestCase {
    override func setUp() {
        super.setUp()

        // Use custom service with mock URLSession
        let mockSession = URLSession(configuration: .ephemeral)
        let mockService = FeatureFlagsService(
            baseURL: URL(string: "http://localhost:4000")!,
            session: mockSession,
            authManager: MockAuthManager()
        )

        // Test feature flags with mock service
    }
}
```

## Best Practices

### 1. Check Features at Decision Points
```swift
// ❌ Bad - Check once at app start
let hasTranslation = FeatureFlags.shared.hasFeature(.translationEnabled)

// ✅ Good - Check when needed
func translateButtonTapped() {
    guard FeatureFlags.shared.hasFeature(.translationEnabled) else {
        showUpgradePrompt()
        return
    }
    performTranslation()
}
```

### 2. Handle Quota Gracefully
```swift
// ✅ Show remaining quota before action
func showTranslationUI() {
    if let limit = FeatureFlags.shared.getTranslationLimit() {
        let remaining = limit - currentUsage
        if remaining <= 0 {
            showQuotaExhaustedAlert()
        } else if remaining <= 5 {
            showLowQuotaWarning(remaining: remaining)
        }
    }
}
```

### 3. Observe Feature Changes
```swift
// ✅ React to tier upgrades/downgrades
NotificationCenter.default.addObserver(
    forName: .featureFlagsUpdated,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.updateUIForCurrentFeatures()
}
```

### 4. Fallback to Cached Features
```swift
// ✅ Don't block UI on network calls
Task {
    // Start with cached features (instant)
    updateUI()

    // Then sync with backend (background)
    try? await FeatureFlags.shared.fetchFeatures()
    // UI updates automatically via NotificationCenter
}
```

---

## Available Features

| Feature | Enum Case | Description |
|---------|-----------|-------------|
| Translation | `.translationEnabled` | AI-powered message translation |
| Thread Summary | `.threadSummarization` | Generate conversation summaries |
| Semantic Search | `.semanticSearch` | AI-powered message search |
| E2EE | `.e2ee` | End-to-end encryption |
| Voice Calls | `.voiceCalls` | Voice calling feature |
| Video Calls | `.videoCalls` | Video calling feature |
| File Sharing | `.fileSharing` | File attachment support |

See `FeatureFlags.Feature` enum for complete list.

---

**Need help?** Check the implementation summary at `/docs/feature-flags-implementation-summary.md`
