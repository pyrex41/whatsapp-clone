# Authentication System - Issues Summary

## Overview

This document provides a comprehensive summary of all issues identified in the WhatsApp clone's Auth0 authentication implementation across iOS, Expo, and Phoenix backend.

---

## 🔴 CRITICAL ISSUES (Fix Immediately)

### 1. No JWT Signature Verification
**Location**: `globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`
**Lines**: 50-65

**Problem**:
The backend accepts JWT tokens without verifying their cryptographic signature. The code only checks if required claims (`sub`, `aud`, `iss`) exist, but never validates that the token was actually signed by Auth0.

**Code**:
```elixir
# auth0_verifier.ex lines 50-65
defp verify_auth0_claims(claims) do
  # In production, verify:
  # 1. Token signature against Auth0's public keys
  # 2. Issuer (iss) matches your Auth0 domain
  # 3. Audience (aud) matches your API identifier
  # 4. Token hasn't expired (exp)
  # For development, we'll accept it
  cond do
    !Map.has_key?(claims, "sub") -> {:error, :missing_sub}
    !Map.has_key?(claims, "aud") -> {:error, :missing_audience}
    !Map.has_key?(claims, "iss") -> {:error, :missing_issuer}
    true -> {:ok, claims}
  end
end
```

**Attack Vector**:
```bash
# Attacker can create a fake JWT with valid claims
{
  "sub": "auth0|victim_user_id",
  "aud": "globalbridge-api",
  "iss": "https://dev-1672riu03fjuf7so.us.auth0.com/"
}
# Backend accepts this without checking signature
# Attacker impersonates any user
```

**Impact**:
- Any attacker can forge a JWT token with correct claims
- Can impersonate any user by setting `sub` to their Auth0 ID
- Complete authentication bypass
- **Severity**: CRITICAL

**Fix Required**:
```elixir
# 1. Fetch Auth0's JWKS (public keys)
jwks_url = "https://#{auth0_domain}/.well-known/jwks.json"

# 2. Use Joken or JOSE library to verify signature
defp verify_token_signature(token, jwks) do
  with {:ok, header} <- Joken.peek_header(token),
       {:ok, key} <- find_key_by_kid(jwks, header["kid"]),
       {:ok, claims} <- Joken.verify(token, key) do
    {:ok, claims}
  else
    error -> {:error, :invalid_signature}
  end
end

# 3. Verify all claims including expiration
defp verify_claims(claims) do
  now = System.system_time(:second)

  cond do
    claims["exp"] < now -> {:error, :token_expired}
    claims["iss"] != expected_issuer -> {:error, :wrong_issuer}
    claims["aud"] != expected_audience -> {:error, :wrong_audience}
    true -> {:ok, claims}
  end
end
```

---

### 2. No Token Expiration Check
**Location**: `globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`
**Lines**: 50-65

**Problem**:
Backend never checks the `exp` (expiration), `iat` (issued at), or `nbf` (not before) claims. Tokens that expired months or years ago are still accepted.

**Impact**:
- Stolen tokens remain valid forever
- No way to revoke compromised tokens
- Increases attack window significantly
- **Severity**: CRITICAL

**Fix Required**:
```elixir
defp check_expiration(claims) do
  now = System.system_time(:second)
  exp = Map.get(claims, "exp", 0)

  if exp < now do
    {:error, :token_expired}
  else
    {:ok, claims}
  end
end
```

---

### 3. Development Mode Authentication Bypass
**Location**: `globalbridge_backend/lib/globalbridge_backend_web/channels/user_socket.ex`
**Lines**: 66-109

**Problem**:
When `dev_mode: true` is set in config, the backend completely bypasses all authentication. This is enabled in `config/dev.exs` and never explicitly disabled in `config/prod.exs`.

**Code**:
```elixir
# user_socket.ex lines 66-109
def connect(params, socket, _connect_info) do
  config = Application.get_env(:globalbridge_backend, GlobalbridgeBackendWeb.UserSocket, [])
  dev_mode = Keyword.get(config, :dev_mode, false)

  if dev_mode do
    Logger.warning("⚠️ DEV MODE: Accepting connection without authentication")
    # Accept ANY connection without checking token
    {:ok, assign(socket, :user_id, generate_dev_user_id())}
  else
    # ... actual auth logic ...
  end
end
```

**Impact**:
- If accidentally enabled in production, anyone can connect
- No credentials required at all
- Complete system compromise
- **Severity**: CRITICAL

**Fix Required**:
```elixir
# config/prod.exs - explicitly disable
config :globalbridge_backend, GlobalbridgeBackendWeb.UserSocket,
  dev_mode: false  # MUST be false in production

# user_socket.ex - add safeguard
def connect(params, socket, _connect_info) do
  if Mix.env() == :prod and dev_mode do
    raise "CRITICAL: dev_mode cannot be enabled in production!"
  end
  # ... rest of logic ...
end
```

---

### 4. Secrets Committed to Git
**Location**: `globalbridge_backend/.env`
**Status**: Committed to repository

**Problem**:
The `.env` file containing `AUTH0_CLIENT_SECRET` is committed to Git and visible in the repository history.

**Exposed Secret**:
```bash
AUTH0_CLIENT_SECRET=kT0Pl...xfvH7  # Real secret visible in repo
```

**Impact**:
- Anyone with repo access can see the secret
- Secret is in Git history permanently
- Can't be fully removed without rewriting history
- Attackers could use secret to impersonate your application
- **Severity**: CRITICAL

**Fix Required**:
1. Add `.env` to `.gitignore`
2. Rotate the Auth0 client secret in Auth0 dashboard
3. Use environment variables in production
4. Consider using secret management service (AWS Secrets Manager, HashiCorp Vault)

```bash
# .gitignore
.env
.env.local
.env.*.local
*.secret
```

---

## 🟠 HIGH PRIORITY ISSUES

### 5. Simple Token Fallback Bypass
**Location**: `globalbridge_backend/lib/globalbridge_backend_web/channels/user_socket.ex`
**Lines**: 123-158

**Problem**:
If a token doesn't look like a JWT, the system falls back to accepting simple "user:uuid" format tokens.

**Code**:
```elixir
# Lines 123-158
case Auth0Verifier.verify_token(token) do
  {:ok, user} ->
    {:ok, assign(socket, :user_id, user.id)}

  {:error, _reason} ->
    # Fallback: try parsing as simple token
    case parse_simple_token(token) do
      {:ok, user_id} -> {:ok, assign(socket, :user_id, user_id)}
      _ -> :error
    end
end

defp parse_simple_token("user:" <> uuid_string) do
  case Ecto.UUID.cast(uuid_string) do
    {:ok, user_id} -> {:ok, user_id}
    :error -> :error
  end
end
```

**Attack Vector**:
```bash
# Attacker sends token: "user:00000000-0000-0000-0000-000000000001"
# System accepts it and assigns that user_id
# No Auth0 verification at all
```

**Impact**:
- Bypasses Auth0 completely
- Can connect as any user if you know their UUID
- **Severity**: HIGH

**Fix Required**:
Remove the fallback entirely or require additional authentication for simple tokens.

---

### 6. Hardcoded iOS Credentials
**Location**: `clients/ios/GlobalBridge/Core/Config/Auth0Config.swift`
**Lines**: 15-35

**Problem**:
Auth0 domain and client ID are hardcoded directly in source code with comments saying "TEMPORARY" but never fixed.

**Code**:
```swift
// Lines 15-22
static var domain: String {
    let correctDomain = "dev-1672riu03fjuf7so.us.auth0.com"
    let envDomain = ProcessInfo.processInfo.environment["AUTH0_DOMAIN"] ?? "not set"
    print("⚠️ [Auth0Config] FORCING correct domain: \(correctDomain)")
    return correctDomain
}

static var clientId: String {
    let correctClientId = "id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj"
    // ... same pattern ...
}
```

**Impact**:
- Credentials visible in source code
- Difficult to change for different environments
- Can't easily switch between dev/staging/prod
- **Severity**: HIGH

**Fix Required**:
```swift
// 1. Create Auth0.plist configuration file
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Domain</key>
    <string>$(AUTH0_DOMAIN)</string>
    <key>ClientId</key>
    <string>$(AUTH0_CLIENT_ID)</string>
    <key>Audience</key>
    <string>$(AUTH0_AUDIENCE)</string>
</dict>
</plist>

// 2. Read from plist
static var domain: String {
    guard let path = Bundle.main.path(forResource: "Auth0", ofType: "plist"),
          let plist = NSDictionary(contentsOfFile: path),
          let domain = plist["Domain"] as? String else {
        fatalError("Auth0.plist not found or invalid")
    }
    return domain
}
```

---

### 7. Audience Configuration Mismatch
**Location**: Multiple files

**Problem**:
Different audience values across platforms:
- Backend `.env`: `globalbridge-api` ✅
- iOS: `globalbridge-api` ✅
- Expo `.env.example`: `https://globalbridge-api` ❌ (wrong - has https://)
- Docs: `https://api.globalbridge.dev` ❌ (completely different)

**Impact**:
- Expo tokens may fail validation
- Confusion during setup
- Documentation doesn't match implementation
- **Severity**: HIGH

**Fix Required**:
1. Verify actual audience value in Auth0 Dashboard (APIs → Identifier field)
2. Update all configs to match exactly:
   - No `https://` prefix
   - Use exact identifier from Auth0

---

## 🟡 MEDIUM PRIORITY ISSUES

### 8. Duplicate User Creation Logic
**Location**: Multiple files
- `auth0_verifier.ex` lines 67-107
- `user_socket.ex` lines 195-245

**Problem**:
User creation/retrieval logic exists in two places with slight differences. Potential for race conditions if both execute simultaneously.

**Impact**:
- Code duplication
- Maintenance burden
- Potential race condition
- **Severity**: MEDIUM

**Fix Required**:
Consolidate into single `get_or_create_user/1` function.

---

### 9. No Backend Token Refresh
**Location**: Backend (feature missing)

**Problem**:
Backend has no capability to refresh Auth0 tokens. Only supports Guardian token refresh.

**Impact**:
- iOS must handle all token refresh
- Backend can't validate refresh tokens
- Can't implement backend-initiated token refresh
- **Severity**: MEDIUM

**Fix Required**:
Implement Auth0 token refresh endpoint using client credentials.

---

### 10. FeatureFlags Synchronous Token Access
**Location**: `clients/ios/GlobalBridge/Utilities/FeatureFlags.swift`
**Lines**: 113, 159

**Problem**:
Uses synchronous `getAccessToken()` call in async context. Token may not be available.

**Code**:
```swift
// Line 113 - PROBLEM
guard let token = AuthManager.shared.getAccessToken() else {
    completion(.failure(FeatureFlagsError.notAuthenticated))
    return
}
```

**Impact**:
- Feature flags may fail to load
- Race condition on app start
- **Severity**: MEDIUM

**Fix Required**:
```swift
// Make it async
let token = await AuthManager.shared.getAccessToken()
guard let token = token else {
    completion(.failure(FeatureFlagsError.notAuthenticated))
    return
}
```

---

## Additional Observations

### ✅ Things That Work Well

1. **iOS Token Storage**: Properly uses Keychain via CredentialsManager
2. **Automatic Token Refresh**: iOS refreshes tokens 5 minutes before expiry
3. **Auth0 OAuth2 Flow**: Correct implementation of authorization code flow
4. **URL Scheme Configuration**: Properly configured for iOS callbacks
5. **Session Restoration**: iOS correctly restores sessions on app restart

### ⚠️ Warnings

1. **Development Domain**: Using `dev-1672riu03fjuf7so.us.auth0.com` (okay for testing)
2. **HTTP in Development**: Backend uses `ws://localhost:4000` in dev (okay for local testing)
3. **Placeholder Data**: User phone numbers and passwords are placeholders

---

## Recommended Action Plan

### Phase 1: Critical Fixes (Week 1)
- [ ] Implement JWT signature verification with JWKS
- [ ] Add token expiration checking (exp, nbf, iat)
- [ ] Explicitly disable dev_mode in production config
- [ ] Rotate Auth0 client secret immediately
- [ ] Add .env to .gitignore and use environment variables

### Phase 2: High Priority (Week 2)
- [ ] Move iOS credentials to Auth0.plist
- [ ] Fix Expo audience configuration
- [ ] Remove simple token fallback or add security
- [ ] Standardize documentation with correct values
- [ ] Audit all configurations for consistency

### Phase 3: Medium Priority (Week 3)
- [ ] Consolidate user creation logic
- [ ] Fix FeatureFlags async token access
- [ ] Implement comprehensive error logging
- [ ] Add monitoring and alerting for auth failures
- [ ] Implement backend token refresh capability

### Phase 4: Testing & Validation (Week 4)
- [ ] Security audit and penetration testing
- [ ] Integration testing across all platforms
- [ ] Load testing with token refresh
- [ ] Documentation review and updates
- [ ] Prepare production deployment checklist

---

## Testing Checklist

### Manual Testing
- [ ] Login with valid Auth0 credentials
- [ ] Verify tokens stored in Keychain (iOS)
- [ ] Test token auto-refresh (wait 55+ minutes)
- [ ] Kill app and reopen (session restoration)
- [ ] Logout and verify tokens cleared
- [ ] Test with expired token (should reject)
- [ ] Test with forged token (should reject)
- [ ] Test without token (should reject)

### Automated Testing
- [ ] Unit tests for JWT signature verification
- [ ] Unit tests for claim validation (exp, iss, aud)
- [ ] Integration tests for full auth flow
- [ ] Security tests for attack vectors
- [ ] Load tests for token refresh under load

---

## Security Assessment Summary

| Component | Security Rating | Notes |
|-----------|----------------|-------|
| iOS Client | 🟡 Medium | Good patterns, hardcoded credentials issue |
| Expo Client | 🟡 Medium | Good config management, audience mismatch |
| Auth0 Service | 🟢 Good | Properly configured OAuth2 provider |
| Phoenix Backend | 🔴 Critical | No signature verification, multiple bypasses |
| Overall System | 🔴 Critical | Backend vulnerabilities expose entire system |

**Verdict**: System is **NOT PRODUCTION READY** due to critical backend security vulnerabilities. All CRITICAL issues must be resolved before any production deployment.

---

## References

- [Auth0 Documentation - Token Verification](https://auth0.com/docs/secure/tokens/json-web-tokens/validate-json-web-tokens)
- [OWASP - JWT Security Best Practices](https://cheatsheetseries.owasp.org/cheatsheets/JSON_Web_Token_for_Java_Cheat_Sheet.html)
- [RFC 7519 - JSON Web Token (JWT)](https://datatracker.ietf.org/doc/html/rfc7519)
- Joken Library: https://hexdocs.pm/joken/introduction.html
- JOSE Library: https://hexdocs.pm/jose/readme.html

---

**Last Updated**: 2025-01-23
**Analysis Version**: 1.0
**Reviewed By**: Claude Code Agent
