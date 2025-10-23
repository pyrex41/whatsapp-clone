# iOS GlobalBridge Running Guide

## Prerequisites

1. **Backend Server**: The Phoenix backend must be running on `http://localhost:4000`
2. **Xcode**: Version 15.0 or later
3. **iOS Simulator**: iPhone 15 Pro or iPhone Air

## Step 1: Configure URL Scheme in Xcode

**IMPORTANT**: This must be done before running the app!

1. Open `clients/ios/GlobalBridge/GlobalBridge.xcodeproj` in Xcode
2. Select the **GlobalBridge** target
3. Go to the **Info** tab
4. Scroll down to **URL Types** section
5. Click the **+** button to add a new URL Type
6. Configure as follows:
   - **Identifier**: `auth0`
   - **URL Schemes**: `name.reubenbrooks.globalbridge`
   - **Role**: Leave as "None" or "Editor"

## Step 2: Start the Backend Server

In Terminal window 1:
```bash
cd /Users/reuben/gauntlet/whatsapp-clone
./start_backend.sh
```

Wait until you see:
```
[info] Running GlobalBridgeBackendWeb.Endpoint with cowboy 2.x.x at 0.0.0.0:4000 (http)
[info] Access GlobalBridgeBackendWeb.Endpoint at http://localhost:4000
```

## Step 3: Configure Auth0 (One-time setup)

1. Go to [Auth0 Dashboard](https://manage.auth0.com)
2. Navigate to **Applications** → **GlobalBridge iOS**
3. In **Settings** tab, configure:

   **Allowed Callback URLs**:
   ```
   name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
   ```

   **Allowed Logout URLs**:
   ```
   name.reubenbrooks.globalbridge://dev-1672riu03fjuf7so.us.auth0.com/ios/name.reubenbrooks.globalbridge/callback
   ```

4. Save changes

## Step 4: Build and Run the iOS App

### Option A: Using Xcode (Recommended)

1. Open `clients/ios/GlobalBridge/GlobalBridge.xcodeproj` in Xcode
2. Select the **GlobalBridge** scheme
3. Select your target simulator (e.g., iPhone 15 Pro)
4. Press **Cmd+R** to build and run

### Run on Multiple Simulators (Cmd+R)

To install and launch the app on multiple simulators at once (e.g., iPhone 17, iPhone 17 Pro, iPhone 17 Pro Max) when you run in Xcode:

1) Ensure the helper script exists:
- Path: `clients/ios/GlobalBridge/scripts/deploy-to-simulators.sh`

2) Wire it into your scheme as a Run Post-action:
- Xcode → Product → Scheme → Edit Scheme… → Run → Post-actions → + New Run Script Action
- Set "Provide build settings from" to the **GlobalBridge** target
- Script:
  ```bash
  bash "${SRCROOT}/scripts/deploy-to-simulators.sh"
  ```
- Optional: Add an environment variable to control target devices (comma-separated names):
  - Name: `SIM_DEVICE_NAMES`
  - Value: `iPhone 17,iPhone 17 Pro,iPhone 17 Pro Max`

3) Press Cmd+R as usual
- Xcode will build and run on the selected simulator
- The post-action script will also install/launch the app on the additional simulators in parallel

Notes:
- The script auto-detects the built `.app` and bundle id from Xcode environment
- You can change `SIM_DEVICE_NAMES` to any available simulator names
- If a target simulator is not booted, the script boots it automatically

### Option B: Using Command Line

```bash
cd clients/ios/GlobalBridge
xcodebuild -scheme GlobalBridge \
  -destination "platform=iOS Simulator,name=iPhone Air" \
  build && \
xcrun simctl boot "iPhone Air" 2>/dev/null || true && \
xcrun simctl install "iPhone Air" \
  ~/Library/Developer/Xcode/DerivedData/GlobalBridge-*/Build/Products/Debug-iphonesimulator/GlobalBridge.app && \
xcrun simctl launch "iPhone Air" name.reubenbrooks.globalbridge
```

## Step 5: First Launch

On first launch, you should see:

1. **Auth0 Login**: The app will prompt for Auth0 authentication
   - Use your test credentials or create a new account
   - Grant permission when prompted

2. **Notifications Permission**: 
   - Allow notifications when prompted (optional but recommended)

3. **Main Screen**: 
   - You should see the threads list (initially empty)
   - Use the "+" button to create a new thread

## Troubleshooting

### Auth0 Issues

**Error**: "The UIWindowScene for the returned window was not in the foreground active state"
- **Solution**: Make sure the app is in the foreground when initiating login. Try tapping the login button again.

**Error**: "Application not associated with domain"
- **Solution**: Ensure URL scheme is configured in Xcode (Step 1)

### Backend Connection Issues

**Error**: "Connection refused" or "Failed to fetch remote threads"
- **Solution**: 
  1. Ensure backend is running (Step 2)
  2. Check backend logs for errors
  3. Verify backend is accessible at `http://localhost:4000`

### Database Issues

**Error**: Database-related errors
- **Solution**: 
  ```bash
  cd globalbridge_backend
  mix ecto.reset  # Reset database
  mix ecto.migrate  # Run migrations
  ```

### Build Issues

**Error**: Module not found or compilation errors
- **Solution**:
  1. Clean build folder: **Cmd+Shift+K** in Xcode
  2. Delete derived data:
     ```bash
     rm -rf ~/Library/Developer/Xcode/DerivedData/GlobalBridge-*
     ```
  3. Rebuild the project

## Development Tips

1. **Hot Reload**: SwiftUI views support hot reload - make changes and see them instantly
2. **Debug Console**: Use Xcode's debug console to see print statements
3. **Network Inspector**: Use Xcode's network inspector to debug API calls
4. **Simulator Reset**: Device → Erase All Content and Settings (for clean slate)

## Current Configuration

- **Backend URL**: `http://localhost:4000`
- **WebSocket URL**: `ws://localhost:4000/socket`
- **Auth0 Domain**: `dev-1672riu03fjuf7so.us.auth0.com`
- **Client ID**: `id5kQQRxJtDhIQ10C9r6TGKmnu0FwIcj`
- **Bundle ID**: `name.reubenbrooks.globalbridge`

## Next Steps

After successful setup:
1. Create a test thread
2. Send some messages
3. Test offline mode by stopping the backend
4. Verify sync when backend comes back online
### Simulator Push Test (APNs)
1. Ensure app is running in SYSTEM or AUTO mode (Debug menu or set scheme env var `IOS_NOTIFICATIONS_MODE=SYSTEM`).
2. Update `clients/ios/GlobalBridge/test_notification.apns` with a valid `conversation_id` (thread UUID) and `message_id`.
3. Push the payload:

```bash
xcrun simctl push booted name.reubenbrooks.globalbridge clients/ios/GlobalBridge/test_notification.apns
```

- Foreground: OS banner shows with title/body.
- Tap: Opens the referenced thread.
- Swipe down: Quick actions Reply and Mark Read.
- Reply: Sends quick reply back to the thread.
- Mark Read: Sends read receipt for `message_id`.
