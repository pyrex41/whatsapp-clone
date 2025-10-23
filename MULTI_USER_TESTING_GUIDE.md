# Multi-User Testing Guide

## Overview
This guide documents the fixes for real-time messaging between multiple users and the new test user selection system.

## Issues Fixed

### 1. ✅ Actor Isolation Errors
**Problem:** Swift concurrency errors causing app freezes
- `Incorrect actor executor assumption; expected 'GlobalBridge.PhoenixChannelManager' executor`

**Fix:**
- Added `await` keywords to actor-isolated method calls in `PhoenixChannelManager+CDC.swift`
- Changed strong `[self]` captures to `[weak self]` in closures
- Marked parsing methods as `nonisolated`

**Files Modified:**
- `clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixChannelManager.swift`
- `clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixChannelManager+CDC.swift`

### 2. ✅ Typing Indicator Payload Mismatch
**Problem:** Backend crashed when receiving typing indicators
- Backend expected `"is_typing"` but iOS sent `"typing"`

**Fix:**
- Updated payload to `["is_typing": isTyping]`

**Files Modified:**
- `clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixChannelManager.swift` (line 662)

### 3. ✅ Force-Unwrap Crash in CDC Logs
**Problem:** App crashed when parsing invalid CDC logs
- `Fatal error: Unexpectedly found nil while unwrapping an Optional value`

**Fix:**
- Replaced force-unwraps with safe `guard let` statements
- Skip invalid CDC logs with warning instead of crashing

**Files Modified:**
- `clients/ios/GlobalBridge/Core/Storage/DatabaseManager.swift` (lines 850-855)

### 4. ✅ Duplicate Messages
**Problem:** Sender saw their own message twice (local + broadcast)

**Fix:**
- Check for duplicate message IDs before adding to UI
- Allows same-user messages from different devices while preventing duplicates

**Files Modified:**
- `clients/ios/GlobalBridge/Core/State/AppReducer.swift` (lines 352-359)

### 5. ✅ Backend CDC Constraint Error
**Problem:** Backend crashed when trying to insert duplicate messages from CDC sync
- `Ecto.ConstraintError: "messages_id_index" (unique_constraint)`

**Fix:**
- Added `on_conflict: :nothing, conflict_target: :id` to gracefully handle duplicates

**Files Modified:**
- `globalbridge_backend/lib/globalbridge_backend/sync.ex` (line 250)

### 6. ✅ Multi-User Support
**Problem:** Both simulators logged in as the same test user, making all messages appear as "from me"

**Fix:**
- Updated backend to support multiple test tokens:
  - `test-token-alice` → alice
  - `test-token-bob` → bob
  - `test-token-testuser` → testuser
- Created user selection screen for iOS
- Updated AuthManager to support dynamic test user selection

**Files Created:**
- `clients/ios/GlobalBridge/Features/Auth/UserSelectionView.swift`

**Files Modified:**
- `globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`
- `clients/ios/GlobalBridge/Core/Auth/AuthManager.swift`
- `clients/ios/GlobalBridge/GlobalBridge/GlobalBridgeApp.swift`

### 7. ✅ Message UI Styling
**Problem:** Needed clear visual distinction between own and others' messages

**Fix:**
- Own messages: Blue background (#007AFF), white text, right-aligned
- Others' messages: Light gray background, black text, left-aligned

**Files Modified:**
- `clients/ios/GlobalBridge/Features/Chat/ChatScreen.swift` (line 126)

## Test User Accounts

The backend now has 4 test users (created via `mix run priv/repo/seeds.exs`):

| Username   | Display Name  | Token                  | Phone          | Password     |
|------------|---------------|------------------------|----------------|--------------|
| alice      | Alice Smith   | `test-token-alice`     | +15551234567   | alice123     |
| bob        | Bob Johnson   | `test-token-bob`       | +15559876543   | bob123       |
| testuser   | Test User     | `test-token-testuser`  | +11234567890   | password123  |
| demo       | Demo User     | (no token)             | +19876543210   | demo123      |

## Testing Instructions

### Setup
1. **Clean simulator storage:**
   ```bash
   xcrun simctl erase booted  # Or erase all: xcrun simctl erase all
   ```

2. **Backend is ready:**
   - Database seeded with test users
   - Server running on `localhost:4000`

### Multi-Device Testing

1. **Open two iOS simulators** (e.g., iPhone 17 Pro and iPhone 17 Pro Max)

2. **On Device 1:**
   - Launch app
   - See user selection screen
   - Select "Alice Smith" 👩
   - Should see "Team Discussion" thread
   - Tap to open

3. **On Device 2:**
   - Launch app  
   - Select "Bob Johnson" 👨
   - See "Team Discussion" thread
   - Tap to open

4. **Test Messaging:**
   - Alice sends "Hi from Alice"
     - Device 1: See message on **right side in blue**
     - Device 2: See message on **left side in gray**
   
   - Bob sends "Hey Alice!"
     - Device 1: See message on **left side in gray**
     - Device 2: See message on **right side in blue**

### Expected Behavior

✅ **Message Alignment:**
- Your own messages: Right side, blue background, white text
- Others' messages: Left side, light gray background, black text

✅ **Real-time Delivery:**
- Messages appear instantly on both devices
- No duplicates
- Typing indicators work

✅ **Same User, Multiple Devices:**
- If both devices select "Alice", both see messages on right (blue)
- No duplicates on either device

## Known Issues

### Simulator Disk Space
If you see:
```
os_unix.c:45841: (28) seekAndWrite(...) - No space left on device
```

**Fix:**
```bash
xcrun simctl erase all
```

### Message History
New users joining a thread don't see previous messages. This is by design (like Slack).

To add history, modify backend bootstrap to include recent messages.

## Architecture Notes

### Duplicate Prevention
Uses message ID checking instead of sender ID checking:
```swift
let isDuplicate = state.chat.messages.contains(where: { $0.id == message.id })
```

This allows:
- ✅ Same user on multiple devices to see their messages
- ✅ No duplicates on the sending device
- ✅ Messages from other users always appear

### Test Token System (Backend)
Maps tokens to usernames:
```elixir
@test_tokens %{
  "test-token-alice" => "alice",
  "test-token-bob" => "bob",
  "test-token-testuser" => "testuser"
}
```

### User Selection (iOS)
- Shows selection screen on app launch
- Stores selected user in `AuthManager`
- All API calls use the selected user's token
- Selection persists until app restart

## Files Modified

### iOS
- `Core/Auth/AuthManager.swift` - Test user selection support
- `Core/State/AppReducer.swift` - Duplicate message handling
- `Core/Storage/DatabaseManager.swift` - Safe CDC parsing
- `Core/Networking/Phoenix/PhoenixChannelManager.swift` - Actor fixes, typing payload
- `Core/Networking/Phoenix/PhoenixChannelManager+CDC.swift` - Actor isolation fixes  
- `Features/Chat/ChatScreen.swift` - Message styling & debug logging
- `Features/Threads/ThreadsListScreen.swift` - Navigation improvements
- `Features/AppRoot/AppRootView.swift` - Debug logging
- `GlobalBridge/GlobalBridgeApp.swift` - User selection flow

### iOS (New Files)
- `Features/Auth/UserSelectionView.swift` - Test user selection UI

### Backend
- `lib/globalbridge_backend/auth/auth0_verifier.ex` - Multi-token support
- `lib/globalbridge_backend/sync.ex` - CDC duplicate handling

## Next Steps

1. ✅ Rebuild iOS app
2. ✅ Select different users on different simulators
3. ✅ Test real-time messaging
4. ⚠️ Consider adding message history for new thread joiners
5. ⚠️ Add proper Auth0 integration when ready for production

