# New Conversation Flow Implementation

## Overview
Implemented separate, user-friendly flows for creating Direct Messages (DMs) and Group conversations.

## UX Flow

### Direct Messages
1. User clicks "New Conversation" button → sheet appears with two options
2. User selects "New Direct Message"
3. Search interface appears
4. User types to search for people by email/username/display name
5. User selects ONE person → DM is created/opened automatically
6. User is taken to the conversation

### Group Conversations
1. User clicks "New Conversation" button → sheet appears with two options
2. User selects "New Group"
3. User enters group name
4. User searches and selects MULTIPLE people (minimum 2)
5. User clicks "Create" button
6. Group is created and user is taken to the conversation
7. (Future: Add members to existing groups)

## Backend Changes

### 1. User Search API (`/globalbridge_backend/lib/globalbridge_backend/contexts/auth.ex`)
- Added `search_users/3` function
- Searches by email, username, or display name (case-insensitive)
- Excludes the searching user from results
- Returns up to 20 results by default

### 2. Direct Message Creation (`/globalbridge_backend/lib/globalbridge_backend_web/channels/user_channel.ex`)
- Added `handle_in("search_users")` - Search for users
- Added `handle_in("create_dm")` - Create/get DM with one user
- Reuses existing `get_thread_for_direct_message/2` which:
  - Finds existing DM if it exists
  - Creates new DM if it doesn't exist

### 3. Thread Creation Validation (`/globalbridge_backend/lib/globalbridge_backend/contexts/threads.ex`)
- Added `validate_participant_ids/1` - Validates all participant IDs exist before creating thread
- Prevents foreign key constraint violations
- Returns clear error messages for invalid participant IDs
- Updated `create_thread/1` to validate participants before creating

### 4. Group Thread Creation (`/globalbridge_backend/lib/globalbridge_backend_web/channels/user_channel.ex`)
- Updated `handle_in("create_thread")` to handle validation errors
- Supports creating group threads with multiple participants
- Broadcasts thread creation to all participants

## iOS Client Changes

### 1. New Views

#### `NewConversationView.swift`
- Main entry point sheet
- Two options: "New Direct Message" and "New Group"
- Clean, simple UI

#### `NewDirectMessageView.swift`
- User search interface
- Real-time search (triggers on 2+ characters)
- Shows results with user info and online status
- Tap user → creates DM and dismisses sheet
- Empty states for no search, no results, errors

#### `NewGroupView.swift`
- Group name input field
- User search with multi-select
- Selected users shown as chips at top
- Minimum 2 participants required
- "Create" button creates group and dismisses sheet

### 2. Updated Views

#### `ThreadListView.swift`
- Updated to show `NewConversationView` sheet
- Added empty state with call-to-action when no threads exist
- Updated compose button to trigger new conversation flow

### 3. State Management

#### `AppAction.swift`
- Added `phoenixChannel(PhoenixChannelAction)` wrapper
- Added `PhoenixChannelAction` enum with:
  - `searchUsers(query: String)`
  - `userSearchResults(Result<[UserSearchResult], Error>)`
  - `createDM(userId: String)`
  - `createGroup(title: String, participantIds: [String])`
  - `dmCreated(Result<Thread, Error>)`
  - `groupCreated(Result<Thread, Error>)`

#### `BootstrapModels.swift`
- Added `UserSearchResult` model
- Added `UserSearchResponse` wrapper

#### `PhoenixChannelManager.swift`
- Added `searchUsers(query: String)` method
- Added `createDirectMessage(withUserId:)` method
- Existing `createThread()` method handles group creation

## Phoenix Channel Events

### User Channel (`user:{user_id}`)

#### `search_users`
**Request:**
```json
{
  "query": "john"
}
```

**Response:**
```json
{
  "users": [
    {
      "id": "user-uuid",
      "username": "john_doe",
      "email": "john@example.com",
      "display_name": "John Doe",
      "avatar_url": null,
      "is_online": true
    }
  ]
}
```

#### `create_dm`
**Request:**
```json
{
  "user_id": "other-user-uuid"
}
```

**Response:** Thread object (same as bootstrap)

#### `create_thread` (Groups)
**Request:**
```json
{
  "thread_type": "group",
  "title": "My Group",
  "participant_ids": ["user-1-uuid", "user-2-uuid"]
}
```

**Response:** Thread object (same as bootstrap)

**Error Response:**
```json
{
  "reason": "Invalid participant IDs: abc-123, def-456"
}
```

## Error Handling

### Backend
1. **Invalid Participant IDs**: Returns clear error message listing which IDs are invalid
2. **DM Creation**: If user doesn't exist, returns error
3. **Search**: Returns empty array if no results

### iOS Client
1. **Search Errors**: Shows error message with retry option
2. **Empty Results**: Shows "No users found" state
3. **Network Errors**: Handled by existing error handling
4. **Loading States**: Shows progress indicators during operations

## Testing

### Backend Testing
```bash
# Start backend
cd globalbridge_backend
mix phx.server

# Test search users
# (Via iOS client or Phoenix.js client)
channel.push("search_users", { query: "test" })

# Test create DM
channel.push("create_dm", { user_id: "valid-user-id" })

# Test create group
channel.push("create_thread", {
  thread_type: "group",
  title: "Test Group",
  participant_ids: ["user-1", "user-2"]
})

# Test invalid participant
channel.push("create_thread", {
  thread_type: "group",
  title: "Test Group",
  participant_ids: ["invalid-id"]
})
# Should return error
```

### iOS Testing
1. Build and run the iOS app
2. Tap the compose button (square and pencil icon)
3. Select "New Direct Message"
4. Search for a user
5. Tap on a user → should create/open DM
6. Go back and try "New Group"
7. Enter group name, search and select multiple users
8. Tap "Create" → should create group

## Future Enhancements

1. **Add Members to Existing Groups**
   - Add "Add Member" button in group chat view
   - Reuse user search interface
   - New backend endpoint: `add_participant`

2. **Recent Conversations**
   - Show recent DMs in search results
   - Quick access to frequently messaged people

3. **Contact Integration**
   - Import phone contacts
   - Match with existing users
   - Suggest people to message

4. **Search Improvements**
   - Fuzzy matching
   - Search history
   - Suggested users based on common groups

5. **Group Management**
   - Remove members
   - Change group name/avatar
   - Leave group
   - Group admin permissions

## Notes

- DMs are automatically created/retrieved - no duplicate DMs possible
- Groups require at least 2 other participants (3 total including creator)
- All participant IDs are validated before thread creation
- Search is case-insensitive and searches across email, username, and display name
- Online status is shown in search results
- Empty states guide users on what to do next

