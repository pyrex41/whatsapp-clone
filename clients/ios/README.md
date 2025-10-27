# GlobalBridge iOS Client

WhatsApp-like messaging app with real-time translation powered by AI.

## Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ deployment target
- Swift 5.9+
- Auth0 account for authentication

## Setup

### 1. Install Dependencies

Dependencies are managed via Swift Package Manager and should be automatically resolved by Xcode.

### 2. Configure Auth0

The app uses Auth0 for authentication. Configuration is managed in:
- `GlobalBridge/Core/Config/Auth0Config.swift`
- Environment variables in the scheme settings

### 3. Running in Simulator

**IMPORTANT:** To run the app in the iOS Simulator, you must configure the scheme environment:

1. In Xcode, go to **Product → Scheme → Edit Scheme** (or press `Cmd + <`)
2. Select **Run** in the left sidebar
3. Go to the **Arguments** tab
4. Under **Environment Variables**, add or set:
   ```
   BACKEND_ENV = production
   ```
5. Click **Close**

Without this setting, the app may fail to connect to the backend or crash on launch.

### 4. Build and Run

1. Select a simulator (e.g., iPhone 15 Pro)
2. Press **Cmd + R** to build and run
3. Sign in with your Auth0 account

## Troubleshooting

### Simulator Crashes or Won't Launch

If the simulator crashes with "No such process" error:

1. **Clean Build Folder**: Product → Clean Build Folder (`Cmd + Shift + K`)
2. **Delete DerivedData**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/GlobalBridge-*
   ```
3. **Uninstall app from simulator**:
   ```bash
   xcrun simctl uninstall booted name.reubenbrooks.globalbridge
   ```
4. **Rebuild**: Product → Build (`Cmd + B`)

### WebSocket Connection Issues

If you see "Connection Error" or "Failed to join channel":

1. Ensure `BACKEND_ENV = production` is set in scheme environment variables
2. Check that the backend is running at `https://globalbridge-backend.fly.dev`
3. Verify your Auth0 token is valid (try logging out and back in)

### Authentication Issues

If authentication fails:

1. Check Auth0 configuration in `Auth0Config.swift`
2. Verify the Auth0 client ID and domain are correct
3. Check Xcode console for detailed authentication logs (search for `[AUTH]`)

## Architecture

- **SwiftUI** for UI
- **TCA (The Composable Architecture)** for state management
- **Phoenix Channels** for real-time messaging via WebSocket
- **SQLite** for local message storage
- **Auth0** for authentication

## Key Features

- Real-time messaging with WebSocket
- Automatic message translation
- Per-thread database sharding for performance
- In-app notification banners
- Message reactions and replies
- AI-powered conversation summaries
- Smart translation mode detection

## Project Structure

```
GlobalBridge/
├── Core/               # Core functionality
│   ├── AI/            # AI services (translation, summaries)
│   ├── Config/        # Configuration files
│   ├── Models/        # Data models
│   ├── Networking/    # REST and WebSocket clients
│   ├── Services/      # Business logic services
│   ├── State/         # TCA state management
│   └── Utilities/     # Helper utilities
├── Features/          # Feature modules
│   ├── AppRoot/       # Root app view
│   ├── Auth/          # Authentication screens
│   ├── Chat/          # Chat/messaging UI
│   └── Threads/       # Thread list UI
└── UI/                # Shared UI components
    └── Views/         # Reusable views
```

## Environment Variables

Configure these in **Product → Scheme → Edit Scheme → Arguments → Environment Variables**:

| Variable | Values | Description |
|----------|--------|-------------|
| `BACKEND_ENV` | `production`, `local` | Backend environment (use `production` for simulator) |
| `IOS_NOTIFICATIONS_MODE` | `BANNER`, `SYSTEM`, `AUTO` | Notification mode (default: `BANNER` in debug) |

## Contributing

When making changes:

1. Always test in simulator with `BACKEND_ENV = production`
2. Run tests: Product → Test (`Cmd + U`)
3. Ensure clean builds work: Clean Build Folder before committing

## License

[Add your license here]
