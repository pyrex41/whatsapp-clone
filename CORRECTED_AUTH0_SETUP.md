# ✅ Corrected Auth0 Setup (Using Your Bundle ID)

## Your Bundle Identifier
`name.reubenbrooks.globalbridge`

We'll use this as the URL scheme for Auth0 callbacks.

---

## 🔧 Xcode Setup (3 Steps)

### Step 1: Add Auth0 Package (2 minutes)

In Xcode (should already be open):
1. **File** → **Add Package Dependencies**
2. Paste: `https://github.com/auth0/Auth0.swift`
3. Click **Add Package**
4. Select **Auth0** library
5. Click **Add Package**

### Step 2: Add URL Scheme (1 minute)

Still in Xcode:
1. Select **GlobalBridge** target (already selected in your screenshot)
2. Go to **Info** tab (already there)
3. Scroll down to **URL Types** section
4. Click the **+** button
5. Fill in:
   - **Identifier**: `auth0`
   - **URL Schemes**: `name.reubenbrooks.globalbridge`
   - **Role**: `Editor`

### Step 3: Update Auth0 Dashboard (2 minutes)

Go to: https://manage.auth0.com

1. Login and select your Application
2. Go to **Settings** tab
3. Find **Allowed Callback URLs** field
4. **Add this URL:**
   ```
   name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
   ```

5. Find **Allowed Logout URLs** field
6. **Add this URL:**
   ```
   name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge
   ```

7. Click **Save Changes** at the bottom

---

## 🧪 Test It!

### Terminal 1: Start Backend
```bash
cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
mix phx.server
```

### Xcode: Run App
Press **Cmd+R** to run

---

## 📊 Expected Flow

1. **App launches** → Triggers Auth0 login
2. **Safari opens** → Auth0 login page
3. **Login** → Enter your Auth0 credentials
4. **Redirect** → Safari redirects to `name.reubenbrooks.globalbridge://...`
5. **App receives token** → iOS stores JWT
6. **Connects to Phoenix** → Backend verifies token
7. **Joins user channel** → `user:{auth0|your_id}`
8. **Fetches bootstrap** → Gets threads from backend
9. **Success!** → Ready to message

---

## 🎯 Quick Reference

**Your Configuration:**
- Bundle ID: `name.reubenbrooks.globalbridge`
- URL Scheme: `name.reubenbrooks.globalbridge`
- Auth0 Domain: `dev-1672riu03fjuf7so.us.auth0.com`
- Client ID: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`

**Callback URL for Auth0 Dashboard:**
```
name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
```

**Logout URL for Auth0 Dashboard:**
```
name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge
```

---

## ✨ That's It!

Complete the 3 Xcode/Dashboard steps above and you'll be ready to test! The bundle identifier is perfect as-is - we're just using it for the URL scheme. 🚀


