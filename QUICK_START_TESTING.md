# Quick Start - iOS & Backend Integration Testing

## ✅ Authentication Bypass Complete

Both the iOS app and Phoenix backend have been configured to bypass Auth0 authentication for testing.

**Latest Fix**: Updated UserChannel authorization to accept both database UUID and auth0_id, fixing "Unauthorized" errors when joining channels.

## 🚀 Quick Start (2 Steps)

### Step 1: Start the Backend

```bash
cd globalbridge_backend
mix phx.server
```

**Expected output:**
```
[info] Running GlobalbridgeBackendWeb.Endpoint with Bandit 1.x.x at 127.0.0.1:4000 (http)
[info] Access GlobalbridgeBackendWeb.Endpoint at http://localhost:4000
```

### Step 2: Run iOS App

```bash
cd clients/ios/GlobalBridge
open GlobalBridge.xcodeproj
```

Then in Xcode:
- Select a simulator (e.g., iPhone 15 Pro)
- Press `Cmd+R` to build and run

**Expected console output:**
```
⚠️ [AUTH BYPASS] Authentication bypass is ENABLED
⚠️ [AUTH BYPASS] Using test credentials for backend integration testing
✅ [AUTH BYPASS] Bypass authentication configured
   User ID: test-user-123
   Token: test-token-for-backend-integration
```

## ✅ What Should Work

Once both are running, the iOS app should:

1. ✅ Launch without requiring login
2. ✅ Connect to the backend at `localhost:4000`
3. ✅ Make authenticated API calls using the test token
4. ✅ Connect to WebSocket channels
5. ✅ Create and view threads
6. ✅ Send and receive messages
7. ✅ Get real-time message updates

## 📋 Test Checklist

Try these actions in the iOS app:

- [ ] App launches successfully
- [ ] Threads list loads (may be empty initially)
- [ ] Can create a new thread
- [ ] Can open a thread
- [ ] Can send a message
- [ ] Message appears in the chat
- [ ] WebSocket connection indicator shows connected

## 🔍 Monitoring

### Backend Logs

Watch for these messages:
```bash
cd globalbridge_backend
mix phx.server
```

Key log messages:
```
⚠️ [AUTH BYPASS] Test token detected - returning test user
👤 [AUTH BYPASS] Creating test user: test-user-123
✅ [AUTH BYPASS] Test user created: id=<uuid>
[info] GET /api/v1/threads
[info] JOINED thread:lobby in 5ms
```

### iOS Logs

In Xcode, open the console (Cmd+Shift+Y) and look for:
```
⚠️ [AUTH BYPASS] Authentication bypass is ENABLED
🌐 [HTTP] Making request to http://localhost:4000/api/v1/threads
✅ [HTTP] Response: 200
🔌 [Phoenix] Connected to WebSocket
```

## 🐛 Common Issues

### Backend won't start

**Problem**: Mix dependencies not installed
```bash
cd globalbridge_backend
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

### iOS app won't build

**Problem**: Missing dependencies or Xcode cache
1. In Xcode: Product → Clean Build Folder (Cmd+Shift+K)
2. Close Xcode
3. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData/GlobalBridge-*`
4. Reopen project and build

### iOS app crashes on launch

**Problem**: Missing configuration or code compilation error
1. Check Xcode console for specific error
2. Verify all files were saved
3. Clean and rebuild

### Cannot connect to backend

**Problem**: Backend not running or wrong URL
1. Verify backend is running on port 4000
2. Check iOS is configured for `localhost:4000` (it should be)
3. Ensure using iOS Simulator (not physical device)

### WebSocket connection fails

**Problem**: Backend WebSocket not accepting connections
1. Check backend logs for WebSocket errors
2. Verify `check_origin: false` in `config/dev.exs`
3. Restart backend server

### 401 Unauthorized errors

**Problem**: Test token mismatch
1. Verify tokens match in both files:
   - iOS: `AuthManager.swift` → `"test-token-for-backend-integration"`
   - Backend: `auth0_verifier.ex` → `"test-token-for-backend-integration"`
2. Clean and rebuild both projects

## 📁 Files Modified

### iOS App
- `clients/ios/GlobalBridge/Core/Auth/AuthManager.swift`
  - Added `authBypassEnabled = true`
  - Added test credentials
  - Modified auth methods to return test data

### Backend
- `globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`
  - Added test token check
  - Added `get_or_create_test_user/0` function
  - WebSocket auth automatically inherits changes

## 🔐 Security Note

⚠️ **THIS IS FOR TESTING ONLY!**

Before deploying to production:
1. Set `authBypassEnabled = false` in iOS
2. Remove test token check from backend
3. Implement proper Auth0 authentication

## 📖 Full Documentation

For detailed information, see:
- `AUTH_BYPASS_TESTING_GUIDE.md` - Complete guide with troubleshooting
- `README_START_HERE.md` - Project overview
- `TESTING_GUIDE.md` - Comprehensive testing documentation

## 🎯 Next Steps

After verifying integration works:

1. **Test Message Flow**
   - Create multiple threads
   - Send messages back and forth
   - Test real-time updates

2. **Test Error Handling**
   - Stop backend while app is running
   - Check offline message queue
   - Verify reconnection logic

3. **Test Performance**
   - Load testing with many messages
   - Monitor memory usage
   - Check WebSocket stability

4. **Implement Real Auth**
   - Follow Auth0 setup guides
   - Test full authentication flow
   - Migrate test data to real users

---

**Status**: ✅ Ready to Test  
**Last Updated**: October 22, 2025  
**Branch**: `auth_bypass`

