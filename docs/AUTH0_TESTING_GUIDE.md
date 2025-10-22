# Auth0 Integration Testing Guide

## Prerequisites

- ✅ Auth0 dashboard configured
- ✅ iOS app built and running
- ✅ Phoenix backend environment variables set
- ✅ Backend dependencies installed (`mix deps.get`)

---

## Test 1: Phoenix Backend Startup

### Goal: Verify backend can start with Auth0 configuration

### Steps

1. **Set Environment Variables**
   ```bash
   cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
   export AUTH0_DOMAIN="dev-1672riu03fjuf7so.us.auth0.com"
   export AUTH0_AUDIENCE="https://api.globalbridge.dev"
   export GUARDIAN_SECRET_KEY="$(openssl rand -base64 32)"
   ```

2. **Start Phoenix Server**
   ```bash
   mix phx.server
   ```

3. **Expected Output**
   ```
   [info] Running GlobalbridgeBackendWeb.Endpoint with Bandit 1.5.6 at 127.0.0.1:4000
   [debug] 🔐 [AUTH0] Verifying token for domain: dev-1672riu03fjuf7so.us.auth0.com
   ```

### ✅ Passed if
- Server starts without errors
- No "undefined" errors in auth modules

---

## Test 2: Decode Auth0 Token (Development Only)

### Goal: Verify Auth0 token structure and claims

### Steps

1. **Get a Token from iOS**
   - Build and run the iOS app
   - Tap "Login"
   - Complete Auth0 login
   - In Xcode console, look for: `Access Token: eyJhbGci...`
   - Copy the full token

2. **Decode at jwt.io**
   - Go to https://jwt.io
   - Paste the token in the input
   - View the decoded header and payload

3. **Verify Claims**
   
   **Header should contain:**
   ```json
   {
     "typ": "JWT",
     "alg": "RS256",  // ← Important: RS256 not HS256
     "kid": "..."     // ← Key ID from Auth0
   }
   ```

   **Payload should contain:**
   ```json
   {
     "sub": "auth0|...",          // ← Your Auth0 user ID
     "aud": "https://api.globalbridge.dev",  // ← Must match AUTH0_AUDIENCE
     "iss": "https://dev-1672riu03fjuf7so.us.auth0.com/",  // ← Must match AUTH0_DOMAIN
     "exp": 1698005400,           // ← Future timestamp
     "email": "your@email.com",
     "email_verified": true,
     "name": "Your Name"
   }
   ```

### ✅ Passed if
- All required claims are present
- Algorithm is RS256
- Expiration is in the future
- Audience matches your Auth0 API identifier

---

## Test 3: Token Verification in Phoenix (Manual)

### Goal: Verify Auth0Verifier can validate a real token

### Steps

1. **Start Phoenix Console**
   ```bash
   cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
   iex -S mix
   ```

2. **Test Token Verification**
   ```elixir
   # Paste your real Auth0 token here (from iOS)
   token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Ik..."
   
   # Verify the token
   GlobalbridgeBackend.Auth.Auth0Verifier.verify_token(token)
   
   # You should see:
   # {:ok, %{
   #   "sub" => "auth0|...",
   #   "aud" => "https://api.globalbridge.dev",
   #   ...
   # }}
   ```

3. **Check Logs**
   ```
   ✅ [AUTH0] Token verified for user: auth0|...
   ✅ [AUTH0] Audience verified: https://api.globalbridge.dev
   ✅ [AUTH0] Issuer verified: https://dev-1672riu03fjuf7so.us.auth0.com/
   ✅ [AUTH0] Token valid. Expires in 82400 seconds
   ```

### ✅ Passed if
- Token verification returns `:ok` tuple with claims
- All claim verifications show ✅ in logs

### ❌ Failed if
- Audience mismatch → Check `AUTH0_AUDIENCE`
- Issuer mismatch → Check `AUTH0_DOMAIN`
- Token expired → Get a fresh token from iOS

---

## Test 4: WebSocket Connection with Token

### Goal: Connect to Phoenix from iOS with real Auth0 token

### Steps

**On Backend (Terminal 1):**
```bash
cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
mix phx.server
```

Watch for auth logs.

**On iOS (Terminal 2, Xcode):**

1. Open Xcode with iOS project
2. Make sure `AuthManager` is initialized:
   ```swift
   @State private var authToken: String?
   
   Task {
       do {
           authToken = try await AuthManager.shared.login()
       } catch {
           print("Login failed: \(error)")
       }
   }
   ```

3. Connect to WebSocket:
   ```swift
   guard let token = authToken else {
       print("No token available")
       return
   }
   
   let socket = Socket(
       "ws://localhost:4000/socket",
       params: ["token": token]
   )
   socket.connect()
   ```

4. Check Xcode console for socket connection log

**Expected Phoenix Logs:**
```
🔐 [AUTH] Token-based connection attempt
✅ [AUTH0] Token verified for user: auth0|...
✅ [AUTH] Token verified successfully, user_id: UUID, username: ...
📊 [AUTH] Socket assigned: user_id=UUID
```

### ✅ Passed if
- Phoenix logs show "Token verified successfully"
- Socket connection established
- No "error" messages in logs

### ❌ Failed if
- `❌ [AUTH] JWT token verification failed` → See error details below

---

## Test 5: Join a Channel

### Goal: Connect to WebSocket and join a channel

### Steps

**After WebSocket connection from Test 4:**

```swift
// Once socket is connected, join a channel
let channel = socket.channel("user:\(userId)", params: [:])
channel.on("message") { message in
    print("Received: \(message)")
}
channel.join()
```

**Expected Phoenix Logs:**
```
[info] JOINED user:UUID using GlobalbridgeBackendWeb.UserChannel
[debug] 📊 [CHANNEL] User UUID joined user:UUID channel
```

### ✅ Passed if
- "JOINED" message in Phoenix logs
- No authentication errors

---

## Test 6: Token Expiration & Refresh

### Goal: Verify token refresh works before expiration

### Steps

1. **Note Token Expiration (from iOS Console)**
   ```
   ⏰ [AUTH] Token expires in 86400 seconds  // ← Note this
   ```

2. **Wait (or simulate)**
   - Actual test: Wait ~22 hours, check if auto-refresh happens
   - Development: Manually test with custom token with near-future expiration

3. **Manually Trigger Refresh**
   ```swift
   let newToken = try await AuthManager.shared.refreshToken()
   print("New token: \(newToken)")
   ```

4. **Expected Logs**
   ```
   🔄 [AUTH] Token needs refresh, attempting refresh...
   ✅ [AUTH] Token refreshed. New expiration in 86400 seconds
   ⏰ [AUTH] Scheduling token refresh in 82800 seconds
   ```

### ✅ Passed if
- New token is different from old token
- Auto-refresh scheduled for next cycle
- Socket remains connected

---

## Test 7: Error Handling - Expired Token

### Goal: Verify backend rejects expired tokens gracefully

### Steps

1. **Create an Expired Token** (for testing)
   - Get a valid token
   - Modify the "exp" claim to a past timestamp
   - Use modified token at jwt.io to verify it's marked as expired

2. **Try to Connect with Expired Token**
   ```swift
   let socket = Socket("ws://localhost:4000/socket", params: ["token": expiredToken])
   socket.connect()
   ```

3. **Check Phoenix Logs**
   ```
   ⏰ [AUTH] Token expired. Expiration time: ..., Now: ...
   ❌ [AUTH0] Token verification failed: token_expired
   ```

4. **Check iOS Behavior**
   - Socket connection should fail
   - AuthManager should catch error
   - Should trigger token refresh

### ✅ Passed if
- Phoenix rejects with token_expired error
- Doesn't crash or hang
- Error message is helpful

---

## Test 8: Error Handling - Wrong Audience

### Goal: Verify backend rejects tokens for other apps

### Steps

1. **Simulate Wrong Audience**
   - Modify a token (or create in Auth0) with wrong audience
   - Example: `aud: "https://some-other-app.com"`

2. **Try to Connect**
   ```swift
   let socket = Socket("ws://localhost:4000/socket", params: ["token": wrongAudToken])
   socket.connect()
   ```

3. **Check Phoenix Logs**
   ```
   ❌ [AUTH0] Audience mismatch. Expected: https://api.globalbridge.dev, Got: https://some-other-app.com
   ❌ [AUTH0] Token verification failed: invalid_audience
   ```

### ✅ Passed if
- Phoenix clearly rejects with audience mismatch
- Security prevents cross-app token use

---

## Test 9: Error Handling - No Token

### Goal: Verify backend rejects connections without token

### Steps

1. **Connect Without Token**
   ```swift
   let socket = Socket("ws://localhost:4000/socket", params: [:])
   socket.connect()
   ```

2. **Check Phoenix Logs**
   ```
   ❌ [AUTH] Dev mode connection accepted, user_id: ...
   ```
   (or error if dev mode is off)

### ✅ Passed if
- Connection is rejected or fails
- No security bypass

---

## Test 10: Full Flow End-to-End

### Goal: Complete authentication flow from iOS to real-time messaging

### Setup: Two Instances

**Terminal 1 - Backend:**
```bash
cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
export AUTH0_DOMAIN="dev-1672riu03fjuf7so.us.auth0.com"
export AUTH0_AUDIENCE="https://api.globalbridge.dev"
mix phx.server
```

**Terminal 2 - iOS (Xcode):**
- Build and run the app
- Have console visible

### Steps

1. **iOS: Tap Login**
   - App opens Safari
   - You see Auth0 login page
   - Enter credentials
   - Accept redirect
   - App returns to foreground

2. **Xcode Console: Check Token**
   ```
   ✅ [AUTH] Login successful
      User ID: auth0|...
      Access Token: eyJhbGci...
   ```

3. **Backend: Watch for Connection**
   - Should not see any auth errors
   - Wait ~5 seconds

4. **Xcode: WebSocket Connect Code**
   ```swift
   let token = try await AuthManager.shared.getAccessToken()
   let socket = Socket("ws://localhost:4000/socket", params: ["token": token])
   socket.connect()
   ```

5. **Phoenix: Check Logs**
   ```
   🔐 [AUTH] Token-based connection attempt
   ✅ [AUTH0] Token verified for user: auth0|...
   ✅ [AUTH] Token verified successfully
   [info] JOINED user:UUID using GlobalbridgeBackendWeb.UserChannel
   ```

6. **iOS: Send Test Message**
   ```swift
   channel.push("message", payload: ["content": "Hello from iOS!"])
   ```

7. **Backend: Receive Message**
   ```
   [info] Received message: "Hello from iOS!"
   ```

### ✅ Passed if
- All steps complete without errors
- Messages flow end-to-end
- No authentication failures
- Logs are clean (no warnings except expected ones)

---

## Troubleshooting Quick Reference

| Problem | Check | Solution |
|---------|-------|----------|
| "Audience mismatch" | `AUTH0_AUDIENCE` in .env | Must exactly match Auth0 API identifier |
| "Issuer mismatch" | `AUTH0_DOMAIN` in .env | No `https://` or trailing `/` |
| "Token expired" | Token `exp` claim | Get fresh token from iOS or wait for auto-refresh |
| "Invalid format" | Token format | Ensure full JWT (3 parts with dots) |
| WebSocket won't connect | Logs | Check if dev mode is enabled in config |
| "Auth0 error" (iOS) | iOS console | May be Auth0 config issue, check domain/client ID |
| Phoenix won't start | Logs | Check if Joken dep installed: `mix deps.get` |

---

## Logging Commands

### Phoenix: Check Auth Logs

```elixir
iex> require Logger
iex> Logger.configure(level: :debug)  # Show all debug logs
```

### iOS: Check AuthManager Logs

```swift
// Logs appear automatically in Xcode console
// Look for [AUTH] prefixed messages
print("Auth error: \(AuthManager.shared.authError ?? "none")")
```

---

## Performance Baseline

### Expected Timings

- Token verification: < 100ms
- WebSocket connection: < 500ms  
- Full login flow: 5-15 seconds (includes Auth0 UI)
- Token refresh: < 100ms

---

## Success Criteria

✅ **All tests pass if:**
- [ ] Phoenix starts with Auth0 config
- [ ] Token claims are valid and present
- [ ] Token verification succeeds in console
- [ ] WebSocket connects with valid token
- [ ] Invalid tokens are rejected
- [ ] Token refresh works
- [ ] Channel join succeeds
- [ ] Real-time messaging works
- [ ] Error messages are helpful
- [ ] No crashes or hangs

---

## Next Steps After Testing

1. **If everything passes:**
   - ✅ Your Auth0 + Phoenix + iOS integration is working!
   - Commit these changes
   - Deploy to test environment

2. **If any test fails:**
   - Check logs carefully
   - See troubleshooting section
   - Verify environment variables
   - Review Auth0 configuration
   - Check that all code changes are in place

---

**Last Updated:** October 21, 2025
**Test Framework:** Manual integration testing
**Duration:** ~30 minutes for full suite
