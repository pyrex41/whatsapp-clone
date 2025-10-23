# Production Database Seeding - DEPRECATED

**This document is for historical reference only. Production seeding has been removed as of [current date] to improve startup performance.**

Previously, the production deployment automatically seeded test users and threads on first startup. This functionality has been removed to reduce backend startup time from ~60 seconds to ~5-10 seconds.

## Test Users

The following users are seeded in production:

| Username | Phone Number    | Password     | Display Name  |
|----------|----------------|--------------|---------------|
| testuser | +11234567890   | password123  | Test User     |
| demo     | +19876543210   | demo123      | Demo User     |
| alice    | +15551234567   | alice123     | Alice Smith   |
| bob      | +15559876543   | bob123       | Bob Johnson   |

## Test Threads

Four test threads are created:

1. **Direct: Chat with Alice** (testuser + alice)
2. **Group: Team Discussion** (testuser + alice + bob)
3. **Direct: Chat with Bob** (testuser + bob)
4. **Group: Project Planning** (testuser + demo + alice)

Each thread gets a unique `database_shard_id` for storing messages in sharded SQLite databases.

## How It Works

### Startup Flow

When the Docker container starts, the following happens:

1. **Run Migrations**: `bin/globalbridge_backend eval "GlobalbridgeBackend.Release.migrate()"`
2. **Run Seeds**: `bin/globalbridge_backend eval 'Code.eval_file("priv/repo/seeds_prod.exs")'`
3. **Start Server**: `PHX_SERVER=true bin/globalbridge_backend start`

### Files Involved

- `priv/repo/seeds_prod.exs` - Production seed script (idempotent)
- `rel/overlays/bin/migrate_and_seed` - Startup script that orchestrates the process
- `lib/globalbridge_backend/release.ex` - Release tasks module (migrations)

### Database Storage

All data is stored in the persistent Fly.io volume:

- User data: `/mnt/data/users.db`
- Bridge data: `/mnt/data/bridges.db`
- Sync state: `/mnt/data/sync_state.db`
- Thread messages: `/mnt/data/threads/{thread_id}.db` (one per thread)

## Deployment

### Initial Deployment

```bash
cd globalbridge_backend
fly deploy
```

On first deployment:
- Volume is created at `/mnt/data`
- Migrations run to create schema
- Seeds run to populate test data
- Server starts

### Subsequent Deployments

The seed script is idempotent:
- Checks if users exist before creating them
- Checks if threads exist before creating them
- Safe to run on every deployment

### Manual Seeding

To manually run seeds in production:

```bash
# SSH into the production machine
fly ssh console -a globalbridge-backend

# Run the seed script
/app/bin/globalbridge_backend eval 'Code.eval_file("priv/repo/seeds_prod.exs")'
```

## Development vs Production

### Development (`mix run priv/repo/seeds.exs`)
- Clears existing data first
- Creates users and threads
- Runs locally with mix

### Production (`priv/repo/seeds_prod.exs`)
- Idempotent - checks for existing data
- Never deletes data
- Runs as part of release startup
- Uses Logger for output

## Security Notes

- Test passwords are simple (`password123`, etc.)
- These are **development/testing accounts only**
- In real production, you'd want:
  - Secure passwords
  - Auth0 authentication
  - No pre-seeded accounts
  - Or at minimum, strong passwords in Fly.io secrets

## Troubleshooting

### Check if seeds ran successfully

```bash
fly logs -a globalbridge-backend | grep "🌱"
```

Look for:
```
🌱 Starting production database seeding...
✓ Created user: testuser (...)
✓ Created thread: Chat with Alice (...)
🎉 Production seeding complete!
```

### Verify users exist

```bash
fly ssh console -a globalbridge-backend

# Run Elixir shell
/app/bin/globalbridge_backend remote

# Check users
iex> GlobalbridgeBackend.Repo.all(GlobalbridgeBackend.Schemas.User)
```

### Re-run seeds manually

If you need to force re-creation:

```bash
fly ssh console -a globalbridge-backend
/app/bin/globalbridge_backend eval 'Code.eval_file("priv/repo/seeds_prod.exs")'
```

## Future Enhancements

- Add seed flag to skip seeding in production
- Add more test messages to threads
- Add profile pictures for test users
- Add option to seed different data sets
- Add seed script for staging environment

