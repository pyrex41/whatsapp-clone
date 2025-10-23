# Authentication Strategy

## Current State (Transition Period)

This document explains our dual authentication strategy during the migration from Guardian-based authentication to Auth0.

### Web Client (Phoenix LiveView)

- **Token Type**: Guardian JWT tokens
- **Storage**: Server-side session cookies
- **Flow**:
  1. User authenticates via Auth0 OAuth redirect
  2. Backend exchanges Auth0 code for access token
  3. Backend verifies Auth0 token and finds/creates user
  4. Backend issues Guardian JWT and stores in session
  5. LiveView reads Guardian token from session

**Why Guardian for Web?**
- LiveView requires server-side session management
- Guardian integrates seamlessly with Phoenix sessions
- Provides smooth migration path from legacy web auth

### Mobile Client (iOS) & API Endpoints

- **Token Type**: Auth0 JWT tokens (RS256)
- **Storage**: iOS Keychain (client-side)
- **Flow**:
  1. iOS app uses Auth0 iOS SDK with PKCE
  2. Receives Auth0 access token + refresh token
  3. Sends `Authorization: Bearer <token>` to API
  4. Backend verifies via JWKS (no session required)

**Why Auth0 for Mobile?**
- Industry-standard OAuth2/OIDC implementation
- Native SDKs for iOS with built-in security
- RS256 signature verification via JWKS
- Automatic token refresh

## Architecture Comparison

| Feature | Guardian (Web) | Auth0 (Mobile/API) |
|---------|----------------|-------------------|
| Token Issuance | Phoenix Backend | Auth0 Cloud |
| Signature | HS256 (symmetric) | RS256 (asymmetric) |
| Verification | Guardian library | JWKS + Joken |
| Storage | Server session | Client keychain |
| Refresh | Server-managed | Client + Auth0 |
| User Database | Shared (same users table) | Shared (same users table) |

## Migration Path

### ✅ Phase 1: Auth0 for Mobile/API (COMPLETE)
- [x] Implement JWT verification with JWKS
- [x] Add Auth0Verifier module
- [x] iOS app Auth0 integration
- [x] API Bearer token authentication
- [x] Environment variable configuration

### 🚧 Phase 2: LiveView Transition (IN PROGRESS)
- [x] Auth0 OAuth callback in AuthController
- [x] Hybrid auth (Auth0 verification + Guardian session)
- [ ] Add Auth0 login to AuthLive
- [ ] Migrate existing web users
- [ ] Update session management

### ⏳ Phase 3: Full Auth0 Migration (PLANNED)
- [ ] Direct Auth0 token usage in LiveView
- [ ] Remove Guardian dependency
- [ ] Unified authentication across all clients
- [ ] Single token verification path

## Why Both Systems?

**Short Answer**: We're in the middle of a migration.

**Technical Reasons**:
1. **LiveView Requirements**: Phoenix LiveView works best with server-side sessions
2. **Mobile Requirements**: Mobile apps need client-side token storage
3. **Zero Downtime**: Can't break existing web client during migration
4. **User Database**: Both systems authenticate the same users

## Implementation Details

### Guardian (Web Sessions)

```elixir
# lib/globalbridge_backend_web/live/app_live.ex
def mount(_params, session, socket) do
  case session["guardian_token"] do
    nil -> {:ok, redirect(socket, to: "/")}
    token ->
      case Auth.Guardian.resource_from_token(token) do
        {:ok, user, _claims} -> # Load user data...
      end
  end
end
```

### Auth0 (Mobile/API)

```elixir
# lib/globalbridge_backend/auth/jwt_verifier.ex
def verify_token(token) do
  with {:ok, header} <- decode_header(token),
       {:ok, kid} <- extract_kid(header),
       {:ok, jwk} <- JWKSCache.get_key(kid),
       {:ok, claims} <- verify_signature(token, jwk),
       :ok <- validate_claims(claims) do
    {:ok, claims}
  end
end
```

### OAuth Callback (Bridge Between Systems)

```elixir
# lib/globalbridge_backend_web/controllers/auth_controller.ex
def callback(conn, %{"code" => code}) do
  # 1. Exchange Auth0 code for access token
  {:ok, token_data} = exchange_code_for_token(code)

  # 2. Verify Auth0 token and get user
  {:ok, user} = Auth0Verifier.verify_and_get_user(token_data["access_token"])

  # 3. Issue Guardian token for session
  {:ok, tokens} = Guardian.encode_and_sign(user)

  # 4. Store in session for LiveView
  conn
  |> put_session(:guardian_token, tokens.access)
  |> redirect(to: "/app")
end
```

## Security Considerations

### Current State
- ✅ Auth0 tokens verified with RS256 + JWKS
- ✅ Guardian tokens use Phoenix secret_key_base
- ✅ Sessions are httpOnly cookies
- ✅ CSRF protection enabled
- ✅ All environment variables validated

### During Migration
- ⚠️ Two token verification paths (Guardian + Auth0)
- ⚠️ Ensure both paths validate same user permissions
- ⚠️ Monitor for session/token mismatches

### Post-Migration
- 🎯 Single Auth0 verification path
- 🎯 Remove Guardian dependency
- 🎯 Simplified security model

## Developer Guide

### Running Locally

```bash
# Set Auth0 environment variables
export AUTH0_DOMAIN="your-tenant.auth0.com"
export AUTH0_CLIENT_ID="your_client_id"
export AUTH0_CLIENT_SECRET="your_client_secret"
export AUTH0_AUDIENCE="globalbridge-api"

# Start Phoenix server
cd globalbridge_backend
mix phx.server
```

### Testing Web Authentication
1. Visit http://localhost:4000
2. Click "Sign in with Auth0"
3. Complete Auth0 login
4. Redirected to /app with Guardian session

### Testing Mobile Authentication
1. Open iOS app
2. Complete Auth0 PKCE flow
3. App receives Auth0 access token
4. API calls use `Authorization: Bearer <token>`

## FAQ

**Q: Why not just use Auth0 tokens everywhere?**
A: LiveView requires server-side session state. We're working toward direct Auth0 token usage, but Guardian provides a stable bridge during migration.

**Q: Are Guardian and Auth0 tokens compatible?**
A: No, they're different tokens. However, both authenticate the same users from the same database. The OAuth callback bridges between them.

**Q: When will migration complete?**
A: Phase 3 timeline depends on:
- LiveView session management improvements
- Web client user migration
- Production stability testing

**Q: What if a user has both web and mobile sessions?**
A: They work independently. Web uses Guardian session, mobile uses Auth0 token. Both access the same user data.

## Related Documentation

- [Auth0 Environment Setup](AUTH0_ENV_SETUP.md)
- [JWT Verifier Implementation](lib/globalbridge_backend/auth/jwt_verifier.ex)
- [Guardian Configuration](config/guardian.exs)
- [JWKS Cache](lib/globalbridge_backend/auth/jwks_cache.ex)

## Next Steps

1. Add Auth0 login button to AuthLive
2. Migrate session management to support Auth0 tokens
3. Write migration script for existing web users
4. Plan Guardian deprecation timeline
5. Update all documentation

---

**Last Updated**: 2025-10-22
**Status**: Phase 2 - LiveView Transition In Progress
