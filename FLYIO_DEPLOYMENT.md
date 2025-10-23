# Deploying GlobalBridge to Fly.io

## Prerequisites Fixed

✅ **Dockerfile Updated** - Now includes all required config files:
- `config.exs`
- `prod.exs`
- `guardian.exs` (was missing - FIXED)
- `databases.exs` (was missing - FIXED)

## Deployment Steps

### 1. Install Fly.io CLI

```bash
# macOS
brew install flyctl

# Or use installer
curl -L https://fly.io/install.sh | sh
```

### 2. Sign Up / Login

```bash
# First time
fly auth signup

# Or login
fly auth login
```

### 3. Launch Your App

```bash
cd globalbridge_backend

# This will:
# - Detect Phoenix app
# - Create Dockerfile (already exists)
# - Create fly.toml
# - Set up Postgres database
# - Deploy!
fly launch
```

**During `fly launch`, answer:**
- **App name:** `globalbridge-backend` (or let it generate)
- **Organization:** Personal (default)
- **Region:** Choose nearest region
- **Postgres:** **YES** - set up database
- **Deploy now:** **YES**

### 4. Set Secrets

```bash
# Required secrets
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set AUTH0_DOMAIN=your-tenant.auth0.com
fly secrets set AUTH0_AUDIENCE=your-api-identifier

# Optional: Guardian secret
fly secrets set GUARDIAN_SECRET_KEY=$(mix phx.gen.secret)
```

### 5. Configure Database

The Fly.io launcher creates a Postgres database. Update `config/runtime.exs` if needed for Postgres (currently using SQLite for local dev).

### 6. Deploy

```bash
# Deploy your app
fly deploy

# If on Apple Silicon (M1/M2/M3), use remote builder
fly deploy --remote-only
```

### 7. Verify Deployment

```bash
# Check status
fly status

# View logs
fly logs

# Open in browser
fly open
```

### 8. Database Setup

```bash
# Run migrations
fly ssh console -C "/app/bin/globalbridge_backend eval 'GlobalbridgeBackend.Release.migrate'"

# Seed database
fly ssh console -C "/app/bin/globalbridge_backend eval 'GlobalbridgeBackend.Release.seed'"
```

**Note:** You'll need to create release tasks. Add to `lib/globalbridge_backend/release.ex`:

```elixir
defmodule GlobalbridgeBackend.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix installed.
  """
  @app :globalbridge_backend

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()
    
    # Run the seed script
    seed_script = Path.join([Application.app_dir(:globalbridge_backend), "priv", "repo", "seeds.exs"])
    Code.eval_file(seed_script)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

## Environment Variables for Production

Set these in Fly.io:

```bash
# Required
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly secrets set DATABASE_URL=postgresql://...  # Auto-set by Fly

# Auth0 (if using)
fly secrets set AUTH0_DOMAIN=your-tenant.auth0.com
fly secrets set AUTH0_AUDIENCE=your-api-identifier

# Optional
fly secrets set PHX_HOST=your-app.fly.dev
fly secrets set PORT=4000
```

## Clustering (Optional)

For multiple regions:

```bash
# Add another region
fly regions add ewr  # East coast US

# Scale to 2 instances
fly scale count 2
```

Elixir nodes will automatically cluster thanks to DNS_CLUSTER_QUERY in `config/runtime.exs`.

## Troubleshooting

### Build Fails

```bash
# View build logs
fly logs

# Try remote builder (for M1/M2/M3 Macs)
fly deploy --remote-only
```

### Database Issues

```bash
# Check Postgres status
fly postgres db list

# Connect to database
fly postgres connect -a your-db-name
```

### App Crashes

```bash
# View logs
fly logs

# Get IEx shell into running app
fly ssh console -C "/app/bin/globalbridge_backend remote"
```

## Important Notes

- **Database:** Fly creates Postgres, but app uses SQLite locally. You may need to:
  - Switch to Postgres in production, OR
  - Configure persistent volumes for SQLite
  
- **File Storage:** SQLite shard databases need persistent storage on Fly.io

- **Secrets:** Never commit secrets to git - always use `fly secrets set`

## Next Steps After Deployment

1. **Update iOS app** with production URL:
   ```swift
   // In PhoenixConfig.swift
   static let production = PhoenixConfig(
       socketURL: URL(string: "wss://your-app.fly.dev/socket")!,
       authToken: nil
   )
   ```

2. **Update Auth0 URLs** with Fly.io domain

3. **Test from real devices** (not just simulators)

## Useful Commands

```bash
# Scale
fly scale count 3

# View status
fly status

# Tail logs
fly logs

# SSH into machine
fly ssh console

# Restart app
fly apps restart

# Destroy app
fly apps destroy your-app-name
```

## Cost

Fly.io free tier includes:
- 3 shared-cpu-1x VMs (up to 256MB RAM each)
- 3GB persistent volume storage
- 160GB outbound data transfer

Should be sufficient for testing/development!

