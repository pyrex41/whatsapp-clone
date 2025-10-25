# Developer Mode - Authentication Bypass

## Overview

The backend server includes a developer mode flag that bypasses authentication requirements for easier local testing and development.

## Configuration

Developer mode is controlled by the `:dev_mode` config flag in `config/dev.exs`:

```elixir
config :globalbridge_backend, dev_mode: true
```

**IMPORTANT**: This flag is only set to `true` in `dev.exs`. It should NEVER be enabled in production.

## What Developer Mode Does

When `dev_mode: true` is set:

### 1. HTTP API Authentication Bypass
- All API endpoints that normally require authentication will work without tokens
- A mock user is automatically created for each request with:
  - Random UUID as user ID
  - Username: `"dev_user"`
  - Phone number: `"+15551234567"`
- The mock user is assigned to `conn.assigns.current_user`
- A `dev_mode: true` flag is added to the connection

### 2. WebSocket Authentication Bypass
- WebSocket connections can be established without a JWT token
- You can optionally provide a `user_id` parameter to simulate a specific user
- If no `user_id` is provided, a random UUID is generated
- Mock users are created if they don't exist in the database

## Usage Examples

### HTTP API Requests (Dev Mode)

With dev mode enabled, you can make API requests without any authentication:

```bash
# No Authorization header needed
curl http://localhost:4000/api/v1/threads

# Translation endpoint
curl -X POST http://localhost:4000/api/v1/ai/translate \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello", "target_language": "es"}'

# Feature flags
curl http://localhost:4000/api/v1/features
```

### WebSocket Connections (Dev Mode)

```javascript
// Connect without token
let socket = new Socket("/socket", {})

// Or specify a user_id
let socket = new Socket("/socket", {
  params: {user_id: "some-uuid-here"}
})

socket.connect()
```

### HTTP API Requests (Production Mode - Auth Required)

In production or when `dev_mode: false`:

```bash
# Must provide Authorization header with valid JWT
curl http://localhost:4000/api/v1/threads \
  -H "Authorization: Bearer YOUR_JWT_TOKEN_HERE"
```

## Toggling Developer Mode

### Enable Developer Mode
The flag is already enabled in `config/dev.exs`. Just start the server:

```bash
cd globalbridge_backend
mix phx.server
```

### Disable Developer Mode
To test with authentication in development:

1. Edit `config/dev.exs`
2. Change: `config :globalbridge_backend, dev_mode: false`
3. Restart the server

### Check Current Mode
Watch the server logs when making requests:
- Dev mode bypass: `🔓 [AUTH] Dev mode: bypassing authentication for /api/v1/...`
- Normal auth: `🔍 [AUTH] Found Bearer token in request`

## Security Notes

⚠️ **CRITICAL SECURITY WARNINGS**:

1. **Never enable dev_mode in production**
   - This completely bypasses all authentication
   - Anyone can access all API endpoints
   - All data would be accessible without credentials

2. **Dev mode is not set in other environments**
   - `config/prod.exs` does NOT set `dev_mode`
   - `config/test.exs` does NOT set `dev_mode`
   - Only `config/dev.exs` has `dev_mode: true`

3. **Local development only**
   - Only use dev mode on your local machine
   - Never expose a dev mode server to the internet
   - Don't use dev mode with production databases

## Logs to Look For

### Dev Mode Active
```
🔓 [AUTH] Dev mode: bypassing authentication for /api/v1/threads
🔓 [AUTH] Dev mode connection attempt
✅ [AUTH] Dev mode connection accepted, user_id: xyz (DEV MODE)
```

### Normal Authentication
```
🔍 [AUTH] Found Bearer token in request
✅ [AUTH] Auth0 token verified for user: xyz
✅ [AUTH] Token verified successfully, user_id: xyz
```

## File Locations

- **Config**: `config/dev.exs` (line 4)
- **HTTP Pipeline**: `lib/globalbridge_backend/auth/pipeline.ex` (ensure_authenticated_custom/2)
- **WebSocket Handler**: `lib/globalbridge_backend_web/channels/user_socket.ex` (connect/3)
- **Router**: `lib/globalbridge_backend_web/router.ex` (uses `:auth` pipeline)

## Testing Both Modes

### Test with Dev Mode (No Auth)
1. Ensure `dev_mode: true` in `config/dev.exs`
2. Start server: `mix phx.server`
3. Make requests without Authorization header
4. Should see `🔓 [AUTH] Dev mode` in logs

### Test with Auth Required (Simulate Production)
1. Set `dev_mode: false` in `config/dev.exs`
2. Restart server: `mix phx.server`
3. Make requests without Authorization header → Should get 401 Unauthorized
4. Make requests with valid token → Should work

## Common Issues

### "401 Unauthorized" in Dev Mode
- Check that `dev_mode: true` is set in `config/dev.exs`
- Restart the server after changing config
- Check logs for `🔓 [AUTH] Dev mode` messages

### Dev Mode Not Working
- Verify the config file: `cat config/dev.exs | grep dev_mode`
- Make sure you're running in dev environment: `MIX_ENV=dev mix phx.server`
- Clear compiled files: `mix clean && mix phx.server`

## Example Test Workflow

```bash
# 1. Start backend in dev mode
cd globalbridge_backend
mix phx.server

# 2. In another terminal, test API without auth
curl http://localhost:4000/api/v1/threads
# Should work ✅

# 3. Test WebSocket
# Open browser console at http://localhost:4000
let socket = new Socket("/socket", {})
socket.connect()
// Should connect ✅

# 4. When ready for production testing, disable dev mode
# Edit config/dev.exs: dev_mode: false
# Restart server and verify auth is required
```
