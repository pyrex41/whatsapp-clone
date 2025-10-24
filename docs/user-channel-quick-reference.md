# User Channel Quick Reference Card

## 🚀 Quick Start

```swift
// Initialize
let manager = UserChannelManager(phoenixManager: phoenixManager)

// Connect
try await manager.connect(userId: "user-123")

// Track presence
await manager.onPresenceChange(for: "other-user") { presence in
    print("\(presence.userId) is \(presence.status)")
}

// Send typing
await manager.sendTypingIndicator(conversationId: "conv-id", isTyping: true)
```

## 📱 UI Components

```swift
// Simple dot indicator
PresenceIndicator(status: .online, size: 12)

// Avatar with presence
PresenceAvatar(avatarUrl: url, status: .online, size: 48)

// Typing indicator
TypingIndicatorView(typingUsers: ["Alice"], currentUserId: "me")

// Chat list row
ChatListPresenceRow(
    userName: "Alice",
    lastMessage: "Hey!",
    timestamp: Date(),
    status: .online,
    isTyping: false,
    unreadCount: 3
)
```

## 🎯 Common Patterns

### Track Multiple Users
```swift
for userId in userIds {
    await manager.onPresenceChange(for: userId) { presence in
        updateUI(for: presence)
    }
}
```

### Handle App Lifecycle
```swift
.onChange(of: scenePhase) { _, newPhase in
    Task {
        switch newPhase {
        case .background: await manager.handleBackground()
        case .active: await manager.handleForeground()
        default: break
        }
    }
}
```

### Privacy Settings
```swift
// Hide online status
await manager.setHideOnlineStatus(true)

// Hide typing
await manager.setHideTypingIndicators(true)

// Check settings
let (hideStatus, hideTyping) = await manager.getPrivacySettings()
```

## 🔍 Status Types

| Status | Color | Usage |
|--------|-------|-------|
| `.online` | Green | User is actively using app |
| `.away` | Orange | App backgrounded or idle |
| `.offline` | Gray | Not connected |

## ⚡ Auto-behaviors

- **Typing indicators**: Auto-stop after 5 seconds
- **Background**: Auto-switch to "away" status
- **Foreground**: Auto-reconnect and set "online"
- **Reconnection**: Up to 10 attempts with 3s delay

## 📊 Format Last Seen

```swift
UserChannelManager.formatLastSeen(date)
// "just now"
// "5 minutes ago"
// "2 hours ago"
// "3 days ago"
// "Dec 25"
```

## 🧪 Testing

```swift
// Mock for tests
class MockPhoenixChannelManager: PhoenixChannelManager {
    var joinUserChannelCalled = false

    override func joinUserChannel(userId: String) async throws {
        joinUserChannelCalled = true
    }
}
```

## ⚠️ Common Issues

**Presence not updating?**
- Check WebSocket connected: `phoenixManager.getConnectionState()`
- Verify channel joined: Look for "✅ [USER_CHANNEL] User channel connected"

**Typing not showing?**
- Register handler BEFORE typing starts
- Check privacy settings: `getPrivacySettings()`

**High battery usage?**
- Ensure `handleBackground()` called when backgrounded
- Check for excessive reconnection attempts (should use backoff)

## 📖 Full Documentation

- Integration Guide: `/docs/ios-user-channel-integration-guide.md`
- Task Summary: `/docs/task-18-user-channel-summary.md`
- API Reference: Check source file comments
