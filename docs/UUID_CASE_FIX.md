# UUID Case Normalization Fix

## Summary

Fixed the "Thread not found" error when joining thread channels after successful thread creation. The issue was a **UUID case mismatch** between iOS and backend.

## The Problem

After successfully creating a thread, iOS couldn't join the thread channel:

```
✅ Backend created thread: ca89ba11-10e7-40f1-bcfe-3e47416532bc (lowercase)
❌ iOS tried to join: thread:CA89BA11-10E7-40F1-BCFE-3E47416532BC (uppercase)
❌ Backend lookup failed: Thread not found (case-sensitive query)
```

### Error Logs
```
[info] 🔌 Channel join attempt: thread=CA89BA11-10E7-40F1-BCFE-3E47416532BC
[debug] SELECT * FROM "threads" WHERE (t0."id" = ?) ["CA89BA11-10E7-40F1-BCFE-3E47416532BC"]
[warning] ❌ Channel join denied (thread not found)
```

### Root Cause

1. **Backend**: Creates threads with lowercase UUIDs (PostgreSQL/Ecto default)
2. **iOS**: Swift's `UUID().uuidString` returns uppercase UUIDs
3. **Database Query**: `Repo.get(Thread, thread_id)` performs case-sensitive lookup
4. **Result**: Uppercase UUID doesn't match lowercase UUID in database

## The Solution

Normalize thread_id to lowercase when joining channel:

```elixir
# thread_channel.ex
def join("thread:" <> thread_id, _payload, socket) do
  # Normalize thread_id to lowercase for case-insensitive UUID lookup
  thread_id = String.downcase(thread_id)
  user_id = socket.assigns.user_id

  Logger.info("🔌 Channel join attempt: thread=#{thread_id}, user=#{user_id}")

  case authorize_user(thread_id, user_id) do
    # ... rest of function
  end
end
```

### Why This Works

- UUIDs are case-insensitive by RFC 4122 specification
- Normalizing to lowercase at the entry point ensures consistency
- All downstream functions (authorize_user, is_thread_participant?, etc.) receive lowercase IDs
- Database queries now succeed regardless of how the client formats the UUID

## Verification

### Before Fix
```
[info] 🔌 Channel join attempt: thread=CA89BA11-10E7-40F1-BCFE-3E47416532BC
[debug] SELECT ... WHERE (t0."id" = ?) ["CA89BA11-10E7-40F1-BCFE-3E47416532BC"]
[warning] ❌ Channel join denied (thread not found)
```

### After Fix
```
[info] 🔌 Channel join attempt: thread=ca89ba11-10e7-40f1-bcfe-3e47416532bc
[debug] SELECT ... WHERE (t0."id" = ?) ["ca89ba11-10e7-40f1-bcfe-3e47416532bc"]
[info] ✅ Channel join authorized: thread=ca89ba11-10e7-40f1-bcfe-3e47416532bc
[info] JOINED thread:CA89BA11-10E7-40F1-BCFE-3E47416532BC in 19ms
```

## Testing

### Test Scenario
1. Create a thread on iOS
2. iOS receives thread with lowercase UUID from backend
3. iOS uppercases the UUID (standard Swift behavior)
4. iOS tries to join thread channel with uppercase UUID
5. Backend normalizes to lowercase
6. Thread found and joined successfully ✅

### Expected Results
- ✅ Thread channel joins successfully
- ✅ No "Thread not found" errors
- ✅ Messages can be sent/received
- ✅ Real-time features work (typing indicators, presence, etc.)

## Related Changes

This fix builds on the previous thread creation fix:
- **Thread Creation Fix**: Ensured iOS uses backend-provided user IDs (String) instead of random UUIDs
- **UUID Case Fix**: Ensures thread lookups work regardless of UUID case formatting

## Files Modified

- `globalbridge_backend/lib/globalbridge_backend_web/channels/thread_channel.ex`
  - Added `thread_id = String.downcase(thread_id)` in join/3

## Alternative Solutions Considered

1. **Store UUIDs as uppercase in backend** ❌
   - Would require database migration
   - Break existing data
   - Non-standard (Ecto generates lowercase)

2. **Case-insensitive database queries** ❌
   - Performance overhead
   - Database-specific implementation
   - Affects all queries, not just this one

3. **Normalize on iOS** ❌
   - Requires iOS app update
   - Other clients might have same issue
   - Better to handle on backend

4. **Normalize at backend entry point** ✅ **CHOSEN**
   - No database changes
   - No performance impact
   - Works for all clients
   - Single point of normalization

## Best Practices

When working with UUIDs in distributed systems:

1. **Always normalize UUIDs** at system boundaries (APIs, channels, etc.)
2. **Choose a canonical format** (lowercase is Ecto/PostgreSQL default)
3. **Document UUID format requirements** in API specifications
4. **Use case-insensitive comparisons** when possible
5. **Test with different UUID formats** from different platforms

## Impact

- **No breaking changes**: Existing functionality continues to work
- **Backwards compatible**: Handles both uppercase and lowercase UUIDs
- **Performance**: O(1) string operation, negligible overhead
- **Scope**: Only affects thread channel joins

## Next Steps

1. ✅ Thread creation works with correct user IDs
2. ✅ Thread channel joining works with any UUID case
3. 📋 Test message sending in thread
4. 📋 Test real-time features (typing, presence)
5. 📋 Test with multiple participants

