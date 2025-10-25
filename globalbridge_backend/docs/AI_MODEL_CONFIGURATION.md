# AI Model Configuration Guide

## Overview

The GlobalBridge backend uses multiple AI providers to optimize for cost, performance, and capabilities:

- **Groq (Llama 70B)**: Fast, cost-effective model for translation and language detection
- **XAI (Grok)**: High-quality reasoning model for conversation summarization
- **OpenAI**: Fallback option for general-purpose tasks

## Provider Setup

### 1. Groq (Required for Translation)

**Used by:**
- LanguageDetectionAgent
- TranslatorAgent

**Model:** `llama-3.1-70b-versatile`

**Setup:**
1. Get API key from [Groq Console](https://console.groq.com/)
2. Add to `.env`:
   ```bash
   GROQ_API_KEY="gsk_your_api_key_here"
   TRANSLATION_MODEL="llama-3.1-70b-versatile"
   ```

**Pricing:** Very cost-effective (~$0.59/1M tokens)

### 2. XAI (Required for Summarization)

**Used by:**
- SummarizerAgent

**Model:** `grok-2-1212` (Grok 2)

**Setup:**
1. Get API key from [X.AI](https://x.ai/)
2. Add to `.env`:
   ```bash
   XAI_API_KEY="xai_your_api_key_here"
   SUMMARIZER_MODEL="grok-2-1212"
   ```

**API Documentation:** https://docs.x.ai/docs/models/grok-2-1212

**Pricing:** Competitive pricing for high-quality reasoning

### 3. OpenAI (Optional Fallback)

**Setup:**
```bash
OPENAI_API_KEY="sk-proj_your_api_key_here"
```

## Environment Variables

### Required Variables

```bash
# Groq API (Translation & Language Detection)
GROQ_API_KEY="gsk_..."

# XAI API (Summarization)
XAI_API_KEY="xai_..."
```

### Optional Model Overrides

```bash
# Override default models
OPENAI_MODEL="llama-3.1-70b-versatile"      # Default for general operations
TRANSLATION_MODEL="llama-3.1-70b-versatile" # Translation agent
SUMMARIZER_MODEL="grok-2-1212"              # Summarization agent
```

## Model Routing Logic

The `OpenAIServing` module automatically routes requests to the correct provider based on model name:

```elixir
# Routes to Groq
"llama-3.1-70b-versatile"
"llama-3.1-8b-instant"
"mixtral-8x7b-32768"

# Routes to XAI
"grok-2-1212"
"grok-beta"
"grok-vision-beta"

# Routes to OpenAI
"gpt-4o"
"gpt-4o-mini"
"gpt-3.5-turbo"
```

## Agent-Specific Configuration

### LanguageDetectionAgent
- **Provider:** Groq
- **Model:** `llama-3.1-70b-versatile` (via `OPENAI_MODEL`)
- **Purpose:** Detect source language for translation
- **Cost:** Very low (small prompts)

### TranslatorAgent
- **Provider:** Groq
- **Model:** `llama-3.1-70b-versatile` (via `TRANSLATION_MODEL`)
- **Purpose:** Culturally-aware translation with confidence scoring
- **Cost:** Low to medium (depends on text length)

### SummarizerAgent
- **Provider:** XAI (Grok)
- **Model:** `grok-2-1212` (via `SUMMARIZER_MODEL`)
- **Purpose:** Generate structured conversation summaries
- **Cost:** Medium (processes conversation context)
- **Features:**
  - JSON output with decisions, action items, key points
  - High reasoning capability for extracting insights

## API Endpoints

### Groq
- **Base URL:** `https://api.groq.com/openai/v1/chat/completions`
- **Compatible with:** OpenAI Chat Completions API
- **Max Tokens:** 1000 (configurable)
- **Temperature:** 0.7

### XAI
- **Base URL:** `https://api.x.ai/v1/chat/completions`
- **Compatible with:** OpenAI Chat Completions API
- **Max Tokens:** 2000 (higher for summaries)
- **Temperature:** 0.7

## Testing Configuration

To test if your configuration is working:

```bash
# Start the backend
./dev.sh -f

# Check logs for successful API initialization
# You should see logs like:
# [info] Calling groq API with model: llama-3.1-70b-versatile
# [info] Calling xai API with model: grok-2-1212
```

## Troubleshooting

### "GROQ_API_KEY not set" Error
- Ensure `GROQ_API_KEY` is in your `.env` file
- Restart the server with `./dev.sh -f`
- Check that the `.env` file is being loaded (check server startup logs)

### "XAI_API_KEY not set" Error
- Ensure `XAI_API_KEY` is in your `.env` file
- Restart the server

### Unexpected Model Routing
- Check the model name matches the routing logic
- Review logs: `[debug] Calling {provider} API with model: {model_name}`
- Verify environment variables are set correctly

### API Rate Limits
- Groq: Has generous rate limits for free tier
- XAI: Check your plan's rate limits
- Implement caching to reduce API calls (already configured)

## Cost Optimization

The current configuration is optimized for cost:

1. **Groq Llama 70B** - Very fast inference, minimal cost
2. **Grok** - High quality reasoning at competitive prices
3. **Caching Layer** - Reduces redundant API calls
4. **Cost Tracking** - Monitor usage via `CostTracker` module

## Alternative Models

### Groq Models
```bash
# Faster, less capable
TRANSLATION_MODEL="llama-3.1-8b-instant"

# Balanced option
TRANSLATION_MODEL="mixtral-8x7b-32768"
```

### XAI Models
```bash
# Vision capabilities
SUMMARIZER_MODEL="grok-vision-beta"

# Beta access
SUMMARIZER_MODEL="grok-beta"
```

## Production Recommendations

1. **Set API Keys** via environment variables (not in code)
2. **Monitor Costs** using the built-in `CostTracker`
3. **Enable Caching** (already configured)
4. **Set Rate Limits** in `.env` for API protection
5. **Monitor Logs** for API errors and retries

## Support

- **Groq Issues:** [Groq Discord](https://groq.com/discord)
- **XAI Issues:** [X.AI Documentation](https://docs.x.ai/)
- **Backend Issues:** Check `backend.log` file
