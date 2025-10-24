# 🚀 Production Deployment Ready

Your GlobalBridge backend is now ready to deploy to Fly.io with automatic database seeding!

## What Was Changed

### 1. Fixed Phoenix WebSocket URL ✅
**File**: `clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixConfig.swift`
- **Changed**: `wss://globalbridge.fly.dev/socket` 
- **To**: `wss://globalbridge-backend.fly.dev/socket`
- **Why**: The Fly.io app name is `globalbridge-backend`, not `globalbridge`

### 2. Enabled Dev Mode in Production ⚠️
**Files**: 
- `globalbridge_backend/config/runtime.exs` - Added `DEV_MODE` environment variable support
- `globalbridge_backend/fly.toml` - Set `DEV_MODE = 'true'`

**What this does**: Allows WebSocket connections without Auth0 tokens for testing

⚠️ **Security Note**: This bypasses authentication! Remove `DEV_MODE = 'true'` before production with real users.

### 3. Production Database Seeding 🌱
**Files Created**:
- `priv/repo/seeds_prod.exs` - Idempotent seed script for test users and threads
- `rel/overlays/bin/migrate_and_seed` - Startup script (runs migrations + seeds + starts server)
- `PRODUCTION_SEEDING.md` - Complete documentation

**What gets seeded**:

#### Test Users
| Username | Phone Number    | Password     | Display Name  | User ID (example) |
|----------|----------------|--------------|---------------|-------------------|
| testuser | +11234567890   | password123  | Test User     | Auto-generated UUID |
| demo     | +19876543210   | demo123      | Demo User     | Auto-generated UUID |
| alice    | +15551234567   | alice123     | Alice Smith   | Auto-generated UUID |
| bob      | +15559876543   | bob123       | Bob Johnson   | Auto-generated UUID |

#### Test Threads
1. **Direct: Chat with Alice** (testuser + alice)
2. **Group: Team Discussion** (testuser + alice + bob)
3. **Direct: Chat with Bob** (testuser + bob)
4. **Group: Project Planning** (testuser + demo + alice)

Each thread gets its own sharded SQLite database at `/mnt/data/threads/{thread_id}.db`

### 4. Updated Docker Build
**File**: `globalbridge_backend/Dockerfile`
- **Changed**: `CMD ["/app/bin/server"]`
- **To**: `CMD ["/app/bin/migrate_and_seed"]`
- **Why**: Runs migrations and seeds before starting the server

## Deployment Steps

### Step 1: Deploy to Fly.io

```bash
cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
fly deploy
```

This will:
1. Build the Docker image with your changes
2. Deploy to Fly.io
3. On startup:
   - Run database migrations
   - Seed test users (Alice, Bob, testuser, demo)
   - Seed test threads
   - Start the Phoenix server

**Expected deploy time**: ~3-5 minutes

### Step 2: Verify Deployment

```bash
# Watch the logs
fly logs -a globalbridge-backend

# Look for these success messages:
# 🚀 Starting GlobalBridge Backend...
# 📦 Running database migrations...
# 🌱 Running production seeds...
# ✓ User already exists: testuser
# ✓ Created thread: Chat with Alice
# 🎉 Production seeding complete!
# 🌐 Starting Phoenix server...
```

### Step 3: Test iOS Connection

1. Open Xcode and rebuild the iOS app (to pick up the new WebSocket URL)
2. Run the app on simulator or device
3. The app should now connect to `wss://globalbridge-backend.fly.dev`
4. You should see connection logs in Fly.io logs:

```bash
fly logs -a globalbridge-backend

# Look for:
# ✅ [AUTH] Dev mode connection accepted, user_id: xxx (DEV MODE)
# [info] JOINED user:xxx in 1ms
```

## What's Stored Where

All data is persisted on Fly.io's mounted volume at `/mnt/data`:

```
/mnt/data/
├── users.db              # User accounts, profiles
├── bridges.db            # Bridge data
├── sync_state.db         # Sync state tracking
└── threads/
    ├── {uuid1}.db        # Thread 1 messages
    ├── {uuid2}.db        # Thread 2 messages
    └── ...
```

Each thread gets its own SQLite database for horizontal scalability.

## Testing the Setup

### 1. Connect with iOS App
- Launch the app
- Should auto-connect (dev mode, no auth required)
- You should see threads: "Chat with Alice", "Team Discussion", etc.

### 2. Send Test Messages
```bash
# SSH into production
fly ssh console -a globalbridge-backend

# Start Elixir shell
/app/bin/globalbridge_backend remote

# Check users
iex> GlobalbridgeBackend.Repo.all(GlobalbridgeBackend.Schemas.User)

# Check threads
iex> GlobalbridgeBackend.Repo.all(GlobalbridgeBackend.Schemas.Thread)

# Check thread participants
iex> GlobalbridgeBackend.Repo.all(GlobalbridgeBackend.Schemas.ThreadParticipant)
```

### 3. Check Database Files
```bash
fly ssh console -a globalbridge-backend

# List databases
ls -lh /mnt/data/

# Check users database
sqlite3 /mnt/data/users.db "SELECT username, phone_number, display_name FROM users;"

# Check threads database
sqlite3 /mnt/data/users.db "SELECT id, title, thread_type FROM threads;"
```

## Important Notes

### Security Warnings ⚠️

1. **DEV_MODE is enabled**: Anyone can connect without authentication
   - Remove `DEV_MODE = 'true'` from `fly.toml` before production
   - Implement proper Auth0 flow for real users

2. **Weak Passwords**: Test accounts have simple passwords (`alice123`, etc.)
   - Fine for testing
   - Never use in real production

3. **Public Test Accounts**: These accounts are known to everyone
   - Don't store sensitive data
   - Reset/remove before going live

### Data Persistence ✅

- Data survives app restarts
- Data survives redeployments
- Fly.io volume is persistent
- Seeds are idempotent (won't duplicate data)

### Scaling Considerations

- Each thread has its own database (sharded by `database_shard_id`)
- Good for horizontal scaling
- Single Fly.io machine for now (1GB RAM, shared CPU)
- Can scale up/out as needed

## Next Steps After Testing

1. **Remove DEV_MODE**: 
   ```toml
   # In fly.toml, remove or set to:
   DEV_MODE = 'false'
   ```

2. **Implement Auth0 Flow**:
   - iOS app sends Auth0 token in WebSocket connection
   - Backend verifies token
   - User is authenticated properly

3. **Add Real Users**:
   - Remove test accounts or change passwords
   - Use Auth0 for user management
   - Implement proper authorization

4. **Monitor Production**:
   ```bash
   fly logs -a globalbridge-backend  # Live logs
   fly status -a globalbridge-backend  # App status
   fly volumes list  # Check storage
   ```

5. **Scale if Needed**:
   ```bash
   fly scale memory 2048  # Increase to 2GB RAM
   fly scale count 2  # Add another machine
   ```

## Troubleshooting

### iOS App Won't Connect

1. **Check URL**: Make sure iOS config has `wss://globalbridge-backend.fly.dev/socket`
2. **Check logs**: `fly logs -a globalbridge-backend`
3. **Check app status**: `fly status -a globalbridge-backend`
4. **Restart app**: `fly apps restart globalbridge-backend`

### Seeds Didn't Run

```bash
# SSH and manually run seeds
fly ssh console -a globalbridge-backend
/app/bin/globalbridge_backend eval 'Code.eval_file("priv/repo/seeds_prod.exs")'
```

### Database Issues

```bash
# Check if databases exist
fly ssh console -a globalbridge-backend
ls -la /mnt/data/

# Check database integrity
sqlite3 /mnt/data/users.db "PRAGMA integrity_check;"
```

### App Won't Start

```bash
# Check logs for errors
fly logs -a globalbridge-backend

# Common issues:
# - Missing SECRET_KEY_BASE secret
# - Database path issues
# - Migration failures
```

## Files Reference

All files changed/created for this setup:

```
globalbridge_backend/
├── config/
│   └── runtime.exs              # Added DEV_MODE config
├── priv/repo/
│   └── seeds_prod.exs           # NEW: Production seeds
├── rel/overlays/bin/
│   └── migrate_and_seed         # NEW: Startup script
├── Dockerfile                   # Updated CMD
├── fly.toml                     # Added DEV_MODE env var
├── PRODUCTION_SEEDING.md        # NEW: Seed documentation
└── PRODUCTION_READY.md          # This file

clients/ios/GlobalBridge/
└── Core/Networking/Phoenix/
    └── PhoenixConfig.swift      # Fixed WebSocket URL
```

## Deploy Now!

You're ready to go:

```bash
cd /Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend
fly deploy
```

Good luck! 🚀

