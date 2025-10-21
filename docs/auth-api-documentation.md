# Authentication API Documentation

## Overview
JWT-based authentication system for WhatsApp Clone MVP. Supports user registration, login, token refresh, and E2EE public key management.

## Base URL
```
http://localhost:4000/api/auth
```

## Authentication
Protected endpoints require JWT token in Authorization header:
```
Authorization: Bearer <access_token>
```

---

## Public Endpoints

### 1. Sign Up
**POST** `/signup`

Register a new user account.

**Request Body:**
```json
{
  "username": "john_doe",
  "phone_number": "+1234567890",
  "password": "SecurePassword123",
  "display_name": "John Doe",
  "public_key": "base64_encoded_public_key" // optional
}
```

**Validation Rules:**
- `username`: 3-30 characters, unique
- `phone_number`: E.164 format (e.g., +1234567890), unique
- `password`: Minimum 8 characters
- `display_name`: Maximum 50 characters (optional)
- `public_key`: For E2EE setup (optional)

**Success Response (201 Created):**
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "username": "john_doe",
      "phone_number": "+1234567890",
      "display_name": "John Doe",
      "avatar_url": null,
      "status_message": null,
      "is_online": false,
      "last_seen_at": null,
      "has_public_key": true,
      "inserted_at": "2025-10-20T22:00:00Z",
      "updated_at": "2025-10-20T22:00:00Z"
    },
    "tokens": {
      "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
  }
}
```

**Error Response (422 Unprocessable Entity):**
```json
{
  "errors": {
    "username": ["has already been taken"],
    "phone_number": ["must be valid E.164 format"]
  }
}
```

---

### 2. Login
**POST** `/login`

Authenticate user and receive JWT tokens.

**Request Body:**
```json
{
  "identifier": "john_doe",  // username or phone_number
  "password": "SecurePassword123"
}
```

**Success Response (200 OK):**
```json
{
  "data": {
    "user": {
      "id": "uuid",
      "username": "john_doe",
      "phone_number": "+1234567890",
      "is_online": true,
      "last_seen_at": "2025-10-20T22:05:00Z",
      ...
    },
    "tokens": {
      "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
  }
}
```

**Error Response (401 Unauthorized):**
```json
{
  "error": "Invalid username/phone or password"
}
```

**Notes:**
- Sets `is_online` to `true` and updates `last_seen_at`
- Accepts either username or phone_number as identifier

---

### 3. Refresh Token
**POST** `/refresh`

Refresh access token using refresh token.

**Request Body:**
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Success Response (200 OK):**
```json
{
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

**Error Response (401 Unauthorized):**
```json
{
  "error": "Invalid or expired refresh token"
}
```

---

## Protected Endpoints

### 4. Get Current User
**GET** `/me`

Get authenticated user information.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Success Response (200 OK):**
```json
{
  "data": {
    "id": "uuid",
    "username": "john_doe",
    "phone_number": "+1234567890",
    "display_name": "John Doe",
    "is_online": true,
    "has_public_key": true,
    ...
  }
}
```

**Error Response (401 Unauthorized):**
```json
{
  "error": "not_authenticated",
  "message": "Authentication required"
}
```

---

### 5. Update Public Key
**PUT** `/public-key`

Update user's public key for E2EE.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Request Body:**
```json
{
  "public_key": "base64_encoded_public_key"
}
```

**Success Response (200 OK):**
```json
{
  "data": {
    "id": "uuid",
    "username": "john_doe",
    "has_public_key": true,
    ...
  }
}
```

---

### 6. Get User Public Key
**GET** `/public-key/:user_id`

Retrieve another user's public key for E2EE key exchange.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Success Response (200 OK):**
```json
{
  "data": {
    "user_id": "uuid",
    "public_key": "base64_encoded_public_key"
  }
}
```

**Error Responses:**
- **404 Not Found** - User not found or has no public key
```json
{
  "error": "User has not set up E2EE yet"
}
```

---

### 7. Logout
**POST** `/logout`

Logout user (sets online status to false).

**Headers:**
```
Authorization: Bearer <access_token>
```

**Success Response (200 OK):**
```json
{
  "message": "Logged out successfully"
}
```

**Note:** Updates `is_online` to `false`

---

### 8. Change Password
**PUT** `/password`

Change user password.

**Headers:**
```
Authorization: Bearer <access_token>
```

**Request Body:**
```json
{
  "current_password": "OldPassword123",
  "new_password": "NewPassword456"
}
```

**Success Response (200 OK):**
```json
{
  "message": "Password changed successfully"
}
```

**Error Response (401 Unauthorized):**
```json
{
  "error": "Current password is incorrect"
}
```

---

## JWT Token Details

### Access Token
- **Expiration:** 24 hours
- **Type:** `access`
- **Claims:**
  ```json
  {
    "sub": "user_id",
    "typ": "access",
    "username": "john_doe",
    "phone_number": "+1234567890",
    "exp": 1698000000
  }
  ```

### Refresh Token
- **Expiration:** 7 days
- **Type:** `refresh`
- **Claims:**
  ```json
  {
    "sub": "user_id",
    "typ": "refresh",
    "exp": 1698604800
  }
  ```

---

## Error Response Format

All errors follow this structure:

```json
{
  "error": "error_type",
  "message": "Human-readable error message"
}
```

OR for validation errors:

```json
{
  "errors": {
    "field_name": ["error message 1", "error message 2"]
  }
}
```

---

## HTTP Status Codes

- **200** OK - Request successful
- **201** Created - Resource created successfully
- **400** Bad Request - Missing required fields
- **401** Unauthorized - Authentication failed or missing
- **404** Not Found - Resource not found
- **422** Unprocessable Entity - Validation errors

---

## Security Considerations

1. **Password Hashing:** Bcrypt with salt
2. **JWT Secret:** Configured via `GUARDIAN_SECRET_KEY` environment variable
3. **Token Transmission:** HTTPS required in production
4. **CORS:** Configured for cross-origin requests
5. **Rate Limiting:** Recommended for production

---

## iOS Integration Pattern

### 1. User Registration Flow
```swift
struct SignupRequest: Codable {
    let username: String
    let phoneNumber: String
    let password: String
    let displayName: String?
    let publicKey: String?
}

func signup(username: String, phone: String, password: String) async throws -> AuthResponse {
    let request = SignupRequest(
        username: username,
        phoneNumber: phone,
        password: password,
        displayName: nil,
        publicKey: generatePublicKey() // E2EE key
    )

    let response = try await apiClient.post("/api/auth/signup", body: request)
    // Store tokens in Keychain
    KeychainManager.shared.save(tokens: response.data.tokens)
    return response
}
```

### 2. Authentication Flow
```swift
func login(identifier: String, password: String) async throws -> AuthResponse {
    let request = ["identifier": identifier, "password": password]
    let response = try await apiClient.post("/api/auth/login", body: request)
    KeychainManager.shared.save(tokens: response.data.tokens)
    return response
}
```

### 3. Token Refresh
```swift
func refreshToken() async throws -> Tokens {
    guard let refreshToken = KeychainManager.shared.getRefreshToken() else {
        throw AuthError.noRefreshToken
    }

    let response = try await apiClient.post("/api/auth/refresh",
        body: ["refresh_token": refreshToken])
    KeychainManager.shared.save(tokens: response.data)
    return response.data
}
```

### 4. Authenticated Requests
```swift
class AuthenticatedAPIClient {
    func request(_ endpoint: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))

        // Add auth header
        if let token = KeychainManager.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // Handle token expiration
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 401 {
            // Refresh token and retry
            try await refreshToken()
            return try await self.request(endpoint)
        }

        return data
    }
}
```

---

## Testing Examples

### cURL Examples

**Sign Up:**
```bash
curl -X POST http://localhost:4000/api/auth/signup \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "phone_number": "+1234567890",
    "password": "Password123"
  }'
```

**Login:**
```bash
curl -X POST http://localhost:4000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "testuser",
    "password": "Password123"
  }'
```

**Get Current User:**
```bash
curl -X GET http://localhost:4000/api/auth/me \
  -H "Authorization: Bearer <access_token>"
```

---

## Next Steps for iOS Integration

1. **Keychain Integration:** Store tokens securely
2. **Automatic Token Refresh:** Implement interceptor for 401 responses
3. **E2EE Setup:** Generate and exchange public keys
4. **Biometric Authentication:** Optional Face ID/Touch ID
5. **Offline Support:** Cache user data locally

---

**Documentation Version:** 1.0
**Last Updated:** October 20, 2025
**API Version:** MVP v1
