# MessageBubbleView Usage Guide

## Overview

**MessageBubbleView** is a comprehensive SwiftUI component for displaying chat messages with integrated translation features. It supports multiple content types (text, image, video, audio, file), translation toggles, provider badges, loading states, and error handling.

## Features

- ✅ Multiple content types (text, image, video, audio, file, location, contact)
- ✅ Integrated translation with Apple Translation and Backend AI
- ✅ Translation provider badges (Apple, Cloud AI, Hybrid)
- ✅ Loading and error states
- ✅ Context menu with translation actions
- ✅ Copy original and translated text
- ✅ Cultural notes display
- ✅ Confidence score indicators
- ✅ Accessibility support (VoiceOver, Dynamic Type, High Contrast)
- ✅ Dark mode compatible
- ✅ Smooth animations
- ✅ Read receipts integration

## Basic Usage

### Simple Text Message

```swift
import SwiftUI

struct ChatView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MessageBubbleView(
                    message: Message(
                        threadId: threadId,
                        senderId: currentUserId,
                        content: "Hello, how are you?",
                        messageType: .text,
                        status: .sent
                    ),
                    isOwnMessage: true
                )
            }
        }
    }
}
```

### With Translation Service

```swift
MessageBubbleView(
    message: message,
    isOwnMessage: false,
    translationService: UnifiedTranslationService.shared
)
```

### With Read Receipts

```swift
MessageBubbleView(
    message: message,
    isOwnMessage: true,
    readCount: 3,
    totalParticipants: 5
)
```

## Translation Features

### Automatic Translation

Users can translate messages by:

1. **Long press** on message bubble → Shows context menu
2. **Tap "Translate"** → Translates to user's device language
3. **Tap globe icon** → Toggle translation visibility

### Translation Providers

The system automatically selects the best provider:

- **Apple Translation** (🍎): Fast, private, offline-capable (iOS 15+)
- **Backend AI** (☁️): More languages, cultural notes, online
- **Hybrid** (⚖️): Automatic selection based on availability

### Choose Translation Language

```swift
// Context menu provides "Choose Language..." option
// Opens language picker for manual language selection
```

## Content Types

### Text Messages

```swift
Message(
    threadId: threadId,
    senderId: userId,
    content: "Hello!",
    messageType: .text
)
```

### Image Messages

```swift
Message(
    threadId: threadId,
    senderId: userId,
    content: "Check this out!",
    messageType: .image,
    metadata: [
        "image_url": "https://example.com/image.jpg",
        "caption": "Beautiful sunset"
    ]
)
```

### Video Messages

```swift
Message(
    threadId: threadId,
    senderId: userId,
    content: "Video message",
    messageType: .video,
    metadata: [
        "video_url": "https://example.com/video.mp4",
        "caption": "Watch this!"
    ]
)
```

### Audio Messages

```swift
Message(
    threadId: threadId,
    senderId: userId,
    content: "Voice message",
    messageType: .audio,
    metadata: [
        "duration": "0:15"
    ]
)
```

### File Messages

```swift
Message(
    threadId: threadId,
    senderId: userId,
    content: "document.pdf",
    messageType: .file,
    metadata: [
        "file_name": "Important Document.pdf",
        "file_size": "2458632"  // bytes
    ]
)
```

## Translation Overlay

### TranslationOverlayView

Displays detailed translation information:

```swift
TranslationOverlayView(
    originalText: "Hello, how are you?",
    translation: translationResult,
    onClose: {
        // Handle close
    }
)
```

Features:
- Original text with source language badge
- Translated text with target language badge
- Confidence score indicator
- Provider badge
- Cultural notes (expandable)
- Copy buttons for both original and translation

## Provider Badges

### TranslationProviderBadge

Shows which service provided the translation:

```swift
TranslationProviderBadge(provider: "apple-translation")
// Shows: 🍎 Apple

TranslationProviderBadge(provider: "backend-ai")
// Shows: ☁️ Cloud AI

TranslationProviderBadge(provider: "hybrid")
// Shows: ⚖️ Hybrid
```

### Detailed Badge with Privacy Indicator

```swift
DetailedTranslationProviderBadge(
    provider: "apple-translation",
    showPrivacyBadge: true
)
// Shows: 🍎 Apple + 🔒 Private
```

## MessageBubbleViewModel

### Manual Translation

```swift
let viewModel = MessageBubbleViewModel(
    message: message,
    translationService: UnifiedTranslationService.shared
)

// Translate to user's language
await viewModel.translateToUserLanguage()

// Translate to specific language
await viewModel.translate(to: "es", from: "en")

// Clear translation
viewModel.clearTranslation()

// Retry after error
await viewModel.retryTranslation()
```

### Check Translation State

```swift
viewModel.hasTranslation  // Bool
viewModel.isTranslating   // Bool
viewModel.translation     // TranslationResult?
viewModel.translationError // AIServiceError?
```

### Report Bad Translation

```swift
await viewModel.reportBadTranslation()
// Logs analytics event for quality monitoring
```

## Context Menu Actions

The message bubble provides these context menu actions:

### Translation Section
- **Translate** - Translate to user's language
- **Show/Hide Translation** - Toggle translation visibility
- **Choose Language...** - Pick target language

### Standard Actions
- **Copy** - Copy original message
- **Copy Translation** - Copy translated text
- **Reply** - Reply to message

### Quality Actions
- **Report Bad Translation** - Report translation quality issue

## Accessibility

### VoiceOver Support

Messages are fully accessible with VoiceOver:

```swift
// Accessibility label example:
"You: Hello, how are you? Translation: Hola, ¿cómo estás?"

// Accessibility hint:
"Long press to translate"
```

### Dynamic Type

All text scales appropriately with user's text size preference:

```swift
.environment(\.dynamicTypeSize, .xLarge)
```

### Custom Accessibility Actions

- Translate message
- Copy message
- Copy translation
- Reply to message

## Loading States

### Translation in Progress

```swift
// Shows progress indicator
viewModel.isTranslating == true

// Loading spinner appears next to timestamp
```

### Skeleton Loading

```swift
// Image loading placeholder
Rectangle()
    .fill(Color.gray.opacity(0.2))
    .overlay(ProgressView())
```

## Error States

### Network Error

```swift
// Suggests using Apple Translation
"Network error. Try on-device translation?"
```

### Quota Exceeded

```swift
// Shows upgrade prompt
"Translation quota exceeded. Upgrade for unlimited translations."
```

### Unsupported Language

```swift
// Clear error message
"This language pair is not supported by on-device translation."
```

### Translation Failed

```swift
// Shows retry button
"Translation failed. Tap to retry."
```

## Performance

### Lazy Loading

Images and videos load lazily:

```swift
AsyncImage(url: imageURL) { phase in
    // Handle loading states
}
```

### Translation Caching

Translations are automatically cached:

```swift
// Cache key: source_target_content_hash
// TTL: 24 hours
// Storage: Memory (20MB) + Disk (50MB)
```

### Memory Management

```swift
// ViewModel is automatically cleaned up
// Translation sessions reused
// Images loaded on-demand
```

## Customization

### Custom Colors

```swift
// Override bubble colors
let bubbleColor = isOwnMessage ? .blue : .gray

// Override translation overlay background
let translationBg = colorScheme == .dark ? .systemGray6 : .white
```

### Custom Animations

```swift
.transition(.opacity.combined(with: .scale))
.animation(.spring(response: 0.3, dampingFraction: 0.7))
```

## Integration with Chat View

### Full Chat Implementation

```swift
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var messages: [Message] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(messages) { message in
                    MessageBubbleView(
                        message: message,
                        isOwnMessage: message.senderId == currentUserId,
                        readCount: readCounts[message.id] ?? 0,
                        totalParticipants: thread.participantCount,
                        translationService: UnifiedTranslationService.shared
                    )
                    .id(message.id)
                }
            }
            .padding()
        }
        .onAppear {
            loadMessages()
        }
    }
}
```

## Best Practices

### 1. Use Appropriate Content Types

```swift
// Text only for translatable content
.messageType = .text

// Images, videos, audio for media
.messageType = .image
```

### 2. Provide Metadata

```swift
// Always include relevant metadata
.metadata = [
    "image_url": url,
    "caption": caption,
    "file_size": bytes
]
```

### 3. Handle Errors Gracefully

```swift
if let error = viewModel.translationError {
    // Show user-friendly error message
    // Provide retry option
    // Suggest alternatives (Apple vs Backend)
}
```

### 4. Cache Translations

```swift
// Automatically handled by UnifiedTranslationService
// No manual cache management needed
```

### 5. Respect User Preferences

```swift
// Check user's preferred translation provider
@AppStorage("translationProvider") var provider: TranslationProvider

// Use user's device language as default
let targetLang = Locale.current.language.languageCode?.identifier
```

## Testing

### Unit Tests

```swift
import XCTest
@testable import GlobalBridge

class MessageBubbleViewTests: XCTestCase {
    func testTranslation() async {
        let viewModel = MessageBubbleViewModel(
            message: testMessage,
            translationService: UnifiedTranslationService.shared
        )

        await viewModel.translateToUserLanguage()

        XCTAssertNotNil(viewModel.translation)
    }
}
```

### UI Tests

```swift
func testTranslationFlow() throws {
    let messageBubble = app.otherElements["MessageBubble-0"]
    messageBubble.press(forDuration: 1.0)
    app.buttons["Translate"].tap()

    let translationOverlay = app.otherElements["TranslationOverlay"]
    XCTAssertTrue(translationOverlay.waitForExistence(timeout: 5))
}
```

### Accessibility Tests

```swift
func testVoiceOver() throws {
    let messageBubble = app.otherElements["MessageBubble-0"]
    XCTAssertFalse(messageBubble.label.isEmpty)
}
```

## Troubleshooting

### Translation Not Appearing

1. Check message type is `.text`
2. Verify translation service is configured
3. Check network connectivity
4. Review error state in `viewModel.translationError`

### Images Not Loading

1. Verify `image_url` in metadata
2. Check URL is valid
3. Ensure network permissions
4. Review console for errors

### Performance Issues

1. Use `LazyVStack` for message lists
2. Limit visible message count
3. Enable image caching
4. Profile with Instruments

## Related Components

- **UnifiedTranslationService** - Translation coordination
- **AppleTranslationService** - On-device translation
- **BackendTranslationService** - Cloud AI translation
- **TranslationResult** - Translation data model
- **MessageContentView** - Content type rendering

## Support

For issues or questions:
1. Check this documentation
2. Review unit tests for examples
3. Check console logs for errors
4. Contact iOS team

---

**Version:** 1.0.0
**Last Updated:** October 24, 2025
**Status:** ✅ Production Ready
