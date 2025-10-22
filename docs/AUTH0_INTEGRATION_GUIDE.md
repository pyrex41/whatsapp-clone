# Complete Auth0 + Phoenix + iOS Integration Guide

## Overview

This guide explains how Auth0, Phoenix, and iOS work together to provide secure authentication for GlobalBridge.

### The Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    1. iOS App                               │
│     Opens Safari → Auth0 Login Page → Get ID Token         │
└────────────────┬────────────────────────────────────────────┘
                 │ Auth0 ID Token
                 ▼
┌─────────────────────────────────────────────────────────────┐
│                  2. iOS App                                 │
│     Store token in Keychain                                 │
│     Send to Phoenix via WebSocket connection               │
└────────────────┬────────────────────────────────────────────┘
                 │ WS: { token: "eyJhbGci..." }
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              3. Phoenix Backend                             │
│     Verify Auth0 signature & claims                        │
│     Find or create local user                              │
│     Join authenticated WebSocket channel                   │
└────────────────┬────────────────────────────────────────────┘
                 │ authenticated connection
                 ▼
┌─────────────────────────────────────────────────────────────┐
│           4. Real-time Messaging                           │
│     Send/receive messages over secure WebSocket           │
│     Token auto-refreshes before expiration                │
└─────────────────────────────────────────────────────────────┘
```

---

## Components

### 1. Auth0 (Identity Provider)

**Purpose:** Manages user accounts and authentication

**Responsibilities:**
- User login/signup
- Password management
- Multi-factor authentication (optional)
- Token generation (access + refresh tokens)

**Configuration:**
- Domain: `dev-1672riu03fjuf7so.us.auth0.com`
- Audience: `https://api.globalbridge.dev`
- Scopes: `openid profile email offline_access`

**Setup:**
1. Create Auth0 account at https://manage.auth0.com
2. Create application with native platform
3. Create API with identifier: `https://api.globalbridge.dev`
4. Configure callback URLs in Auth0 Dashboard

### 2. iOS Client (Auth0 SDK + AuthManager)

**Purpose:** Authenticates user and manages tokens

**Key Files:**
- `Auth0Config.swift` - Stores Auth0 configuration (domain, client ID, audience)
- `AuthManager.swift` - Manages authentication state and token lifecycle

**Responsibilities:**
- Display Auth0 login via Safari
- Store tokens securely in Keychain
- Automatically refresh tokens before expiration
- Connect to Phoenix with valid token
- Handle errors and prompt for re-login

**Flow:**

```swift
// 1. User taps "Login"
let token = try await AuthManager.shared.login()

// 2. Auth0 SDK opens Safari
// 3. User logs in at Auth0
// 4. Redirect to app with credentials
// 5. AuthManager stores in Keychain
// 6. AuthManager schedules token refresh (5 minutes before expiry)
```

### 3. Phoenix Backend (Auth0Verifier + UserSocket)

**Purpose:** Validates Auth0 tokens and manages connections

**Key Files:**
- `Auth0Verifier.ex` - Validates Auth0 JWT signatures and claims
- `UserSocket.ex` - Handles WebSocket connections
- `TokenHandler.ex` - Manages token expiration and error responses

**Responsibilities:**
- Verify Auth0 token signature (production: against Auth0's public keys)
- Check required claims (sub, aud, iss, exp)
- Find or create user from Auth0 claims
- Reject expired tokens
- Provide helpful error messages

**Verification Steps:**

```elixir
# 1. Extract JWT parts (header, payload, signature)
# 2. Verify signature (asymmetric: RS256)
# 3. Check "sub" claim (user ID)
# 4. Check "aud" claim (audience) - must match https://api.globalbridge.dev
# 5. Check "iss" claim (issuer) - must match Auth0 domain
# 6. Check "exp" claim (expiration) - must be in the future
# 7. Find or create user by auth0_id
# 8. Join authenticated WebSocket channel
```

---

## Setup Instructions

### Step 1: Configure Auth0

1. **Create Auth0 Application** (if not already done)
   - Go to https://manage.auth0.com
   - Click "Applications" → "Create Application"
   - Select "Native"
   - Name: "GlobalBridge iOS"

2. **Get Your Domain**
   - In Applications → GlobalBridge iOS → Settings
   - Copy the "Domain" field

3. **Get Your Client ID**
   - Same page, copy "Client ID" field

4. **Create Auth0 API**
   - Go to "APIs" → "Create API"
   - Name: "GlobalBridge API"
   - Identifier: `https://api.globalbridge.dev`
   - Signing Algorithm: `RS256`

5. **Configure Callback URLs**
   - In Applications → GlobalBridge iOS → Settings
   - **Allowed Callback URLs** (add):
     ```
     name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
     ```
   - **Allowed Logout URLs** (add):
     ```
     name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge
     ```

### Step 2: Configure iOS App

1. **Update Auth0Config.swift**
   ```swift
   enum Auth0Config {
       static var domain: String { 
           "dev-1672riu03fjuf7so.us.auth0.com" 
       }
       
       static var clientId: String { 
           "id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj" 
       }
       
       static var audience: String { 
           "https://api.globalbridge.dev" 
       }
   }
   ```

2. **Add URL Scheme in Xcode**
   - Select GlobalBridge target
   - Go to "Info" tab
   - Add URL Type:
     - **Identifier:** `auth0`
     - **URL Schemes:** `name.reubenbrooks.globalbridge`

3. **AuthManager is already configured**
   - Handles login/logout
   - Auto-refreshes tokens
   - Stores in Keychain

### Step 3: Configure Phoenix Backend

1. **Set Environment Variables**
   ```bash
   export AUTH0_DOMAIN="dev-1672riu03fjuf7so.us.auth0.com"
   export AUTH0_AUDIENCE="https://api.globalbridge.dev"
   export GUARDIAN_SECRET_KEY="$(openssl rand -base64 32)"
   ```

   Or create `.env` file in backend root:
   ```bash
   AUTH0_DOMAIN=dev-1672riu03fjuf7so.us.auth0.com
   AUTH0_AUDIENCE=https://api.globalbridge.dev
   GUARDIAN_SECRET_KEY=your_secret_key_here
   ```

2. **Install Dependencies**
   ```bash
   cd globalbridge_backend
   mix deps.get
   ```

3. **Verify Auth0Config**
   - `Auth0Verifier` reads from environment variables
   - Falls back to hardcoded values if not set

---

## How It Works

### Authentication Flow

#### 1. User Logs In (iOS)

```swift
// AuthManager.swift
func login() async throws -> String {
    // Auth0 SDK handles the OAuth flow
    let credentials = try await Auth0
        .webAuth(clientId: auth0ClientId, domain: auth0Domain)
        .scope("openid profile email offline_access")
        .audience(auth0Audience)
        .start()
    
    // Credentials contain:
    // - accessToken: JWT for API calls
    // - refreshToken: For getting new access tokens
    // - idToken: Contains user info (sub, email, name)
    
    let credentialsManager = CredentialsManager(...)
    credentialsManager.store(credentials: credentials)  // Keychain
    
    scheduleTokenRefresh()  // Auto-refresh before expiry
    
    return credentials.accessToken
}
```

#### 2. iOS Connects to Phoenix (iOS → Phoenix)

```swift
// In Phoenix channel connection code
let token = try await AuthManager.shared.getAccessToken()
let socket = Socket(
    "ws://localhost:4000/socket",
    params: ["token": token]  // Auth0 token
)
socket.connect()
```

#### 3. Phoenix Validates Token (Phoenix)

```elixir
# UserSocket.ex - connect/3 callback
def connect(%{"token" => token}, socket, _connect_info) do
  case verify_token(token) do
    {:ok, user} ->
      # Token is valid, join authenticated channel
      {:ok, assign(socket, :user_id, user.id)}
    
    {:error, reason} ->
      Logger.warning("Authentication failed: #{reason}")
      :error
  end
end

# verify_token/1 uses Auth0Verifier
defp verify_token(token) do
  case Auth0Verifier.verify_token(token) do
    {:ok, claims} ->
      # Extract user info from Auth0 claims
      auth0_id = claims["sub"]
      email = claims["email"]
      
      # Find or create local user
      ensure_user_exists(auth0_id, email, ...)
    
    {:error, :token_expired} ->
      {:error, :token_expired}
    
    {:error, reason} ->
      {:error, reason}
  end
end
```

#### 4. Token Verification (Phoenix)

```elixir
# Auth0Verifier.ex

def verify_token(token) do
  with {:ok, header, payload, _signature} <- decode_jwt_parts(token),
       {:ok, claims} <- validate_claims(payload),
       :ok <- verify_signature(token, header),
       :ok <- check_required_claims(claims) do
    {:ok, claims}
  end
end

# Checks:
# 1. ✅ JWT format is valid (header.payload.signature)
# 2. ✅ Signature is valid (production: verify against Auth0 public keys)
# 3. ✅ Claims are present: sub, aud, iss, exp
# 4. ✅ Audience matches: https://api.globalbridge.dev
# 5. ✅ Issuer matches: https://dev-1672riu03fjuf7so.us.auth0.com/
# 6. ✅ Token is not expired
```

#### 5. User Auto-Created (Phoenix)

```elixir
# First time user logs in, we create a local record
defp ensure_user_exists(auth0_id, email, name) do
  case Repo.get_by(User, auth0_id: auth0_id) do
    nil ->
      # New user, create locally
      User.create_changeset(%User{}, %{
        auth0_id: auth0_id,
        email: email,
        username: generate_username(email),
        display_name: name
      }) |> Repo.insert()
    
    user ->
      # Existing user
      {:ok, user}
  end
end
```

#### 6. Real-time Connection (Phoenix ↔ iOS)

```elixir
# UserSocket.ex - id/1 callback
def id(socket), do: "user_socket:#{socket.assigns.user_id}"

# iOS is now authenticated and can:
# - Join channels: thread:#{thread_id}
# - Receive messages in real-time
# - Send messages (pushed to other clients)
```

### Token Refresh Flow

#### Automatic Refresh (iOS)

```swift
// AuthManager schedules refresh 5 minutes before expiration
private func scheduleTokenRefresh() {
    let timeUntilExpiry = tokenExpiresAt.timeIntervalSinceNow
    let refreshTime = timeUntilExpiry - (5 * 60)  // Refresh early
    
    Task {
        try? await Task.sleep(nanoseconds: UInt64(refreshTime * 1_000_000_000))
        
        // Auto-refresh happens here
        try? await refreshToken()
    }
}

// Manual refresh if needed
func refreshToken() async throws -> String {
    let credentialsManager = CredentialsManager(...)
    let credentials = try await credentialsManager.credentials()
    
    accessToken = credentials.accessToken  // New token
    refreshToken = credentials.refreshToken  // New refresh token
    
    // Schedule next refresh
    scheduleTokenRefresh()
    
    return credentials.accessToken
}
```

#### On Expiration Error (Phoenix → iOS)

If a token expires between refresh cycles:

```
iOS sends expired token
       ↓
Phoenix: "error: token_expired"
       ↓
iOS: AuthManager catches error
       ↓
iOS: Calls refreshToken()
       ↓
iOS: Retries WebSocket connection with new token
```

---

## Error Scenarios

### Scenario 1: Token Expired

**iOS Side:**
- AutoRefresh task fires
- Gets new token from Auth0
- Retries WebSocket connection

**Phoenix Side:**
```elixir
{:error, :token_expired}
```

### Scenario 2: Invalid Audience

**Phoenix:**
```
Expected: https://api.globalbridge.dev
Got: https://wrong-app.com
Result: {:error, :invalid_audience}
```

**Why:** Token is for a different app

**Fix:** Check `AUTH0_AUDIENCE` matches Auth0 API identifier

### Scenario 3: Invalid Signature (Production)

**Phoenix:**
```
Signature does not match Auth0 public key
Result: {:error, :signature_invalid}
```

**Why:** Token was forged or corrupted

**Security:** Production backend will verify signatures against Auth0's JWKS endpoint

### Scenario 4: User Not Found in DB

**Phoenix:**
```elixir
# Auth0 token is valid, but we haven't created local user
ensure_user_exists(auth0_id, email, name)
# → Creates new user automatically
# → Connection succeeds
```

---

## Configuration Reference

### Environment Variables

| Variable | Value | Source |
|----------|-------|--------|
| `AUTH0_DOMAIN` | `dev-1672riu03fjuf7so.us.auth0.com` | Auth0 Dashboard |
| `AUTH0_AUDIENCE` | `https://api.globalbridge.dev` | Auth0 API Identifier |
| `GUARDIAN_SECRET_KEY` | `<random 32+ chars>` | Generate with `openssl rand -base64 32` |

### iOS Configuration

| Config | Value |
|--------|-------|
| Bundle ID | `name.reubenbrooks.globalbridge` |
| URL Scheme | `name.reubenbrooks.globalbridge` |
| Auth0 Domain | `dev-1672riu03fjuf7so.us.auth0.com` |
| Auth0 Client ID | `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj` |
| Auth0 Audience | `https://api.globalbridge.dev` |

### JWT Token Claims

**Access Token (from Auth0):**
```json
{
  "sub": "auth0|6359f8c8f1a2b3c4d5e6f7g",
  "aud": "https://api.globalbridge.dev",
  "iss": "https://dev-1672riu03fjuf7so.us.auth0.com/",
  "exp": 1698005400,
  "iat": 1697921000,
  "email": "user@example.com",
  "email_verified": true,
  "name": "John Doe"
}
```

**Required Claims Verified by Backend:**
- `sub` - User ID (unique identifier)
- `aud` - Audience (must match `AUTH0_AUDIENCE`)
- `iss` - Issuer (must match `https://{AUTH0_DOMAIN}/`)
- `exp` - Expiration time (must be > now)

---

## Testing

### 1. Test Auth0 Login (iOS)

```swift
let token = try await AuthManager.shared.login()
print("Token: \(token)")
print("User ID: \(AuthManager.shared.getUserId())")
```

Expected output:
```
✅ [AUTH] Login successful
   User ID: auth0|6359f8c8f1a2b3c4d5e6f7g
   Access Token: eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

### 2. Decode Token (Development Only)

Use https://jwt.io to decode and inspect the token:
- **Header:** Shows algorithm (RS256)
- **Payload:** Shows claims (sub, aud, iss, exp, etc.)
- **Signature:** Can be verified against Auth0 public keys

### 3. Test Phoenix Connection (iOS)

```swift
let token = try await AuthManager.shared.getAccessToken()
let socket = Socket("ws://localhost:4000/socket", params: ["token": token])
socket.connect()
```

Check Phoenix logs:
```
🔐 [AUTH] Token-based connection attempt
✅ [AUTH0] Token verified for user: auth0|6359f8c8f1a2b3c4d5e6f7g
✅ [AUTH] Token verified successfully
```

### 4. Test Token Expiration

In development, you can manually test expiration:

```elixir
# In Phoenix console:
iex> Auth0Verifier.decode_unverified(token)
# Look at the "exp" field, check if current time > exp

# In iOS:
let expiredToken = "..."  # Use a token with past exp time
try await Phoenix.connect(token: expiredToken)
# Should fail with :token_expired error
```

---

## Production Checklist

- [ ] Auth0 Domain and Client ID are set
- [ ] Auth0 Callback URLs are configured
- [ ] iOS URL Scheme is registered
- [ ] Environment variables are set
- [ ] `GUARDIAN_SECRET_KEY` is strong and random
- [ ] Production Auth0 app is configured
- [ ] JWT signature verification is enabled (check Auth0Verifier production notes)
- [ ] SSL/TLS is enabled for Phoenix
- [ ] Token expiration times are appropriate
- [ ] Error messages don't leak sensitive information
- [ ] Logging is configured appropriately (not too verbose in production)

---

## Troubleshooting

### Phoenix Logs

#### "Audience mismatch"
```
Check: AUTH0_AUDIENCE matches Auth0 API identifier
Solution: Verify in Auth0 Dashboard → APIs → Your API → Identifier
```

#### "Issuer mismatch"
```
Check: AUTH0_DOMAIN is correct and doesn't have https:// or /
Solution: Should be just the domain like "dev-abc123.us.auth0.com"
```

#### "Token expired"
```
Check: Client time is synced with server
Solution: Auto-refresh should handle this, but ensure clocks are accurate
```

### iOS Logs

#### "No valid credentials available"
```
Check: Token hasn't been stored in Keychain
Solution: Complete login flow first, check for errors during login
```

#### "Auth0 error: ..."
```
Check: Auth0 domain, client ID, and URL scheme are correct
Solution: Print `AuthManager.shared.authError` to see details
```

---

## Resources

- [Auth0 Documentation](https://auth0.com/docs)
- [Auth0 iOS SDK](https://github.com/auth0/Auth0.swift)
- [Phoenix WebSocket Guide](https://hexdocs.pm/phoenix/Phoenix.Socket.html)
- [JWT.io - Token Inspector](https://jwt.io)
- [RFC 7519 - JWT](https://tools.ietf.org/html/rfc7519)

---

**Last Updated:** October 21, 2025
**Maintainer:** @reuben
