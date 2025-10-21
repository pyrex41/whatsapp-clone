# GlobalBridge Expo Client

This Expo project is wired to the Phoenix backend that runs on port **4000**. All network calls point at
`EXPO_PUBLIC_API_URL`, which is read at runtime by `app.config.ts`. Follow the steps below to run the client
against your local backend.

## 1. Install dependencies

```bash
cd clients/globalbridge-expo
npm install --legacy-peer-deps
```

## 2. Start the Phoenix backend (port 4000)

From the repository root:

```bash
cd ../globalbridge_backend
mix phx.server
```

The API should now be reachable at `http://localhost:4000/api` and the websocket endpoint at
`ws://localhost:4000/socket`.

## 3. Choose the correct API URL for your simulator / device

| Environment           | Command                                                                 |
|-----------------------|-------------------------------------------------------------------------|
| iOS simulator (same Mac) | `npm run dev:ios`                                                         |
| Android emulator      | `npm run dev:android`                                                     |
| Physical device       | `EXPO_PUBLIC_API_URL=http://{YOUR_LAN_IP}:4000/api expo start --tunnel` |

Each script sets `EXPO_PUBLIC_API_URL` so both REST calls (`/api/v1/...`) and Phoenix Channels use the
correct host. For physical devices make sure `{YOUR_LAN_IP}` points to the machine running Phoenix.

You can also copy `.env.example` to `.env.local` and adjust the value; Expo will pick it up automatically.

## 4. Auth0 SSO Setup (optional / recommended)

Backend websockets now accept Auth0 JWTs. To sign in with Auth0 from the Expo app:

1. Set these environment variables (see `.env.example`):

   - `EXPO_PUBLIC_AUTH0_DOMAIN=your-tenant.us.auth0.com`
   - `EXPO_PUBLIC_AUTH0_CLIENT_ID=your-client-id`
   - `EXPO_PUBLIC_AUTH0_AUDIENCE=https://globalbridge-api`

2. In your Auth0 application, configure Allowed Callback URLs to include the scheme from `app.config.ts` (default `globalbridge://`) and your dev URLs as needed.

3. Launch the app and tap “Sign in with Auth0”. The app will obtain an access token and connect Phoenix Channels with it.

The app still supports legacy email/password login when Auth0 vars are not set.

## 5. Verify the connection

Once the Metro bundler launches and the app loads:

1. If using Auth0: tap “Sign in with Auth0”; otherwise email/password login posts to `/api/auth/login`.
2. After authentication the realtime service opens a websocket to `ws://<host>:4000/socket` and passes the token.
3. Threads/messages are fetched via REST; CDC background sync now prefers Phoenix Channel `cdc:pull` when connected, falling back to `/api/v1/sync/pull`.

If you see network errors, confirm:

- Phoenix is running and reachable from the simulator/device.
- `EXPO_PUBLIC_API_URL` matches the correct host/IP for your environment.
- Firewalls allow traffic on port 4000.

## Scripts reference

- `npm run lint` – ESLint v9 flat config (see `eslint.config.js`).
- `npm run typecheck` – TypeScript project check via `tsconfig.json`.
- `npm run test` – Vitest unit tests.
- `npm run dev:ios` / `npm run dev:android` – start Expo with API URL targeting Phoenix on port 4000.

Happy hacking!
