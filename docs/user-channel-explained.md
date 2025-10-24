# User Channel Explained

**Date:** 2025-10-24

---

## 🎯 What is the User Channel?

The **User Channel** is a WebSocket channel that handles **app-level operations** for a specific user. It's like a "personal hub" that manages everything related to the user themselves, not specific conversations.

**Topic Format:** `user:{user_id}`

**Example:** `user:550e8400-e29b-41d4-a716-446655440000`

---

## 📊 Conceptual Comparison: User Channel vs Thread Channel

Think of your messaging app as having two types of WebSocket channels:

### **Thread Channel** (Already Implemented ✅)
**Topic:** `thread:{thread_id}`
**Scope:** **One specific conversation**
**Purpose:** Handle messages within a single thread

**Operations:**
- Send/receive messages in **this thread**
- Edit/delete messages in **this thread**
- Mark messages as read in **this thread**
- See who's typing in **this thread**
- Sync changes for **this thread** (CDC)

**Think of it like:** Being inside a specific group chat room

---

### **User Channel** (Not Yet Implemented ❌)
**Topic:** `user:{user_id}`
**Scope:** **Entire app for this user**
**Purpose:** Handle user-level operations across all threads

**Operations:**
- **Manage contacts** (add, remove, search)
- **Create new threads/DMs**
- **Search for users** across the platform
- **Get all threads** user is part of
- **Bootstrap** app on launch (get everything at once)
- **Listen for notifications** when someone creates a new thread with you

**Think of it like:** Being in the app's "home screen" / main menu

---

## 🔑 Why Do We Need Both?

### Real-World Analogy: WhatsApp

**Thread Channel = Being inside a chat:**
- You're in "Mom's Birthday Party" group chat
- You send messages, see who's typing, read messages
- Everything is scoped to **this one conversation**

**User Channel = Being on the main WhatsApp screen:**
- You see **all your chats** (threads list)
- You tap "New Chat" to **create a DM** with someone
- You search for "John" to **find users** to message
- You manage your **contacts**
- When someone adds you to a new group, you get notified

---

## 📋 User Channel Operations (9 total)

### 1. **Bootstrap** (App Launch)
**What:** Get all user data in one call when app launches

**Why:** Instead of making 3-5 separate API calls on launch, get everything at once:
- User profile
- All threads
- All contacts

**Example:**
```javascript
userChannel.push("bootstrap", {})
  .receive("ok", response => {
    // response.user - your profile
    // response.threads - all your conversations
    // response.contacts - your contact list
  })
```

**iOS Usage:**
```swift
// On app launch after authentication
let bootstrap = try await userChannelManager.bootstrap()

self.currentUser = bootstrap.user
self.threads = bootstrap.threads
self.contacts = bootstrap.contacts

// App is now ready!
```

---

### 2. **Create Thread** (Start Group Chat)
**What:** Create a new group conversation with multiple people

**Example:**
```javascript
userChannel.push("create_thread", {
  title: "Team Standup",
  participant_ids: ["alice-uuid", "bob-uuid", "charlie-uuid"]
})
  .receive("ok", response => {
    // response.thread - newly created thread
  })
```

**iOS Usage:**
```swift
// User taps "New Group" button, selects 3 people
let newThread = try await userChannelManager.createThread(
    title: "Team Standup",
    participantIds: [alice.id, bob.id, charlie.id]
)

// Navigate to new thread
navigateToThread(newThread)
```

**Without User Channel:** You'd have to use REST API instead of real-time WebSocket

---

### 3. **Create Direct Message** (Start 1-on-1 Chat)
**What:** Create or open a DM with one specific person

**Smart behavior:** If DM already exists with this person, returns existing thread. If not, creates new one.

**Example:**
```javascript
userChannel.push("create_dm", {
  other_user_id: "alice-uuid"
})
  .receive("ok", response => {
    // response.thread - DM thread (existing or new)
  })
```

**iOS Usage:**
```swift
// User taps on "Alice" in contacts to message her
let dmThread = try await userChannelManager.createDirectMessage(
    otherUserId: alice.id
)

// Navigate to DM (might be existing or new)
navigateToThread(dmThread)
```

**Without User Channel:** You'd have to:
1. First check if DM exists via REST API
2. If not, create it via another REST API call
3. Then navigate to it

With User Channel: **One real-time call**, backend handles everything

---

### 4. **Search Users** (Find People on Platform)
**What:** Search for users across the entire platform to message them

**Example:**
```javascript
userChannel.push("search_users", {
  query: "john"
})
  .receive("ok", response => {
    // response.users - [John Doe, John Smith, Johnny...]
  })
```

**iOS Usage:**
```swift
// User types "john" in search bar
let users = try await userChannelManager.searchUsers(query: "john")

// Show results:
// - John Doe (@johndoe)
// - John Smith (@jsmith)
// - Johnny Walker (@johnny_w)
```

**Use Case:** "New Message" → Type name to find person → Start DM

---

### 5. **Get Contacts**
**What:** Get your full contact list

**Example:**
```javascript
userChannel.push("get_contacts", {})
  .receive("ok", response => {
    // response.contacts - your saved contacts
  })
```

**iOS Usage:**
```swift
// User opens "Contacts" tab
let contacts = try await userChannelManager.getContacts()

// Show list:
// - Alice (alice@example.com)
// - Bob (bob@example.com)
// - Charlie (charlie@example.com)
```

---

### 6. **Add Contact**
**What:** Save someone to your contacts with a custom display name

**Example:**
```javascript
userChannel.push("add_contact", {
  contact_user_id: "alice-uuid",
  display_name: "Alice (Work)"
})
  .receive("ok", response => {
    // response.contact - newly added contact
  })
```

**iOS Usage:**
```swift
// User taps "Add to Contacts" after messaging someone
try await userChannelManager.addContact(
    contactUserId: alice.id,
    displayName: "Alice (Work)"
)

// Alice now shows as "Alice (Work)" in your contacts
```

---

### 7. **Remove Contact**
**What:** Remove someone from your contacts

**Example:**
```javascript
userChannel.push("remove_contact", {
  contact_id: "contact-uuid"
})
  .receive("ok", response => {
    // Contact removed
  })
```

**iOS Usage:**
```swift
// User swipes left on contact and taps "Delete"
try await userChannelManager.removeContact(contactId: contact.id)

// Contact removed from list
```

---

### 8. **Search Contacts**
**What:** Search within your saved contacts

**Example:**
```javascript
userChannel.push("search_contacts", {
  query: "alice"
})
  .receive("ok", response => {
    // response.contacts - matching contacts
  })
```

**iOS Usage:**
```swift
// User types "alice" in contacts search bar
let results = try await userChannelManager.searchContacts(query: "alice")

// Show:
// - Alice (Work)
// - Alice Smith
```

---

### 9. **Sync Contacts (CDC)**
**What:** Sync contact changes using CDC (offline support)

**Example:**
```javascript
userChannel.push("sync_contacts", {
  since: "2025-10-24T10:00:00Z"
})
  .receive("ok", response => {
    // response.changes - contact changes since timestamp
    // response.cursor - save for next sync
  })
```

**iOS Usage:**
```swift
// Background sync when app comes online
let syncResult = try await userChannelManager.syncContacts(
    since: lastSyncTimestamp
)

// Apply changes locally
for change in syncResult.changes {
    applyContactChange(change)
}

// Save new cursor
lastSyncTimestamp = syncResult.cursor
```

---

### 10. **Receive Notifications (Broadcast Event)**
**What:** Server pushes notification when someone adds you to a new thread

**Example:**
```javascript
userChannel.on("thread_created", payload => {
  // Someone just created a thread and added you!
  // payload.thread - the new thread

  // Show notification: "Alice added you to 'Weekend Plans'"
})
```

**iOS Usage:**
```swift
// Listen for new threads
userChannelManager.onThreadCreated = { newThread in
    // Show push notification or in-app banner
    showNotification("You were added to '\(newThread.title)'")

    // Add to threads list
    self.threads.append(newThread)
}
```

---

## 🎬 Real-World User Flows

### Flow 1: Opening the App (First Time)

**Without User Channel (Current - Multiple API Calls):**
```swift
// 1. Get user profile
let user = try await authAPI.getCurrentUser()

// 2. Get all threads
let threads = try await threadAPI.listThreads()

// 3. Get contacts
let contacts = try await contactAPI.getContacts()

// Total: 3 separate HTTP requests, 3 network round trips
```

**With User Channel (Future - Single Real-Time Call):**
```swift
// 1. Join user channel
try await userChannelManager.joinUserChannel(userId: currentUser.id)

// 2. Bootstrap - get everything at once
let bootstrap = try await userChannelManager.bootstrap()

self.currentUser = bootstrap.user
self.threads = bootstrap.threads
self.contacts = bootstrap.contacts

// Total: 1 WebSocket message, already connected, instant
```

**Benefits:**
- ✅ Faster: One call instead of three
- ✅ Real-time: WebSocket already open
- ✅ Simpler: One method call

---

### Flow 2: Starting a DM with Someone

**Without User Channel (Current - Multiple Steps):**
```swift
// User taps on "Alice" in search results to message her

// 1. Check if DM exists
let existingThreads = try await threadAPI.listThreads()
let dmThread = existingThreads.first { thread in
    thread.participants.count == 2 &&
    thread.participants.contains(alice.id)
}

// 2. If not, create it
if dmThread == nil {
    dmThread = try await threadAPI.createDirectMessage(otherUserId: alice.id)
}

// 3. Navigate to thread
navigateToThread(dmThread)

// Total: 2-3 API calls
```

**With User Channel (Future - Single Call):**
```swift
// User taps on "Alice" in search results to message her

// 1. Create or get DM (backend handles check)
let dmThread = try await userChannelManager.createDirectMessage(
    otherUserId: alice.id
)

// 2. Navigate to thread
navigateToThread(dmThread)

// Total: 1 WebSocket message
// Backend automatically returns existing thread or creates new one
```

**Benefits:**
- ✅ Simpler: Don't need to check if DM exists
- ✅ Faster: One call
- ✅ Real-time: Instant response

---

### Flow 3: Creating a Group Chat

**Without User Channel (Current):**
```swift
// User selects 3 friends and taps "Create Group"

// Need to use REST API
let thread = try await threadAPI.createThread(
    title: "Weekend Plans",
    participantIds: [alice.id, bob.id, charlie.id]
)

navigateToThread(thread)
```

**With User Channel (Future):**
```swift
// User selects 3 friends and taps "Create Group"

let thread = try await userChannelManager.createThread(
    title: "Weekend Plans",
    participantIds: [alice.id, bob.id, charlie.id]
)

navigateToThread(thread)

// PLUS: All participants get real-time notification via their User Channels!
```

**Benefits:**
- ✅ Real-time notifications for all participants
- ✅ Consistent with rest of app (WebSocket)

---

### Flow 4: Finding Someone to Message

**Without User Channel (Current):**
```swift
// User types "john" in search bar

// REST API call
let users = try await searchAPI.searchUsers(query: "john")

// Show results
displaySearchResults(users)
```

**With User Channel (Future):**
```swift
// User types "john" in search bar

let users = try await userChannelManager.searchUsers(query: "john")

displaySearchResults(users)

// Same result, but via already-open WebSocket
```

**Benefits:**
- ✅ Consistent: All operations via WebSocket
- ✅ Faster: No new HTTP connection needed
- ✅ Could add real-time: Show "John is typing..." if searching while chatting

---

## 📱 iOS App Architecture

### Current State (Thread Channel Only)

```
┌─────────────────────────────────────┐
│          iOS App                    │
│                                     │
│  ┌───────────────────────────────┐ │
│  │    REST API Calls              │ │
│  │  - Login                       │ │
│  │  - Get threads                 │ │
│  │  - Get contacts                │ │
│  │  - Create thread               │ │
│  │  - Search users                │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  Thread Channel (WebSocket)   │ │
│  │  - Send message                │ │
│  │  - Receive message             │ │
│  │  - Typing indicator            │ │
│  │  - CDC sync                    │ │
│  └───────────────────────────────┘ │
│                                     │
└─────────────────────────────────────┘
```

**Problem:** App-level operations use REST, conversation operations use WebSocket. **Inconsistent.**

---

### Future State (Thread + User Channels)

```
┌─────────────────────────────────────┐
│          iOS App                    │
│                                     │
│  ┌───────────────────────────────┐ │
│  │    REST API Calls              │ │
│  │  - Login (OAuth)               │ │
│  │  - AI features                 │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  User Channel (WebSocket)     │ │
│  │  ✨ NEW!                       │ │
│  │  - Bootstrap                   │ │
│  │  - Create thread/DM            │ │
│  │  - Manage contacts             │ │
│  │  - Search users                │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  Thread Channel (WebSocket)   │ │
│  │  ✅ Already implemented        │ │
│  │  - Send/receive messages       │ │
│  │  - Typing indicator            │ │
│  │  - CDC sync                    │ │
│  └───────────────────────────────┘ │
│                                     │
└─────────────────────────────────────┘
```

**Better:** All real-time operations via WebSocket. **Consistent, fast, real-time.**

---

## 🏗️ iOS Implementation Architecture

### High-Level Structure

```swift
// MARK: - Main Manager
@MainActor
class UserChannelManager: ObservableObject {
    // Published state
    @Published var threads: [Thread] = []
    @Published var contacts: [Contact] = []

    // Dependencies
    private var userChannel: Channel?
    private let phoenixManager: PhoenixChannelManager

    // MARK: - Connection
    func joinUserChannel(userId: String) async throws {
        let topic = "user:\(userId)"
        userChannel = try await phoenixManager.joinChannel(topic: topic)

        // Set up listeners
        setupEventListeners()
    }

    // MARK: - Bootstrap
    func bootstrap() async throws -> BootstrapData {
        // Get user, threads, contacts in one call
    }

    // MARK: - Thread Management
    func createThread(title: String, participantIds: [String]) async throws -> Thread {
        // Create group chat
    }

    func createDirectMessage(otherUserId: String) async throws -> Thread {
        // Create or get existing DM
    }

    // MARK: - Contact Management
    func getContacts() async throws -> [Contact] { }
    func addContact(contactUserId: String, displayName: String) async throws -> Contact { }
    func removeContact(contactId: String) async throws { }
    func searchContacts(query: String) async throws -> [Contact] { }

    // MARK: - User Search
    func searchUsers(query: String) async throws -> [User] { }

    // MARK: - CDC
    func syncContacts(since: String?) async throws -> ContactSyncResult { }

    // MARK: - Event Listeners
    private func setupEventListeners() {
        // Listen for "thread_created" broadcasts
        userChannel?.on("thread_created") { payload in
            // Someone added you to a new thread!
        }
    }
}
```

### Usage in SwiftUI Views

```swift
// MARK: - App-Level View Model
@MainActor
class AppViewModel: ObservableObject {
    @Published var threads: [Thread] = []
    @Published var contacts: [Contact] = []

    private let userChannelManager: UserChannelManager

    func onAppLaunch() async {
        do {
            // 1. Authenticate
            try await authManager.login()

            // 2. Join user channel
            try await userChannelManager.joinUserChannel(
                userId: authManager.userId!
            )

            // 3. Bootstrap - get everything
            let bootstrap = try await userChannelManager.bootstrap()

            self.threads = bootstrap.threads
            self.contacts = bootstrap.contacts

            // App is ready!

        } catch {
            print("Launch failed: \(error)")
        }
    }
}

// MARK: - New Message View
struct NewMessageView: View {
    @ObservedObject var userChannelManager: UserChannelManager
    @State private var searchQuery = ""
    @State private var searchResults: [User] = []

    var body: some View {
        VStack {
            // Search bar
            TextField("Search users...", text: $searchQuery)
                .onChange(of: searchQuery) { query in
                    Task {
                        searchResults = try await userChannelManager.searchUsers(
                            query: query
                        )
                    }
                }

            // Results
            List(searchResults) { user in
                Button(user.username) {
                    // Start DM
                    Task {
                        let dmThread = try await userChannelManager.createDirectMessage(
                            otherUserId: user.id
                        )
                        navigateToThread(dmThread)
                    }
                }
            }
        }
    }
}

// MARK: - Contacts View
struct ContactsView: View {
    @ObservedObject var userChannelManager: UserChannelManager

    var body: some View {
        List(userChannelManager.contacts) { contact in
            HStack {
                Text(contact.displayName ?? "Unknown")
                Spacer()
                Button("Message") {
                    // Start DM with contact
                    Task {
                        let dmThread = try await userChannelManager.createDirectMessage(
                            otherUserId: contact.contactUserId
                        )
                        navigateToThread(dmThread)
                    }
                }
            }
            .swipeActions {
                Button("Delete", role: .destructive) {
                    Task {
                        try await userChannelManager.removeContact(
                            contactId: contact.id
                        )
                    }
                }
            }
        }
    }
}
```

---

## 📊 Summary: Why User Channel is Critical

### What's Missing Without It?

1. **❌ No contact management** - Can't add/remove/search contacts
2. **❌ No thread creation** - Can't start group chats or DMs easily
3. **❌ No user search** - Can't find people to message
4. **❌ Slow app launch** - Multiple REST calls instead of one bootstrap
5. **❌ No real-time notifications** - Won't know when added to new threads
6. **❌ Inconsistent architecture** - Mix of REST and WebSocket

### What We Get With It?

1. **✅ Full contact management** - Add, remove, search contacts
2. **✅ Easy thread creation** - One call to create group or DM
3. **✅ Platform-wide user search** - Find anyone to message
4. **✅ Fast app launch** - Bootstrap gets everything at once
5. **✅ Real-time notifications** - Instant updates when added to threads
6. **✅ Consistent architecture** - All real-time ops via WebSocket
7. **✅ Better offline support** - CDC sync for contacts

---

## 🎯 Bottom Line

**User Channel = "Home Screen" Operations**
- Everything you do **before** entering a specific conversation
- Managing your **contacts**
- **Creating** new threads
- **Finding** people to message
- Getting **notified** of new threads

**Thread Channel = "Inside Chat" Operations**
- Everything you do **inside** a specific conversation
- **Sending/receiving** messages
- **Editing/deleting** messages
- **Reading** receipts
- **Typing** indicators

**Both are essential for a complete messaging app.**

---

**Effort:** 3-4 days to implement
**Impact:** High - Enables core app functionality
**Priority:** Approved for next sprint ✅

---

**Last Updated:** 2025-10-24
