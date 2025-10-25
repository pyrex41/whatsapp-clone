# Environment Setup Guide

## Quick Setup

### 1. Copy the example .env file

```bash
cd globalbridge_backend
cp .env.example .env
```

### 2. Edit .env and add your API keys

```bash
# Edit the .env file
nano .env  # or use your preferred editor
```

### 3. Required Configuration for Translation Tests

At minimum, you need:

```bash
# Required for translation and language detection
GROQ_API_KEY="gsk_your_groq_api_key_here"

# Optional: Set detection strategy
LANGUAGE_DETECTION_STRATEGY="combined"  # or "dedicated"

# Optional: Set Groq model
GROQ_MODEL="llama-3.3-70b-versatile"

# Required for vector operations (if using vec endpoints)
SQLITE_VEC_PATH="/path/to/your/vec0.dylib"
```

---

## Getting API Keys

### Groq API Key (Required for Translation)

1. Go to https://console.groq.com/
2. Sign up or log in
3. Navigate to API Keys
4. Create a new API key
5. Copy the key (format: `gsk_...`)
6. Add to .env: `GROQ_API_KEY="gsk_your_key_here"`

**Cost:** Groq offers generous free tier with fast inference

---

## Configuration Options

### Language Detection Strategy

Choose which strategy to use by default:

```bash
# Fast, good accuracy (recommended for production)
LANGUAGE_DETECTION_STRATEGY="combined"

# Best accuracy (recommended for critical applications)
LANGUAGE_DETECTION_STRATEGY="dedicated"
```

**Can be overridden per-request** in the API call.

### Groq Model Selection

```bash
# Recommended (latest, best performance)
GROQ_MODEL="llama-3.3-70b-versatile"

# Alternative (if you prefer older version)
GROQ_MODEL="llama-3.1-70b-versatile"
```

### SQLite Vector Extension

Required for semantic search and RAG features:

```bash
# macOS
SQLITE_VEC_PATH="/usr/local/lib/vec0.dylib"

# Linux
SQLITE_VEC_PATH="/usr/local/lib/vec0.so"

# Or wherever you installed sqlite-vec
```

**To install sqlite-vec:** https://github.com/asg017/sqlite-vec

---

## Testing Your Configuration

### Test that .env is loaded

```bash
cd globalbridge_backend
mix test test/globalbridge_backend/ai/language_detection_service_test.exs --exclude integration
```

You should see:
```
✓ Loaded environment variables from .env
```

### Test with actual API calls

```bash
# Quick integration test
mix test test/globalbridge_backend/ai/language_detection_service_test.exs --include integration --max-cases 1
```

If configured correctly, you'll see successful API calls.

### Run full test suite

```bash
./test_translation_strategies.sh
```

---

## Troubleshooting

### "GROQ_API_KEY not configured" error

**Solution:** Make sure your .env file has:
```bash
GROQ_API_KEY="gsk_your_actual_key_here"
```

No quotes inside quotes, no extra spaces.

### "SQLITE_VEC_PATH not set" warning

**Solution:** Either:
1. Install sqlite-vec and set the path in .env, or
2. Ignore if you're not using vector/semantic search features

### .env not loading in tests

**Solution:** The `test/test_helper.exs` now loads .env automatically. Make sure:
1. The .env file is in the `globalbridge_backend/` directory
2. You're running tests from the `globalbridge_backend/` directory
3. The .env file is properly formatted (no syntax errors)

### Tests still failing with "API key not set"

**Debug steps:**
```bash
# 1. Check if .env exists
ls -la .env

# 2. Check .env content (without exposing keys)
head -5 .env

# 3. Manually export and test
export GROQ_API_KEY="your_key"
mix test test/globalbridge_backend/ai/language_detection_service_test.exs --include integration --max-cases 1
```

---

## Environment Variables Reference

### Required for Translation

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GROQ_API_KEY` | ✅ Yes | - | Groq API key for LLM calls |

### Optional Translation Config

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LANGUAGE_DETECTION_STRATEGY` | ❌ No | `"dedicated"` | Detection strategy: `"combined"` or `"dedicated"` |
| `GROQ_MODEL` | ❌ No | `"llama-3.3-70b-versatile"` | Groq model to use |
| `TRANSLATION_MODEL` | ❌ No | `"llama-3.1-70b-versatile"` | Specific model for translation |

### Optional Vector/RAG Config

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SQLITE_VEC_PATH` | ⚠️ Conditional | - | Path to vec0 shared library (required for vector ops) |

### Optional Other APIs

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `XAI_API_KEY` | ⚠️ Conditional | - | For Grok models (summarization) |
| `OPENAI_API_KEY` | ❌ No | - | For OpenAI models (if not using Groq) |
| `ANTHROPIC_API_KEY` | ❌ No | - | For Claude models (task-master) |

---

## Production Checklist

Before deploying to production:

- [ ] All API keys set in production environment
- [ ] `LANGUAGE_DETECTION_STRATEGY` configured based on testing results
- [ ] `SQLITE_VEC_PATH` set correctly for your platform
- [ ] Rate limits configured appropriately
- [ ] Tested both detection strategies
- [ ] Verified cost projections
- [ ] Monitoring/alerting configured

---

## Example .env File

```bash
# ============================================
# Translation & Language Detection (Required)
# ============================================
GROQ_API_KEY="gsk_your_groq_api_key_here"
GROQ_MODEL="llama-3.3-70b-versatile"
LANGUAGE_DETECTION_STRATEGY="combined"

# ============================================
# Vector Database (Optional)
# ============================================
SQLITE_VEC_PATH="/usr/local/lib/vec0.dylib"

# ============================================
# Other AI Models (Optional)
# ============================================
XAI_API_KEY="xai_your_xai_key_here"
SUMMARIZER_MODEL="grok-2-1212"

# ============================================
# Rate Limiting (Optional - uses defaults)
# ============================================
AI_RATE_LIMIT_TRANSLATE=60
AI_RATE_LIMIT_SUMMARIZE_THREAD=10
```

---

## Next Steps

1. ✅ Copy .env.example → .env
2. ✅ Add GROQ_API_KEY
3. ✅ Set LANGUAGE_DETECTION_STRATEGY
4. ✅ (Optional) Set SQLITE_VEC_PATH
5. ✅ Test: `./test_translation_strategies.sh`
6. ✅ Review results and choose strategy
7. ✅ Deploy to production

---

## Support

- **Can't get API key?** Check https://console.groq.com/
- **Tests failing?** Review error messages and check configuration
- **Need help?** See docs/TESTING_TRANSLATION_STRATEGIES.md for detailed troubleshooting
