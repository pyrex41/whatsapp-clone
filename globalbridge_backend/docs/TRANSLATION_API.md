# Translation API Documentation

## Overview

The Translation API provides AI-powered text translation with idiom detection and cultural context. It uses the Groq API for fast, accurate translations and automatically identifies idiomatic expressions to provide cultural notes.

## Table of Contents

- [Authentication](#authentication)
- [Endpoint](#endpoint)
- [Request Format](#request-format)
- [Response Format](#response-format)
- [Examples](#examples)
- [Rate Limiting](#rate-limiting)
- [Error Handling](#error-handling)
- [Implementation Details](#implementation-details)

## Authentication

### Development Mode (No Auth Required)

In development, authentication is **automatically bypassed** when `dev_mode: true` is set in `config/dev.exs`:

```elixir
config :globalbridge_backend, dev_mode: true
```

This allows you to test the API without JWT tokens. A mock user is automatically created for each request.

**Dev Mode Features:**
- No Authorization header needed
- Automatic mock user creation
- All API endpoints accessible
- See [DEV_MODE.md](DEV_MODE.md) for full details

### Production Mode (Auth Required)

In production, you must provide a valid JWT token:

```bash
curl -X POST 'http://localhost:4000/api/v1/ai/translate' \
  -H 'Authorization: Bearer YOUR_JWT_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"text": "Hello", "target_language": "es"}'
```

## Endpoint

```
POST /api/v1/ai/translate
```

**Base URL:** `http://localhost:4000` (development)

**Full URL:** `http://localhost:4000/api/v1/ai/translate`

## Request Format

### Headers

- `Content-Type: application/json` (required)
- `Authorization: Bearer <token>` (required in production, optional in dev mode)

### Request Body

```json
{
  "text": "Hello, how are you?",
  "target_language": "es",
  "source_language": "en"
}
```

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | string | Yes | - | Text to translate (max 10,000 characters) |
| `target_language` | string | Yes | - | Target language code (e.g., "es", "fr", "de") |
| `source_language` | string | No | "auto" | Source language code or "auto" for detection |

### Supported Language Codes

- `en` - English
- `es` - Spanish
- `fr` - French
- `de` - German
- `it` - Italian
- `pt` - Portuguese
- `ru` - Russian
- `ja` - Japanese
- `zh` - Chinese
- `ar` - Arabic
- And many more...

## Response Format

### Success Response

**HTTP Status:** `200 OK`

```json
{
  "success": true,
  "translation": "Hola, ¿cómo estás?",
  "confidence": 0.99,
  "cultural_notes": [],
  "source_language": "English",
  "target_language": "es"
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `success` | boolean | Always `true` for successful translations |
| `translation` | string | The translated text |
| `confidence` | float | Translation confidence score (0.0 to 1.0) |
| `cultural_notes` | array | Cultural context for idioms (may be empty) |
| `source_language` | string | Detected or provided source language |
| `target_language` | string | Target language code |

### Translation with Idioms

When idioms are detected, cultural notes are provided:

```json
{
  "success": true,
  "translation": "Está lloviendo gatos y perros",
  "confidence": 0.95,
  "cultural_notes": [
    "The phrase 'It is raining cats and dogs' is an idiom that means raining very heavily. The literal translation is provided, but in Spanish, a more common equivalent idiom is 'Está lloviendo a cántaros' or 'Está lloviendo torrentes'."
  ],
  "source_language": "English",
  "target_language": "es"
}
```

### Error Response

**HTTP Status:** `400 Bad Request` or `422 Unprocessable Entity`

```json
{
  "error": "Target language is required"
}
```

**HTTP Status:** `429 Too Many Requests`

```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests to translate endpoint",
  "retry_after_seconds": 42,
  "limit": 60,
  "window": "60 seconds"
}
```

## Examples

### Basic Translation (Dev Mode)

```bash
curl -X POST 'http://localhost:4000/api/v1/ai/translate' \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Hello, how are you?",
    "target_language": "es"
  }'
```

**Response:**
```json
{
  "success": true,
  "translation": "Hola, ¿cómo estás?",
  "confidence": 0.99,
  "cultural_notes": [],
  "source_language": "English",
  "target_language": "es"
}
```

### Translation with Source Language

```bash
curl -X POST 'http://localhost:4000/api/v1/ai/translate' \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Bonjour",
    "source_language": "fr",
    "target_language": "en"
  }'
```

**Response:**
```json
{
  "success": true,
  "translation": "Hello",
  "confidence": 0.99,
  "cultural_notes": [],
  "source_language": "French",
  "target_language": "en"
}
```

### Translation with Idioms

```bash
curl -X POST 'http://localhost:4000/api/v1/ai/translate' \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "It is raining cats and dogs",
    "target_language": "es"
  }'
```

**Response:**
```json
{
  "success": true,
  "translation": "Está lloviendo gatos y perros",
  "confidence": 0.95,
  "cultural_notes": [
    "The phrase 'It is raining cats and dogs' is an idiom that means raining very heavily. The literal translation is provided, but in Spanish, a more common equivalent idiom is 'Está lloviendo a cántaros' or 'Está lloviendo torrentes'."
  ],
  "source_language": "English",
  "target_language": "es"
}
```

### Using JSON File

```bash
# Create JSON file
cat > translation_request.json << 'EOF'
{
  "text": "The early bird catches the worm",
  "target_language": "fr"
}
EOF

# Make request
curl -X POST 'http://localhost:4000/api/v1/ai/translate' \
  -H 'Content-Type: application/json' \
  -d @translation_request.json
```

## Rate Limiting

The translation endpoint is rate-limited to prevent abuse and control costs.

### Rate Limits by Tier

| Tier | Limit | Window |
|------|-------|--------|
| Free | 60 requests | 60 seconds |
| Pro | 200 requests | 60 seconds |
| Enterprise | 1000 requests | 60 seconds |

### Rate Limit Headers

Every response includes rate limit information:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1705123456
```

### Rate Limit Exceeded

When rate limit is exceeded, you'll receive:

**HTTP Status:** `429 Too Many Requests`

```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests to translate endpoint",
  "retry_after_seconds": 42,
  "limit": 60,
  "window": "60 seconds"
}
```

**Response Headers:**
```
Retry-After: 42
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1705123456
```

## Error Handling

### Common Errors

#### Missing Required Parameters

**Request:**
```json
{
  "text": "Hello"
}
```

**Response (400):**
```json
{
  "error": "Target language is required"
}
```

#### Text Too Long

**Request:**
```json
{
  "text": "... (10,001+ characters) ...",
  "target_language": "es"
}
```

**Response (400):**
```json
{
  "error": "Text must be 10,000 characters or less"
}
```

#### Invalid Language Code

**Request:**
```json
{
  "text": "Hello",
  "target_language": "invalid"
}
```

**Response (400):**
```json
{
  "error": "Invalid language code"
}
```

#### Translation Service Error

**Response (422):**
```json
{
  "error": "Translation failed"
}
```

#### Internal Server Error

**Response (500):**
```json
{
  "error": "An error occurred during translation"
}
```

## Implementation Details

### Architecture

The translation API uses a simplified direct approach, bypassing the complex Agens multi-agent system:

```
Client Request
    ↓
AIController.translate/2
    ↓
Input Validation (AIValidator)
    ↓
Rate Limiting Check (RateLimitAI plug)
    ↓
simple_translate/2 (Direct Groq API call)
    ↓
Groq API (llama-3.3-70b-versatile)
    ↓
JSON Response with translation + cultural notes
```

### Key Components

#### 1. Controller (`AIController`)

Located: `lib/globalbridge_backend_web/controllers/ai_controller.ex`

Handles:
- Request validation
- Authentication check (dev mode bypass)
- Rate limiting
- Error handling
- Response formatting

#### 2. Direct Translation (`simple_translate/2`)

Located: `lib/globalbridge_backend_web/controllers/ai_controller.ex:401-472`

Features:
- Direct Groq API integration
- JSON-mode responses for reliability
- Automatic idiom detection
- Cultural context generation
- Error recovery

**Model Used:** `llama-3.3-70b-versatile` (configurable via `GROQ_MODEL` env var)

**Temperature:** `0.3` (balanced between accuracy and creativity)

#### 3. Input Validation (`AIValidator`)

Located: `lib/globalbridge_backend_web/validators/ai_validator.ex`

Validates:
- Text length (max 10,000 characters)
- Language codes
- Required parameters

#### 4. Rate Limiting (`RateLimitAI` plug)

Located: `lib/globalbridge_backend_web/plugs/rate_limit_ai.ex`

Features:
- Per-user per-endpoint limits
- Configurable via environment variables
- Automatic retry-after headers
- Telemetry events for monitoring

### Environment Variables

```bash
# Required
GROQ_API_KEY=your_groq_api_key_here

# Optional
GROQ_MODEL=llama-3.3-70b-versatile  # Default model
AI_RATE_LIMIT_TRANSLATE=60          # Requests per minute
```

### Why Direct Implementation?

The original Agens-based multi-agent translation system was replaced with a direct implementation because:

1. **Agens Job System Bug** - The framework attempted to execute a non-existent 4th step after completing 3 steps
2. **Complexity** - Multi-agent orchestration added unnecessary overhead for simple translations
3. **Reliability** - Direct API calls are more predictable and easier to debug
4. **Performance** - Eliminates agent coordination overhead
5. **Maintainability** - Simpler code is easier to maintain and extend

The direct implementation maintains all features (translation, confidence, cultural notes) while being more reliable.

## Best Practices

### 1. Handle Rate Limits Gracefully

```javascript
async function translateWithRetry(text, targetLang) {
  try {
    const response = await fetch('/api/v1/ai/translate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text, target_language: targetLang })
    });

    if (response.status === 429) {
      const retryAfter = response.headers.get('Retry-After');
      await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
      return translateWithRetry(text, targetLang);
    }

    return await response.json();
  } catch (error) {
    console.error('Translation failed:', error);
    throw error;
  }
}
```

### 2. Show Cultural Notes to Users

Cultural notes are valuable for understanding translations. Always display them when present:

```javascript
const result = await translate("It's raining cats and dogs", "es");

if (result.cultural_notes && result.cultural_notes.length > 0) {
  console.log("Translation:", result.translation);
  console.log("Cultural Context:");
  result.cultural_notes.forEach(note => console.log("  -", note));
}
```

### 3. Cache Translations

To reduce API calls and costs, cache translations:

```javascript
const translationCache = new Map();

function getCacheKey(text, targetLang) {
  return `${text}:${targetLang}`;
}

async function translateWithCache(text, targetLang) {
  const key = getCacheKey(text, targetLang);

  if (translationCache.has(key)) {
    return translationCache.get(key);
  }

  const result = await translate(text, targetLang);
  translationCache.set(key, result);

  return result;
}
```

### 4. Validate Input Client-Side

Reduce unnecessary API calls by validating input:

```javascript
function validateTranslationInput(text, targetLang) {
  if (!text || text.trim().length === 0) {
    throw new Error("Text cannot be empty");
  }

  if (text.length > 10000) {
    throw new Error("Text must be 10,000 characters or less");
  }

  if (!targetLang || !isValidLanguageCode(targetLang)) {
    throw new Error("Invalid target language");
  }
}
```

## Troubleshooting

### Issue: "no route found for POST /api/ai/translate"

**Problem:** Using incorrect endpoint URL

**Solution:** Use `/api/v1/ai/translate` (note the `v1`)

```bash
# ❌ Wrong
curl -X POST 'http://localhost:4000/api/ai/translate'

# ✅ Correct
curl -X POST 'http://localhost:4000/api/v1/ai/translate'
```

### Issue: "401 Unauthorized" in Dev Mode

**Problem:** Dev mode not enabled or server not restarted

**Solution:**
1. Check `config/dev.exs`: `config :globalbridge_backend, dev_mode: true`
2. Restart server: `mix phx.server`
3. Verify logs show: `🔓 [AUTH] Dev mode: bypassing authentication`

### Issue: "GROQ_API_KEY not configured"

**Problem:** Missing API key

**Solution:** Add to your `.env` or environment:

```bash
export GROQ_API_KEY=your_api_key_here
```

### Issue: "Translation failed"

**Problem:** Various causes (API error, network issue, invalid input)

**Solution:** Check server logs for detailed error:

```bash
tail -f logs/dev.log | grep "AI endpoint error"
```

### Issue: JSON Parse Error with Apostrophes

**Problem:** Shell escaping issues with curl

**Solution:** Use a JSON file instead:

```bash
# Create file
cat > request.json << 'EOF'
{"text": "Don't worry", "target_language": "es"}
EOF

# Use file
curl -X POST 'http://localhost:4000/api/v1/ai/translate' \
  -H 'Content-Type: application/json' \
  -d @request.json
```

## Related Documentation

- [DEV_MODE.md](DEV_MODE.md) - Authentication bypass for development
- [API_RATE_LIMITING.md](API_RATE_LIMITING.md) - Detailed rate limiting documentation
- [FEATURE_FLAGS.md](FEATURE_FLAGS.md) - Feature access by user tier

## Support

For issues or questions:
1. Check server logs: `tail -f logs/dev.log`
2. Verify dev mode: Look for `🔓 [AUTH] Dev mode` messages
3. Test with simple request first
4. Check rate limit headers in response

## Changelog

### v1.0.0 (2025-01-24)

- ✅ Initial release with direct Groq API implementation
- ✅ Dev mode authentication bypass support
- ✅ Automatic idiom detection and cultural notes
- ✅ Per-user rate limiting (60 req/min default)
- ✅ Comprehensive error handling
- ✅ Input validation (10,000 char limit)
- ✅ Support for auto language detection
- ✅ High confidence scores (typically 0.9+)

### Previous Versions

- **v0.1.0** - Original Agens-based multi-agent implementation (deprecated due to framework bugs)
