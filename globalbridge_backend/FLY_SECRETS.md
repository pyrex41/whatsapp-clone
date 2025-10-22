# Fly.io Secrets Configuration

## Required Secrets

Run these commands **before** deploying:

```bash
cd globalbridge_backend

# 1. SECRET_KEY_BASE (Required - Phoenix sessions/cookies)
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)

# 2. GUARDIAN_SECRET_KEY (Required - JWT authentication)
fly secrets set GUARDIAN_SECRET_KEY=$(mix phx.gen.secret)

# 3. PHX_HOST (Required - Your Fly.io hostname)
fly secrets set PHX_HOST=your-app-name.fly.dev

# 4. DATABASE_PATH (For SQLite - if using persistent volumes)
fly secrets set DATABASE_PATH=/mnt/data/globalbridge.db
```

## Optional Secrets

```bash
# Auth0 (if using real Auth0 instead of test tokens)
fly secrets set AUTH0_DOMAIN=your-tenant.auth0.com
fly secrets set AUTH0_AUDIENCE=your-api-identifier

# Port (defaults to 4000)
fly secrets set PORT=4000

# DNS Clustering (auto-set by Fly.io)
# fly secrets set DNS_CLUSTER_QUERY=your-app.internal
```

## Quick Setup (Copy-Paste)

**Replace `YOUR-APP-NAME` with your actual Fly.io app name:**

```bash
# Generate and set all required secrets
fly secrets set \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  GUARDIAN_SECRET_KEY=$(mix phx.gen.secret) \
  PHX_HOST=YOUR-APP-NAME.fly.dev \
  DATABASE_PATH=/mnt/data/globalbridge.db
```

## Verify Secrets

```bash
# List all secrets (values are hidden)
fly secrets list
```

## Database Consideration

### Current Setup: SQLite

Your app uses SQLite with sharded databases. For production on Fly.io:

**Option 1: Use Fly Volumes (Persistent SQLite)**

```bash
# Create a persistent volume
fly volumes create globalbridge_data --size 10

# Update fly.toml
[mounts]
  source = "globalbridge_data"
  destination = "/mnt/data"
```

**Option 2: Switch to Postgres (Recommended for Production)**

Fly.io automatically creates a Postgres database during `fly launch`.

You'd need to:
1. Update `config/runtime.exs` to use `DATABASE_URL` instead of `DATABASE_PATH`
2. Update Ecto adapter from SQLite to Postgres
3. Run migrations

## After Setting Secrets

```bash
# Deploy
fly deploy --remote-only

# Verify deployment
fly status

# Check logs
fly logs
```

## Secrets Summary

| Secret | Required | Purpose | Generate With |
|--------|----------|---------|---------------|
| `SECRET_KEY_BASE` | ✅ Yes | Phoenix sessions | `mix phx.gen.secret` |
| `GUARDIAN_SECRET_KEY` | ✅ Yes | JWT tokens | `mix phx.gen.secret` |
| `PHX_HOST` | ✅ Yes | App hostname | Your Fly.io URL |
| `DATABASE_PATH` | ✅ Yes* | SQLite path | `/mnt/data/globalbridge.db` |
| `DATABASE_URL` | If Postgres | Postgres connection | Auto-set by Fly |
| `AUTH0_DOMAIN` | Optional | Auth0 | Your Auth0 tenant |
| `AUTH0_AUDIENCE` | Optional | Auth0 | Your API ID |
| `PORT` | Optional | HTTP port | `4000` (default) |

*Required if using SQLite with volumes

## Quick Start

```bash
# 1. Set secrets
fly secrets set \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  GUARDIAN_SECRET_KEY=$(mix phx.gen.secret) \
  PHX_HOST=globalbridge.fly.dev \
  DATABASE_PATH=/mnt/data/globalbridge.db

# 2. Create volume (for SQLite)
fly volumes create globalbridge_data --size 10

# 3. Deploy
fly deploy --remote-only

# 4. Verify
fly status
fly logs
```

Done! 🚀

