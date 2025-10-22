# Final Auth0 Setup Steps

## ✅ Already Configured

**Backend** - `.env` file created with:
```
AUTH0_DOMAIN=dev-1672riu03fjuf7so.us.auth0.com
AUTH0_CLIENT_ID=id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj
AUTH0_AUDIENCE=globalbridge-api
```

**iOS** - `Auth0Config.swift` has your credentials as defaults

## 🔧 Xcode Setup Required

### Step 1: Add Auth0 Swift Package

1. Open Xcode project:
   ```bash
   cd /Users/reuben/gauntlet/whatsapp-clone/clients/ios/GlobalBridge
   open GlobalBridge.xcodeproj
   ```

2. In Xcode:
   - Click **File** → **Add Package Dependencies**
   - Paste URL: `https://github.com/auth0/Auth0.swift`
   - Click **Add Package**
   - Select **Auth0** library
   - Click **Add Package**

### Step 2: Configure URL Scheme

Auth0 needs a custom URL scheme for the callback after login.

1. In Xcode, select the **GlobalBridge** project
2. Select the **GlobalBridge** target
3. Go to the **Info** tab
4. Expand **URL Types** section
5. Click **+** to add a new URL Type
6. Set:
   - **Identifier**: `auth0`
   - **URL Schemes**: `com.globalbridge.app`
   - **Role**: `Editor`

### Step 3: Update Auth0 Dashboard

Go to your Auth0 Dashboard → Applications → Your Application

**Add these URLs:**

**Allowed Callback URLs:**
```
com.globalbridge.app://dev-1672riu03fjuf7so.us.auth0.com/ios/com.globalbridge.app/callback
```

**Allowed Logout URLs:**
```
com.globalbridge.app://dev-1672riu03fjuf7so.us.auth0.com/ios/com.globalbridge.app
```

**Allowed Web Origins:**
```
com.globalbridge.app
```

## 🧪 Testing

### 1. Start Backend Server

```bash
cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
mix phx.server
```

You should see:
```
[info] Running GlobalbridgeBackendWeb.Endpoint with Bandit 1.x.x at 127.0.0.1:4000 (http)
```

### 2. Run iOS App

In Xcode:
- Select iPhone simulator or device
- Click **Run** (Cmd+R)

**Expected Flow:**

1. **Auth0 Login Opens** - Safari/Browser opens with Auth0 login page
2. **Login** - Enter your Auth0 credentials
3. **Redirect to App** - Browser redirects back to iOS app
4. **Console Logs** - You should see:

   ```
   🔐 [AUTH] Starting Auth0 login...
   ✅ [AUTH] Login successful
      User ID: auth0|...
      Email: your-email@example.com
   🔌 Connecting to Phoenix...
   ✅ Connected successfully
   📥 [USER_CHANNEL] Joining user channel: user:auth0|...
   ✅ [USER_CHANNEL] Successfully joined
   📥 [BOOTSTRAP] Fetching bootstrap data...
   ✅ [BOOTSTRAP] Parsed X threads
   ✅ Synced X threads from backend
   ```

5. **Backend Logs** - You should see:

   ```
   🔐 [AUTH0] Token claims: sub=auth0|..., email=your-email
   ✅ [AUTH0] User created (or existing user found)
   ✅ [USER_CHANNEL] User joined their channel
   📥 [USER_CHANNEL] Bootstrap request from user
   ✅ [USER_CHANNEL] Bootstrap successful
   ```

### 3. Create a Test Thread

Once logged in, you can test thread creation:

1. In iOS app, create a new thread (UI flow)
2. Backend will create the thread first
3. iOS syncs it locally
4. You can now join the thread channel and send messages!

**Backend logs:**
```
🆕 [USER_CHANNEL] Create thread request: type=direct, creator=auth0|...
✅ [USER_CHANNEL] Thread created: <thread-uuid>
📢 [USER_CHANNEL] Broadcasting thread_created
```

**iOS logs:**
```
🆕 [CREATE_THREAD] Creating thread
✅ [CREATE_THREAD] Thread created
✅ Thread created and synced
📥 [JOIN] joinConversation called for: <thread-uuid>
✅ [JOIN] Successfully joined channel
```

## 🐛 Troubleshooting

### "No such module 'Auth0'" in Xcode
- Make sure you added the Auth0 package (see Step 1)
- Clean build folder: Product → Clean Build Folder
- Rebuild: Cmd+B

### Auth0 login page doesn't open
- Check URL scheme is configured correctly
- Verify domain: `dev-1672riu03fjuf7so.us.auth0.com`
- Check console for errors

### Backend rejects token
- Check backend `.env` file exists with correct domain
- Restart Phoenix server after adding `.env`
- Check backend logs for specific auth error

### "Thread not found" still happening
- This means iOS is trying to join old local-only threads
- **Solution**: Bootstrap will clear local DB and sync from backend
- Create new threads via the app (they'll sync properly)

## 🎯 Success Indicators

✅ Backend compiles without errors
✅ iOS Auth0 configured
✅ Credentials in place
⏳ Auth0 package needs to be added to Xcode
⏳ URL scheme needs to be configured
⏳ Auth0 Dashboard callback URLs need to be set

Once you complete the Xcode setup (Steps 1-3), **everything should work**!

## 📞 Quick Reference

**Your Auth0 Details:**
- Domain: `dev-1672riu03fjuf7so.us.auth0.com`
- Client ID: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`
- Audience: `globalbridge-api`
- URL Scheme: `com.globalbridge.app`

**Callback URL (for Auth0 Dashboard):**
```
com.globalbridge.app://dev-1672riu03fjuf7so.us.auth0.com/ios/com.globalbridge.app/callback
```

**Files Already Configured:**
- ✅ `globalbridge_backend/.env`
- ✅ `clients/ios/GlobalBridge/Core/Config/Auth0Config.swift`
- ✅ All code implementation complete!


