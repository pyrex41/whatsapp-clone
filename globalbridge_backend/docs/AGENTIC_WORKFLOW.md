# Agentic Workflow: Frontend to AI Agents

## Overview

This document explains how frontend requests flow through the system to the AGENS agents, detailing the complete agentic workflow from HTTP request to LLM response.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                     Frontend (iOS/React)                         │
│                 HTTP POST /api/ai/* requests                     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Phoenix HTTP Layer                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │          AIController (REST Endpoints)                   │   │
│  │  - /translate, /summarize_thread, /search_semantic       │   │
│  │  - /extract_tasks, /analyze_tone, /vec_health            │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
┌───────────┐      ┌──────────────┐   ┌─────────────┐
│Validation │      │Authorization │   │Rate Limiting│
│ (Input)   │      │  (Thread)    │   │  (User)     │
└─────┬─────┘      └──────┬───────┘   └──────┬──────┘
      └────────────────────┼──────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Business Logic Layer                          │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐         │
│  │Translation │  │Summarization │  │Semantic Search   │         │
│  │   Job      │  │     Job      │  │   + RAG          │         │
│  └─────┬──────┘  └──────┬───────┘  └────────┬─────────┘         │
└────────┼─────────────────┼───────────────────┼───────────────────┘
         │                 │                   │
         ▼                 ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AGENS Agent Layer                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐   │
│  │LanguageDetection │  │  Translator      │  │ Summarizer   │   │
│  │     Agent        │  │     Agent        │  │    Agent     │   │
│  │  (Groq Llama)    │  │  (Groq Llama)    │  │  (XAI Grok)  │   │
│  └────────┬─────────┘  └────────┬─────────┘  └──────┬───────┘   │
└───────────┼──────────────────────┼────────────────────┼──────────┘
            └──────────────────────┼────────────────────┘
                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                  OpenAIServing (GenServer)                       │
│           Multi-Provider LLM Gateway                             │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Route by Model:                                          │   │
│  │  - "llama-*" → Groq API                                   │   │
│  │  - "grok-*"  → XAI API                                    │   │
│  │  - Other     → OpenAI API                                 │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────┬───────────────┬──────────────┬────────────────┘
                   │               │              │
                   ▼               ▼              ▼
        ┌──────────────┐  ┌─────────────┐  ┌──────────────┐
        │   Groq API   │  │  XAI API    │  │  OpenAI API  │
        │  (Llama 70B) │  │  (Grok 2)   │  │  (Fallback)  │
        └──────────────┘  └─────────────┘  └──────────────┘
```

## Request Flow Details

### 1. Translation Request

**Endpoint:** `POST /api/ai/translate`

**Request Body:**
```json
{
  "text": "Hello, how are you?",
  "target_language": "es",
  "source_language": "en"
}
```

**Flow:**
```
1. AIController.translate/2
   ├─ Validate input (text, languages)
   ├─ Check authentication & authorization
   ├─ Rate limiting check
   └─ Execute TranslationJob
      │
2. TranslationJob (Agens.Job)
   ├─ Step 1: LanguageDetectionAgent
   │   ├─ Agent Config: identity, context, constraints
   │   ├─ Call OpenAIServing
   │   ├─ Route to Groq (llama-3.1-70b-versatile)
   │   ├─ Detect: "English"
   │   └─ Pass result to next step
   │
   └─ Step 2: TranslatorAgent
       ├─ Use CulturalContextTool.pre/1
       │   └─ Analyze cultural elements
       ├─ Build translation prompt with cultural context
       ├─ Call OpenAIServing
       ├─ Route to Groq (llama-3.1-70b-versatile)
       ├─ Get: "Translation: Hola, ¿cómo estás?\nConfidence: 0.95"
       └─ Parse result → {:ok, %{translation: "...", confidence: 0.95}}
```

**Response:**
```json
{
  "success": true,
  "translation": {
    "translation": "Hola, ¿cómo estás?",
    "confidence": 0.95
  },
  "source_language": "en",
  "target_language": "es"
}
```

### 2. Thread Summarization Request

**Endpoint:** `POST /api/ai/summarize_thread`

**Request Body:**
```json
{
  "thread_id": "abc123-...",
  "max_length": 200
}
```

**Flow:**
```
1. AIController.summarize_thread/2
   ├─ Validate thread_id, max_length
   ├─ Check user has access to thread
   ├─ Rate limiting check
   └─ Execute SummarizationJob
      │
2. SummarizationJob.summarize_thread/3
   │
   ├─ Step 1: RAGRetrieverAgent.retrieve/3
   │   ├─ Generate search query from objective
   │   │   └─ "comprehensive summary" → "key points important information main topics"
   │   ├─ Call SemanticSearch.search_with_context/3
   │   │   ├─ Generate embedding for query
   │   │   ├─ Search vec0 virtual table (message_embeddings)
   │   │   ├─ Apply recency bias (weight: 0.3)
   │   │   ├─ Return top 20 messages
   │   │   └─ Build context string (max 8000 tokens)
   │   └─ Return: {:ok, %{results: [...], context: "formatted context"}}
   │
   └─ Step 2: SummarizerAgent.summarize/3
       ├─ Build full prompt with:
       │   ├─ Conversation context (from RAG)
       │   ├─ Agent identity & context
       │   └─ Structured JSON output constraints
       ├─ Call OpenAIServing
       ├─ Route to XAI (grok-2-1212) - detected via "summarize" keyword
       ├─ Get JSON response
       └─ Parse to structured summary:
           {
             "summary": "Team discussed project timeline...",
             "decisions": ["Approved budget increase"],
             "action_items": ["John: Update roadmap by Friday"],
             "key_points": ["Q4 deadline confirmed"],
             "participants": ["Alice", "Bob", "John"],
             "confidence_score": 0.92
           }
```

**Response:**
```json
{
  "success": true,
  "summary": {
    "thread_id": "abc123",
    "objective": "comprehensive summary",
    "summary": {
      "summary": "Team discussed project timeline...",
      "decisions": ["Approved budget increase"],
      "action_items": ["John: Update roadmap by Friday"],
      "key_points": ["Q4 deadline confirmed"],
      "participants": ["Alice", "Bob", "John"],
      "confidence_score": 0.92
    },
    "retrieved_messages": 18
  },
  "thread_id": "abc123",
  "max_length": 200
}
```

### 3. Semantic Search Request

**Endpoint:** `POST /api/ai/search_semantic`

**Request Body:**
```json
{
  "query": "project deadline",
  "thread_id": "abc123-...",
  "limit": 10,
  "recency_bias": true
}
```

**Flow:**
```
1. AIController.search_semantic/2
   ├─ Validate query, thread_id, limit
   ├─ Check thread access
   └─ Call SemanticSearch.search/3
      │
2. SemanticSearch.search/3
   ├─ Generate embedding for query
   │   └─ EmbeddingService.generate("project deadline")
   ├─ Get thread's shard database
   ├─ Query vec0 virtual table:
   │   SELECT message_id, content, distance
   │   FROM message_embeddings
   │   WHERE embedding MATCH ?
   │   ORDER BY distance
   │   LIMIT 10
   ├─ Apply recency bias formula:
   │   final_score = (1 - recency_weight) * similarity + recency_weight * recency_score
   └─ Return ranked results
```

**Response:**
```json
{
  "success": true,
  "query": "project deadline",
  "results": [
    {
      "message_id": "msg-1",
      "content": "We need to finish by Dec 31st",
      "score": 0.94,
      "timestamp": "2024-10-20T10:00:00Z"
    }
  ],
  "total_results": 8,
  "thread_id": "abc123"
}
```

### 4. Task Extraction Request

**Endpoint:** `POST /api/ai/extract_tasks`

**Request Body:**
```json
{
  "thread_id": "abc123-...",
  "query": "tasks, deadlines, decisions"
}
```

**Flow:**
```
1. AIController.extract_tasks/2
   ├─ Validate thread_id, query
   ├─ Check thread access
   └─ Call TaskExtractionTool.extract_from_thread/3
      │
2. TaskExtractionTool.extract_from_thread/3
   ├─ Generate embedding for query
   ├─ RAG search (top 20 messages, recency_weight: 0.3)
   ├─ Build context from retrieved messages
   └─ Extract structured data:
       ├─ Use Agens.Tool behavior callbacks
       ├─ pre/1: Format extraction prompt
       ├─ execute/1: Call LLM for extraction
       └─ post/1: Parse to structured format
           {
             "tasks": [
               {
                 "id": "task-1",
                 "description": "Update documentation",
                 "assignee": "Alice",
                 "priority": "high",
                 "status": "pending",
                 "confidence": 0.88
               }
             ],
             "deadlines": [...],
             "decisions": [...]
           }
```

## Model Routing Logic

The `OpenAIServing` module uses **context-aware routing**:

```elixir
# 1. Check prompt keywords
if prompt contains "summarize|summary|analyze this conversation":
  model = SUMMARIZER_MODEL (grok-2-1212) → XAI API

else if prompt contains "translate|translation":
  model = TRANSLATION_MODEL (llama-3.1-70b-versatile) → Groq API

else if prompt contains "detect.*language":
  model = OPENAI_MODEL (llama-3.1-70b-versatile) → Groq API

else:
  model = OPENAI_MODEL (default) → Provider based on model name

# 2. Determine provider by model name
if model starts with "grok-":
  provider = XAI

else if model contains "llama" or "mixtral":
  provider = Groq

else:
  provider = OpenAI
```

## Agent Execution Pattern

All agents follow this pattern:

```elixir
1. Configuration Phase (Agent.Config)
   ├─ Define agent name (:translator_agent)
   ├─ Specify serving (:openai_serving)
   ├─ Optional tool (CulturalContextTool)
   └─ Prompt structure:
       ├─ identity: "You are an expert translator..."
       ├─ context: "Your task is to..."
       └─ constraints: "Output in this format..."

2. Execution Phase
   ├─ Tool pre-processing (if tool specified)
   │   └─ CulturalContextTool.pre(input) → cultural analysis
   ├─ Prompt construction
   │   └─ Combine: tool output + agent prompt + user input
   ├─ GenServer.call(:openai_serving, {:run, message})
   │   └─ OpenAIServing routes to appropriate provider
   └─ Parse result
       └─ Agent-specific parsing (e.g., parse_result/1)

3. Response Phase
   ├─ Validate parsed output
   ├─ Return structured data
   └─ Log telemetry & costs
```

## RAG (Retrieval-Augmented Generation) Flow

Used in: Summarization, Task Extraction, Semantic Search

```
1. Query Analysis
   ├─ User query → "summarize this thread"
   └─ Generate optimized search query
       └─ "key points important information main topics"

2. Embedding Generation
   ├─ EmbeddingService.generate(query)
   └─ Returns: vector embedding [384 dimensions]

3. Vector Search
   ├─ Access thread's shard database
   ├─ Query vec0 virtual table: message_embeddings
   ├─ Cosine similarity search
   └─ Return top-k matches

4. Recency Bias (optional)
   ├─ Calculate time decay score
   ├─ Blend: similarity × (1-w) + recency × w
   └─ Re-rank results

5. Context Building
   ├─ Format retrieved messages
   ├─ Truncate to max length (8000 tokens)
   └─ Build structured context string

6. LLM Processing
   ├─ Context + Instructions → LLM
   └─ Generate: summary, tasks, or answers
```

## Caching Strategy

Multiple caching layers optimize performance:

```
1. Embedding Cache (Cachex :ai_cache)
   ├─ Key: hash(text)
   ├─ TTL: 24 hours
   └─ Saves: ~$0.0001 per repeated text

2. Translation Cache
   ├─ Key: hash(text + source_lang + target_lang)
   ├─ TTL: 7 days
   └─ Saves: ~$0.001 per repeated translation

3. Semantic Search Cache
   ├─ Key: hash(query + thread_id + params)
   ├─ TTL: 1 hour
   └─ Saves: RAG retrieval time (~100-200ms)

4. Summary Cache
   ├─ Key: thread_id + hash(recent_messages)
   ├─ TTL: 30 minutes
   └─ Saves: Expensive summarization calls
```

## Cost Tracking

Every AI operation is tracked:

```elixir
# In OpenAIServing, after each API call:
CostTracker.track_usage(%{
  model: "llama-3.1-70b-versatile",
  provider: :groq,
  operation: :translation,
  input_tokens: 150,
  output_tokens: 50,
  estimated_cost: 0.00012,  # $0.59/1M tokens
  user_id: user_id,
  timestamp: DateTime.utc_now()
})

# Query costs:
CostTracker.get_user_usage(user_id, :daily)
CostTracker.get_total_cost(:monthly)
```

## Error Handling & Resilience

Each layer has error handling:

```
1. HTTP Layer (AIController)
   ├─ Input validation
   ├─ Authentication/authorization
   ├─ Rate limiting
   └─ Safe error responses (no internal details)

2. Business Logic Layer (Jobs/Agents)
   ├─ Graceful degradation
   ├─ Fallback models
   └─ Retry logic (exponential backoff)

3. LLM Layer (OpenAIServing)
   ├─ Provider failover
   ├─ Timeout handling (30s per request)
   ├─ Response validation
   └─ Logging for debugging

4. Storage Layer (RAG/Vector)
   ├─ Handle missing embeddings
   ├─ Empty result sets
   └─ Shard database errors
```

## Performance Metrics

Typical latencies:

| Operation | RAG Search | LLM Call | Total | Cost |
|-----------|------------|----------|-------|------|
| Translation | N/A | 200-500ms | 300-600ms | $0.0002 |
| Summarization | 100-200ms | 1-2s | 1.5-2.5s | $0.003 |
| Semantic Search | 50-150ms | N/A | 50-150ms | $0.0001 |
| Task Extraction | 100-200ms | 800ms-1.5s | 1-2s | $0.002 |

## Environment Variables Reference

```bash
# Required
GROQ_API_KEY="gsk_..."
XAI_API_KEY="xai_..."

# Model Selection
OPENAI_MODEL="llama-3.1-70b-versatile"      # Default/Language Detection
TRANSLATION_MODEL="llama-3.1-70b-versatile" # Translation
SUMMARIZER_MODEL="grok-2-1212"              # Summarization

# Optional Overrides
SQLITE_VEC_PATH="/path/to/vec0.dylib"       # Vector search
```

## API Endpoints Summary

| Endpoint | Method | Agent(s) Used | Model | Purpose |
|----------|--------|---------------|-------|---------|
| `/api/ai/translate` | POST | LanguageDetection, Translator | Groq Llama 70B | Text translation |
| `/api/ai/summarize_thread` | POST | RAGRetriever, Summarizer | XAI Grok 2 | Thread summarization |
| `/api/ai/search_semantic` | POST | None (direct RAG) | N/A | Semantic search |
| `/api/ai/extract_tasks` | POST | TaskExtractionTool | Groq Llama 70B | Task extraction |
| `/api/ai/analyze_tone` | POST | ToneAnalyzer (TODO) | TBD | Sentiment analysis |
| `/api/ai/vec_health` | POST | None | N/A | Vector DB health check |

## Next Steps for Frontend Integration

1. **Add API Keys** to `.env`
2. **Test endpoints** with curl/Postman
3. **Implement retry logic** in frontend
4. **Add loading states** for async operations
5. **Cache responses** client-side when appropriate
6. **Monitor costs** via dashboard (to be built)

---

This agentic workflow provides a robust, scalable, and cost-effective AI system for the GlobalBridge application.
