# GlobalBridge Backend API Documentation

**Base URL**: `http://localhost:4000` (development)
**Version**: 1.0
**Last Updated**: October 24, 2025

## Table of Contents

1. [Authentication](#authentication)
2. [REST API Endpoints](#rest-api-endpoints)
3. [WebSocket Channels](#websocket-channels)
4. [Error Responses](#error-responses)
5. [Rate Limiting](#rate-limiting)

---

## Authentication

### Overview

The API uses JWT (JSON Web Token) authentication via the Guardian library. All protected endpoints require a valid JWT token in the `Authorization` header.

### Headers

```
Authorization: Bearer <jwt_token>
```

### Token Lifecycle

- **Access Token**: Short-lived, used for API requests
- **Refresh Token**: Long-lived, used to obtain new access tokens

---

## REST API Endpoints

### Authentication Endpoints

#### 1. Sign Up

**Endpoint**: `POST /api/auth/signup`
**Authentication**: None
**Rate Limit**: Yes

**Request Body**:
```json
{
  "username": "john_doe",
  "phone_number": "+12345678900",
  "password": "SecurePass123!",
  "display_name": "John Doe",
  "public_key": "optional_e2ee_public_key"
}
```

**Validation**:
- `username`: 3-30 characters
- `phone_number`: E.164 format
- `password`: minimum 8 characters
- `display_name`: optional
- `public_key`: optional (for E2EE)

**Success Response** (201):
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "username": "john_doe",
      "phone_number": "+12345678900",
      "display_name": "John Doe",
      "inserted_at": "2025-10-24T10:00:00Z"
    },
    "tokens": {
      "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
  }
}
```

---

#### 2. Login

**Endpoint**: `POST /api/auth/login`
**Authentication**: None
**Rate Limit**: Yes

**Request Body**:
```json
{
  "identifier": "john_doe",
  "password": "SecurePass123!"
}
```

**Note**: `identifier` can be either username or phone_number

**Success Response** (200):
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "username": "john_doe",
      "phone_number": "+12345678900"
    },
    "tokens": {
      "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
  }
}
```

---

#### 3. Refresh Token

**Endpoint**: `POST /api/auth/refresh`
**Authentication**: None
**Rate Limit**: Yes

**Request Body**:
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success Response** (200):
```json
{
  "data": {
    "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

---

#### 4. Get Current User

**Endpoint**: `GET /api/auth/me`
**Authentication**: Required
**Rate Limit**: No

**Success Response** (200):
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "username": "john_doe",
      "phone_number": "+12345678900",
      "display_name": "John Doe",
      "public_key": "e2ee_public_key",
      "tier": "free",
      "inserted_at": "2025-10-24T10:00:00Z"
    }
  }
}
```

---

#### 5. Update Public Key (E2EE)

**Endpoint**: `PUT /api/auth/public-key`
**Authentication**: Required
**Rate Limit**: No

**Request Body**:
```json
{
  "public_key": "new_e2ee_public_key"
}
```

**Success Response** (200):
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "public_key": "new_e2ee_public_key"
    }
  }
}
```

---

#### 6. Get User Public Key

**Endpoint**: `GET /api/auth/public-key/:user_id`
**Authentication**: Required
**Rate Limit**: No

**Success Response** (200):
```json
{
  "data": {
    "user_id": "uuid",
    "public_key": "e2ee_public_key"
  }
}
```

**Error Responses**:
- 404: User not found or no public key set

---

#### 7. Logout

**Endpoint**: `POST /api/auth/logout`
**Authentication**: Required
**Rate Limit**: No

**Success Response** (200):
```json
{
  "message": "Logged out successfully"
}
```

---

#### 8. Change Password

**Endpoint**: `PUT /api/auth/password`
**Authentication**: Required
**Rate Limit**: No

**Request Body**:
```json
{
  "current_password": "OldPass123!",
  "new_password": "NewPass123!"
}
```

**Success Response** (200):
```json
{
  "message": "Password changed successfully"
}
```

---

#### 9. OAuth Flow (Auth0)

**Initiate OAuth**:
`GET /api/auth/auth0`

**OAuth Callback**:
`GET /api/auth/auth0/callback?code=xxx&state=xxx`

**Note**: OAuth flow redirects to `/app` after successful authentication with tokens stored in session.

---

### Thread Endpoints

#### 10. List Threads

**Endpoint**: `GET /api/v1/threads`
**Authentication**: Required
**Rate Limit**: No

**Success Response** (200):
```json
{
  "data": {
    "threads": [
      {
        "id": "uuid",
        "title": "Project Discussion",
        "is_archived": false,
        "inserted_at": "2025-10-24T10:00:00Z",
        "updated_at": "2025-10-24T12:00:00Z"
      }
    ]
  }
}
```

---

### Bootstrap Endpoint

#### 11. Bootstrap Data

**Endpoint**: `GET /api/bootstrap`
**Authentication**: Required
**Rate Limit**: No

**Query Parameters**:
- `limit`: number of threads to fetch (default: 20, max: 50)
- `offset`: pagination offset (default: 0)

**Success Response** (200):
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "username": "john_doe",
      "phone_number": "+12345678900",
      "inserted_at": "2025-10-24T10:00:00Z"
    },
    "threads": [
      {
        "id": "uuid",
        "name": "Project Discussion",
        "unread_count": 0,
        "created_at": "2025-10-24T10:00:00Z",
        "updated_at": "2025-10-24T12:00:00Z",
        "last_message": null,
        "bridge": null
      }
    ],
    "pagination": {
      "limit": 20,
      "offset": 0,
      "has_more": false
    },
    "bridges": [],
    "csrf_token": "token_value"
  }
}
```

---

### AI Endpoints

All AI endpoints require authentication and are rate-limited.

#### 12. Translate Text

**Endpoint**: `POST /api/v1/ai/translate`
**Authentication**: Required
**Rate Limit**: Yes

**Request Body**:
```json
{
  "text": "Hello world",
  "target_language": "es",
  "source_language": "en"
}
```

**Validation**:
- `text`: max 10,000 characters (required)
- `target_language`: valid language code (required)
- `source_language`: valid language code (optional, defaults to "auto")

**Success Response** (200):
```json
{
  "success": true,
  "translation": "Hola mundo",
  "source_language": "en",
  "target_language": "es"
}
```

---

#### 13. Analyze Tone

**Endpoint**: `POST /api/v1/ai/analyze_tone`
**Authentication**: Required
**Rate Limit**: Yes

**Request Body**:
```json
{
  "text": "This is great!",
  "language": "en"
}
```

**Validation**:
- `text`: max 10,000 characters (required)
- `language`: valid language code (optional, defaults to "en")

**Success Response** (200):
```json
{
  "success": true,
  "analysis": {
    "tone": "positive",
    "confidence": 0.85,
    "emotions": ["joy", "enthusiasm"],
    "language": "en"
  },
  "text": "This is great!"
}
```

---

#### 14. Summarize Thread

**Endpoint**: `POST /api/v1/ai/summarize_thread`
**Authentication**: Required
**Rate Limit**: Yes

**Request Body**:
```json
{
  "thread_id": "uuid",
  "max_length": 200
}
```

**Validation**:
- `thread_id`: valid UUID (required)
- `max_length`: 1-1,000 (optional, defaults to 200)

**Success Response** (200):
```json
{
  "success": true,
  "summary": "Summary of the thread discussion...",
  "thread_id": "uuid",
  "max_length": 200
}
```

---

#### 15. Semantic Search

**Endpoint**: `POST /api/v1/ai/search_semantic`
**Authentication**: Required
**Rate Limit**: Yes

**Request Body**:
```json
{
  "query": "project deadline",
  "thread_id": "uuid",
  "limit": 10,
  "recency_bias": true,
  "translate": false
}
```

**Validation**:
- `query`: max 1,000 characters (required)
- `thread_id`: valid UUID (optional)
- `limit`: 1-50 (optional, defaults to 10)
- `recency_bias`: boolean (optional, defaults to true)
- `translate`: boolean (optional, defaults to false)

**Success Response** (200):
```json
{
  "success": true,
  "query": "project deadline",
  "results": [
    {
      "message_id": "uuid",
      "content": "The project deadline is next Friday",
      "score": 0.92,
      "timestamp": "2025-10-24T10:00:00Z"
    }
  ],
  "total_results": 1,
  "thread_id": "uuid"
}
```

---

#### 16. Extract Tasks

**Endpoint**: `POST /api/v1/ai/extract_tasks`
**Authentication**: Required
**Rate Limit**: Yes

**Request Body**:
```json
{
  "thread_id": "uuid",
  "query": "tasks, deadlines, decisions"
}
```

**Validation**:
- `thread_id`: valid UUID (required)
- `query`: max 1,000 characters (optional, defaults to "tasks, deadlines, decisions, commitments")

**Success Response** (200):
```json
{
  "success": true,
  "extraction": {
    "tasks": [
      {
        "description": "Complete documentation",
        "deadline": "2025-10-31",
        "assignee": "john_doe"
      }
    ],
    "decisions": ["Use OpenAPI for documentation"],
    "commitments": ["Deploy by end of month"]
  },
  "thread_id": "uuid",
  "query": "tasks, deadlines, decisions"
}
```

---

#### 17. Vector Health Check

**Endpoint**: `POST /api/v1/ai/vec_health`
**Authentication**: Required
**Rate Limit**: No

**Request Body**:
```json
{
  "thread_id": "uuid"
}
```

**Success Response** (200):
```json
{
  "success": true,
  "thread_id": "uuid",
  "shard_id": "shard_uuid",
  "vec_extension_available": true,
  "embeddings_table_exists": true,
  "embeddings_count": 42
}
```

---

### CDC Sync Endpoints

#### 18. Pull Changes

**Endpoint**: `POST /api/v1/sync/pull`
**Authentication**: Required
**Rate Limit**: No

**Request Body**:
```json
{
  "thread_id": "uuid",
  "since": "2025-10-24T10:00:00Z"
}
```

**Alternative Parameters**:
- `last_sync_cursor`: ISO8601 timestamp (legacy parameter)

**Success Response** (200):
```json
{
  "data": {
    "changes": [
      {
        "id": "cdc_uuid",
        "table_name": "messages",
        "operation": "INSERT",
        "record_id": "message_uuid",
        "new_data": {
          "id": "message_uuid",
          "content": "Hello",
          "sender_id": "user_uuid"
        },
        "changed_at": "2025-10-24T10:00:00Z"
      }
    ],
    "cursor": "2025-10-24T12:00:00Z"
  }
}
```

---

#### 19. Push Changes

**Endpoint**: `POST /api/v1/sync/push`
**Authentication**: Required
**Rate Limit**: No

**Request Body**:
```json
{
  "thread_id": "uuid",
  "changes": [
    {
      "table_name": "messages",
      "operation": "INSERT",
      "record_id": "temp_message_uuid",
      "new_data": {
        "content": "Hello from mobile",
        "sender_id": "user_uuid"
      }
    }
  ]
}
```

**Success Response** (200):
```json
{
  "data": {
    "applied": 1,
    "failed": 0,
    "results": [
      {
        "success": true,
        "record_id": "temp_message_uuid",
        "server_id": "message_uuid"
      }
    ]
  }
}
```

---

### Feature Flag Endpoints

#### 20. Get All Features

**Endpoint**: `GET /api/v1/features`
**Authentication**: Required
**Rate Limit**: No

**Success Response** (200):
```json
{
  "data": {
    "tier": "free",
    "features": {
      "ai_translation": true,
      "ai_tone_analysis": true,
      "semantic_search": false,
      "thread_summarization": false,
      "task_extraction": false,
      "advanced_rate_limits": false
    },
    "limits": {
      "max_threads": 10,
      "max_messages_per_thread": 1000,
      "ai_requests_per_day": 50
    }
  }
}
```

---

#### 21. Check Specific Feature

**Endpoint**: `GET /api/v1/features/:feature`
**Authentication**: Required
**Rate Limit**: No

**Example**: `GET /api/v1/features/ai_translation`

**Success Response** (200):
```json
{
  "data": {
    "feature": "ai_translation",
    "has_access": true,
    "tier": "free"
  }
}
```

---

#### 22. Update Tier

**Endpoint**: `PUT /api/v1/features/tier`
**Authentication**: Required
**Rate Limit**: No

**Request Body**:
```json
{
  "tier": "pro"
}
```

**Valid Tiers**: `free`, `pro`, `enterprise`

**Success Response** (200):
```json
{
  "data": {
    "tier": "pro",
    "features": {
      "ai_translation": true,
      "ai_tone_analysis": true,
      "semantic_search": true,
      "thread_summarization": true,
      "task_extraction": true,
      "advanced_rate_limits": true
    },
    "message": "Tier updated successfully"
  }
}
```

---

## WebSocket Channels

### Connection Setup

**WebSocket URL**: `ws://localhost:4000/socket`
**Transport**: WebSocket
**Protocol**: Phoenix Channels

### Connection Example (JavaScript)

```javascript
import { Socket } from "phoenix"

const socket = new Socket("ws://localhost:4000/socket", {
  params: { token: "your_jwt_token" }
})

socket.connect()
```

---

### Thread Channel

**Topic**: `thread:{thread_id}`
**Authentication**: Required (JWT token in connection params)

#### Join Channel

```javascript
const threadChannel = socket.channel(`thread:${threadId}`, {})

threadChannel.join()
  .receive("ok", response => {
    console.log("Joined thread", response)
    // response.messages - recent messages
    // response.participants - thread participants
  })
  .receive("error", error => {
    console.error("Failed to join", error)
  })
```

#### Incoming Events (Client → Server)

##### 1. Send Message

```javascript
threadChannel.push("new_message", {
  content: "Hello, world!",
  encrypted_content: "optional_e2ee_content",
  reply_to_id: "optional_message_uuid",
  attachments: []
})
  .receive("ok", response => {
    // response.message - saved message with server ID
  })
  .receive("error", error => {
    // error.reason
  })
```

##### 2. Fetch Message History

```javascript
threadChannel.push("fetch_messages", {
  limit: 50,
  before_id: "message_uuid",  // optional cursor
  after_id: "message_uuid"     // optional cursor
})
  .receive("ok", response => {
    // response.messages
    // response.has_more
  })
```

##### 3. Edit Message

```javascript
threadChannel.push("edit_message", {
  message_id: "message_uuid",
  content: "Updated content",
  encrypted_content: "optional_e2ee_content"
})
  .receive("ok", response => {
    // response.message
  })
  .receive("error", error => {
    // error.reason (e.g., "unauthorized", "not_found")
  })
```

##### 4. Delete Message

```javascript
threadChannel.push("delete_message", {
  message_id: "message_uuid"
})
  .receive("ok", response => {
    // response.message_id
  })
  .receive("error", error => {
    // error.reason
  })
```

##### 5. Typing Indicator

```javascript
threadChannel.push("typing", {
  typing: true  // or false when stopped
})
  .receive("ok", () => {})
```

##### 6. Mark as Read

```javascript
threadChannel.push("mark_read", {
  message_id: "message_uuid"
})
  .receive("ok", response => {
    // response.read_receipt
  })
```

##### 7. Get Read Receipts

```javascript
threadChannel.push("get_read_receipts", {
  message_id: "message_uuid"
})
  .receive("ok", response => {
    // response.receipts - array of {user_id, read_at}
  })
```

##### 8. CDC Pull

```javascript
threadChannel.push("cdc:pull", {
  since: "2025-10-24T10:00:00Z"  // ISO8601 timestamp
})
  .receive("ok", response => {
    // response.changes - array of CDC records
    // response.cursor - new cursor for next pull
  })
```

##### 9. CDC Push

```javascript
threadChannel.push("cdc:push", {
  changes: [
    {
      table_name: "messages",
      operation: "INSERT",
      record_id: "temp_uuid",
      new_data: { content: "Hello" }
    }
  ]
})
  .receive("ok", response => {
    // response.applied
    // response.failed
    // response.results
  })
```

#### Broadcast Events (Server → Client)

##### 1. New Message

```javascript
threadChannel.on("new_message", payload => {
  // payload.message - full message object
  // payload.sender - sender user object
})
```

##### 2. Message Edited

```javascript
threadChannel.on("message_edited", payload => {
  // payload.message - updated message
  // payload.editor_id - user who edited
})
```

##### 3. Message Deleted

```javascript
threadChannel.on("message_deleted", payload => {
  // payload.message_id
  // payload.deleted_by - user who deleted
})
```

##### 4. User Typing

```javascript
threadChannel.on("user_typing", payload => {
  // payload.user_id
  // payload.username
  // payload.typing - true/false
})
```

##### 5. Message Read

```javascript
threadChannel.on("message_read", payload => {
  // payload.message_id
  // payload.user_id
  // payload.read_at
})
```

##### 6. Presence State

```javascript
threadChannel.on("presence_state", state => {
  // state - map of online users
  // Example: { "user_uuid": { metas: [{ online_at: "..." }] } }
})

threadChannel.on("presence_diff", diff => {
  // diff.joins - users who joined
  // diff.leaves - users who left
})
```

---

### User Channel

**Topic**: `user:{user_id}`
**Authentication**: Required (JWT token in connection params)

#### Join Channel

```javascript
const userChannel = socket.channel(`user:${userId}`, {})

userChannel.join()
  .receive("ok", response => {
    console.log("Joined user channel", response)
  })
  .receive("error", error => {
    console.error("Failed to join", error)
  })
```

#### Incoming Events (Client → Server)

##### 1. Bootstrap

```javascript
userChannel.push("bootstrap", {})
  .receive("ok", response => {
    // response.threads - all user threads
    // response.contacts - user's contacts
    // response.user - user profile
  })
```

##### 2. Create Thread

```javascript
userChannel.push("create_thread", {
  title: "Project Discussion",
  participant_ids: ["user_uuid_1", "user_uuid_2"]
})
  .receive("ok", response => {
    // response.thread - created thread
  })
```

##### 3. Create Direct Message

```javascript
userChannel.push("create_dm", {
  other_user_id: "user_uuid"
})
  .receive("ok", response => {
    // response.thread - DM thread (existing or new)
  })
```

##### 4. Search Users

```javascript
userChannel.push("search_users", {
  query: "john"
})
  .receive("ok", response => {
    // response.users - matching users
  })
```

##### 5. Search Contacts

```javascript
userChannel.push("search_contacts", {
  query: "jane"
})
  .receive("ok", response => {
    // response.contacts
  })
```

##### 6. Get Contacts

```javascript
userChannel.push("get_contacts", {})
  .receive("ok", response => {
    // response.contacts
  })
```

##### 7. Sync Contacts (CDC)

```javascript
userChannel.push("sync_contacts", {
  since: "2025-10-24T10:00:00Z"
})
  .receive("ok", response => {
    // response.changes
    // response.cursor
  })
```

##### 8. Add Contact

```javascript
userChannel.push("add_contact", {
  contact_user_id: "user_uuid",
  display_name: "John Doe"
})
  .receive("ok", response => {
    // response.contact
  })
```

##### 9. Remove Contact

```javascript
userChannel.push("remove_contact", {
  contact_id: "contact_uuid"
})
  .receive("ok", response => {
    // response.success
  })
```

#### Broadcast Events (Server → Client)

##### 1. Thread Created

```javascript
userChannel.on("thread_created", payload => {
  // payload.thread - new thread object
})
```

---

## Error Responses

### Standard Error Format

```json
{
  "error": "Error message description"
}
```

### HTTP Status Codes

- **200 OK**: Success
- **201 Created**: Resource created successfully
- **400 Bad Request**: Invalid request parameters
- **401 Unauthorized**: Missing or invalid authentication
- **403 Forbidden**: Access denied to resource
- **404 Not Found**: Resource not found
- **422 Unprocessable Entity**: Validation failed
- **429 Too Many Requests**: Rate limit exceeded
- **500 Internal Server Error**: Server error

### Common Error Messages

#### Authentication Errors

```json
{
  "error": "Invalid or expired refresh token"
}
```

```json
{
  "error": "Access denied to this thread"
}
```

#### Validation Errors

```json
{
  "error": "Missing required fields: identifier and password"
}
```

```json
{
  "error": "Text must be between 1 and 10,000 characters"
}
```

#### Rate Limiting

```json
{
  "error": "Rate limit exceeded. Try again later."
}
```

---

## Rate Limiting

### Overview

Rate limiting is implemented using the Hammer library with configurable limits per user tier.

### Rate-Limited Endpoints

- `POST /api/auth/signup` - 5 requests per hour
- `POST /api/auth/login` - 10 requests per hour
- `POST /api/auth/refresh` - 20 requests per hour
- All `/api/v1/ai/*` endpoints - varies by tier

### Rate Limit Headers

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 99
X-RateLimit-Reset: 1729780800
```

### Tier-Based Limits

#### Free Tier
- AI requests: 50 per day
- Max threads: 10
- Max messages per thread: 1,000

#### Pro Tier
- AI requests: 500 per day
- Max threads: 100
- Max messages per thread: 10,000

#### Enterprise Tier
- AI requests: Unlimited
- Max threads: Unlimited
- Max messages per thread: Unlimited

---

## Data Types

### User Object

```typescript
{
  id: string (UUID)
  username: string
  phone_number: string (E.164 format)
  display_name: string | null
  public_key: string | null
  tier: "free" | "pro" | "enterprise"
  inserted_at: string (ISO8601)
  updated_at: string (ISO8601)
}
```

### Thread Object

```typescript
{
  id: string (UUID)
  title: string | null
  is_archived: boolean
  database_shard_id: string
  inserted_at: string (ISO8601)
  updated_at: string (ISO8601)
}
```

### Message Object

```typescript
{
  id: string (UUID)
  content: string
  encrypted_content: string | null
  sender_id: string (UUID)
  reply_to_id: string (UUID) | null
  attachments: Array
  inserted_at: string (ISO8601)
  updated_at: string (ISO8601)
}
```

### CDC Change Object

```typescript
{
  id: string (UUID)
  table_name: "messages" | "threads" | "participants" | "contacts"
  operation: "INSERT" | "UPDATE" | "DELETE"
  record_id: string (UUID)
  old_data: object | null
  new_data: object | null
  changed_at: string (ISO8601)
}
```

---

## Environment Configuration

### Required Environment Variables

```bash
# Database
DATABASE_PATH=/path/to/users.db

# Auth0 (OAuth)
AUTH0_DOMAIN=your-tenant.auth0.com
AUTH0_CLIENT_ID=your_client_id
AUTH0_CLIENT_SECRET=your_client_secret
AUTH0_AUDIENCE=globalbridge-api

# AI Services
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Server
SECRET_KEY_BASE=your_secret_key_base
PHX_HOST=localhost
PORT=4000
```

---

## Development Tips

### Testing Authentication

1. Sign up or login to get tokens
2. Store `access` token for subsequent requests
3. Use `refresh` token when access token expires
4. Include token in `Authorization: Bearer <token>` header

### Testing WebSocket Channels

1. Establish socket connection with JWT token
2. Join channel with proper topic format
3. Listen for broadcast events before pushing
4. Handle presence tracking for online status

### CDC Sync Pattern

1. **Initial Sync**: Call `/api/v1/sync/pull` with no `since` parameter
2. **Store Cursor**: Save the returned `cursor` value
3. **Subsequent Syncs**: Use stored cursor as `since` parameter
4. **Push Changes**: Use `/api/v1/sync/push` to send local changes

### Error Handling

Always check HTTP status codes and handle errors gracefully:

```javascript
try {
  const response = await fetch('/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identifier, password })
  })

  if (!response.ok) {
    const error = await response.json()
    console.error('Login failed:', error.error)
    return
  }

  const data = await response.json()
  // Store tokens
} catch (error) {
  console.error('Network error:', error)
}
```

---

## Support

For questions or issues, contact the backend team or file an issue in the repository.

**Last Updated**: October 24, 2025
**Maintained By**: GlobalBridge Backend Team
