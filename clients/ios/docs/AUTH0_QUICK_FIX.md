# Auth0 Quick Fix Guide

## The Problem

You're seeing these errors:
- ❌ Auth0 login screen never appears
- ❌ `Token verification failed: :invalid_jwt`
- ❌ `Unable to load threads`

## The Root Cause

Auth0 is returning **encrypted JWE tokens** (5 parts) instead of **standard JWT tokens** (3 parts). The backend can only decode JWT tokens.

Additionally, the Auth0 callback URL may not be registered in your Auth0 dashboard, preventing the login UI from appearing.

## The Fix (5 minutes)

### Step 1: Register Callback URL in Auth0

1. Go to https://manage.auth0.com/dashboard
2. Navigate to **Applications > Applications**
3. Click on your application: **GlobalBridge** (Client ID: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`)
4. Go to the **Settings** tab
5. Scroll down to **Application URIs**

**Add this to "Allowed Callback URLs":**
```
name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
```

**Add this to "Allowed Logout URLs":**
```
name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
```

6. Scroll down and click **Save Changes**

### Step 2: Configure API to Return JWT Instead of JWE

1. In Auth0 Dashboard, go to **Applications > APIs**
2. Find the API with identifier: **`globalbridge-api`**
3. Click on it to open settings
4. Go to **Settings** tab
5. Scroll to **Access Settings** section
6. Find **Signing Algorithm**: Should be **RS256** ✅
7. **IMPORTANT**: If there's a "Token Format" or "Token Encryption" setting:
   - Set it to **"JWT"** (not "JWE" or "Opaque")
   - Disable token encryption if enabled
8. Scroll down and click **Save**

### Step 3: Verify Changes

1. **Clear iOS app data**: Delete the app and reinstall (or logout first)
2. **Start backend**:
   ```bash
   cd globalbridge_backend
   mix phx.server
   ```
3. **Run iOS app** from Xcode in Debug mode
4. **Watch console logs**:
   - iOS should show: "🌐 [AUTH] About to open Auth0 web login UI..."
   - Safari/Auth0 login screen should appear
   - After login: "✅ [AUTH] Auth0 webAuth completed successfully!"
   - Should show: "Access Token Parts: 3 (JWT=3, JWE=5)" ✅
   - Backend should show: "🔍 [AUTH0] Token format: JWT (3 parts) ✅"

## What Changed in Code

### iOS: Enhanced Auth0 Logging

**File**: `clients/ios/GlobalBridge/Core/Auth/AuthManager.swift`

Now provides detailed diagnostics:
- Shows Auth0 configuration before login
- Prints callback URL requirements
- Analyzes token format (JWT vs JWE)
- Provides Auth0 dashboard configuration instructions

### Backend: JWE Detection

**File**: `globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`

Now detects JWE tokens and provides helpful error messages:
```
❌ [AUTH0] Token format: JWE (5 parts) - ENCRYPTED TOKEN DETECTED!
   ⚠️  Backend cannot decode JWE tokens. You must configure Auth0 to return JWT tokens.
   📋 Fix: Auth0 Dashboard > APIs > globalbridge-api > Settings > Token Format: JWT
```

## Expected Console Output After Fix

### iOS Console (Success):
```
🔐 [AUTH] Starting Auth0 login...
📱 [AUTH] Bundle ID: name.reubenbrooks.globalbridge
🔍 [AUTH] Auth0 Configuration:
   - Domain: dev-1672riu03fjuf7so.us.auth0.com
   - Client ID: id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj
   - Audience: globalbridge-api
🔗 [AUTH] Expected callback: name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
🌐 [AUTH] About to open Auth0 web login UI...
🚀 [AUTH] Calling Auth0.webAuth().start()...
[User logs in via Safari]
✅ [AUTH] Auth0 webAuth completed successfully!
📊 [AUTH] Token details:
   - Access Token: eyJhbGciOiJSUzI1NiIsInR5cCI6...
   - Access Token Parts: 3 (JWT=3, JWE=5) ✅
   - ID Token Parts: 3 (JWT=3, JWE=5) ✅
🔌 [REALTIME] Connecting with Auth0 token...
✅ [REALTIME] Phoenix connected
👤 [REALTIME] Joining user channel for: auth0|68ed8a33262e564977c4a95b
✅ [REALTIME] User channel joined
📥 [LOAD_THREADS] Starting thread load...
✅ [LOAD_THREADS] Loaded 3 threads from local DB
```

### Backend Console (Success):
```
🔐 [AUTH0] Attempting to verify token: eyJhbGciOiJSUzI1NiIs...
🔍 [AUTH0] Token format: JWT (3 parts) ✅
🔐 [AUTH0] Token claims: sub=auth0|68ed8a33262e564977c4a95b, email=user@example.com
✅ [AUTH0] Existing user found: id=abc-123, username=user_1234567890
✅ [USER_CHANNEL] User channel joined: user:auth0|68ed8a33262e564977c4a95b
```

## Troubleshooting

### Still Seeing JWE Tokens?

If you still see "Access Token Parts: 5 (JWT=3, JWE=5)":
1. Wait 1-2 minutes for Auth0 settings to propagate
2. Clear app data completely
3. Logout and login again
4. If persists, check if there's an "Encryption" section in API settings - disable it

### Auth0 UI Still Not Appearing?

1. Check Xcode console for Auth0 errors
2. Verify callback URL is EXACTLY as shown (no extra spaces/characters)
3. Try logging out first: `AuthManager.shared.logout()`
4. Restart the app

### Backend Still Rejecting Token?

Check backend logs for specific error:
- If `JWE token not supported`: Auth0 API settings not saved correctly
- If `invalid_jwt`: Token might be malformed
- If `not_auth0_token`: Claims missing (check `sub`, `iss`, `aud`)

## Need More Help?

See full documentation in:
- `clients/ios/docs/AUTH0_SETUP.md` - Complete Auth0 configuration guide
- `clients/ios/docs/BACKEND_CONFIGURATION.md` - Environment switching guide

## Summary of Required Actions

✅ **Code Changes**: Already done
⚠️  **Auth0 Dashboard**: **YOU NEED TO DO THIS**
   - Register callback URL
   - Set API token format to JWT
🧪 **Testing**: After Auth0 changes, clear app and test login
