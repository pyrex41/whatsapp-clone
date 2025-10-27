# Translation Option 2 Implementation Plan

## Overview
Smart replies appear FAST in user's home language (1-2s). When tapped, if translation is enabled for that thread, iOS translates just that one suggestion (~1s) and inserts the translated text into the composer.

## ✅ Completed (Part 1: Settings & User Language)

### 1. Settings Screen Created
- **File**: `/Features/Settings/SettingsView.swift`
- Replaced debug menu with proper Settings screen
- Gear icon (⚙️) in navigation bar
- Sections:
  - Language (Home Language picker)
  - Account (user info)
  - Notifications (from old debug menu)
  - Developer Tools (DEBUG only)

### 2. User Language Setting
- **AppState**: Added `userLanguage: String = "en"`
- **AppAction**: Added `case setUserLanguage(String)`
- **AppReducer**: Handles language change
- **Supported Languages**:
  - 🇺🇸 English (en)
  - 🇪🇸 Spanish (es)
  - 🇫🇷 French (fr)
  - 🇩🇪 German (de)
  - 🇮🇹 Italian (it)
  - 🇵🇹 Portuguese (pt)
  - 🇨🇳 Chinese (zh)
  - 🇯🇵 Japanese (ja)
  - 🇰🇷 Korean (ko)
  - 🇸🇦 Arabic (ar)

### 3. UI Integration
- **ThreadsListScreen**: Settings button replaces debug menu
- **ThreadsListCompactView**: Same for iPhone layout
- Removed `#if DEBUG` wrappers - Settings now available in all builds

## 🔄 Next Steps (Part 2: Smart Reply Translation Flow)

### 1. Remove Translation Toggle from Suggestions
**Files to modify**:
- `SmartReplySuggestion.swift` - Remove `translatedText` field
- `SmartReplyComposerView.swift` - Remove 🌐 globe button and toggle state
- Revert callback from `(SmartReplySuggestion, String, Int)` to `(SmartReplySuggestion, Int)`

### 2. Add Thread-Level Formality Preference (Local Storage)
**Purpose**: Remember user's last formality choice per thread

**Implementation**:
```swift
// Store in UserDefaults or local database
struct ThreadFormalityPreference: Codable {
    let threadId: String
    let formality: TranslationFormality // informal, neutral, formal
    let lastUsed: Date
}
```

**Storage**:
- Key: `"thread_formality_\(threadId)"`
- Default: `.neutral`
- Update when user picks formality from translation preview

### 3. Implement Translate-on-Tap
**File**: `ChatScreen.swift`

**Flow**:
```swift
onSuggestionTap: { suggestion, timeMs in
    // Check if translation enabled for this thread
    guard let threadPref = store.state.translationPreferences[threadId],
          threadPref.enabled,
          let targetLang = threadPref.targetLanguage else {
        // No translation - insert suggestion.content directly
        store.send(.acceptSuggestion(..., modifiedContent: nil))
        return
    }

    // Get last formality used for this thread (default: neutral)
    let formality = getFormalityPreference(threadId: threadId) ?? .neutral

    // Show loading state
    store.send(.setTranslatingMessage(true))

    // Translate this ONE suggestion
    Task {
        let translated = try await phoenixManager.translate(
            text: suggestion.content,
            sourceLanguage: store.state.userLanguage,
            targetLanguage: targetLang,
            formality: formality
        )

        // Insert translated text
        store.send(.setTranslatingMessage(false))
        store.send(.acceptSuggestion(..., modifiedContent: translated))
    }
}
```

### 4. Add Loading State UI
**File**: `MessageComposerView.swift` or `ChatScreen.swift`

```swift
// Add to AppState
var isTranslatingMessage: Bool = false

// Add action
case setTranslatingMessage(Bool)

// UI
if store.state.isTranslatingMessage {
    HStack {
        ProgressView()
            .scaleEffect(0.8)
        Text("Translating...")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color(.systemGray6))
}
```

### 5. Add Error Toast
**Fallback Behavior**: Insert original text + show error toast

```swift
do {
    let translated = try await phoenixManager.translate(...)
    // Insert translated text
} catch {
    // Insert original English text anyway
    store.send(.acceptSuggestion(..., modifiedContent: nil))

    // Show error toast
    store.send(.showToast(
        message: "Translation failed. Sent in \(store.state.userLanguage).",
        type: .error
    ))
}
```

### 6. Update Smart Reply Fetch
**File**: Backend integration in PhoenixChannelManager

**Current**:
```swift
phoenixManager.fetchSmartReplies(threadId: threadId)
```

**New**:
```swift
phoenixManager.fetchSmartReplies(
    threadId: threadId,
    userLanguage: store.state.userLanguage  // Pass user's language
)
```

**Backend Change** (Elixir):
```elixir
def smart_reply(conn, %{"thread_id" => thread_id, "user_language" => user_lang} = params) do
  {:ok, suggestions} = AIService.generate_smart_replies(
    thread_id: thread_id,
    language: user_lang  # Generate in user's language
  )

  json(conn, %{suggestions: suggestions})
end
```

### 7. Update All Tests
Update test signatures from:
```swift
onSuggestionTap: { suggestion, textToInsert, timeMs in ... }
```

To:
```swift
onSuggestionTap: { suggestion, timeMs in ... }
```

**Files**:
- SmartReplyErrorStateTests.swift
- SuggestionDismissalTests.swift
- ProactiveSuggestionVisualTests.swift
- SmartReplyTimeTrackingTests.swift

## User Experience Timeline

### Scenario 1: No Translation (English → English)
```
1. User sees suggestions in English (1-2s)
2. User taps "Thanks!"
3. "Thanks!" inserted into composer INSTANTLY
4. User hits send
```

### Scenario 2: With Translation (English → Spanish)
```
1. User sees suggestions in English (1-2s)
2. User taps "Thanks!"
3. Loading spinner appears (~1s)
4. "¡Gracias!" inserted into composer
5. User reviews translation
6. User hits send
```

## Formality Preference Flow

```
1. First time translating in a thread
   → Uses default "neutral" formality
   → Stores: thread_formality_abc123 = "neutral"

2. User manually changes formality in translation preview
   → Updates: thread_formality_abc123 = "informal"

3. Next time user taps a suggestion in same thread
   → Automatically uses "informal" (remembered preference)
```

## Implementation Order

1. ✅ Settings screen + user language
2. 🔄 Remove translation toggle from suggestions
3. 🔄 Add thread formality preference (local storage)
4. 🔄 Implement translate-on-tap logic
5. 🔄 Add loading state UI
6. 🔄 Add error toast
7. 🔄 Update backend integration
8. 🔄 Update all tests

## Questions Answered

**Q: Where does home language setting live?**
A: Settings page (gear icon) → Language section → Home Language picker

**Q: How to handle formality?**
A: Thread-level setting stored locally. Defaults to neutral, remembers user's last choice per thread.

**Q: Fallback if translation fails?**
A: Insert original English text + show error toast

**Q: Should iOS cache translations?**
A: Future optimization - can cache common phrases like "Thanks!" → "¡Gracias!"
