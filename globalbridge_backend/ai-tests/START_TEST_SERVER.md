# Translation API Test Server

## Quick Start

### Start the Test Server

```bash
cd ai-tests
node server.js
```

Or using npm:

```bash
cd ai-tests
npm start
```

The server will start on **http://localhost:3030**

### Open in Browser

Once the server is running, open your browser to:

```
http://localhost:3030
```

## Features

### Visual Test Interface

- **Run All Tests** - Execute all 19 test cases sequentially
- **Run Selected** - Check specific tests and run only those
- **Individual Test Runs** - Click "Run" on any test to execute it alone
- **Clear Results** - Reset all test results

### Real-Time Results

- ✓ **Passed** - Green checkmark for successful tests
- ✗ **Failed** - Red X for failed tests
- ○ **Pending** - Gray circle for tests not yet run

### Test Details

Click on any test to expand and see:
- Request details (method, URL, headers, body)
- Expected vs Actual response comparison
- Response time in milliseconds
- HTTP status code
- Error messages (if any)

### Filtering

Filter tests by status:
- **All Tests** - Show everything
- **Passed** - Only successful tests
- **Failed** - Only failed tests
- **Not Run** - Tests that haven't been executed yet

### Statistics

Live counters showing:
- Total passed tests
- Total failed tests
- Total available tests

## Test Cases

The server loads tests from `translation_test_cases.json` which includes:

### Basic Translations
- English to Spanish
- Spanish to English (auto-detect)
- English to Japanese
- English to French
- English to German
- English to Arabic

### Idiom Detection
- "Raining cats and dogs" (English)
- Chinese idiom "一石二鸟"
- Modern slang ("lit", "GOAT")

### Special Cases
- Long text (paragraphs)
- Mixed language text
- Emoji handling
- Technical jargon
- Code snippets
- Numbers and dates
- Business formal tone
- Cultural references (Thanksgiving)

### Error Cases
- Missing target language
- Missing text parameter
- Invalid language code
- Empty text

## API Endpoints

The test server exposes these endpoints:

### GET /api/tests
Returns all test cases from the JSON file.

**Response:**
```json
[
  {
    "id": "basic_en_to_es",
    "description": "Basic English to Spanish translation",
    "request": { ... },
    "expected": { ... },
    "notes": "..."
  },
  ...
]
```

### POST /api/run/:testId
Runs a specific test by ID.

**Example:**
```bash
curl -X POST http://localhost:3030/api/run/basic_en_to_es
```

**Response:**
```json
{
  "testId": "basic_en_to_es",
  "passed": true,
  "response": {
    "success": true,
    "translation": "Hola, ¿cómo estás?",
    "confidence": 0.99,
    ...
  },
  "expected": { ... },
  "statusCode": 200,
  "responseTime": 1247,
  "timestamp": "2025-01-24T..."
}
```

## Test Comparison Logic

The server compares actual responses with expected results using these rules:

1. **Error Tests** - Checks if error message is present
2. **Success Field** - Must match if specified
3. **Cultural Notes** - If `hasCulturalNotes: true`, checks array has items
4. **Confidence** - Allows ±0.1 variance from expected
5. **Languages** - Flexible matching (contains check)
6. **Translation** - Checks existence (not exact match due to LLM variation)

## Architecture

```
┌─────────────────┐
│   Browser UI    │
│  (localhost:    │
│     3030)       │
└────────┬────────┘
         │
         │ HTTP Requests
         │
┌────────▼────────┐      ┌──────────────────┐
│  Node.js Test   │──────▶│  Translation API │
│     Server      │◀──────│  (localhost:4000)│
│  (server.js)    │ Fetch └──────────────────┘
└─────────────────┘
         │
         │ Read
         │
┌────────▼────────────────┐
│ translation_test_       │
│  cases.json             │
└─────────────────────────┘
```

## Customization

### Add New Tests

Edit `translation_test_cases.json` and add your test:

```json
{
  "id": "my_custom_test",
  "description": "Description here",
  "request": {
    "method": "POST",
    "url": "http://localhost:4000/api/v1/ai/translate",
    "headers": {
      "Content-Type": "application/json"
    },
    "body": {
      "text": "Your text",
      "target_language": "es"
    }
  },
  "expected": {
    "success": true,
    "confidence": 0.90
  },
  "notes": "Test notes"
}
```

Restart the server to load new tests.

### Change Server Port

Edit `server.js` line 6:

```javascript
const PORT = 3030;  // Change to your preferred port
```

### Modify Comparison Logic

Edit the `compareResults()` function in `server.js` to customize how tests are validated.

## Tips

1. **Run Backend First** - Make sure the Phoenix server is running on port 4000
2. **Dev Mode** - Ensure dev mode is enabled in `config/dev.exs`
3. **Browser Console** - Open DevTools to see request/response details
4. **Test Order** - Tests run sequentially with a 100ms delay between each
5. **Fresh Results** - Click "Clear Results" to reset and run tests again

## Troubleshooting

### "Error loading tests"
- Check that `translation_test_cases.json` exists
- Verify JSON syntax is valid

### "Failed to fetch" errors
- Ensure backend API is running on `http://localhost:4000`
- Check dev mode is enabled
- Verify network connectivity

### Tests timeout
- Increase `recv_timeout` in backend if translations are slow
- Check Groq API key is configured

### Can't access http://localhost:3030
- Verify Node.js server is running
- Check port 3030 is not in use
- Try `http://127.0.0.1:3030` instead

## Example Session

```bash
# Terminal 1: Start backend
cd globalbridge_backend
./dev.sh -f

# Terminal 2: Start test server
cd globalbridge_backend/ai-tests
node server.js

# Browser: http://localhost:3030
# Click "Run All Tests" and watch results appear!
```

## Screenshot Guide

### Main Interface
- Header with title and description
- Control buttons (Run All, Run Selected, Clear)
- Live statistics (Passed/Failed/Total)
- Filter buttons
- Test list with expandable details

### Test States
- **Pending** (gray) - Not run yet
- **Running** (yellow, pulsing) - Currently executing
- **Passed** (green) - Successful
- **Failed** (red) - Failed validation

### Test Details
Click any test to see:
- Full request JSON
- Expected vs Actual comparison
- Error details (if failed)
- Response metadata

Enjoy testing! 🧪✨
