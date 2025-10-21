# iOS Implementation Guide - Tasks 17, 21, 22

This guide provides instructions for completing the iOS frontend implementation of typing indicators, read receipts, presence indicators, and push notifications.

## Overview

Three features have been implemented:
- **Task 17**: Typing Indicators & Read Receipts
- **Task 21**: Presence Indicators
- **Task 22**: Push Notifications

## Files Created

### Models
- `Core/Models/Phoenix/TypingIndicator.swift` - Typing indicator and read receipt models
- `Core/Models/Phoenix/PhoenixMessage.swift` - Already existed (PhoenixMessage, UserPresence)

### Services
- `Core/Services/NotificationManager.swift` - Push notification management

### Networking (Enhanced)
- `Core/Networking/Phoenix/PhoenixChannelManager.swift` - Added typing and receipt handlers
- `Core/Networking/Phoenix/PhoenixStateManager.swift` - Added state management for typing/receipts/presence

### UI Components
- `UI/Views/TypingIndicatorView.swift` - Animated typing indicator UI
- `UI/Views/PresenceBadgeView.swift` - Online/offline status badges
- `UI/Views/MessageCellView.swift` - Message cell with read receipts
- `UI/Views/ChatView.swift` - Main chat view with all features
- `UI/Views/ThreadListView.swift` - Thread list with presence indicators

### Tests
- `Tests/TypingIndicatorTests.swift`
- `Tests/ReadReceiptTests.swift`
- `Tests/NotificationManagerTests.swift`
- `Tests/PhoenixStateManagerTests.swift`

## Manual Xcode Configuration Required

### 1. Add Push Notification Capability

Open `GlobalBridge.xcodeproj` in Xcode:

1. Select the **GlobalBridge** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **Push Notifications**
5. Add **Background Modes** and enable:
   - Remote notifications
   - Background fetch

### 2. Update Info.plist

Add the following keys to `Info.plist`:

```xml
<key>NSUserNotificationsUsageDescription</key>
<string>We need notification permissions to send you messages and updates.</string>

<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
    <string>fetch</string>
</array>
```

### 3. Add Required Files to Xcode Project

The Swift files have been created but need to be added to the Xcode project:

1. In Xcode, right-click on the appropriate group
2. Select **Add Files to "GlobalBridge"...**
3. Navigate to and select the new files:
   - All files in `UI/Views/`
   - All files in `Core/Services/`
   - All files in `Tests/`
4. Ensure **Copy items if needed** is checked
5. Select **GlobalBridge** target for main files
6. Select **GlobalBridgeTests** target for test files

### 4. APNs Certificate Setup

For push notifications to work:

1. Go to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Create an **Apple Push Notification service SSL** certificate
4. Download and install the certificate
5. Configure your backend to send notifications using this certificate

## Feature Implementation Details

### Task 17: Typing Indicators & Read Receipts

**Typing Indicators:**
- Automatically sent when user types in message input
- Auto-clears after 5 seconds of inactivity
- Displays animated dots with user names
- Handles multiple users typing simultaneously

**Read Receipts:**
- Sent when message is visible on screen
- Shows checkmark indicators (sent/delivered/read)
- Displays read count in group chats
- Color-coded status indicators

**Usage Example:**
```swift
// In ChatView - typing is handled automatically
// When user types, indicator is sent via:
await phoenixState.sendTypingIndicator(
    conversationId: conversationId,
    isTyping: true
)

// Read receipts sent when message appears:
await phoenixState.sendReadReceipt(
    conversationId: conversationId,
    messageId: messageId
)
```

### Task 21: Presence Indicators

**Presence Features:**
- Real-time online/offline status
- Presence badges on avatars (green/orange/gray)
- Last seen timestamps
- Updates via Phoenix Presence

**Usage Example:**
```swift
// Presence is automatically tracked via PhoenixStateManager
let presences = phoenixState.getPresence(for: conversationId)

// Display in UI:
PresenceAvatarView(
    avatarUrl: user.avatarUrl,
    status: presence.status,
    size: 48
)
```

### Task 22: Push Notifications

**Notification Features:**
- Permission request on app launch
- Foreground notifications (banners while app is open)
- Background notifications (when app is closed)
- Notification tap handling with navigation
- Custom notification actions (Reply, Mark as Read)
- Badge count management

**Usage Example:**
```swift
// Request permissions (done in GlobalBridgeApp):
try await notificationManager.requestAuthorization()

// Schedule local notification:
try await notificationManager.scheduleLocalNotification(
    title: "New Message",
    body: "Hello from Alice!",
    conversationId: "conv1",
    messageId: "msg1"
)

// Handle notification tap (done in GlobalBridgeApp):
notificationManager.onNotificationTap { response in
    // Navigate to conversation
}
```

## Testing

### Unit Tests

Run tests in Xcode:
1. Press `Cmd + U` or select **Product > Test**
2. Tests cover:
   - Typing indicator state management
   - Read receipt tracking
   - Notification handling
   - Phoenix state integration

### Simulator Testing

1. **Typing Indicators:**
   - Open ChatView
   - Type in message input
   - Observe "typing..." indicator appears in simulator

2. **Read Receipts:**
   - Send a message
   - Observe checkmark changes from sent → delivered → read

3. **Presence:**
   - View ThreadListView
   - Observe green/gray badges on avatars
   - Check presence status in chat header

4. **Notifications:**
   - Run app in simulator
   - Accept notification permission when prompted
   - Send test notification (see below)
   - Verify banner appears
   - Tap notification to test navigation

### Testing Push Notifications

**Local Notification Test:**
```swift
// Add this to a button in your UI for testing:
Task {
    try? await NotificationManager.shared.scheduleLocalNotification(
        title: "Test Notification",
        body: "This is a test message",
        conversationId: "test_conv",
        messageId: "test_msg",
        delay: 3 // 3 seconds delay
    )
}
```

**Remote Notification Test:**
Use the simulator's push notification feature:
1. Create a file `test_notification.apns`:
```json
{
  "aps": {
    "alert": {
      "title": "New Message",
      "body": "Hello from the backend!"
    },
    "badge": 1,
    "sound": "default"
  },
  "conversation_id": "conv123",
  "message_id": "msg456"
}
```

2. Drag the file onto the simulator
3. Or use terminal:
```bash
xcrun simctl push booted com.globalbridge.app test_notification.apns
```

## Integration with Backend

### Phoenix Channel Events

The iOS app expects these events from the backend:

**Typing Indicators:**
```elixir
# Backend broadcasts:
Phoenix.Channel.broadcast!(socket, "user_typing", %{
  user_id: user_id,
  conversation_id: conversation_id,
  is_typing: true,
  timestamp: DateTime.utc_now()
})
```

**Read Receipts:**
```elixir
# Backend broadcasts:
Phoenix.Channel.broadcast!(socket, "read_receipt", %{
  user_id: user_id,
  conversation_id: conversation_id,
  message_id: message_id,
  read_at: DateTime.utc_now()
})
```

**Presence:**
```elixir
# Backend tracks presence:
Phoenix.Presence.track(socket, user_id, %{
  status: "online",
  online_at: DateTime.utc_now()
})
```

## Architecture Patterns

### State Management
- Uses Swift's `@Observable` macro for reactive state
- `PhoenixStateManager` is the single source of truth
- UI automatically updates when state changes

### Concurrency
- All Phoenix operations use Swift's async/await
- Actor isolation prevents data races
- Main actor ensures UI updates on main thread

### Error Handling
- Graceful degradation when features unavailable
- Proper error logging for debugging
- User-friendly error messages

## Common Issues & Solutions

### Issue: Notifications not appearing
**Solution:** Check notification permissions in Settings app

### Issue: Typing indicator not clearing
**Solution:** Verify 5-second auto-clear timer is working

### Issue: Presence always shows offline
**Solution:** Ensure Phoenix Presence is configured on backend

### Issue: Read receipts not updating
**Solution:** Check Phoenix channel is properly joined

## Next Steps

1. **Add to Xcode Project:**
   - Add all new Swift files to Xcode project
   - Verify build succeeds

2. **Configure Capabilities:**
   - Add Push Notifications capability
   - Add Background Modes capability

3. **Test Features:**
   - Run unit tests
   - Test in simulator
   - Test with backend integration

4. **Production Setup:**
   - Configure APNs certificate
   - Set up production Phoenix server
   - Test on physical device

## Performance Considerations

- Typing indicators auto-clear after 5 seconds to prevent memory leaks
- Read receipts batch updates to minimize network calls
- Presence updates use Phoenix Presence diff for efficiency
- Notifications cleared after viewing to prevent badge count buildup

## Security Considerations

- Device tokens handled securely
- User IDs validated before sending events
- Notification payloads sanitized
- Presence information respects user privacy settings
