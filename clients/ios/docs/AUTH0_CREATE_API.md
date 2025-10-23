# Creating Auth0 API for GlobalBridge

## The Situation

You have a **Native Application** configured in Auth0, but no **API** defined yet. This is why:

1. The audience `globalbridge-api` doesn't have a corresponding API in Auth0
2. Auth0 may be returning encrypted tokens (JWE) or opaque tokens
3. The backend is expecting JWT tokens with user claims

## Two Options to Fix This

### Option 1: Create Auth0 API (Recommended for Production)

This is the proper approach for production apps.

#### Step 1: Create the API in Auth0 Dashboard

1. Go to https://manage.auth0.com/dashboard
2. Navigate to **Applications > APIs** in the left sidebar
3. Click **+ Create API** button (top right)
4. Fill in the form:
   - **Name**: `GlobalBridge API`
   - **Identifier**: `globalbridge-api` (MUST match exactly what's in your code)
   - **Signing Algorithm**: `RS256`
5. Click **Create**

#### Step 2: Configure API Settings

After creating the API:

1. Go to **Settings** tab
2. Verify:
   - **Identifier**: `globalbridge-api` ✅
   - **Token Expiration**: 86400 seconds (24 hours) is fine
   - **Signing Algorithm**: RS256 ✅
3. Under **Access Settings**:
   - **Allow Offline Access**: Enable (for refresh tokens)
   - **Allow Skipping User Consent**: Enable (for your own app)
4. Scroll down and click **Save Changes**

#### Step 3: Grant Access from Your Application

1. Go back to **Applications > Applications**
2. Click on your **GlobalBridge** native application
3. Go to **APIs** tab
4. You should see **GlobalBridge API** listed
5. Make sure it's **Authorized**
6. Set the toggle to **ON** if needed

#### Step 4: Add Callback URLs (Still Required)

In your **GlobalBridge** native application (Applications > Applications > GlobalBridge):

1. Go to **Settings** tab
2. Find **Application URIs** section
3. Add to **Allowed Callback URLs**:
   ```
   name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
   ```
4. Add to **Allowed Logout URLs**:
   ```
   name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
   ```
5. Click **Save Changes**

### Option 2: Use ID Token Instead (Quick Fix for Development)

If you don't want to create an API right now, you can use the ID token instead of the access token. ID tokens are always JWT format and contain user identity.

#### Changes Required in Backend

**File**: `globalbridge_backend/lib/globalbridge_backend_web/channels/user_socket.ex`

Find the line around line 35-40 where it extracts the token from params:

```elixir
# Current code (expects access token)
token = params["token"]
```

Change to accept ID token if access token fails:

```elixir
# Try access token first, fall back to ID token
token = params["token"] || params["id_token"]
```

#### Changes Required in iOS App

**File**: `clients/ios/GlobalBridge/Core/State/AppEnvironment.swift`

Find the lines where we get the access token (around lines 202-203, 224-228, 253-254):

Replace:
```swift
let token = await AuthManager.shared.getAccessToken()
```

With:
```swift
// For development without Auth0 API: use ID token instead of access token
let token = await AuthManager.shared.getIdToken()
```

And add this method to **AuthManager.swift**:

```swift
/// Get current ID token (contains user identity)
func getIdToken() async -> String? {
    // ID tokens don't need refresh (use access token refresh if needed)
    if needsRefresh() {
        do {
            _ = try await refreshToken()
        } catch {
            print("❌ [AUTH] Token refresh failed: \(error)")
            return nil
        }
    }

    // ID token is stored during login
    // For now, return access token as fallback
    // TODO: Store and return actual ID token
    return accessToken
}
```

**Note**: This is a quick fix for development but not recommended for production. The proper way is to create an API.

## Why Create an API?

**Without API**:
- ❌ Access tokens may be opaque (can't decode)
- ❌ No clear separation between authentication and authorization
- ❌ Can't set custom token expiration for backend access
- ❌ Harder to manage API permissions

**With API**:
- ✅ Access tokens are always JWT format
- ✅ Can decode and verify tokens server-side
- ✅ Separate token expiration for API access
- ✅ Can add custom claims and scopes
- ✅ Production-ready security model

## Recommended Approach

**For now (to get unblocked)**:
1. Add the callback URLs to your native application (Option 1, Step 4)
2. Use ID token instead of access token (Option 2) - quick code changes

**For production**:
1. Create the Auth0 API (Option 1, Steps 1-3)
2. Revert to using access tokens
3. Add proper token verification with signature checking

## What to Do Right Now

Let me know which approach you want:

**A)** Create the API in Auth0 (I'll guide you through it)
**B)** Use ID token for now (I'll make the code changes)

Either way, you **MUST** add the callback URLs to your Auth0 native application settings (Option 1, Step 4) for the login UI to appear.

## Testing After Changes

Regardless of which option you choose:

1. **Delete iOS app** (clear stored credentials)
2. **Start backend**: `cd globalbridge_backend && mix phx.server`
3. **Run iOS app** from Xcode
4. **You should see**:
   - Auth0 login screen appears in Safari ✅
   - Login completes successfully ✅
   - Backend accepts the token ✅
   - Threads load ✅

## Current Error Explained

The JWE token error happens because:

1. Without an API defined, Auth0 doesn't know what format to use for access tokens
2. The `audience` parameter in your iOS app points to `globalbridge-api` which doesn't exist
3. Auth0 may return an encrypted token or opaque token instead of JWT
4. Backend expects JWT format (3 parts: header.payload.signature)

Creating the API with identifier `globalbridge-api` solves this by telling Auth0 exactly what token format to use.
