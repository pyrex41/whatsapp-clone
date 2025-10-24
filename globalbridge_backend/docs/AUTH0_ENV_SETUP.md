# Auth0 Environment Variables Setup

## Overview

The Phoenix backend uses Auth0 for authentication. This guide explains all the environment variables needed.

## Environment Variables

### Auth0 Configuration

These variables must be set for Auth0 token verification to work:

```bash
# Your Auth0 domain (e.g., dev-abc123.us.auth0.com)
# Get from: Auth0 Dashboard → Applications → Your App → Settings → Domain
# Do NOT include https:// or trailing slash
AUTH0_DOMAIN=dev-1672riu03fjuf7so.us.auth0.com

# Your Auth0 application's audience (API identifier)
# Get from: Auth0 Dashboard → APIs → Your API → Identifier
# This is what Auth0 issues in the "aud" claim
AUTH0_AUDIENCE=https://api.globalbridge.dev
```

### Guardian JWT Configuration

For internal token generation (if using Guardian JWT as a backup):

```bash
# Guardian secret key for signing internal JWTs
# Generate with: openssl rand -base64 32
# Should be at least 32 characters
GUARDIAN_SECRET_KEY=your_secret_key_here_minimum_32_characters_long
```

### Database Configuration

```bash
# Path to SQLite database file
DATABASE_PATH=./priv/shared_dbs/users.db

# Connection pool size
POOL_SIZE=10
```

### Server Configuration

```bash
# Phoenix endpoint host
PHX_HOST=localhost

# Server port
PORT=4000

# Enable server mode
PHX_SERVER=true
```

### Development/Production

```bash
# Mix environment (dev, test, prod)
MIX_ENV=dev
```

## Setting Up for Development

### Option 1: Create a `.env` file (manual setup)

1. Create `.env` in the backend root:
```bash
cd globalbridge_backend
touch .env
```

2. Add the variables:
```bash
AUTH0_DOMAIN=dev-1672riu03fjuf7so.us.auth0.com
AUTH0_AUDIENCE=https://api.globalbridge.dev
GUARDIAN_SECRET_KEY=$(openssl rand -base64 32)
DATABASE_PATH=./priv/shared_dbs/users.db
POOL_SIZE=10
PHX_HOST=localhost
PORT=4000
PHX_SERVER=true
MIX_ENV=dev
```

3. Load the `.env` file when starting the server:
```bash
set -a && source .env && set +a && mix phx.server
```

### Option 2: Export in shell profile

Add to your `~/.zshrc` or `~/.bashrc`:
```bash
export AUTH0_DOMAIN="dev-1672riu03fjuf7so.us.auth0.com"
export AUTH0_AUDIENCE="https://api.globalbridge.dev"
export GUARDIAN_SECRET_KEY="$(openssl rand -base64 32)"
```

Then reload: `source ~/.zshrc`

### Option 3: Use Direnv (recommended)

1. Create `.envrc` in the backend root:
```bash
cd globalbridge_backend
echo 'export AUTH0_DOMAIN="dev-1672riu03fjuf7so.us.auth0.com"' > .envrc
echo 'export AUTH0_AUDIENCE="https://api.globalbridge.dev"' >> .envrc
echo 'export GUARDIAN_SECRET_KEY="'$(openssl rand -base64 32)'"' >> .envrc
direnv allow
```

## Getting Auth0 Configuration Values

### 1. Find Your Auth0 Domain

- Go to: [Auth0 Dashboard](https://manage.auth0.com)
- Click your tenant (top-right)
- You'll see your domain like: `dev-abc123.us.auth0.com`

### 2. Find Your Client ID and Tenant

- Go to: [Auth0 Dashboard → Applications](https://manage.auth0.com/#/applications)
- Click your **GlobalBridge** application
- Copy the **Domain** and **Client ID**

### 3. Find Your Audience (API Identifier)

- Go to: [Auth0 Dashboard → APIs](https://manage.auth0.com/#/apis)
- Look for your API (or create one if it doesn't exist)
- The **Identifier** is your audience
- For this project, it should be: `https://api.globalbridge.dev`

## Verification

To verify your environment variables are set correctly, start the backend and check the logs:

```bash
mix phx.server
```

You should see:
```
🔐 [AUTH0] Verifying token for domain: dev-1672riu03fjuf7so.us.auth0.com
✅ [AUTH0] Audience verified: https://api.globalbridge.dev
```

## Production Setup

For production:

1. Set variables via your hosting platform's environment variable UI
2. Never commit `.env` files to version control
3. Use strong, random `GUARDIAN_SECRET_KEY`
4. Ensure `AUTH0_DOMAIN` and `AUTH0_AUDIENCE` match your production Auth0 app

### Example: Heroku

```bash
heroku config:set AUTH0_DOMAIN="your-production-domain.us.auth0.com"
heroku config:set AUTH0_AUDIENCE="https://api.yourproduction.com"
heroku config:set GUARDIAN_SECRET_KEY="$(openssl rand -base64 32)"
```

## Troubleshooting

### Error: "Audience mismatch"

- Check that `AUTH0_AUDIENCE` exactly matches your Auth0 API identifier
- Don't add quotes or extra characters
- Example: ✅ `https://api.globalbridge.dev` ❌ `"https://api.globalbridge.dev"`

### Error: "Invalid issuer"

- Verify `AUTH0_DOMAIN` is correct
- Don't include `https://` or trailing slash
- Example: ✅ `dev-abc123.us.auth0.com` ❌ `https://dev-abc123.us.auth0.com/`

### Token verification failing

1. Check logs for which claim is failing (sub, aud, iss, exp)
2. Decode the token at [jwt.io](https://jwt.io) to see actual values
3. Compare with your environment variables

## Next Steps

Once environment variables are set:

1. ✅ Start the Phoenix server: `mix phx.server`
2. ✅ Test with iOS app: Send Auth0 token from iOS
3. ✅ Monitor logs for successful verification
4. ✅ Join WebSocket channels as authenticated user

---

**Last Updated:** October 21, 2025
