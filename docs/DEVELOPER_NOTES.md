# GlobalBridge Developer Notes

## Test Users & Credentials

This document contains all test user accounts for development and testing.

---

## Primary Test Users (Database Seeds)

These users are created when you run the database seeds script. Use these for development and manual testing.

### User 1 - Standard Test User
```
Username:     testuser
Phone:        +11234567890
Password:     password123
Display Name: Test User
Status:       Available for testing
Tier:         free
```

### User 2 - Demo Account
```
Username:     demo
Phone:        +19876543210
Password:     demo123
Display Name: Demo User
Status:       Demo account
Tier:         free
```

### User 3 - Alice
```
Username:     alice
Phone:        +15551234567
Password:     alice123
Display Name: Alice Smith
Status:       Hey there! I'm using GlobalBridge
Tier:         free
```

### User 4 - Bob
```
Username:     bob
Phone:        +15559876543
Password:     bob123
Display Name: Bob Johnson
Status:       Busy
Tier:         free
```

---

## Running Database Seeds

To create the primary test users in your development database:

```bash
cd globalbridge_backend
mix run priv/repo/seeds.exs
```

This will:
- Clear existing users (in dev environment only)
- Create all 4 test users listed above
- Display confirmation messages

**Output:**
```
Clearing existing users...
Creating test users...
✓ Created test user: testuser (+11234567890)
✓ Created demo user: demo (+19876543210)
✓ Created user: alice (Alice Smith)
✓ Created user: bob (Bob Johnson)
```

---

## Automated Test Users

These users are automatically created during test suite execution. **Do not use these for manual testing.**

### Authentication Test User
```
Username:     testuser
Phone:        +1234567890
Password:     TestPassword123
Display Name: Test User
File:         test/globalbridge_backend_web/controllers/auth_controller_test.exs
Purpose:      Testing authentication, login, signup, token refresh
```

### Public Key Test User
```
Username:     user2
Phone:        +1987654321
Password:     Password123
Public Key:   user2_public_key
File:         test/globalbridge_backend_web/controllers/auth_controller_test.exs
Purpose:      Testing end-to-end encryption key exchange
```

### Sync Test Users (syncuser1-7)
```
syncuser1 | +11234567890 | password123 | Sync User 1
syncuser2 | +11234567891 | password123 | Sync User 2
syncuser3 | +11234567892 | password123 | (test isolation)
syncuser4 | +11234567893 | password123 | (test isolation)
syncuser5 | +11234567894 | password123 | (access control)
syncuser6 | +11234567895 | password123 | (access control)
syncuser7 | +11234567896 | password123 | (access control)

File:    test/globalbridge_backend_web/controllers/sync_controller_test.exs
Purpose: Testing CDC sync, conflict resolution, authorization
```

---

## Frontend Development Credentials

### Elm Web Client (Dev Mode)

When running the Elm client in development mode (`npm run dev`), the login form auto-fills with:

```
Identifier: devuser
Password:   dev123456
```

**⚠️ WARNING:** The `devuser` account does NOT exist in the backend seeds. You must either:

1. **Create the user via signup** (recommended):
   - Open Elm frontend: http://localhost:3000
   - Navigate to signup (if implemented)
   - Create account with username `devuser` and password `dev123456`

2. **OR use an existing test user**:
   - Change `devMode` preset in `clients/elm-client/src/Page/Login.elm` lines 33-34:
   ```elm
   { identifier = "testuser"  -- Use existing user
   , password = "password123"
   ```

### iOS Swift Client

No hardcoded test credentials in iOS app. Use any test user from the seeds.

---

## API Authentication Examples

### Login with Username
```bash
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "testuser",
    "password": "password123"
  }'
```

### Login with Phone Number
```bash
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "+11234567890",
    "password": "password123"
  }'
```

### Response
```json
{
  "data": {
    "user": {
      "id": "uuid-here",
      "username": "testuser",
      "phone_number": "+11234567890",
      "display_name": "Test User",
      "is_online": true,
      "has_public_key": false
    },
    "tokens": {
      "access_token": "eyJhbGciOi...",
      "refresh_token": "eyJhbGciOi..."
    }
  }
}
```

---

## Database Management

### Reset All Data
```bash
cd globalbridge_backend

# Drop and recreate database
mix ecto.drop
mix ecto.create
mix ecto.migrate

# Reseed test users
mix run priv/repo/seeds.exs
```

**⚠️ IMPORTANT:** If you encounter "no such column" errors like `no such column: u0.public_key`, your database schema is out of sync. Run the reset commands above to fix it.

**Last Database Reset:** 2025-10-21 (Fixed missing `public_key` column issue)

### View Database (Development)
```bash
cd globalbridge_backend

# SQLite database location
sqlite3 priv/repo/test.db

# View users table
.headers on
.mode column
SELECT id, username, phone_number, display_name FROM users;
```

### Check User Count
```bash
cd globalbridge_backend
mix run -e "IO.inspect(GlobalbridgeBackend.Repo.aggregate(GlobalbridgeBackend.Schemas.User, :count))"
```

---

## Testing with Multiple Clients

### Scenario: Alice and Bob Direct Messaging

**Terminal 1 - Alice (Elm Web Client)**
```bash
cd clients/elm-client
npm run dev
# Open http://localhost:3000
# Login: alice / alice123
```

**Terminal 2 - Bob (iOS Simulator)**
```bash
cd clients/ios/GlobalBridge
open GlobalBridge.xcodeproj
# Run in Xcode simulator
# Login: bob / bob123
```

**Terminal 3 - Backend Server**
```bash
cd globalbridge_backend
mix phx.server
# Backend at http://localhost:4000
```

**Terminal 4 - Phoenix Channel Inspector**
```bash
# Monitor WebSocket connections
cd globalbridge_backend
iex -S mix phx.server
# In IEx console:
GlobalbridgeBackendWeb.Endpoint.config(:pubsub_server)
|> Phoenix.PubSub.subscribers("thread:*")
```

---

## Environment Variables

### Backend (globalbridge_backend/.env)
```bash
# Database
DATABASE_URL=ecto://user:pass@localhost/globalbridge_dev

# JWT Secrets
GUARDIAN_SECRET_KEY=your-dev-secret-key-minimum-32-chars

# Phoenix
SECRET_KEY_BASE=your-phoenix-secret-key-base

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# Server
PORT=4000
```

### Elm Frontend (clients/elm-client/.env)
```bash
VITE_API_URL=http://localhost:4000
```

---

## Common Development Tasks

### Create New Test User via API
```bash
curl -X POST http://localhost:4000/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "username": "newuser",
    "phone_number": "+15555555555",
    "password": "securepass123",
    "display_name": "New User"
  }'
```

### Check User Online Status
```elixir
# In IEx console (iex -S mix phx.server)
user = GlobalbridgeBackend.Repo.get_by!(GlobalbridgeBackend.Schemas.User, username: "testuser")
user.is_online
# Returns: true or false
```

### Monitor Phoenix Presence
```elixir
# In IEx console
alias GlobalbridgeBackendWeb.Presence
Presence.list("thread:some-thread-id")
# Returns: %{user_id => %{metas: [%{online_at: timestamp, phx_ref: ref}]}}
```

### View Active Phoenix Channels
```elixir
# In IEx console
Process.whereis(GlobalbridgeBackendWeb.Endpoint)
|> :sys.get_state()
|> elem(1)
|> Map.get(:channels)
```

---

## Troubleshooting

### Issue: "Invalid credentials" when logging in with test user

**Cause:** Database not seeded or user doesn't exist

**Solution:**
```bash
cd globalbridge_backend
mix run priv/repo/seeds.exs
```

### Issue: Elm frontend shows "devuser" but login fails

**Cause:** `devuser` is a frontend preset that doesn't exist in backend

**Solution:** Either:
1. Create `devuser` via signup
2. OR change preset in `clients/elm-client/src/Page/Login.elm` to use `testuser`

### Issue: "User already exists" when running seeds

**Cause:** Seeds script only clears users in dev environment, not test

**Solution:**
```bash
# Force clear and reseed
cd globalbridge_backend
MIX_ENV=dev mix run priv/repo/seeds.exs
```

### Issue: Token expired errors

**Cause:** JWT access tokens expire after 1 hour

**Solution:**
```bash
# Use refresh token endpoint
curl -X POST http://localhost:4000/api/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "your-refresh-token-here"}'
```

---

## Quick Reference

**Fastest way to test the app:**

1. Start backend: `cd globalbridge_backend && mix phx.server`
2. Seed users: `mix run priv/repo/seeds.exs`
3. Start Elm client: `cd clients/elm-client && npm run dev`
4. Open browser: http://localhost:3000
5. Login with: `testuser` / `password123`

**Two-user conversation test:**

1. Browser 1: Login as `alice` / `alice123`
2. Browser 2 (private/incognito): Login as `bob` / `bob123`
3. Create direct thread between Alice and Bob
4. Send messages back and forth

---

## File Locations

- **Seeds Script:** `globalbridge_backend/priv/repo/seeds.exs`
- **Auth Tests:** `globalbridge_backend/test/globalbridge_backend_web/controllers/auth_controller_test.exs`
- **Sync Tests:** `globalbridge_backend/test/globalbridge_backend_web/controllers/sync_controller_test.exs`
- **Elm Dev Preset:** `clients/elm-client/src/Page/Login.elm` (lines 32-38)
- **User Schema:** `globalbridge_backend/lib/globalbridge_backend/schemas/user.ex`
- **Auth Context:** `globalbridge_backend/lib/globalbridge_backend/contexts/auth.ex`

---

**Last Updated:** 2025-10-21
**Project:** GlobalBridge WhatsApp Clone
**Backend:** Phoenix/Elixir + PostgreSQL
**Clients:** Elm (Web), Swift (iOS)
