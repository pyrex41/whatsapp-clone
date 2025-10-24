# iOS App - Connect to Fly.io Backend

## Quick Setup

### After Deploying to Fly.io:

**1. Get your Fly.io app URL:**
```bash
fly status
# Look for: Hostname = your-app-name.fly.dev
```

**2. Update iOS Phoenix Config:**

Open: `clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixConfig.swift`

Replace line 46:
```swift
socketURL: URL(string: "wss://YOUR-APP-NAME.fly.dev/socket")!,
```

With your actual Fly.io URL:
```swift
socketURL: URL(string: "wss://globalbridge-backend.fly.dev/socket")!,
```

**3. That's it!** 

The app automatically uses:
- **Debug builds (Simulator):** `ws://localhost:4000/socket`
- **Release builds (Device):** `wss://your-app.fly.dev/socket`

## Testing the Production Backend

### Option 1: Test from Simulator (Override to Production)

Temporarily change `PhoenixConfig.current`:

```swift
public static var current: PhoenixConfig {
    return .production  // Force production for testing
}
```

### Option 2: Run on Real Device

1. Archive app (Product > Archive)
2. Distribute to device via TestFlight or Ad Hoc
3. App automatically uses production backend

## Environment Switching

### Current Setup (Automatic):

```swift
public static var current: PhoenixConfig {
    #if DEBUG
    return .development  // ← Simulator/Debug builds
    #else
    return .production   // ← Device/Release builds
    #endif
}
```

### Manual Override for Testing:

```swift
public static var current: PhoenixConfig {
    return .production  // Always use production
    // return .development  // Always use local
}
```

## What Changes Based on Environment

| Setting | Development (Local) | Production (Fly.io) |
|---------|---------------------|---------------------|
| **Socket URL** | `ws://localhost:4000/socket` | `wss://your-app.fly.dev/socket` |
| **Protocol** | HTTP WebSocket (`ws://`) | Secure WebSocket (`wss://`) |
| **Logging** | Enabled (verbose) | Disabled (quiet) |
| **Reconnect Attempts** | 5 | 10 |
| **Reconnect Delay** | 2s | 5s |

## Auth0 URLs

If using Auth0 (not test tokens), update callback URLs:

**Auth0 Dashboard → Applications → Your App → Settings:**

Add to **Allowed Callback URLs:**
```
com.globalbridge://*.auth0.com/ios/com.globalbridge/callback
```

Add to **Allowed Logout URLs:**
```
com.globalbridge://*.auth0.com/ios/com.globalbridge/logout
```

## Backend CORS Configuration

Make sure your Fly.io backend allows iOS connections:

In `config/prod.exs`:
```elixir
config :globalbridge_backend, GlobalbridgeBackendWeb.Endpoint,
  url: [host: "your-app.fly.dev", port: 443, scheme: "https"],
  check_origin: false  # Or specify your iOS app scheme
```

## Testing Checklist

### Local Development (Current Setup):
- ✅ Simulator connects to `localhost:4000`
- ✅ Test users (alice, bob, testuser) work
- ✅ Real-time messaging works

### Production Testing:
1. Deploy backend to Fly.io
2. Update `PhoenixConfig.production` URL
3. Build app for device (or override `.current`)
4. Test real-time messaging through Fly.io

## Troubleshooting

### "Connection Failed" on Device

**Check:**
1. Fly.io app is running: `fly status`
2. URL is correct in `PhoenixConfig.swift`
3. Using `wss://` not `ws://`
4. Backend CORS allows iOS

**View backend logs:**
```bash
fly logs
```

### Works on Simulator, Fails on Device

- Simulator uses `DEBUG` build → `localhost`
- Device uses `RELEASE` build → Fly.io
- Make sure production URL is set correctly

### Test Production from Simulator

Temporarily override:
```swift
public static var current: PhoenixConfig {
    return .production  // Test Fly.io from simulator
}
```

Then rebuild and run.

## Files Modified

### iOS Changes:
- ✅ `Core/Networking/Phoenix/PhoenixConfig.swift` - Added `.current` with auto-detection
- ✅ `Core/State/AppEnvironment.swift` - Uses `PhoenixConfig.current`

### Backend Changes (For Deployment):
- ✅ `Dockerfile` - Fixed to include all config files
- ✅ `config/runtime.exs` - (check for production database URL)

## Quick Reference

**Development (localhost):**
```swift
PhoenixConfig.development
// ws://localhost:4000/socket
```

**Production (Fly.io):**
```swift
PhoenixConfig.production  
// wss://your-app.fly.dev/socket
```

**Auto-detect:**
```swift
PhoenixConfig.current
// Uses DEBUG/RELEASE flag to choose
```

## Next Steps

1. ✅ Deploy backend: `fly deploy --remote-only`
2. ✅ Get URL: `fly status`
3. ✅ Update line 46 in `PhoenixConfig.swift`
4. ✅ Build app
5. ✅ Test!

Everything is ready! Just update the URL after deploying.

