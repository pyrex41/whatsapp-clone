# Auth0 Phone Number Bug Fix

## Problem

Auth0 users were unable to connect to the backend due to a phone number conflict:

```
❌ [AUTH0] User creation failed: [phone_number: {"has already been taken", 
   [constraint: :unique, constraint_name: "users_phone_number_index"]}]
```

### Root Cause

The `auth0_verifier.ex` was using a hardcoded placeholder phone number for all Auth0 users:

```elixir
attrs = %{
  auth0_id: auth0_id,
  email: email,
  username: username,
  display_name: name,
  phone_number: "+10000000000",  # ❌ HARDCODED - causes unique constraint violation
  password_hash: "auth0_managed"
}
```

When a second Auth0 user tried to log in, the backend attempted to create them with the same hardcoded phone number `+10000000000`, which violated the unique constraint.

## Solution

Removed the hardcoded phone number from Auth0 user creation. Auth0 users authenticate via email/password, not phone numbers:

```elixir
attrs = %{
  auth0_id: auth0_id,
  email: email,
  username: username,
  display_name: name,
  # phone_number removed - Auth0 users don't need it
  password_hash: "auth0_managed"
}
```

## Why This Works

1. **Phone number is optional**: The User schema only requires `username`, not `phone_number`
2. **Auth0 users use email**: They authenticate with email/password via Auth0
3. **Can be added later**: If a user wants to add a phone number later, they can do so via profile settings

## User Types

### Auth0 Users (Email/Password)
- ✅ Required: `username`, `email`, `auth0_id`
- ✅ Optional: `phone_number` (can be added later)
- ✅ Authentication: Via Auth0 email/password

### Local Users (Phone/Password)  
- ✅ Required: `username`, `phone_number`, `password_hash`
- ✅ Optional: `email` (can be added later)
- ✅ Authentication: Via local phone/password

## Testing

1. ✅ First Auth0 user can log in successfully
2. ✅ Second Auth0 user can log in successfully (no phone number conflict)
3. ✅ Multiple Auth0 users can coexist
4. ✅ Phone numbers can still be added to user profiles later if needed

## Files Changed

- `globalbridge_backend/lib/globalbridge_backend/auth/auth0_verifier.ex`
  - Removed hardcoded `phone_number: "+10000000000"`
  - Added comments explaining why phone numbers aren't needed for Auth0 users

## Backend Restart Required

After making this change, the backend must be restarted:

```bash
# Kill existing backend
lsof -ti:4000 | xargs kill -9

# Restart backend
cd /Users/reuben/gauntlet/whatsapp-clone
./start_backend.sh > backend.log 2>&1 &
```

## Result

Auth0 users can now successfully:
- ✅ Log in via Auth0 email/password
- ✅ Connect to Phoenix websocket
- ✅ Join their user channel
- ✅ Create and manage conversations
- ✅ Multiple users can use the app simultaneously

