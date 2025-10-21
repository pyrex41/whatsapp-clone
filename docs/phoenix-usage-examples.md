# Phoenix Channel Client - Usage Examples

## Quick Start

### 1. Basic Setup in SwiftUI App

```swift
import SwiftUI
import GlobalBridge

@main
struct GlobalBridgeApp: App {
    @State private var phoenixState = PhoenixStateManager(config: .development)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(phoenixState)
                .task {
                    do {
                        try await phoenixState.connect(authToken: "your-jwt-token")
                    } catch {
                        print("Failed to connect: \(error)")
                    }
                }
        }
    }
}
```

### 2. Chat View Integration

```swift
import SwiftUI

struct ChatView: View {
    @Environment(PhoenixStateManager.self) private var phoenix
    let conversationId: String
    @State private var messageText = ""

    var messages: [PhoenixMessage] {
        phoenix.getMessages(for: conversationId)
    }

    var body: some View {
        VStack {
            // Connection status
            ConnectionStatusBanner(state: phoenix.connectionState)

            // Message list
            ScrollView {
                LazyVStack {
                    ForEach(messages) { message in
                        MessageRow(message: message)
                    }
                }
            }

            // Message input
            HStack {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)

                Button("Send") {
                    Task {
                        try? await phoenix.sendMessage(
                            conversationId: conversationId,
                            content: messageText
                        )
                        messageText = ""
                    }
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .task {
            try? await phoenix.joinConversation(conversationId)
        }
    }
}
```

### 3. Connection Status Banner

```swift
import SwiftUI

struct ConnectionStatusBanner: View {
    let state: PhoenixConnectionState

    var body: some View {
        Group {
            switch state {
            case .connected:
                EmptyView()

            case .connecting:
                HStack {
                    ProgressView()
                    Text("Connecting...")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))

            case .reconnecting:
                HStack {
                    ProgressView()
                    Text("Reconnecting...")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))

            case .disconnected:
                Text("Disconnected")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))

            case .error(let error):
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error.localizedDescription)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
            }
        }
    }
}
```

### 4. Message Row Component

```swift
import SwiftUI

struct MessageRow: View {
    let message: PhoenixMessage
    @State private var currentUserId = "current-user-id" // Get from auth

    var isCurrentUser: Bool {
        message.senderId == currentUserId
    }

    var body: some View {
        HStack {
            if isCurrentUser { Spacer() }

            VStack(alignment: isCurrentUser ? .trailing : .leading) {
                Text(message.content)
                    .padding(12)
                    .background(isCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(isCurrentUser ? .white : .primary)
                    .cornerRadius(16)

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if isCurrentUser {
                        MessageStatusIcon(status: message.status)
                    }
                }
            }

            if !isCurrentUser { Spacer() }
        }
        .padding(.horizontal)
    }
}

struct MessageStatusIcon: View {
    let status: PhoenixMessage.MessageStatus

    var body: some View {
        switch status {
        case .sending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundColor(.secondary)
        case .delivered:
            Image(systemName: "checkmark.circle")
                .font(.caption2)
                .foregroundColor(.blue)
        case .read:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.blue)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
}
```

### 5. Presence Indicator

```swift
import SwiftUI

struct PresenceIndicator: View {
    @Environment(PhoenixStateManager.self) private var phoenix
    let conversationId: String
    let userId: String

    var presence: UserPresence? {
        phoenix.getPresence(for: conversationId)[userId]
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        switch presence?.status {
        case .online: return .green
        case .away: return .orange
        case .offline, .none: return .gray
        }
    }

    private var statusText: String {
        switch presence?.status {
        case .online: return "Online"
        case .away: return "Away"
        case .offline, .none:
            if let lastSeen = presence?.lastSeen {
                return "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"
            }
            return "Offline"
        }
    }
}
```

### 6. Advanced: Manual Phoenix Manager Usage

```swift
import Foundation
import GlobalBridge

actor ChatService {
    private let phoenixManager: PhoenixChannelManager
    private var activeConversations: Set<String> = []

    init(config: PhoenixConfig = .development) {
        self.phoenixManager = PhoenixChannelManager(config: config)
    }

    func connect(authToken: String) async throws {
        try await phoenixManager.connect(authToken: authToken)

        // Set up global message handler
        await setupMessageHandlers()
    }

    func joinConversation(_ conversationId: String) async throws {
        guard !activeConversations.contains(conversationId) else { return }

        try await phoenixManager.joinConversation(conversationId)
        activeConversations.insert(conversationId)

        // Set up conversation-specific handlers
        await phoenixManager.onMessage(conversationId: conversationId) { message in
            Task {
                await self.handleMessage(message)
            }
        }
    }

    func sendMessage(
        to conversationId: String,
        content: String,
        replyTo replyToId: String? = nil
    ) async throws -> PhoenixMessage {
        try await phoenixManager.sendMessage(
            conversationId: conversationId,
            content: content,
            replyToId: replyToId
        )
    }

    func markAsRead(conversationId: String, messageId: String) async throws {
        try await phoenixManager.markAsRead(
            conversationId: conversationId,
            messageId: messageId
        )
    }

    private func setupMessageHandlers() async {
        // Set up presence handler
        await phoenixManager.onPresence { conversationId, presence in
            print("Presence update in \(conversationId): \(presence)")
            // Handle presence update
        }
    }

    private func handleMessage(_ message: PhoenixMessage) {
        // Process incoming message
        print("Received message: \(message.content)")
        // Update local storage, show notification, etc.
    }
}
```

### 7. Testing Example

```swift
import XCTest
@testable import GlobalBridge

final class ChatIntegrationTests: XCTestCase {
    var chatService: ChatService!

    override func setUp() async throws {
        chatService = ChatService(config: .development)

        // Skip if server not available
        do {
            try await chatService.connect(authToken: "test-token")
        } catch {
            throw XCTSkip("Phoenix server not available")
        }
    }

    func testSendAndReceiveMessage() async throws {
        let conversationId = "test-\(UUID().uuidString)"

        try await chatService.joinConversation(conversationId)

        let message = try await chatService.sendMessage(
            to: conversationId,
            content: "Test message"
        )

        XCTAssertEqual(message.content, "Test message")
        XCTAssertEqual(message.conversationId, conversationId)
    }
}
```

### 8. Configuration Examples

```swift
// Development (local server)
let devConfig = PhoenixConfig.development

// Production
let prodConfig = PhoenixConfig.production

// Custom staging environment
let stagingConfig = PhoenixConfig(
    socketURL: URL(string: "wss://staging.globalbridge.app/socket")!,
    authToken: nil,
    connectionTimeout: 15,
    heartbeatInterval: 45,
    maxReconnectAttempts: 8,
    reconnectDelay: 3,
    enableLogging: true
)

// Custom with authentication
let authenticatedConfig = PhoenixConfig(
    socketURL: URL(string: "wss://api.globalbridge.app/socket")!,
    authToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    connectionTimeout: 10,
    heartbeatInterval: 30,
    maxReconnectAttempts: 10,
    reconnectDelay: 5,
    enableLogging: false
)
```

### 9. Error Handling Pattern

```swift
import SwiftUI

struct ChatViewController: View {
    @Environment(PhoenixStateManager.self) private var phoenix
    @State private var errorMessage: String?
    @State private var showError = false

    func sendMessageWithErrorHandling(_ content: String, to conversationId: String) {
        Task {
            do {
                try await phoenix.sendMessage(
                    conversationId: conversationId,
                    content: content
                )
            } catch PhoenixError.notConnected {
                errorMessage = "Not connected to server. Please check your connection."
                showError = true
            } catch PhoenixError.channelNotJoined {
                // Try to rejoin and retry
                try? await phoenix.joinConversation(conversationId)
                try? await phoenix.sendMessage(
                    conversationId: conversationId,
                    content: content
                )
            } catch PhoenixError.timeout {
                errorMessage = "Request timed out. Please try again."
                showError = true
            } catch {
                errorMessage = "An error occurred: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    var body: some View {
        // Your view content
        EmptyView()
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
    }
}
```

### 10. SwiftUI Preview Helper

```swift
import SwiftUI

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView(conversationId: "conv1")
            .environment(PhoenixStateManager.preview)
    }
}
```

## Best Practices

### 1. Connection Management
- Connect once in the app lifecycle (in App.swift)
- Reuse the same PhoenixStateManager instance
- Use Environment to pass to child views

### 2. Error Handling
- Always handle connection errors gracefully
- Show user-friendly error messages
- Implement retry logic for transient failures

### 3. Resource Cleanup
- Leave conversations when views disappear
- Disconnect on app termination
- Use `task` modifier for automatic cleanup

### 4. Performance
- Use LazyVStack for long message lists
- Implement pagination for message history
- Debounce typing indicators

### 5. Testing
- Use XCTSkip for server-dependent tests
- Mock PhoenixStateManager for UI tests
- Test error scenarios thoroughly

## File Paths Reference

- Config: `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixConfig.swift`
- Manager: `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixChannelManager.swift`
- State: `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixStateManager.swift`
- Models: `/Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge/Core/Models/Phoenix/PhoenixMessage.swift`
