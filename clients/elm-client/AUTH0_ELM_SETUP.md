# Auth0 Setup for Elm Web Client

## ✅ Already Configured

- ✅ Auth0 SPA SDK added to package.json
- ✅ Auth0 module (`auth0.js`) created
- ✅ Ports added for Auth0 login/logout
- ✅ Main.elm updated to use Auth0
- ✅ Phoenix channels for bootstrap
- ✅ Credentials configured in `auth0.js`
- ✅ npm install completed
- ✅ Elm compiles successfully

## 🎯 Auth0 Dashboard Configuration

The Elm web client runs in the browser, so it needs slightly different callback URLs than iOS.

### Go to: https://manage.auth0.com

1. **Login** to your Auth0 account
2. Go to **Applications** → Select your application
3. Click **Settings** tab

### Add Web Client URLs

**Allowed Callback URLs** - Add:
```
http://localhost:3000
http://localhost:3000/callback
https://yourdomain.com
https://yourdomain.com/callback
```

**Allowed Logout URLs** - Add:
```
http://localhost:3000
https://yourdomain.com
```

**Allowed Web Origins** - Add:
```
http://localhost:3000
https://yourdomain.com
```

**Allowed Origins (CORS)** - Add:
```
http://localhost:3000
https://yourdomain.com
```

4. Click **Save Changes**

## 🚀 Running the Elm Client

### Terminal 1: Start Backend
```bash
cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
mix phx.server
```

### Terminal 2: Start Elm Dev Server
```bash
cd /Users/reuben/gauntlet/whatsapp-clone/clients/elm-client
npm run dev
```

Then open: http://localhost:3000

## 🎬 Expected Flow

1. **Browser opens** → Shows "Login with Auth0" button
2. **Click button** → Redirects to Auth0 login page
3. **Login** → Enter your Auth0 credentials
4. **Redirect back** → Returns to http://localhost:3000
5. **Auth0 processes callback** → Extracts JWT token
6. **Elm receives session** → Stores user data
7. **Phoenix connects** → WebSocket to `ws://localhost:4000/socket`
8. **Joins user channel** → `user:{auth0|your_id}`
9. **Requests bootstrap** → Pushes "bootstrap" message
10. **Receives threads** → Displays thread list
11. **Success!** → Can join threads and send messages

## 📊 Console Output to Expect

**Browser Console:**
```javascript
[Auth0] Initializing client...
[Auth0] Client initialized successfully
[Auth0] Login requested by Elm
[Auth0] Handling redirect callback...
[Auth0] Redirect handled successfully
[Auth0] Login complete, sending session to Elm
[Session] Restored Auth0 session for user: Test User
[Phoenix] Socket initialized
[Phoenix] Socket connected
[Phoenix] Joined user:{auth0|...}
[Phoenix] Message sent to user:{auth0|...}: bootstrap
```

**Backend Console:**
```
🔐 [AUTH0] Token claims: sub=auth0|..., email=your@email.com
✅ [AUTH0] User created: id=uuid, username=your_email_...
✅ [USER_CHANNEL] User joined their channel
📥 [USER_CHANNEL] Bootstrap request
📊 [USER_CHANNEL] Found 0 threads
✅ [USER_CHANNEL] Bootstrap successful
```

## 🔍 How It Works

### Architecture
```
Browser
  ↓
[Click "Login with Auth0"]
  ↓
[Auth0 Login Page] ← Hosted by Auth0
  ↓
[Auth0 Returns JWT] ← Callback to localhost:3000
  ↓
[auth0.js extracts token] ← getSessionData()
  ↓
[Elm receives SessionData] ← onAuth0LoginComplete port
  ↓
[Phoenix Socket connects] ← initSocket port with token
  ↓
[Backend verifies token] ← user_socket.ex
  ↓
[Join user channel] ← user:{userId}
  ↓
[Request bootstrap] ← push "bootstrap" message
  ↓
[Receive threads] ← Backend returns threads
  ↓
[Display thread list]
```

### Files Modified
- `src/Ports.elm` - Added Auth0 ports
- `src/main.js` - Integrated auth0.js
- `src/auth0.js` - New Auth0 client wrapper
- `src/Main.elm` - Auth0 login flow
- `package.json` - Added @auth0/auth0-spa-js

## 🧪 Testing

1. **Start both servers** (backend and Elm dev server)
2. **Open browser** to http://localhost:3000
3. **Should see** "Login with Auth0" button
4. **Click button** → Auth0 login page opens
5. **Login** → Should redirect back and connect to Phoenix
6. **Check console** → Should show successful connection and bootstrap
7. **Thread list should load** (empty if no threads created yet)

## 🐛 Troubleshooting

**"Failed to get access token" in console**
- Check Auth0 Dashboard has correct callback URLs
- Verify domain and client ID in `auth0.js`
- Clear browser localStorage and try again

**"Socket not connected" errors**
- Make sure backend is running on port 4000
- Check browser console for WebSocket errors
- Verify Auth0 token is being passed to Phoenix

**Blank page after Auth0 redirect**
- Check browser console for JavaScript errors
- Verify Auth0 redirect_uri matches localhost:3000
- Try clearing browser cache

**Backend rejects token**
- Check backend `.env` has AUTH0_DOMAIN
- Restart backend after adding `.env`
- Check backend logs for specific auth error

## 📝 Configuration Summary

**Your Auth0 Settings:**
- Domain: `dev-1672riu03fjuf7so.us.auth0.com`
- Client ID: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`
- Audience: `globalbridge-api`

**Callback URLs (for Auth0 Dashboard):**
```
http://localhost:3000
http://localhost:3000/callback
```

**Files Already Configured:**
- ✅ `src/auth0.js` - Auth0 client with your credentials
- ✅ `src/Ports.elm` - Auth0 ports defined
- ✅ `src/main.js` - Auth0 integration wired up
- ✅ `src/Main.elm` - Auth0 login flow implemented
- ✅ `package.json` - Auth0 SDK installed

## 🎯 Next Steps

1. **Update Auth0 Dashboard** with web callback URLs (see above)
2. **Start backend**: `cd globalbridge_backend && mix phx.server`
3. **Start Elm client**: `cd clients/elm-client && npm run dev`
4. **Open browser**: http://localhost:3000

## 🔑 Create the API (Fix “Service not found: globalbridge-api”)

Your SPA requests an access token with audience `globalbridge-api` (see `src/auth0.js`). If you see `error=access_denied&error_description=Service not found: globalbridge-api` after login, the API isn’t created in your Auth0 tenant yet.

1. In the Auth0 Dashboard, go to **APIs** → **Create API**
2. Name: `GlobalBridge API`
3. Identifier (Audience): `globalbridge-api`
4. Signing Algorithm: `RS256`
5. Save

Optional (recommended):
- Enable RBAC and “Add Permissions in the Access Token” if you’ll use scopes.
- In your SPA Application → Advanced Settings → Refresh Token Rotation, enable it if you keep `useRefreshTokens: true` in `auth0.js`.

After creating the API, retry login from http://localhost:3000.
5. **Test Auth0 login!** 🎉

The Elm client will now work exactly like the iOS client:
- ✅ Auth0 authentication
- ✅ WebSocket-only communication
- ✅ Bootstrap via user channel
- ✅ Thread sync from backend
- ✅ No more "thread not found" errors!
