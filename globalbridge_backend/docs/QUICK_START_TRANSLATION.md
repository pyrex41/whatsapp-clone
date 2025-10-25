# Translation Endpoint - Quick Start

## 🚀 TL;DR

Target language is now **optional**. When omitted, we auto-detect and translate to English using one of two strategies you can test and compare.

---

## 📋 Quick Examples

### Example 1: Direct Translation
```bash
POST /api/v1/ai/translate
{
  "text": "Hello world",
  "target_language": "es"
}
```
**Result:** Translates to Spanish, no detection needed

---

### Example 2: Auto-Detect (Fast)
```bash
POST /api/v1/ai/translate
{
  "text": "Hola mundo",
  "detection_strategy": "combined"
}
```
**Result:** 1 API call, detects Spanish + translates to English

---

### Example 3: Auto-Detect (Accurate)
```bash
POST /api/v1/ai/translate
{
  "text": "Hola mundo",
  "detection_strategy": "dedicated"
}
```
**Result:** 2 API calls, more accurate detection + translation

---

## ⚙️ Configuration

```bash
# Set default strategy
export LANGUAGE_DETECTION_STRATEGY=combined  # or "dedicated"
```

---

## 🔍 Which Strategy to Use?

| Use Case | Strategy | Why |
|----------|----------|-----|
| Production | `combined` | Faster, cheaper, good accuracy |
| Critical apps | `dedicated` | Best accuracy |
| Rare languages | `dedicated` | More reliable detection |
| Common languages | `combined` | Fast enough |

---

## 📊 Response Format

```json
{
  "success": true,
  "translation": "translated text",
  "confidence": 0.98,
  "cultural_notes": [],
  "source_language": "Spanish",
  "source_language_code": "es",
  "target_language": "English",
  "target_language_code": "en",
  "detection_strategy": "combined"
}
```

---

## 🧪 Test Both Strategies

```bash
# Set your token
TOKEN="your_jwt_token"

# Test combined (fast)
curl -X POST http://localhost:4000/api/v1/ai/translate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Bonjour", "detection_strategy": "combined"}'

# Test dedicated (accurate)
curl -X POST http://localhost:4000/api/v1/ai/translate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Bonjour", "detection_strategy": "dedicated"}'

# Compare results!
```

---

## 📚 Full Documentation

See `docs/translation_endpoint_guide.md` for complete details.

## 📝 Implementation Details

See `docs/TRANSLATION_IMPLEMENTATION_SUMMARY.md` for architecture overview.
