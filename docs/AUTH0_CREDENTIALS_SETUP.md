# Where to Put Your Auth0 Credentials

## Backend Setup

Create a file: `globalbridge_backend/.env`

```bash
# Auth0 Configuration
AUTH0_DOMAIN=your-domain.us.auth0.com
AUTH0_AUDIENCE=globalbridge-api
```

Then restart the Phoenix server:
```bash
cd globalbridge_backend
mix phx.server
```

## iOS Setup

### Option 1: Xcode Scheme Environment Variables (Easiest)

1. Open Xcode
2. Select the **GlobalBridge** scheme at the top
3. Click **Product** menu → **Scheme** → **Edit Scheme...**
4. Select **Run** in the left sidebar
5. Click the **Arguments** tab
6. Under **Environment Variables**, click **+** to add:

```
AUTH0_DOMAIN = your-domain.us.auth0.com
AUTH0_CLIENT_ID = your_client_id_here
AUTH0_AUDIENCE = globalbridge-api
```

### Option 2: Info.plist (Alternative)

Edit `clients/ios/GlobalBridge/GlobalBridge/Info.plist` and add:

```xml
<key>Auth0Domain</key>
<string>your-domain.us.auth0.com</string>
<key>Auth0ClientId</key>
<string>your_client_id_here</string>
<key>Auth0Audience</key>
<string>globalbridge-api</string>
```

## Auth0 Dashboard Configuration

In your Auth0 application settings:

### Allowed Callback URLs
```
com.globalbridge.app://YOUR_AUTH0_DOMAIN/ios/com.globalbridge.app/callback
```

### Allowed Logout URLs
```
com.globalbridge.app://YOUR_AUTH0_DOMAIN/ios/com.globalbridge.app
```

### Allowed Web Origins
```
com.globalbridge.app
```

## Quick Start

1. Get your Auth0 credentials from Auth0 Dashboard
2. Add to backend `.env` file
3. Add to iOS Xcode scheme
4. Run backend: `mix phx.server`
5. Run iOS app in Xcode
6. App will open Auth0 login
7. After login, app fetches threads from backend
8. Create threads, send messages!

## What Happens When You Run

1. **iOS app starts**
2. **Auth0 login page opens** in system browser
3. **User logs in** with Auth0 credentials
4. **iOS receives JWT token**
5. **Connects to Phoenix** with token at `ws://localhost:4000/socket`
6. **Backend verifies token** and creates/finds user
7. **Joins user channel** `user:{userId}`
8. **Fetches bootstrap data** (threads, user info)
9. **Syncs to local SQLite**
10. **Joins thread channels** for each thread
11. **Ready to send messages!**

## Testing Without Auth0 (Dev Mode)

If you need to test without Auth0, the backend supports dev mode:

1. Set `DEV_MODE=true` in backend `.env`
2. Backend will accept connections without tokens
3. Backend will auto-create mock users

However, iOS app now requires Auth0, so you'd need to provide mock credentials.

## Troubleshooting

**"AUTH0_DOMAIN not configured"**
- Check Xcode scheme environment variables are set
- OR check Info.plist has Auth0 keys

**Backend rejects token**
- Verify backend `.env` has correct AUTH0_DOMAIN
- Check token audience matches (should be `globalbridge-api`)
- Look at backend logs for specific error

**Auth0 login page doesn't load**
- Verify Auth0 Domain is correct
- Check Auth0 Client ID matches your application
- Ensure internet connection is working

**"Thread not found" errors**
- This is expected if you have old local-only threads
- Create new threads via the app (they'll sync to backend)
- Old threads will be cleared on bootstrap

## Success!

Once configured, you should see in logs:

**Backend:**
```
🔐 [AUTH0] Token claims: sub=auth0|abc123, email=user@example.com
✅ [AUTH0] User created: id=uuid, username=user_123
✅ [USER_CHANNEL] User uuid joined their channel
📥 [USER_CHANNEL] Bootstrap request from user: uuid
✅ [USER_CHANNEL] Bootstrap successful for user: uuid
```

**iOS:**
```
🔐 [AUTH] Starting Auth0 login...
✅ [AUTH] Login successful
🔌 [PHOENIX] Connecting to Phoenix...
✅ [PHOENIX] Connected successfully
📥 [USER_CHANNEL] Joining user channel: user:auth0|abc123
✅ [USER_CHANNEL] Successfully joined
📥 [BOOTSTRAP] Fetching bootstrap data...
✅ [BOOTSTRAP] Parsed 0 threads (or however many you have)
✅ Synced 0 threads from backend
```

Your app is now fully connected and syncing with the backend! 🎉


