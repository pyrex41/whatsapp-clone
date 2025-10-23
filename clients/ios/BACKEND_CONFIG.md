# Backend Configuration Guide

The iOS app can connect to either your local development backend or the production backend on Fly.io.

## Quick Setup

### Default Behavior
- **DEBUG builds** (running in Simulator/Xcode): Uses `localhost:4000`
- **RELEASE builds** (TestFlight/App Store): Uses `globalbridge-backend.fly.dev`

### Override with Environment Variable

Set `BACKEND_ENV` to control which backend to use:

| Value | Backend |
|-------|---------|
| `local`, `dev`, `development` | http://localhost:4000 |
| `production`, `prod` | https://globalbridge-backend.fly.dev |

## How to Set Environment Variable in Xcode

### Method 1: Edit Scheme (Recommended)
1. Click the scheme selector at the top (next to the device selector)
2. Select **"Edit Scheme..."**
3. Select **"Run"** in the left sidebar
4. Go to the **"Arguments"** tab
5. Under **"Environment Variables"**, click the **+** button
6. Add:
   - **Name:** `BACKEND_ENV`
   - **Value:** `local` (for localhost) or `production` (for Fly.io)
7. Check the ✓ checkbox to enable it
8. Click **"Close"**

### Method 2: Command Line Build
```bash
# For local backend
xcodebuild -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  BACKEND_ENV=local

# For production backend  
xcodebuild -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  BACKEND_ENV=production
```

## What Changes with Each Backend

### Local Backend (`localhost:4000`)
- **WebSocket:** `ws://localhost:4000/socket`
- **REST API:** `http://localhost:4000`
- **Auth:** Uses your local Auth0 dev tenant
- **Data:** Uses your local PostgreSQL database
- **Requires:** Backend running with `./start_backend.sh` or similar

### Production Backend (Fly.io)
- **WebSocket:** `wss://globalbridge-backend.fly.dev/socket`
- **REST API:** `https://globalbridge-backend.fly.dev`
- **Auth:** Uses production Auth0 tenant
- **Data:** Uses production PostgreSQL on Fly.io
- **Requires:** User account created on production

## Starting Local Backend

```bash
cd globalbridge_backend
./start_backend.sh
```

Or manually:
```bash
cd globalbridge_backend
AUTH0_DOMAIN=dev-1672riu03fjuf7so.us.auth0.com \
AUTH0_CLIENT_ID=id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj \
AUTH0_CLIENT_SECRET=dxN02R9JoaHhE-k0zIugmYg_Tkgtgw24MZu7YfwK0-x_z4z4chsFVTsNSDjToRl1 \
AUTH0_AUDIENCE=globalbridge-api \
DEV_MODE=true \
mix phx.server
```

## Verification

Check the Xcode console on app launch. You should see:
```
🔌 [PHOENIX] About to connect to backend
   - Backend URL: ws://localhost:4000/socket     // for local
   - Backend URL: wss://globalbridge-backend.fly.dev/socket  // for production
```

## Troubleshooting

### "Connection refused" on localhost
- Make sure the backend is running (`mix phx.server`)
- Check that it's listening on port 4000
- Verify no firewall is blocking the connection

### 401 Unauthorized
- User account may not exist on that backend
- Token may be from different Auth0 tenant
- Try logging out and back in

### Stuck on production when expecting local
- Check scheme environment variables (Method 1 above)
- Verify `BACKEND_ENV` is set to `local` or `dev`
- Clean build folder (Cmd+Shift+K) and rebuild

