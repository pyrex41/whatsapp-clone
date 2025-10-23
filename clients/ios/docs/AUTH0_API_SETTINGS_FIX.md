# Fix Auth0 API to Return JWT Instead of JWE

## Current Problem

Your Auth0 API is returning **encrypted JWE tokens** (5 parts) instead of **standard JWT tokens** (3 parts).

Backend error:
```
❌ [AUTH0] Token format: JWE (5 parts) - ENCRYPTED TOKEN DETECTED!
```

## The Fix - Configure Your Auth0 API

### Step 1: Go to Your API Settings

1. In Auth0 Dashboard, click **Applications** in left sidebar
2. Click **APIs** (it's under Applications)
3. Find and click on your API (should be named `GlobalBridge API` or similar)
4. Click on the **Settings** tab

### Step 2: Verify/Update These Settings

Look for these specific settings:

#### Signing Algorithm
- **Must be**: `RS256` ✅
- If it shows anything else (HS256, etc.), change it to RS256

#### Token Settings (This is the critical part!)

Look for a section called one of these:
- "Access Token Settings"
- "Token Configuration"
- "Token Format"
- "JSON Web Token Signature Algorithm"

**You need to ensure the API returns JWT tokens, not JWE (encrypted) tokens.**

### Step 3: Disable Token Encryption (If Present)

Some Auth0 plans have a "Token Encryption" option:

- If you see **"Enable Token Encryption"** toggle → Turn it **OFF** ❌
- If you see **"Token Format"** dropdown → Select **"JWT"** (not "JWE" or "Opaque")

### Step 4: Check Advanced Settings

Scroll down to **Advanced Settings** section and expand it:

1. Click on **"OAuth"** tab
2. Look for **"JSON Web Token Signature Algorithm"**
3. Ensure it's set to **RS256**

### Step 5: Save Changes

Scroll to the bottom and click **"Save Changes"**

## How to Verify It Worked

After saving, the API settings should show:
- ✅ Identifier: `globalbridge-api`
- ✅ Signing Algorithm: `RS256`
- ✅ Token Encryption: OFF (or Token Format: JWT)

## Test the Fix

1. **Delete the iOS app** completely (to clear cached tokens)
2. **Restart backend**: `cd globalbridge_backend && mix phx.server`
3. **Run iOS app** from Xcode
4. **Watch backend console** - should see:
   ```
   🔍 [AUTH0] Token format: JWT (3 parts) ✅
   ```

Instead of:
   ```
   ❌ [AUTH0] Token format: JWE (5 parts) - ENCRYPTED TOKEN DETECTED!
   ```

## If You Don't See These Options

If your Auth0 dashboard doesn't have "Token Encryption" or "Token Format" settings, it means:

1. Your plan might not support token encryption (which is good - it defaults to JWT)
2. The JWE tokens might be coming from a different cause

In that case, try this alternative:

### Alternative: Use ID Token Instead

The ID token is ALWAYS JWT format. We can modify the code to use ID token instead of access token for development.

Let me know if you can't find the token encryption settings and I'll make the code changes to use ID token instead!

## What Your Settings Should Look Like

```
API Settings:
├─ Identifier: globalbridge-api ✅
├─ Signing Algorithm: RS256 ✅
├─ Token Lifetime: 86400 (default) ✅
└─ Token Encryption: OFF ✅ (or Token Format: JWT)
```
