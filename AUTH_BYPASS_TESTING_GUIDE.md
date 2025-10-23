# Authentication Bypass Testing Guide

## Overview

This guide explains how authentication has been temporarily bypassed on both the iOS client and Phoenix backend to facilitate integration testing without requiring Auth0 setup.

## Changes Made

### iOS Client Changes

**File**: `clients/ios/GlobalBridge/Core/Auth/AuthManager.swift`

Added authentication bypass mode with the following changes:

1. **Bypass Flag**: 
   ```swift
   private let authBypassEnabled = true
   ```
   Set to `true` to enable bypass mode for testing.

2. **Test Credentials**:
   ```swift
   private let testUserId = "test-user-123"
   private let testAccessToken = "test-token-for-backend-integration"
   ```

3. **Modified Methods**:
   - `init()`: Automatically sets up bypass auth if enabled
   - `login()`: Returns test token immediately when bypass is enabled
   - `getAccessToken()`: Always returns test token in bypass mode
   - `needsRefresh()`: Token never needs refresh in bypass mode

4. **Bypass Setup**:
   - Sets `isAuthenticated = true`
   - Sets `userId = "test-user-123"`
   - Sets `accessToken = "test-token-for-backend-integration"`
   - Sets token expiration to 24 hours from startup

### Backend Changes

**File**: `globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`

Added support for test token authentication:

1. **Test Token Constants**:
   ```elixir
   @test_token "test-token-for-backend-integration"
   @test_user_id "test-user-123"
   ```

2. **Token Verification**:
   - `verify_and_get_user/1`: Checks if incoming token matches test token
   - If test token is detected, returns or creates test user
   - Otherwise, proceeds with normal Auth0 JWT verification

3. **Test User Creation**:
   - New function `get_or_create_test_user/0`
   - Creates a test user with:
     - `auth0_id`: "test-user-123"
     - `email`: "test@example.com"
     - `username`: "test_user"
     - `display_name`: "Test User"
     - `phone_number`: "+10000000000"

4. **Automatic WebSocket Support**:
   - WebSocket authentication in `user_socket.ex` uses `Auth0Verifier`
   - No changes needed - automatically accepts test token

## How to Test

### 1. Start the Backend

```bash
cd globalbridge_backend
mix deps.get
mix ecto.create
mix ecto.migrate
mix phx.server
```

The server should start on `http://localhost:4000`

### 2. Build and Run iOS App

Open the iOS project in Xcode:

```bash
cd clients/ios/GlobalBridge
open GlobalBridge.xcodeproj
```

Build and run the app on a simulator or device (Cmd+R).

### 3. Verify Authentication Bypass

Look for these log messages:

**iOS App Console**:
```
⚠️ [AUTH BYPASS] Authentication bypass is ENABLED
⚠️ [AUTH BYPASS] Using test credentials for backend integration testing
✅ [AUTH BYPASS] Bypass authentication configured
   User ID: test-user-123
   Token: test-token-for-backend-integration
```

**Backend Console**:
```
⚠️ [AUTH BYPASS] Test token detected - returning test user
👤 [AUTH BYPASS] Creating test user: test-user-123
✅ [AUTH BYPASS] Test user created: id=<uuid>
```

### 4. Test Backend Integration

The iOS app should now be able to:

- ✅ Make authenticated API requests to the backend
- ✅ Connect to Phoenix WebSocket channels
- ✅ Create and view threads
- ✅ Send and receive messages
- ✅ Receive real-time updates

### 5. Monitor Logs

**Watch iOS logs** for network requests and responses:
```
🌐 [HTTP] Making request to...
✅ [HTTP] Request successful
```

**Watch backend logs** for incoming requests:
```
[info] GET /api/v1/threads
[info] Sent 200 in 5ms
```

## Important Notes

### Security Warning

⚠️ **NEVER deploy these changes to production!**

This authentication bypass is ONLY for development and testing. Before deploying to production:

1. Set `authBypassEnabled = false` in `AuthManager.swift`
2. Remove or comment out the test token check in `auth0_verifier.ex`
3. Implement proper Auth0 authentication

### Development vs Production

The current setup is suitable for:
- ✅ Local development
- ✅ Integration testing
- ✅ Backend API testing
- ✅ Real-time features testing

It is NOT suitable for:
- ❌ Production deployment
- ❌ Security testing
- ❌ User acceptance testing with real users

### Reverting Changes

To disable authentication bypass and return to Auth0:

**iOS**: Change this line in `AuthManager.swift`:
```swift
private let authBypassEnabled = false  // Changed from true
```

**Backend**: Remove the test token check in `auth0_verifier.ex`:
```elixir
def verify_and_get_user(token) do
  # Remove this entire if/else block:
  # if token == @test_token do
  #   ...
  # end
  
  # Keep only the Auth0 verification logic
  Logger.info("🔐 [AUTH0] Attempting to verify token: #{String.slice(token, 0, 20)}...")
  ...
end
```

## Testing Checklist

Use this checklist to verify integration:

- [ ] Backend starts without errors
- [ ] iOS app launches successfully
- [ ] iOS app shows "AUTH BYPASS" log messages
- [ ] Backend shows "AUTH BYPASS" log messages
- [ ] Test user is created in database
- [ ] iOS app can load threads list
- [ ] iOS app can create new threads
- [ ] iOS app can send messages
- [ ] iOS app receives real-time message updates
- [ ] WebSocket connection stays stable
- [ ] No authentication errors in logs

## Troubleshooting

### iOS App Not Connecting

1. Check that backend is running on `http://localhost:4000`
2. Verify the iOS app is configured to connect to localhost
3. Check network permissions in iOS simulator/device

### Backend Rejecting Requests

1. Verify test token matches exactly in both iOS and backend
2. Check that `auth0_verifier.ex` changes are compiled
3. Restart backend server: `mix phx.server`

### WebSocket Connection Fails

1. Check WebSocket URL configuration in iOS
2. Verify `user_socket.ex` is using `Auth0Verifier`
3. Check backend logs for WebSocket connection attempts
4. Ensure test user was created successfully

### Database Errors

1. Run migrations: `mix ecto.migrate`
2. Reset database: `mix ecto.drop && mix ecto.create && mix ecto.migrate`
3. Check that User schema supports all required fields

## Next Steps

After successful integration testing:

1. **Implement proper Auth0 authentication**
   - Follow Auth0 setup guides for iOS and Phoenix
   - Configure Auth0 credentials in both apps
   - Test full Auth0 flow

2. **Add user management features**
   - User profile editing
   - User search and discovery
   - Friend/contact management

3. **Enhance security**
   - Implement token refresh logic
   - Add token expiration handling
   - Add proper error handling for auth failures

4. **Add production readiness**
   - Environment-based configuration
   - Proper logging levels for production
   - Security headers and CORS configuration
   - Rate limiting and abuse prevention

## Questions?

If you encounter any issues not covered in this guide:

1. Check the logs on both iOS and backend
2. Verify all code changes are in place
3. Ensure dependencies are up to date
4. Try restarting both the backend and iOS app

---

**Last Updated**: October 22, 2025
**Status**: Active Development - Testing Mode Only

