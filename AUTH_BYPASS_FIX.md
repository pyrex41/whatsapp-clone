# Authentication Bypass Fix - WebSocket Authorization

## 🐛 Problem

When the iOS app tried to join WebSocket channels, it was getting "Unauthorized" errors:

```
👤 [REALTIME] Joining user channel for: test-user-123
📥 [USER_CHANNEL] Joining user channel: user:test-user-123
[Phoenix] SwiftPhoenixClient: receive , ["6","6","user:test-user-123","phx_reply",{"response":{"reason":"Unauthorized"},"status":"error"}]
❌ [USER_CHANNEL] Failed to join: user:test-user-123
❌ [USER_CHANNEL] Error: ["reason": Unauthorized]
```

## 🔍 Root Cause

The issue was a mismatch between how the iOS app and backend identify users:

### iOS Side
- Uses `"test-user-123"` as the `userId` (the auth0_id)
- Tries to join channel `"user:test-user-123"`

### Backend Side
- WebSocket assigns `socket.assigns.user_id` as the database UUID (e.g., `"550e8400-e29b-41d4-a716-446655440000"`)
- UserChannel checked: `if socket.assigns.user_id == user_id` 
- This compared the UUID against `"test-user-123"` → **FAILED**

## ✅ Solution

Updated the **UserChannel** authorization to check BOTH the database UUID and the auth0_id:

### File Changed
`globalbridge_backend/lib/globalbridge_backend_web/channels/user_channel.ex`

### Code Changes

**Before**:
```elixir
def join("user:" <> user_id, _payload, socket) do
  if socket.assigns.user_id == user_id do
    {:ok, %{joined_at: DateTime.utc_now()}, socket}
  else
    {:error, %{reason: "Unauthorized"}}
  end
end
```

**After**:
```elixir
def join("user:" <> user_id, _payload, socket) do
  # Verify user owns this channel
  # For test user, check both UUID and auth0_id to support bypass mode
  socket_user_id = socket.assigns.user_id
  socket_user = socket.assigns[:user]
  socket_auth0_id = if socket_user, do: socket_user.auth0_id, else: nil

  authorized? =
    socket_user_id == user_id or
      socket_auth0_id == user_id

  if authorized? do
    Logger.info("✅ [USER_CHANNEL] User #{user_id} joined their channel")
    {:ok, %{joined_at: DateTime.utc_now()}, socket}
  else
    Logger.warning(
      "❌ [USER_CHANNEL] Unauthorized join attempt: socket_user=#{socket_user_id}, socket_auth0_id=#{socket_auth0_id}, channel_user=#{user_id}"
    )

    {:error, %{reason: "Unauthorized"}}
  end
end
```

## 🎯 How It Works Now

1. **iOS App connects** with test token `"test-token-for-backend-integration"`
2. **Backend WebSocket** verifies token via `Auth0Verifier.verify_and_get_user/1`
3. **Backend creates/finds** test user with `auth0_id = "test-user-123"`
4. **Socket assigns**:
   - `socket.assigns.user_id = <database_uuid>`
   - `socket.assigns.user = <User struct with auth0_id="test-user-123">`
5. **iOS tries to join** `"user:test-user-123"`
6. **UserChannel checks**:
   - Does `socket.assigns.user_id == "test-user-123"`? No (it's a UUID)
   - Does `socket.assigns.user.auth0_id == "test-user-123"`? **YES** ✅
7. **Authorization succeeds!**

## 📋 Testing

### Backend Logs - Success
```
⚠️ [AUTH BYPASS] Test token detected - returning test user
✅ [AUTH BYPASS] Test user found: id=550e8400-e29b-41d4-a716-446655440000
✅ [USER_CHANNEL] User test-user-123 joined their channel
```

### iOS Logs - Success
```
👤 [REALTIME] Joining user channel for: test-user-123
✅ [USER_CHANNEL] Successfully joined: user:test-user-123
✅ [REALTIME] User channel joined
```

## 🔄 Why This Approach

### Option 1: Change iOS to use database UUID ❌
- **Problem**: iOS doesn't know the database UUID until after connecting
- **Issue**: Chicken-and-egg problem

### Option 2: Change backend to use auth0_id everywhere ❌
- **Problem**: Would require changing entire database schema
- **Issue**: auth0_id is not a UUID, might break foreign keys

### Option 3: Accept both identifiers ✅ (Chosen)
- **Advantage**: Works with both test bypass and real Auth0
- **Advantage**: No schema changes needed
- **Advantage**: Backward compatible
- **Advantage**: Minimal code change

## 🎉 Benefits

1. **Test Mode Works**: iOS app can now join channels using auth0_id
2. **Production Compatible**: Real Auth0 users can still use database UUID
3. **Flexible**: Supports both identifier types
4. **Safe**: Still validates user owns the channel
5. **Simple**: Single file change, no migrations

## 🚀 Next Steps

Now that WebSocket authorization works, you can test:

- [x] WebSocket connection
- [x] User channel joining
- [ ] Thread channel joining (may need similar fix)
- [ ] Message sending/receiving
- [ ] Real-time updates
- [ ] Thread creation

If you encounter similar "Unauthorized" errors on thread channels, the same approach can be applied to `ThreadChannel`'s `authorize_user/2` function.

## 📝 Files Modified

1. **`globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`**
   - Added test token detection
   - Added test user creation

2. **`globalbridge_backend/lib/globalbridge_backend_web/channels/user_channel.ex`** ← **THIS FIX**
   - Updated join authorization to check both UUID and auth0_id

3. **`clients/ios/GlobalBridge/Core/Auth/AuthManager.swift`**
   - Added authentication bypass mode
   - Returns test token and user ID

---

**Status**: ✅ Fixed  
**Date**: October 22, 2025  
**Impact**: Critical - Enables all WebSocket functionality in test mode

