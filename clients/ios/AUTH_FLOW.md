# Authentication Flow

## Proper Startup Sequence

The app now follows a logical authentication-first flow:

```
1. App Launches
   └─> .onAppear

2. Check Authentication Status
   └─> .checkAuthentication
       └─> Checks if user has valid Auth0 token

3a. Already Authenticated Path
    └─> .authenticationChecked(isAuthenticated: true)
        └─> .loadUserAndThreads
            ├─> Connect to Phoenix with token
            ├─> Fetch user identity from backend
            └─> Fetch threads list

3b. Not Authenticated Path
    └─> .authenticationChecked(isAuthenticated: false)
        └─> Trigger Auth0 login (shows web UI)
            └─> User logs in
                └─> .userAuthenticated
                    └─> .loadUserAndThreads
                        ├─> Connect to Phoenix with token
                        ├─> Fetch user identity from backend
                        └─> Fetch threads list

4. Data Loaded
   └─> .threadsLoaded(success: (user, threads))
       ├─> Set user in AppState
       ├─> Set threads in AppState
       └─> Auto-select first thread
```

## Key Principles

### ✅ DO: Authentication First
- Always check authentication before fetching data
- Show login UI if user is not authenticated
- Wait for login completion before proceeding
- Only connect to backend after authentication confirmed

### ❌ DON'T: Assume Authentication
- Never try to fetch data without checking auth first
- Don't call `ensureConnection()` expecting it to handle login
- Don't continue execution while login modal is showing
- Don't mix authentication logic with data loading

## Environment Configuration

### Backend Selection

The app checks the `BACKEND_ENV` environment variable:

| Value | Backend | WebSocket | REST API |
|-------|---------|-----------|----------|
| `local`, `dev`, `development` | Local | ws://localhost:4000 | http://localhost:4000 |
| `production`, `prod` | Fly.io | wss://globalbridge-backend.fly.dev | https://globalbridge-backend.fly.dev |
| (not set) | Based on DEBUG flag | DEBUG: local, RELEASE: production | Same as WebSocket |

### Setting in Xcode

1. Product menu → Scheme → Edit Scheme...
2. Run → Arguments tab
3. Environment Variables section
4. Add: `BACKEND_ENV` = `local` (for localhost)

## Code Organization

### AppAction.swift
Defines the action sequence:
- `.onAppear` - App started
- `.checkAuthentication` - Check auth status
- `.authenticationChecked(Bool)` - Auth check result
- `.userAuthenticated` - Login completed
- `.loadUserAndThreads` - Fetch data (only after auth)
- `.threadsLoaded(Result)` - Data loaded

### AppReducer.swift
Implements the state machine that enforces the authentication-first flow.

### AppEnvironment.swift
- `RealtimeClient.ensureConnection` - Assumes already authenticated, just connects to Phoenix
- `DatabaseClient.loadThreads` - Returns both user and threads from backend bootstrap

### AuthManager.swift
- `isAuthenticated` - Check if user has valid token
- `login()` - Show Auth0 web login UI
- `getAccessToken()` - Get current token (nil if not authenticated)

## Why This Matters

**Before:** The app would try to connect to Phoenix and fetch threads immediately, triggering login mid-flight, causing race conditions and confusing error states.

**After:** The app checks authentication first, shows login if needed, waits for completion, then proceeds with data loading in a clean, sequential flow.

This eliminates:
- Race conditions between login and data fetching
- Confusing error messages
- Failed API calls during authentication
- Unnecessary retry logic

