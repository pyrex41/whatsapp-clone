# Cross-Client Authentication & Thread Sync Issues - Complete Analysis

## Executive Summary

All three clients (iOS, Expo, Elm) are experiencing authentication or thread fetching issues, but for **completely different reasons**:

| Client | Root Cause | Severity | Time to Fix |
|--------|-----------|----------|-------------|
| **Expo** | API field mismatch: sends `email` instead of `identifier` | 🔴 CRITICAL | 5 minutes |
| **Elm** | Tokens not stored in Model after login | 🔴 CRITICAL | 30 minutes |
| **iOS** | No authentication system implemented at all | 🔴 CRITICAL | 4-8 hours |
| **Backend** | Missing unread_count and last_message | 🟡 MEDIUM | 2 hours |

---

## Backend API Standard (Expected Behavior)

### Authentication Endpoints

#### POST `/api/auth/login`
**Expected Request**:
```json
{
  "identifier": "username_or_phone",  // NOT "email"
  "password": "password123"
}
```

**Expected Response**:
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "username": "devuser",
      "phone_number": "+1234567890"
    },
    "tokens": {
      "access_token": "eyJhbGc...",
      "refresh_token": "eyJhbGc..."
    }
  }
}
```

#### POST `/api/auth/refresh`
**Expected Request**:
```json
{
  "refresh_token": "eyJhbGc..."
}
```

#### POST `/api/auth/logout`
**Expected Headers**:
```
Authorization: Bearer {access_token}
```

### Data Endpoints (All Require JWT)

#### GET `/api/bootstrap/`
**Expected Headers**:
```
Authorization: Bearer {access_token}
```

**Expected Response**:
```json
{
  "data": {
    "user": { ... },
    "threads": [
      {
        "id": "uuid",
        "name": "Thread Name",
        "unread_count": 0,        // TODO: Always 0 (not implemented)
        "last_message": null,      // TODO: Always null (not implemented)
        "created_at": "2024-01-01T12:00:00Z",
        "updated_at": "2024-01-01T12:00:00Z"
      }
    ],
    "csrf_token": "..."
  }
}
```

### Phoenix WebSocket

#### Connection Parameters
**Expected**:
```javascript
socket.connect({ token: "eyJhbGc..." })  // JWT access token
```

**Dev Mode Fallback** (development only):
```javascript
socket.connect({ user_id: "optional_uuid" })
```

#### Thread Channel Join
**Topic Format**: `"thread:{thread_id}"`

**Authorization**: Automatic via user_id from socket connection

---

## Client-by-Client Analysis

### 🔴 Expo Client (React Native)

#### Issues
1. **LOGIN API FIELD MISMATCH** (auth-service.ts:44)
   - Sends: `{ email, password }`
   - Should send: `{ identifier, password }`
   - Git commit `da2efea` claims to fix this but code wasn't actually changed

#### What Works
- ✅ Token storage (SecureStore)
- ✅ Session state management (Zustand)
- ✅ API client with auto-logout on 401
- ✅ Phoenix channel connection
- ✅ Thread hooks with React Query
- ✅ CDC sync mechanism
- ✅ Realtime message handling

#### Fix Required
**File**: `clients/globalbridge-expo/src/services/auth-service.ts`
**Line**: 44
**Change**:
```typescript
// FROM:
body: JSON.stringify({ email, password })

// TO:
body: JSON.stringify({ identifier: email, password })
```

#### Environment Setup
**File**: `.env.local` (copy from `.env.example`)
```bash
# iOS Simulator
EXPO_PUBLIC_API_URL=http://127.0.0.1:4000/api

# Android Emulator
EXPO_PUBLIC_API_URL=http://10.0.2.2:4000/api

# Physical Device
EXPO_PUBLIC_API_URL=http://<YOUR_LAN_IP>:4000/api
```

---

### 🔴 Elm Web Client

#### Issues
1. **TOKENS NOT STORED IN MODEL** (Main.elm:463)
   - Login API works and returns tokens
   - Tokens stored in localStorage
   - BUT Model never captures them
   - `getAuthToken()` always returns empty string
   - All authenticated requests fail with 401

#### What Works
- ✅ Login form and validation
- ✅ API request formatting
- ✅ CORS configuration
- ✅ localStorage token storage (via Ports)
- ✅ Backend returns correct response

#### Fix Required
**File**: `clients/elm-client/src/Main.elm`

**1. Update Model Type** (add token fields):
```elm
type alias Model =
    { flags : Flags
    , apiConfig : ApiConfig
    , authState : AuthState
    , accessToken : String        -- ADD THIS
    , refreshToken : String        -- ADD THIS
    , currentPage : Page
    , threads : Threads.Model
    , messages : Messages.Model
    , bridges : Bridges.Model
    }
```

**2. Store Tokens on Login** (line 118):
```elm
Login.LoginResponse (Ok response) ->
    ( { model
        | authState = Authenticated response.user
        , accessToken = response.accessToken      -- STORE TOKEN
        , refreshToken = response.refreshToken    -- STORE TOKEN
        , currentPage = ThreadListPage (ThreadList.init model.threads)
      }
    , Cmd.batch [ ... ]
    )
```

**3. Fix getAuthToken** (line 463):
```elm
getAuthToken : Model -> String
getAuthToken model =
    case model.authState of
        Authenticated _ -> model.accessToken
        _ -> ""
```

**4. Restore Tokens from Session** (line 160):
```elm
SessionRestored (Just sessionData) ->
    ( { model
        | authState = Authenticated user
        , accessToken = sessionData.accessToken    -- RESTORE TOKEN
        , refreshToken = sessionData.refreshToken  -- RESTORE TOKEN
      }
    , cmd
    )
```

---

### 🔴 iOS Client (Swift)

#### Issues
1. **NO AUTHENTICATION SYSTEM** (AuthManager.swift is a stub)
   - No login API calls
   - No JWT token storage
   - No Keychain integration

2. **THREADS NEVER FETCHED FROM BACKEND**
   - `DatabaseManager.fetchThreads()` only queries local SQLite
   - Never calls `/api/bootstrap` endpoint
   - Local database always empty on fresh install

3. **PHOENIX CHANNEL AUTH ISSUES**
   - No JWT token passed to socket
   - Thread IDs don't match backend UUIDs
   - Joining channels with non-existent thread IDs fails

4. **NO HTTP CLIENT**
   - No URLSession wrapper
   - Can't make REST API calls
   - Only WebSocket works (but without auth)

#### What Works
- ✅ Local SQLite database schema
- ✅ Phoenix WebSocket connection (but unauthenticated)
- ✅ TCA state management
- ✅ CDC log tracking
- ✅ Thread/Message models

#### Fix Required
This requires implementing the entire authentication and API layer:

**Files to Create/Modify**:
1. `Core/Auth/AuthManager.swift` - Real implementation
2. `Core/Networking/HTTP/HTTPClient.swift` - NEW FILE NEEDED
3. `Core/Networking/HTTP/APIEndpoint.swift` - NEW FILE NEEDED
4. `Core/Networking/Phoenix/PhoenixConfig.swift` - Add token field
5. `Core/Storage/DatabaseManager.swift` - Add bootstrap fetch
6. `Core/State/AppEnvironment.swift` - Wire up HTTP client

**Implementation Tasks**:
1. Create URLSession-based HTTP client
2. Implement login flow with JWT storage in Keychain
3. Call `/api/bootstrap` to fetch threads
4. Pass JWT to Phoenix socket connection
5. Synchronize thread IDs between local and backend

**Estimated Time**: 4-8 hours of development

---

## Backend Improvements Needed

### 🟡 Bootstrap Endpoint Missing Data

**File**: `globalbridge_backend/lib/globalbridge_backend_web/controllers/bootstrap_controller.ex`

**Issues**:
1. `unread_count` always returns 0 (line 20)
2. `last_message` always returns null (line 23)
3. Bridge data not implemented

**Impact**: Clients can't show:
- Unread badge counts
- Message previews in thread list
- Bridge functionality

**Fix Required**:
```elixir
# Calculate actual unread count from read_receipts table
unread_count = Threads.get_unread_count(thread.id, user.id)

# Fetch last message from thread's shard database
last_message = Messages.get_last_message(thread.id)
```

---

## Cross-Client Consistency Check

### ✅ Consistent Across All Clients

| Feature | iOS | Expo | Elm |
|---------|-----|------|-----|
| Login endpoint | ❌ | ✅ | ✅ |
| Token storage | ❌ | ✅ | ✅ |
| Phoenix channels | ⚠️ | ✅ | N/A |
| Thread fetching | ❌ | ✅ | ⚠️ |
| Message rendering | N/A | ✅ | N/A |

### ❌ Inconsistencies Identified

1. **iOS**: Uses local-only thread IDs (no backend sync)
2. **Expo**: Sends wrong field name in login request
3. **Elm**: Doesn't store tokens after successful login
4. **Backend**: Missing unread counts and message previews

---

## Recommended Fix Order

### Phase 1: Quick Wins (1 hour)
1. **Fix Expo login field** (5 minutes)
2. **Fix Elm token storage** (30 minutes)
3. **Test Expo and Elm end-to-end** (25 minutes)

### Phase 2: Backend Improvements (2 hours)
4. **Implement unread_count calculation**
5. **Implement last_message fetching**
6. **Test all clients receive correct data**

### Phase 3: iOS Complete Rewrite (4-8 hours)
7. **Create HTTP client layer**
8. **Implement real AuthManager**
9. **Add bootstrap API call**
10. **Wire up Phoenix auth**
11. **Test iOS end-to-end**

---

## Testing Checklist

After fixes are applied, verify:

### Expo Client
- [ ] Login with `devuser` / `dev123456` succeeds
- [ ] JWT token stored in SecureStore
- [ ] `/api/bootstrap` returns threads
- [ ] Phoenix channel connects with JWT
- [ ] Messages display in real-time

### Elm Client
- [ ] Login with `devuser` / `dev123456` succeeds
- [ ] Tokens stored in localStorage
- [ ] Tokens stored in Elm Model
- [ ] `/api/bootstrap` called with Bearer token
- [ ] Thread list displays
- [ ] Page refresh maintains session

### iOS Client
- [ ] Login flow exists
- [ ] JWT stored in Keychain
- [ ] Bootstrap endpoint called
- [ ] Threads fetched from backend
- [ ] Phoenix connects with JWT
- [ ] Can join thread channels

### All Clients
- [ ] Thread list shows unread counts
- [ ] Thread list shows last message preview
- [ ] Real-time messages work
- [ ] Logout clears session
- [ ] Token refresh works

---

## Files Modified/Created

### Expo
- `clients/globalbridge-expo/src/services/auth-service.ts` (1 line)

### Elm
- `clients/elm-client/src/Main.elm` (Model type + 4 handlers)

### iOS (Extensive)
- `clients/ios/GlobalBridge/Core/Auth/AuthManager.swift` (rewrite)
- `clients/ios/GlobalBridge/Core/Networking/HTTP/HTTPClient.swift` (new)
- `clients/ios/GlobalBridge/Core/Networking/HTTP/APIEndpoint.swift` (new)
- `clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixConfig.swift` (add token)
- `clients/ios/GlobalBridge/Core/Storage/DatabaseManager.swift` (add bootstrap)

### Backend
- `globalbridge_backend/lib/globalbridge_backend_web/controllers/bootstrap_controller.ex` (add unread/last_message)

---

**Investigation Date**: 2025-10-21
**Report Generated by**: Claude Code Multi-Agent Investigation System
