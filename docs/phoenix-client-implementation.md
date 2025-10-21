# Phoenix Channel Client Implementation (iOS)

## Overview

This document describes the Phoenix Channel client implementation for real-time message synchronization in the iOS GlobalBridge application.

## Architecture

### Components

1. **PhoenixConfig**: Configuration management for Phoenix connections
2. **PhoenixChannelManager**: Core WebSocket connection manager (actor)
3. **PhoenixStateManager**: Observable state management integration
4. **PhoenixMessage**: Message and event models
5. **UserPresence**: Presence tracking models

## Files Created

```
clients/ios/GlobalBridge/
├── Core/
│   ├── Networking/Phoenix/
│   │   ├── PhoenixConfig.swift
│   │   ├── PhoenixChannelManager.swift
│   │   └── PhoenixStateManager.swift
│   └── Models/Phoenix/
│       └── PhoenixMessage.swift
└── Tests/Phoenix/
    ├── PhoenixChannelManagerTests.swift
    └── PhoenixStateManagerTests.swift
```

## Key Features

### 1. Connection Management

- **Automatic reconnection** with configurable attempts and delay
- **Connection state monitoring** (disconnected, connecting, connected, reconnecting, error)
- **Secure authentication** via token-based auth
- **Heartbeat monitoring** for connection health

### 2. Channel Operations

- **Join/leave conversations** with error handling
- **Message sending** with confirmation
- **Message updates** and deletions
- **Read receipts** tracking

### 3. Real-time Events

- **New message notifications**
- **Message updates** (edits, status changes)
- **Typing indicators**
- **Presence tracking** (online/offline/away)
- **User join/leave events**

### 4. State Management

- **Observable pattern** using Swift's Observation framework
- **MainActor isolation** for UI safety
- **Automatic state updates** via async handlers
- **Message ordering** by timestamp
- **Presence aggregation** by conversation

## Usage Examples

### Basic Setup

```swift
import GlobalBridge

// Create state manager
let stateManager = PhoenixStateManager(config: .development)

// In SwiftUI View
struct ContentView: View {
    @State private var phoenixState = PhoenixStateManager.preview

    var body: some View {
        // Use phoenixState.messages, phoenixState.connectionState, etc.
    }
}
```

### Connecting to Phoenix

```swift
// Connect with authentication
try await stateManager.connect(authToken: "user-jwt-token")

// Join a conversation
try await stateManager.joinConversation("conversation-123")
```

### Sending Messages

```swift
// Send a message
try await stateManager.sendMessage(
    conversationId: "conversation-123",
    content: "Hello, World!"
)

// Reply to a message
try await stateManager.sendMessage(
    conversationId: "conversation-123",
    content: "This is a reply",
    replyToId: "message-456"
)
```

### Observing State

```swift
// Messages are automatically updated
let messages = stateManager.getMessages(for: "conversation-123")

// Presence is automatically tracked
let presence = stateManager.getPresence(for: "conversation-123")

// Connection state is observable
switch stateManager.connectionState {
case .connected:
    // Show connected UI
case .reconnecting:
    // Show reconnecting indicator
case .error(let error):
    // Show error message
default:
    break
}
```

## Configuration

### Development

```swift
PhoenixConfig.development
// - URL: ws://localhost:4000/socket
// - Logging: enabled
// - Max reconnect: 5 attempts
// - Reconnect delay: 2 seconds
```

### Production

```swift
PhoenixConfig.production
// - URL: wss://api.globalbridge.app/socket
// - Logging: disabled
// - Max reconnect: 10 attempts
// - Reconnect delay: 5 seconds
```

### Custom

```swift
let config = PhoenixConfig(
    socketURL: URL(string: "wss://custom.example.com/socket")!,
    authToken: "optional-token",
    connectionTimeout: 15,
    heartbeatInterval: 45,
    maxReconnectAttempts: 8,
    reconnectDelay: 3,
    enableLogging: true
)
```

## Message Models

### PhoenixMessage

```swift
struct PhoenixMessage {
    let id: String
    let conversationId: String
    let senderId: String
    let content: String
    let timestamp: Date
    let status: MessageStatus // sending, sent, delivered, read, failed
    let metadata: MessageMetadata? // replies, edits, attachments
}
```

### UserPresence

```swift
struct UserPresence {
    let userId: String
    let status: PresenceStatus // online, offline, away
    let lastSeen: Date?
}
```

## Error Handling

All errors conform to `LocalizedError` for user-friendly messages:

- `PhoenixError.notConnected` - Attempting operations without connection
- `PhoenixError.connectionTimeout` - Connection took too long
- `PhoenixError.channelNotJoined` - Channel operation without join
- `PhoenixError.joinFailed` - Failed to join channel
- `PhoenixError.sendFailed` - Failed to send message
- `PhoenixError.decodingFailed` - Failed to parse server response
- `PhoenixError.timeout` - Request timeout

## Testing

Comprehensive test coverage for:

- Connection lifecycle
- Channel join/leave operations
- Message sending and receiving
- Error scenarios
- State management updates
- Configuration validation

Run tests:
```bash
cd clients/ios/GlobalBridge
xcodebuild test -scheme GlobalBridge
```

## Integration with Backend

This client is designed to work with the Phoenix backend implemented in **Task 3**:

- **Socket endpoint**: `/socket`
- **Channel topic**: `conversation:{id}`
- **Events**: `new_message`, `message_updated`, `user_typing`, `presence_diff`
- **Push events**: `new_message`, `mark_read`

## Dependencies

- **SwiftPhoenixClient** (5.3.5+): WebSocket and Phoenix protocol implementation
- **Swift 6.0**: Concurrency and Observation framework
- **iOS 18.6+**: Deployment target

## Thread Safety

- `PhoenixChannelManager` is an **actor** for safe concurrent access
- `PhoenixStateManager` uses **@MainActor** for UI safety
- All state updates are serialized and thread-safe

## Memory Management

- Weak references to prevent retain cycles
- Automatic cleanup on deinit
- Task cancellation on cleanup
- Channel cleanup on disconnect

## Performance Considerations

- **Lazy channel joining** - only join when needed
- **Message deduplication** - updates existing messages instead of duplicating
- **Efficient sorting** - messages sorted by timestamp
- **Background state updates** - periodic state polling in background task

## Next Steps

1. **Integration with SwiftUI views** (Task 11)
2. **Local persistence** integration (Task 8)
3. **Push notification** handling (Task 12)
4. **E2E encryption** integration (Task 6)

## Task 10 Completion

All subtasks completed:

- ✅ **10.1**: SwiftPhoenixClient dependency (already in project.pbxproj)
- ✅ **10.2**: PhoenixChannelManager actor structure created
- ✅ **10.3**: Channel connection logic implemented
- ✅ **10.4**: Incoming message event handling implemented
- ✅ **10.5**: State management system integration completed

## Connection Patterns (Stored in Memory)

```javascript
{
  "phoenix_client": {
    "architecture": "actor-based",
    "state_management": "observable",
    "reconnection": "automatic",
    "error_handling": "comprehensive",
    "thread_safety": "actor + MainActor",
    "testing": "unit + integration"
  },
  "patterns": {
    "connection": "async/await with timeout",
    "channel_join": "checked continuation",
    "message_send": "promise-based",
    "state_updates": "observation framework",
    "presence": "diff-based tracking"
  }
}
```
