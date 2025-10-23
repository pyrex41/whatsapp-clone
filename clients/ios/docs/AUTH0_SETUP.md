# Auth0 Configuration Guide

## Problem Summary

The iOS app is experiencing Auth0 authentication issues:

1. **Auth0 UI not appearing**: The Auth0 web login screen isn't showing up when the app tries to authenticate
2. **JWE vs JWT token format**: Auth0 is returning encrypted JWE tokens (5 parts) instead of standard JWT tokens (3 parts)
3. **Backend verification failing**: The Phoenix backend expects 3-part JWT tokens and fails to decode JWE tokens

## Required Auth0 Dashboard Configuration

### 1. Register Callback URLs

The Auth0 application **MUST** have the following URLs registered:

**Application**: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`
**Domain**: `dev-1672riu03fjuf7so.us.auth0.com`

#### Allowed Callback URLs:
```
name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
```

#### Allowed Logout URLs:
```
name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
```

#### Allowed Web Origins (if needed):
```
name.reubenbrooks.globalbridge://*
```

### 2. Application Type

- **Application Type**: Native
- **Token Endpoint Authentication Method**: None (for public mobile apps)

### 3. Token Format Configuration

**CRITICAL**: The backend currently expects standard JWT tokens, not encrypted JWE tokens.

To fix JWE token issues, configure the API in Auth0 Dashboard:

1. Go to **Applications > APIs** in Auth0 Dashboard
2. Find the API with identifier: `globalbridge-api`
3. Go to **Settings** tab
4. Under **Access Settings**:
   - Set **Token Format** to "JWT" (not "Opaque" or "JWE")
   - Ensure **Signing Algorithm** is "RS256"
5. Click **Save**

### 4. Advanced Settings

Under **Advanced Settings**:

#### Grant Types
Enable these grant types:
- ✅ Authorization Code
- ✅ Refresh Token
- ✅ Implicit (for hybrid flows)

#### Other Settings
- **OIDC Conformant**: Yes
- **Refresh Token Rotation**: Enabled (recommended for security)
- **Refresh Token Expiration**: 2592000 seconds (30 days)

## iOS App Configuration

The iOS app is already configured correctly:

### Info.plist
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>name.reubenbrooks.globalbridge</string>
        </array>
    </dict>
</array>
<key>Auth0Domain</key>
<string>dev-1672riu03fjuf7so.us.auth0.com</string>
<key>Auth0ClientId</key>
<string>id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj</string>
<key>Auth0Audience</key>
<string>globalbridge-api</string>
```

### Auth0Config.swift
- Domain: `dev-1672riu03fjuf7so.us.auth0.com`
- Client ID: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`
- Audience: `globalbridge-api`

## Backend Configuration

The backend Auth0 verifier expects:

- **Issuer**: `https://dev-1672riu03fjuf7so.us.auth0.com/`
- **Audience**: `globalbridge-api`
- **Algorithm**: RS256
- **Token Format**: 3-part JWT (header.payload.signature)

### Current Issue

The backend's `Auth0Verifier.decode_jwt/1` function at line 34 of `auth0_verifier.ex`:

```elixir
defp decode_jwt(token) do
  case String.split(token, ".") do
    [_header, payload, _signature] ->
      case Base.url_decode64(payload, padding: false) do
        {:ok, json} -> Jason.decode(json)
        error -> error
      end
    _ ->
      {:error, :invalid_jwt_format}
  end
end
```

This expects exactly 3 parts. JWE tokens have 5 parts and are encrypted, so they can't be decoded this way.

## Troubleshooting

### Auth0 UI Not Appearing

If the Auth0 login screen doesn't appear:

1. **Check Callback URL**: Verify it's registered in Auth0 Dashboard
2. **Check Logs**: Run the iOS app and look for Auth0 error messages in Xcode console
3. **Clear Credentials**: The app might have stored credentials from a previous login
   ```swift
   // In AuthManager, call logout first
   try await AuthManager.shared.logout()
   ```
4. **Check URL Scheme**: Verify `CFBundleURLSchemes` in Info.plist matches what Auth0 expects

### JWE Token Errors

If you see `"❌ [AUTH0] Token verification failed: :invalid_jwt"`:

1. **Check API Settings**: Ensure Token Format is "JWT" not "JWE" in Auth0 Dashboard
2. **Verify Audience**: Must be exactly `globalbridge-api` (no `https://`)
3. **Check Algorithm**: Must be RS256

### Backend Verification Errors

If backend shows `Unable to verify token`:

1. **Check JWKS Cache**: Backend fetches Auth0's public keys from `https://dev-1672riu03fjuf7so.us.auth0.com/.well-known/jwks.json`
2. **Verify Issuer**: Must match `https://dev-1672riu03fjuf7so.us.auth0.com/` (with trailing slash)
3. **Check Token Claims**: Use [jwt.io](https://jwt.io) to decode the token and verify claims

## Testing

### Test Login Flow

1. **Clear Stored Credentials**:
   ```bash
   # Delete app and reinstall
   # Or call logout() in the app
   ```

2. **Run App in Debug Mode**:
   - Backend: `mix phx.server` (on http://localhost:4000)
   - iOS: Run from Xcode in Debug configuration
   - Watch Xcode console for detailed Auth0 logs

3. **Expected Flow**:
   ```
   🔐 [AUTH] Starting Auth0 login...
   🌐 [AUTH] About to open Auth0 web login UI...
   🚀 [AUTH] Calling Auth0.webAuth().start()...
   [Safari/Auth0 opens - you login]
   [Callback URL redirects back to app]
   ✅ [AUTH] Auth0 webAuth completed successfully!
   📊 [AUTH] Token details...
   ```

4. **Verify Token**:
   - Check that Access Token has 3 parts (JWT) not 5 (JWE)
   - Copy access token and verify at [jwt.io](https://jwt.io)
   - Should contain `aud: "globalbridge-api"` and `iss: "https://dev-1672riu03fjuf7so.us.auth0.com/"`

## Alternative: Use ID Token Instead

If JWE issues persist, consider using the ID token instead of access token:

**Pros**:
- ID tokens are always JWT format (not encrypted)
- Contain user identity claims

**Cons**:
- Not intended for API authorization (but works for development)
- Need to modify backend to accept ID tokens

## Summary

**Immediate Actions Required**:

1. ✅ **iOS App**: Diagnostic logging added (already done)
2. ⚠️  **Auth0 Dashboard**: Register callback URL (USER ACTION REQUIRED)
3. ⚠️  **Auth0 Dashboard**: Set API token format to JWT (USER ACTION REQUIRED)
4. 🔄 **Backend**: Either handle JWE tokens OR wait for Auth0 API settings to take effect
5. 🧪 **Test**: Clear credentials, run app, verify Auth0 UI appears and tokens are JWT format
