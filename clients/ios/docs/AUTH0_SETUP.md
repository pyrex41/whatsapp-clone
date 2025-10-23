# Auth0 Setup for iOS Client

## Configuration

The iOS app needs three Auth0 configuration values:

1. **Domain** - Your Auth0 domain (e.g., `dev-abc123.us.auth0.com`)
2. **Client ID** - Your Auth0 application client ID
3. **Audience** - Your API audience/identifier (e.g., `globalbridge-api`)

## Setup Options

### Option 1: Xcode Scheme Environment Variables (Recommended for Development)

1. In Xcode, select the `GlobalBridge` scheme
2. Go to **Product > Scheme > Edit Scheme...**
3. Select **Run** on the left sidebar
4. Select the **Arguments** tab
5. Under **Environment Variables**, add:
   - `AUTH0_DOMAIN` = `your-domain.us.auth0.com`
   - `AUTH0_CLIENT_ID` = `your_client_id_here`
   - `AUTH0_AUDIENCE` = `globalbridge-api` (or your API identifier)

### Option 2: Info.plist (Alternative)

1. Open `GlobalBridge/Info.plist`
2. Add these keys:
   ```xml
   <key>Auth0Domain</key>
   <string>your-domain.us.auth0.com</string>
   <key>Auth0ClientId</key>
   <string>your_client_id_here</string>
   <key>Auth0Audience</key>
   <string>globalbridge-api</string>
   ```

## Auth0 Application Configuration

In your Auth0 Dashboard, configure your application:

### Allowed Callback URLs
```
com.globalbridge.app://YOUR_AUTH0_DOMAIN/ios/com.globalbridge.app/callback
```

### Allowed Logout URLs
```
com.globalbridge.app://YOUR_AUTH0_DOMAIN/ios/com.globalbridge.app
```

### Allowed Web Origins
```
com.globalbridge.app
```

## Backend Configuration

The backend also needs Auth0 configuration. Create a `.env` file in `globalbridge_backend/`:

```bash
AUTH0_DOMAIN=your-domain.us.auth0.com
AUTH0_AUDIENCE=globalbridge-api
```

The backend will automatically decode and verify Auth0 JWT tokens.

## Testing

Once configured:

1. Run the iOS app
2. The app will automatically trigger Auth0 login on first launch
3. After authentication, the app will:
   - Connect to Phoenix WebSocket with Auth0 token
   - Join user channel
   - Fetch threads from backend
   - Display threads in UI

## Troubleshooting

### "AUTH0_DOMAIN not configured" error
- Make sure you've set the environment variables in Xcode scheme
- Or added them to Info.plist

### Auth0 login webpage doesn't load
- Check that your Auth0 domain is correct
- Verify your Client ID matches the Auth0 application

### Backend rejects token
- Ensure backend has correct `AUTH0_DOMAIN` in .env
- Verify token audience matches between iOS and backend
- Check backend logs for specific auth errors


