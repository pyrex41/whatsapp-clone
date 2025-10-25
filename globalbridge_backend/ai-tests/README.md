# Translation API Test Cases

This directory contains comprehensive test cases for the Translation API endpoint `/api/v1/ai/translate`.

## Test Cases File

- `translation_test_cases.json` - JSON array of test cases with request/response specifications

## How to Run Tests

### Manual Testing with curl

Each test case in the JSON file includes the exact request structure. You can run them manually:

```bash
# Example: Basic translation test
curl -X POST 'http://localhost:4000/api/v1/ai/translate' \
  -H 'Content-Type: application/json' \
  -d '{
    "text": "Hello, how are you?",
    "target_language": "es"
  }'
```

### Automated Testing Script

Create a simple test runner script:

```bash
#!/bin/bash
# test_runner.sh

TEST_FILE="translation_test_cases.json"
BASE_URL="http://localhost:4000"

echo "Running Translation API Tests..."
echo "================================="

# Read JSON and run each test
jq -c '.[]' "$TEST_FILE" | while read -r test_case; do
  id=$(echo "$test_case" | jq -r '.id')
  description=$(echo "$test_case" | jq -r '.description')

  echo ""
  echo "Test: $id"
  echo "Description: $description"

  # Extract request body
  request_body=$(echo "$test_case" | jq '.request.body')

  # Make the request
  response=$(curl -s -X POST "$BASE_URL/api/v1/ai/translate" \
    -H 'Content-Type: application/json' \
    -d "$request_body")

  echo "Response: $response"

  # Basic validation - check if success field exists
  if echo "$response" | jq -e '.success' >/dev/null 2>&1; then
    echo "✅ Success response received"
  elif echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    echo "ℹ️  Error response (expected for error tests)"
  else
    echo "❌ Invalid response format"
  fi

  echo "---"
done
```

### Test Categories

The test cases cover:

1. **Basic Translations** - Simple text in various language pairs
2. **Idiom Detection** - Cultural idioms that should trigger notes
3. **Language Detection** - Auto-detection of source language
4. **Edge Cases** - Emojis, code snippets, mixed languages, long text
5. **Error Handling** - Missing parameters, invalid inputs
6. **Cultural Context** - Holiday references, slang, business formality
7. **Technical Content** - Jargon, numbers, dates

### Expected Results

- **Success tests**: Should return `{"success": true, ...}` with translation
- **Idiom tests**: Should include `cultural_notes` array with explanations
- **Error tests**: Should return `{"error": "..."}` with appropriate message
- **Confidence scores**: Typically 0.90+ for good translations

### Rate Limiting

The API has rate limits (60 requests/minute default). If you run many tests quickly, you may hit:

```json
{
  "error": "Rate limit exceeded",
  "message": "Too many requests to translate endpoint",
  "retry_after_seconds": 42,
  "limit": 60,
  "window": "60 seconds"
}
```

Wait for the `retry_after_seconds` before continuing.

### Dev Mode

Make sure the server is running in dev mode for testing without authentication:

```elixir
# config/dev.exs
config :globalbridge_backend, dev_mode: true
```

## Test Case Structure

Each test case has:

```json
{
  "id": "unique_identifier",
  "description": "What the test validates",
  "request": {
    "method": "POST",
    "url": "endpoint_url",
    "headers": {"Content-Type": "application/json"},
    "body": {"text": "...", "target_language": "..."}
  },
  "expected": {
    "success": true,
    "translation": "expected text",
    "confidence": 0.99,
    "cultural_notes": [],
    "source_language": "English",
    "target_language": "es"
  },
  "notes": "Additional context"
}
```

## Adding New Tests

To add new test cases:

1. Edit `translation_test_cases.json`
2. Add a new object to the array
3. Follow the existing structure
4. Test manually first to verify expected results
5. Update this README if adding new categories