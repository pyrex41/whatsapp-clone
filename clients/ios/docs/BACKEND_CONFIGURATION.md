# Backend Configuration Guide

This guide explains how to switch between local and production backends in the iOS app.

## Current Setup

The app automatically configures based on your build configuration:

### Development (Default)
- **WebSocket**: `ws://localhost:4000/socket`
- **REST API**: `http://localhost:4000`
- **Build Config**: Debug builds
- **Usage**: Local development and testing

### Production
- **WebSocket**: `wss://globalbridge-backend.fly.dev/socket`
- **REST API**: `https://globalbridge-backend.fly.dev`
- **Build Config**: Release builds or when `BACKEND_ENV=production`
- **Usage**: Testing against deployed backend

## Switching Backends

### Method 1: Build Configuration (Automatic)
- **Debug builds** → Uses localhost automatically
- **Release builds** → Uses production automatically

No configuration needed!

### Method 2: Environment Variable (Manual Override)

To test against production while in Debug mode:

1. **In Xcode**, edit your scheme:
   - Product → Scheme → Edit Scheme...
   - Select "Run" on the left
   - Go to "Arguments" tab
   - Under "Environment Variables", add:
     ```
     BACKEND_ENV = production
     ```

2. **Run the app** - it will now connect to Fly.io backend

3. **To switch back to localhost**:
   - Remove or disable the `BACKEND_ENV` variable
   - OR change its value to `development`

## Verification

When the app starts, check the Xcode console for:

```
🏠 [PhoenixConfig] Using LOCAL backend: localhost:4000
```

Or for production:

```
🌐 [PhoenixConfig] Using PRODUCTION backend: globalbridge-backend.fly.dev
```

## Running Local Backend

Before connecting to localhost, ensure your backend is running:

```bash
cd globalbridge_backend
mix phx.server
```

The backend will be available at `http://localhost:4000`

## API Endpoints

### WebSocket (Phoenix Channels)
- **Local**: `ws://localhost:4000/socket`
- **Production**: `wss://globalbridge-backend.fly.dev/socket`

### REST API
- **Local**: `http://localhost:4000/api/v1/*`
- **Production**: `https://globalbridge-backend.fly.dev/api/v1/*`

### Bootstrap API
- **Local**: `http://localhost:4000/api/v1/bootstrap`
- **Production**: `https://globalbridge-backend.fly.dev/api/v1/bootstrap`

## Current Environment Variables in Xcode

Your Xcode scheme currently has these environment variables:

```
AUTH0_AUDIENCE = https://globalbridge-api/
AUTH0_CLIENT_ID = id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj
AUTH0_DOMAIN = dev-1672riu03fjuf7so.us.auth0.com
```

To add backend configuration:

1. Product → Scheme → Edit Scheme...
2. Run → Arguments → Environment Variables
3. Click "+" and add:
   - Name: `BACKEND_ENV`
   - Value: `production` (or `development`)

## Troubleshooting

### "Connection failed" errors

1. **For localhost**: Ensure backend is running on port 4000
   ```bash
   cd globalbridge_backend
   mix phx.server
   ```

2. **For production**: Check Fly.io status
   ```bash
   fly status -a globalbridge-backend
   ```

### Wrong backend being used

Check the console logs when app starts:
- Should see `🏠 [PhoenixConfig]...` for local
- Should see `🌐 [PhoenixConfig]...` for production

### Auth0 errors

Auth0 configuration is separate from backend URLs. The current Auth0 setup:
- Domain: `dev-1672riu03fjuf7so.us.auth0.com`
- Works with both local and production backends

## Code References

Backend configuration is managed in:
- `PhoenixConfig.swift:56` - WebSocket configuration
- `ThreadService.swift:16` - REST API configuration
- `AppEnvironment.swift:93` - Active configuration selection
