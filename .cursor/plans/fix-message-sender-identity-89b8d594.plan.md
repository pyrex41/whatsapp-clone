<!-- 89b8d594-e7a9-483a-9784-09d6ad80404a 138da596-df74-4b7d-a403-3e8fe9793204 -->
# Fix Message Sender Identity After Re-login

## Problem

When logging out and back in with a different test user, messages appear with wrong sender identification because the user identity bootstrap is skipped when local threads exist.

**Root Cause:** In `AppEnvironment.swift` lines 124-146, the bootstrap only runs when `localThreads.isEmpty`, which means user identity never updates when threads exist locally.

## Solution

Separate user identity fetching from thread syncing - always bootstrap user info on app load.

---

## Implementation Steps

### Step 1: Add User-Only Bootstrap Method

**File:** `clients/ios/GlobalBridge/Core/Storage/DatabaseManager.swift`

After the existing `syncThreadsFromBackend` method (around line 548), add a new method that fetches only user data without syncing threads:

```swift
/// Fetch user data from backend without syncing threads
func fetchUserFromBackend(phoenixManager: PhoenixChannelManager) async throws -> User {
    print("👤 [USER_SYNC] Fetching user from backend...")
    
    let bootstrap = try await phoenixManager.fetchBootstrap()
    let user = User.from(bootstrap.user)
    
    print("✅ [USER_SYNC] Received user: \(user.id) - \(user.displayName)")
    return user
}
```

### Step 2: Update AppEnvironment Load Logic

**File:** `clients/ios/GlobalBridge/Core/State/AppEnvironment.swift`

Replace lines 116-146 with the following logic that always bootstraps user but conditionally syncs threads:

```swift
loadThreads: {
    _ = try await initializationTask.value
    
    print("📥 [LOAD_THREADS] Starting thread load...")
    
    // ALWAYS fetch user identity from backend
    print("👤 [LOAD_THREADS] Fetching current user identity...")
    let user = try await databaseManager.fetchUserFromBackend(phoenixManager: phoenixManager)
    print("✅ [LOAD_THREADS] User identity confirmed: \(user.id)")
    await AuthManager.shared.setBootstrappedUser(user)
    
    // Check if we should sync threads from backend
    let localThreads = try await databaseManager.fetchThreads()
    
    if localThreads.isEmpty {
        print("📥 [LOAD_THREADS] No local threads, syncing from backend...")
        
        do {
            // Sync threads from backend via Phoenix bootstrap
            let (syncedThreads, _) = try await databaseManager.syncThreadsFromBackend(phoenixManager: phoenixManager)
            print("✅ [LOAD_THREADS] Synced \(syncedThreads.count) threads from backend")
            return syncedThreads
        } catch {
            print("❌ [LOAD_THREADS] Bootstrap sync failed: \(error)")
            print("❌ [LOAD_THREADS] Error details: \(error.localizedDescription)")
            throw error
        }
    } else {
        print("✅ [LOAD_THREADS] Loaded \(localThreads.count) threads from local DB")
        return localThreads
    }
},
```

### Step 3: Optional - Clear Local Data on Logout

**File:** `clients/ios/GlobalBridge/Core/Auth/AuthManager.swift`

For a cleaner experience during development/testing with multiple test users, add a method to clear bootstrapped user on logout (around line 186):

```swift
// Clear local state
accessToken = nil
refreshToken = nil
userId = nil
tokenExpiresAt = nil
isAuthenticated = false
authError = nil
bootstrappedUser = nil  // Add this line

print("✅ [AUTH] Logout complete")
```

### Step 4: Add Debug Logging (Optional but Recommended)

**File:** `clients/ios/GlobalBridge/Features/Chat/ChatScreen.swift`

Update line 24 to add detailed debug logging for sender comparison:

```swift
let isOwn = message.senderId == store.state.user.id
let _ = print("🔍 [OWNERSHIP] Message \(message.id) | senderId=\(message.senderId) | currentUserId=\(store.state.user.id) | isOwn=\(isOwn)")
```

---

## Testing

1. Log in as Test User 1
2. Send a few messages (verify blue bubbles on right)
3. Log out
4. Log in as Test User 2
5. Send messages (should show blue bubbles correctly)
6. Verify that User 1's old messages appear on left (gray bubbles)
7. Verify User 2's new messages appear on right (blue bubbles)

## Expected Outcome

- User identity always updates from backend on app load
- Message ownership comparison works correctly after re-login
- Blue bubbles appear for current user's messages
- Previous user's messages appear as "other sender" messages