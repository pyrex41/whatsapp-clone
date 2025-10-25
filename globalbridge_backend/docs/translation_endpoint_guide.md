# Translation Endpoint - Complete Guide

## Overview

The `/api/v1/ai/translate` endpoint provides intelligent translation with optional automatic language detection, idiom analysis, and cultural context.

## Endpoint

```
POST /api/v1/ai/translate
```

## Authentication

Required: JWT token in Authorization header

```http
Authorization: Bearer <your_jwt_token>
```

---

## Request Parameters

### Required Parameters

| Parameter | Type | Validation | Description |
|-----------|------|------------|-------------|
| `text` | string | Max 10,000 chars, non-empty | Text to translate |

### Optional Parameters

| Parameter | Type | Default | Validation | Description |
|-----------|------|---------|------------|-------------|
| `target_language` | string | `null` (auto-detect → English) | Valid ISO 639-1 code | Target language code |
| `source_language` | string | `"auto"` | Valid ISO 639-1 code or "auto" | Source language hint |
| `detection_strategy` | string | From `LANGUAGE_DETECTION_STRATEGY` env | `"dedicated"` or `"combined"` | Language detection method |

### Supported Language Codes

```
en (English)    es (Spanish)     fr (French)
de (German)     it (Italian)     pt (Portuguese)
ja (Japanese)   zh (Chinese)     ko (Korean)
ru (Russian)    ar (Arabic)      hi (Hindi)
```

---

## Language Detection Strategies

### When `target_language` is NOT provided:

The endpoint automatically detects the source language and translates to English by default.

#### Strategy 1: "dedicated" (Default)
- **How it works**: Makes 2 separate LLM calls
  1. Dedicated language detection call (optimized prompt)
  2. Translation call using detected language
- **Pros**: More accurate language detection
- **Cons**: Slower (2 API calls), slightly higher cost
- **Use when**: Accuracy is critical, especially for less common languages

#### Strategy 2: "combined"
- **How it works**: Single LLM call that detects and translates
- **Pros**: Faster (1 API call), lower cost
- **Cons**: Slightly less accurate detection
- **Use when**: Speed matters, working with common languages

### When `target_language` IS provided:

No language detection occurs. Direct translation is performed.

---

## Request Examples

### Example 1: Direct Translation (with target language)

```bash
curl -X POST https://api.globalbridge.app/api/v1/ai/translate \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Break a leg on your exam!",
    "target_language": "es"
  }'
```

### Example 2: Auto-Detection (no target language)

```bash
curl -X POST https://api.globalbridge.app/api/v1/ai/translate \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Hola, ¿cómo estás?"
  }'
```
*Automatically detects Spanish and translates to English*

### Example 3: Auto-Detection with Strategy Selection

```bash
curl -X POST https://api.globalbridge.app/api/v1/ai/translate \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Bonjour le monde",
    "detection_strategy": "combined"
  }'
```
*Uses single-call detection+translation for speed*

---

## Response Format

### Success Response (200 OK)

```json
{
  "success": true,
  "translation": "Hello, how are you?",
  "confidence": 0.98,
  "cultural_notes": [],
  "source_language": "Spanish",
  "source_language_code": "es",
  "target_language": "English",
  "target_language_code": "en",
  "detection_strategy": "combined"
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `success` | boolean | Always `true` on success |
| `translation` | string | The translated text |
| `confidence` | float | Translation quality score (0.0-1.0) |
| `cultural_notes` | array | Idioms and cultural expressions detected (see below) |
| `source_language` | string | Source language full name |
| `source_language_code` | string | Source language ISO 639-1 code |
| `target_language` | string | Target language full name |
| `target_language_code` | string | Target language ISO 639-1 code |
| `detection_strategy` | string | Strategy used: `"none"`, `"dedicated"`, or `"combined"` |

### Cultural Notes Structure

When idioms or cultural phrases are detected:

```json
{
  "cultural_notes": [
    {
      "source_phrase": "Break a leg",
      "explanation": "A theatrical idiom meaning 'good luck'",
      "target_equivalent": "¡Mucha mierda!",
      "cultural_context": "Theater tradition of wishing performers good luck by saying the opposite"
    }
  ]
}
```

---

## Error Responses

### 400 Bad Request - Validation Errors

```json
{
  "error": "Text must not exceed 10,000 characters"
}
```

```json
{
  "error": "Language must be one of: en, es, fr, de, it, pt, ja, zh, ko, ru, ar, hi"
}
```

### 401 Unauthorized

```json
{
  "error": "Unauthorized"
}
```

### 422 Unprocessable Entity

```json
{
  "error": "Translation failed"
}
```

### 429 Too Many Requests

```http
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1234567890
Retry-After: 45

{
  "error": "Rate limit exceeded",
  "message": "Too many requests to translate endpoint",
  "retry_after_seconds": 45,
  "limit": 60,
  "window": "60 seconds"
}
```

### 500 Internal Server Error

```json
{
  "error": "An error occurred during translation"
}
```

---

## Rate Limiting

- **Limit**: 60 requests per minute per user
- **Headers included in responses**:
  - `X-RateLimit-Limit`: Maximum requests allowed
  - `X-RateLimit-Remaining`: Requests remaining in current window
  - `X-RateLimit-Reset`: Unix timestamp when limit resets

---

## Configuration

### Environment Variables

```bash
# Required
GROQ_API_KEY=your_groq_api_key

# Optional
GROQ_MODEL=llama-3.3-70b-versatile              # Default model
LANGUAGE_DETECTION_STRATEGY=dedicated           # "dedicated" or "combined"
```

### Detection Strategy Configuration

Set the default strategy in your environment:

```bash
# For accuracy (default)
export LANGUAGE_DETECTION_STRATEGY=dedicated

# For speed
export LANGUAGE_DETECTION_STRATEGY=combined
```

Can be overridden per-request using the `detection_strategy` parameter.

---

## Backend Processing Flow

### Flow 1: With Target Language Provided

```
1. Request arrives with text + target_language
2. JWT authentication
3. Rate limit check (60/min per user)
4. Input validation (text ≤10k chars, valid language code)
5. Convert language code to full name (es → Spanish)
6. Build translation prompt with full language name
7. Call Groq API (llama-3.3-70b-versatile)
8. Parse JSON response
9. Convert source language name to code
10. Return response with detection_strategy="none"

Total time: ~1.5-2 seconds
API calls: 1
```

### Flow 2: Without Target Language (Dedicated Strategy)

```
1. Request arrives with only text
2. JWT authentication
3. Rate limit check
4. Input validation
5. Call 1: Dedicated language detection
   - Optimized prompt for detection only
   - Returns: {language: "Spanish", confidence: 0.98}
   - Time: ~500-800ms
6. Call 2: Translation to English
   - Uses detected language info
   - Returns full translation result
   - Time: ~1-1.5s
7. Merge detection + translation results
8. Return response with detection_strategy="dedicated"

Total time: ~2-3 seconds
API calls: 2
```

### Flow 3: Without Target Language (Combined Strategy)

```
1. Request arrives with only text
2. JWT authentication
3. Rate limit check
4. Input validation
5. Single call: Detect + Translate
   - Prompt asks LLM to detect language AND translate
   - Returns complete result in one response
   - Time: ~1.5-2 seconds
6. Parse response with all fields
7. Return response with detection_strategy="combined"

Total time: ~1.5-2 seconds
API calls: 1
```

---

## Code Architecture

### New Modules Created

1. **`GlobalbridgeBackend.AI.LanguageDetectionService`**
   - Location: `lib/globalbridge_backend/ai/language_detection_service.ex`
   - Functions:
     - `detect_language_dedicated/1` - Dedicated detection (2-step)
     - `detect_and_translate/2` - Combined detection+translation (1-step)
     - `get_language_name/1` - Code → Name mapping
     - `get_language_code/1` - Name → Code mapping
     - `get_detection_strategy/0` - Read env configuration

2. **Updated `AIValidator`**
   - Added: `validate_optional_target_language/1`
   - Allows `nil` for target_language to trigger auto-detection

3. **Updated `AIController`**
   - Modified: `translate/2` action
   - Added: `execute_translation/3` - Strategy router
   - Added: `get_detection_strategy/1` - Strategy resolver
   - Modified: `simple_translate/2` - Now uses full language names

### Data Flow

```
Request
  ↓
AIController.translate/2
  ↓
Validate inputs (AIValidator)
  ↓
Get detection strategy
  ↓
execute_translation/3
  ├─ target_lang = nil → Auto-detection
  │   ├─ :dedicated → detect_language_dedicated + simple_translate
  │   └─ :combined → detect_and_translate
  └─ target_lang present → simple_translate
      ↓
Response with full language names + codes
```

---

## Performance & Cost

### API Call Costs (Groq llama-3.3-70b-versatile)

- **Input tokens**: ~$0.05 per 1M tokens
- **Output tokens**: ~$0.20 per 1M tokens

### Average Translation Costs

| Scenario | API Calls | Avg Tokens | Est. Cost | Latency |
|----------|-----------|------------|-----------|---------|
| Direct translation (target provided) | 1 | 150 total | $0.00002 | 1.5-2s |
| Auto-detection (dedicated) | 2 | 200 total | $0.00003 | 2-3s |
| Auto-detection (combined) | 1 | 150 total | $0.00002 | 1.5-2s |

### Recommendations

- **For production**: Use `"combined"` strategy as default for cost/speed balance
- **For critical applications**: Use `"dedicated"` strategy for better accuracy
- **For rare languages**: Use `"dedicated"` strategy (more reliable detection)

---

## Testing Examples

### Test Case 1: Spanish to English (Auto-Detection, Combined)

**Request:**
```bash
curl -X POST http://localhost:4000/api/v1/ai/translate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Me encanta programar", "detection_strategy": "combined"}'
```

**Expected Response:**
```json
{
  "success": true,
  "translation": "I love programming",
  "confidence": 0.97,
  "cultural_notes": [],
  "source_language": "Spanish",
  "source_language_code": "es",
  "target_language": "English",
  "target_language_code": "en",
  "detection_strategy": "combined"
}
```

### Test Case 2: English to Spanish (Direct)

**Request:**
```bash
curl -X POST http://localhost:4000/api/v1/ai/translate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Break a leg!", "target_language": "es"}'
```

**Expected Response:**
```json
{
  "success": true,
  "translation": "¡Buena suerte!",
  "confidence": 0.95,
  "cultural_notes": [
    {
      "source_phrase": "Break a leg",
      "explanation": "Idiom meaning 'good luck'",
      "target_equivalent": "¡Mucha mierda!",
      "cultural_context": "Theater superstition"
    }
  ],
  "source_language": "English",
  "source_language_code": "en",
  "target_language": "Spanish",
  "target_language_code": "es",
  "detection_strategy": "none"
}
```

### Test Case 3: French Auto-Detection (Dedicated)

**Request:**
```bash
curl -X POST http://localhost:4000/api/v1/ai/translate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Bonjour le monde", "detection_strategy": "dedicated"}'
```

**Expected Response:**
```json
{
  "success": true,
  "translation": "Hello world",
  "confidence": 0.99,
  "cultural_notes": [],
  "source_language": "French",
  "source_language_code": "fr",
  "target_language": "English",
  "target_language_code": "en",
  "detection_strategy": "dedicated"
}
```

---

## Troubleshooting

### Issue: "GROQ_API_KEY not configured"

**Solution**: Set environment variable
```bash
export GROQ_API_KEY=your_actual_api_key
```

### Issue: Translation returns "unknown" language code

**Cause**: LLM returned language name not in mapping

**Solution**: Add to `@language_name_to_code` map in `LanguageDetectionService`

### Issue: Slow response times (>5 seconds)

**Possible causes**:
1. Using dedicated strategy (2 API calls)
2. Groq API latency issues
3. Large text input

**Solutions**:
1. Switch to combined strategy
2. Check Groq API status
3. Reduce text length if possible

---

## Future Enhancements

1. **Caching**: Cache translations for identical text+target combinations
2. **Batch API**: Support translating multiple texts in one request
3. **Streaming**: Stream translation results for long texts
4. **Custom Models**: Allow model selection per request
5. **Confidence Thresholds**: Reject low-confidence translations
6. **Language Preferences**: User-specific default target languages

---

## Related Documentation

- [AI Endpoints Overview](./ai_endpoints_overview.md)
- [Language Detection Service API](./language_detection_service.md)
- [Rate Limiting Configuration](./rate_limiting.md)
- [Cost Tracking & Optimization](./cost_optimization.md)
