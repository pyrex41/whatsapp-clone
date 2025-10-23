# PRD: Unified Auth with Auth0 + Ueberauth for iOS and Elm Clients

## Summary

Replace ad-hoc/legacy auth flows with a unified Auth0-based identity system integrated into the Phoenix backend using Ueberauth and JWT verification. Both the native iOS app and the Elm web client will authenticate with Auth0 (PKCE), then call Phoenix APIs with `Authorization: Bearer <access_token>`. Phoenix will verify RS256 JWTs using Auth0 JWKS and map Auth0 users to local users. Phoenix Channels will accept the same tokens for real-time features.

The goal is a cohesive, secure, and mobile/web-friendly auth layer that preserves Auth0 as the IdP while using Ueberauth for OAuth flows and a proper JWT verification path for API/Channels.

## Goals

- Use Auth0 as the single identity provider for iOS and Elm clients.
- Integrate Ueberauth + `ueberauth_auth0` for OAuth flows and testing/browser flows.
- Verify Auth0 RS256 access tokens server-side in Phoenix for all protected APIs and Channels.
- Create/lookup local users on first login via Auth0 claims (e.g., `sub`, `email`, `name`).
- Support real-time via Phoenix Channels authenticated with the same Auth0 token.
- Minimize server-side token storage; prefer stateless verification and client-side refresh with Auth0.

## Non-Goals

- Replacing Auth0 with custom JWT issuance (we continue to use Auth0 tokens).
- Supporting cookie-based session auth for mobile clients (API will be token-based).
- Building a full roles/permissions system upfront (basic role claim mapping only).

## Clients

- iOS (SwiftUI/UIKit): Auth0 iOS SDK with PKCE; tokens stored securely in Keychain; use Bearer token for API/Channels.
- Elm web client: PKCE-based Auth0 flow. Recommended: use a minimal JS wrapper via Elm ports (Auth0 SPA SDK) or redirect-flow via Phoenix+Ueberauth for bootstrap; store access token in memory or sessionStorage.

## Architecture Overview

- Identity: Auth0 (tenant domain, app client ID/secret, audience for API).
- Phoenix: `GlobalbridgeBackend` as API+Channels server.
  - Ueberauth + `ueberauth_auth0` for OAuth flows and optional web testing.
  - RS256 JWT verification for API/Channels using Auth0 JWKS (cache with TTL).
  - Local `users` table maps to Auth0 users via `auth0_id` (`sub`).
  - Optional Guardian kept for legacy compatibility during migration; not used for new clients.

## Flows

### iOS Flow (Primary)
1. iOS uses Auth0 iOS SDK with PKCE to authenticate the user.
2. iOS receives `access_token` (and `refresh_token` if `offline_access` scope granted).
3. iOS sends API requests with `Authorization: Bearer <access_token>` to Phoenix.
4. Phoenix verifies JWT signature and claims using Auth0 JWKS; on success, finds or creates local user by `sub`.
5. On 401 (token expired), iOS uses refresh token to obtain a new access token from Auth0 and retries.
6. For Channels, iOS connects to `/socket` passing `token` param with the same `access_token`.

### Elm Web Client Flow
Two supported options; pick one per environment:

- Option A: SPA PKCE via Auth0 JS SDK (recommended)
  - A small JS bridge handles Auth0 login/logout/refresh (Auth0 SPA SDK), exposed to Elm via ports.
  - Elm receives/stores the access token (memory/sessionStorage), uses Bearer token for API/Channels.

- Option B: Redirect via Phoenix + Ueberauth
  - Elm triggers `/auth/auth0` route (Phoenix) to start Auth0 OAuth redirect.
  - After callback, Phoenix optionally issues a one-time bootstrap page or token handoff for Elm to capture (e.g., via fragment/hash) and continue as a pure token client.
  - This is useful for environments where embedding the Auth0 JS SDK is undesirable.

In both options, Elm calls Phoenix APIs with `Authorization: Bearer <access_token>` and connects to Channels with `params: %{token: access_token}`.

## Backend Requirements (Phoenix)

### Dependencies

- `:ueberauth`, `:ueberauth_auth0` for OAuth flows.
- `:jose` (existing) or `:joken` + `:joken_jwks` for RS256 verification. We can start with `:jose` and add JWKS caching.
- `:httpoison` or `:finch`/`Req` for fetching JWKS (prefer a caching layer).

### Config

Add environment variables and config entries:

- `AUTH0_DOMAIN` (e.g., `your-tenant.auth0.com`)
- `AUTH0_CLIENT_ID`
- `AUTH0_CLIENT_SECRET`
- `AUTH0_AUDIENCE` (API identifier configured in Auth0)
- `AUTH0_CALLBACK_URL` (e.g., `https://yourapp.com/auth/auth0/callback`)

Example (runtime.exs):

```
config :ueberauth, Ueberauth,
  providers: [
    auth0: {Ueberauth.Strategy.Auth0, [default_audience: System.get_env("AUTH0_AUDIENCE")]} 
  ]

config :ueberauth, Ueberauth.Strategy.Auth0.OAuth,
  domain: System.get_env("AUTH0_DOMAIN"),
  client_id: System.get_env("AUTH0_CLIENT_ID"),
  client_secret: System.get_env("AUTH0_CLIENT_SECRET")
```

### Routes

```
scope "/auth", GlobalbridgeBackendWeb do
  pipe_through :api
  get  "/auth0/callback", AuthController, :callback   # Ueberauth callback (web/testing)
  post "/auth0/login",    AuthController, :login      # iOS/Elm: send access_token for verification
end

pipeline :api_auth do
  plug GlobalbridgeBackendWeb.Plugs.Auth  # Verifies Auth0 JWT; assigns :current_user
end

scope "/api", GlobalbridgeBackendWeb do
  pipe_through [:api, :api_auth]
  # protected resources...
end
```

### Controllers/Plugs (Key Behaviors)

- `AuthController.callback/2` (Ueberauth):
  - On success: find/create local user via `auth.uid`/`auth.info.email`.
  - Return a minimal success page for SPA bootstrap or a JSON payload for testing.

- `AuthController.login/2` (token verification):
  - Accepts `%{"access_token" => token}`.
  - Verifies JWT (signature + claims: `iss`, `aud`, `exp`, `nbf`).
  - Finds/creates local user; returns `{ user, token }` JSON.

- `GlobalbridgeBackendWeb.Plugs.Auth`:
  - Extracts `Authorization: Bearer ...`, verifies JWT, assigns `:current_user` or returns 401.

- `GlobalbridgeBackendWeb.UserSocket`:
  - Accept `params["token"]` and reuse the same verification path.

### JWT Verification Details

- Verify RS256 signature using Auth0 JWKS at `https://<domain>/.well-known/jwks.json`.
- Cache JWKS for at least 10–15 minutes; refresh on `kid` mismatch.
- Validate:
  - `iss` equals `https://<domain>/`
  - `aud` contains configured API audience
  - `exp` and `nbf` within bounds
  - Optional: map role claims (e.g., `https://yourapp.com/roles`).

### User Mapping

- Local `users` table fields (minimum): `id`, `auth0_id` (unique), `email` (unique), `display_name`, timestamps.
- On first login: create user if `auth0_id` not found; update `email`/`display_name` on subsequent logins.
- Record `last_login_at` (optional) for audit.

## iOS Requirements

- Use Auth0 iOS SDK (PKCE) to obtain `access_token` (+ `refresh_token` if `offline_access`).
- Store tokens in Keychain.
- Send Bearer token for API; on 401, refresh and retry.
- For Channels: pass same token in socket params.
- Scopes: `openid profile email offline_access`.

## Elm Web Client Requirements

- Option A (SPA SDK): Use a small JS bridge that wraps Auth0 SPA SDK methods for login/logout/renew; communicate via Elm ports.
- Option B (Redirect): Trigger Phoenix `/auth/auth0` to start OAuth, then receive token on redirect (hash/fragment or bootstrap page) for Elm to capture and store in sessionStorage.
- Always send Bearer token; avoid cookies; prefer in-memory/sessionStorage over localStorage.

## Security & Compliance

- HTTPS only in production.
- Rate limit `/auth/auth0/login` and sensitive endpoints (e.g., PlugAttack).
- Strict CORS for development and known client origins.
- JWKS caching with graceful fallback; rotate on `kid` changes.
- Logging: redact tokens; log only short prefixes; include `sub` and `jti` where safe.
- Telemetry for 401/403 rates and token verification latency.

## Migration Plan

1. Add Ueberauth and Auth0 config; create `AuthController` and `Auth` plug.
2. Implement robust JWT verification (replace any dev-only decoding in `Auth0Verifier`).
3. Update `UserSocket` to strictly require verified Auth0 tokens (keep Guardian fallback behind a feature flag during migration).
4. Backfill existing users: store `auth0_id` for known emails; mark legacy password fields as "auth0_managed" or deprecate.
5. Deprecate legacy login endpoints and Phoenix.Token issuance for mobile; communicate cutover to clients.
6. Update iOS to use Auth0 PKCE and Bearer tokens exclusively.
7. Update Elm client to use Option A (preferred) or Option B; ensure CORS and redirect URLs configured.
8. Remove legacy paths/flags after successful rollout.

## Acceptance Criteria

- API returns 401 without valid Bearer token; 200 with valid Auth0 token for protected routes.
- Ueberauth callback succeeds and maps user data; QA can complete web-based login.
- iOS login -> token -> API/Channels flow verified end-to-end; 401 -> refresh -> retry works.
- Elm login with chosen option verified; token applied to API/Channels.
- JWKS cache implemented; signature and claims validated; `aud`/`iss` enforced.
- User records created on first login and reused on subsequent logins.
- Rate limiting and CORS configured for target origins.

## API Contracts

- `POST /auth/auth0/login`
  - Request: `{ "access_token": "<string>" }`
  - Response (200): `{ "token": "<string>", "user": { "id": "<uuid>", "email": "...", "display_name": "..." } }`
  - Errors: `401 { "error": "unauthorized" }`, `400 { "error": "invalid_token" }`

- Protected endpoints: require `Authorization: Bearer <token>`; return `401` on failure.

## Deliverables

- Phoenix: Ueberauth config, `AuthController`, `Auth` plug, hardened `Auth0Verifier` with JWKS verification and caching, updated `UserSocket`.
- iOS: Auth0 PKCE login, Keychain storage, Bearer usage, refresh handling, Channels connection with token.
- Elm: Auth integration (SPA SDK + ports or redirect flow), token storage, Bearer usage, Channels support.
- Docs: Env var setup, callback URLs, client configuration, and runbooks for QA.

## Open Questions

- Do we need a server-issued short-lived session/token in addition to Auth0 tokens for web-only optimizations? (Default: no.)
- Preferred Elm auth option (SPA SDK vs redirect)?
- Role/permissions claims namespace and mapping policy.

## High-Level Task Breakdown (for Task Master)

1. Backend: Add Ueberauth + Auth0 config and routes
2. Backend: Implement JWT verification via JWKS with caching
3. Backend: Create Auth plug and wire into `:api_auth` pipeline
4. Backend: Update `UserSocket` to require verified tokens
5. Backend: Map Auth0 claims to local user; add `auth0_id` index if missing
6. iOS: Add Auth0 PKCE login, token storage, refresh handling
7. iOS: Apply Bearer token to API; Channels connection with token
8. Elm: Implement chosen auth option (SPA SDK + ports or redirect)
9. Security: Add rate limiting, tighten CORS, redact logging
10. QA: E2E tests for iOS and Elm; 401/refresh retries; Channel auth

