# AI Backend Infrastructure PRD
# GlobalBridge Messenger - Elixir/Phoenix with Agens + RAG

**Version:** 2.0
**Last Updated:** 2025-10-23
**Document Type:** Technical Product Requirements
**Status:** Implementation Planning
**Architecture Approach:** Agens (v0.1.3) Multi-Agent Framework

---

## Executive Summary

Build a production-ready AI backend for GlobalBridge Messenger targeting the **International Communicator** persona. The system provides intelligent translation, cultural context awareness, and semantic search using:

- **Agens Elixir** (v0.1.3) for native multi-agent workflows leveraging OTP/BEAM concurrency
- **SQLite vector extension (sqlite-vec)** for RAG (Retrieval Augmented Generation)
- **Per-thread vector storage** for privacy, scalability, and data co-location
- **OpenAI/Anthropic providers** with cost optimization and caching

**Key Architectural Decision:** Replacing LangChain Elixir with Agens provides better alignment with Elixir's strengths:
- ✅ Native OTP/GenServer patterns for agent orchestration
- ✅ Lightweight with zero unnecessary abstraction overhead
- ✅ Superior support for function calling via Agens.Tool
- ✅ Natural multi-step job/step workflows mapping to PRD chains
- ✅ Production-ready proof-of-concept (v0.1.3)

**Core Capabilities:**
1. Real-time translation with cultural context hints
2. Formality and tone analysis for cross-cultural communication
3. Slang/idiom explanations
4. Multilingual semantic search powered by RAG
5. Intelligent processing: task extraction, summarization, structured data

**Performance Targets:**
- Translation: <5s (P95)
- Thread summarization: <10s for 100 messages
- Semantic search: <500ms per query
- Embedding generation: <2s per message (async background)

**Cost Optimization:**
- Redis caching for translations (7-day TTL)
- Batch embedding generation (10 messages at once)
- Model selection by complexity (GPT-4 for translation, Claude Haiku for summaries)
- Estimated cost: $42/month for 100 translations/day per user

---

## 1. Problem Statement & User Needs

### 1.1 Target Persona: International Communicator

**Profile:**
- Age: 25-45
- Occupation: Freelancers, remote workers, NGO coordinators working across 2-4 time zones
- Technical Proficiency: High (comfortable with multiple communication platforms)
- Languages: Multilingual teams (English + 1-2 other languages)

**Pain Points the AI Backend Solves:**

1. **Language Barriers:**
   - "I need to translate messages quickly but Google Translate misses cultural context"
   - "I don't know if this phrase sounds formal or casual in Spanish"
   - "What does 'ASAP' mean in Indian business culture?"

2. **Information Overload:**
   - "I have 200 unread messages across 3 languages - what did we decide?"
   - "Did anyone mention a deadline in yesterday's discussion?"
   - "I need to find when we talked about the budget, but I don't remember the exact words"

3. **Cultural Misunderstandings:**
   - "This message sounds rude in English but might be normal in their culture"
   - "I want to adjust my message formality for a Japanese client"
   - "Does this idiom translate well to German business context?"

### 1.2 Success Criteria

**Must Have (MVP):**
- ✅ Translate messages with 85%+ accuracy across 5+ languages
- ✅ Detect and explain cultural idioms with confidence scores
- ✅ Semantic search finds relevant messages across languages (80%+ precision)
- ✅ Extract action items and deadlines with 75%+ accuracy
- ✅ Summarize threads capturing key decisions and unresolved questions

**Performance Requirements:**
- Translation latency: <5s for 90% of requests
- Search latency: <500ms for 95% of queries
- Uptime: 99.5% (excluding AI provider outages)
- Cost: <$0.05 per active user per day

---

## 2. Technical Architecture

### 2.1 System Overview with Agens Multi-Agent Framework

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS Client (Swift)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  AIService.swift                                     │   │
│  │  - translate(text, targetLang)                       │   │
│  │  - analyzeTone(text)                                 │   │
│  │  - summarizeThread(threadId)                         │   │
│  │  - searchSemantic(query, threadId)                   │   │
│  └──────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTPS POST /api/v1/ai/*
┌────────────────────────────▼────────────────────────────────┐
│              Phoenix Backend (Elixir)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  MessagingWeb.AIController                           │   │
│  │  - translate/2                                       │   │
│  │  - analyze_tone/2                                    │   │
│  │  - summarize_thread/2                                │   │
│  │  - search_semantic/2                                 │   │
│  │  - extract_tasks/2                                   │   │
│  └─────────────┬────────────────────────────────────────┘   │
│                │                                             │
│  ┌─────────────▼────────────────────────────────────────┐   │
│  │  Messaging.AI (Agens Multi-Agent Orchestration)     │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  TranslationJob (Agens.Job)                    │  │   │
│  │  │  ┌──────────────────────────────────────────┐  │  │   │
│  │  │  │  Step 1: TranslatorAgent                 │  │  │   │
│  │  │  │  - Language detection via LLM            │  │  │   │
│  │  │  │  - Translation with cultural context     │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  │  ┌──────────────────────────────────────────┐  │  │   │
│  │  │  │  Step 2: CulturalContextTool (Agens.Tool)│  │  │   │
│  │  │  │  - Idiom detection & explanation         │  │  │   │
│  │  │  │  - Cultural note generation              │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  SummarizationJob (Agens.Job + RAG)            │  │   │
│  │  │  ┌──────────────────────────────────────────┐  │  │   │
│  │  │  │  Step 1: RAGRetrieverAgent               │  │  │   │
│  │  │  │  - Vector search for key messages        │  │  │   │
│  │  │  │  - Context building from retrieval       │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  │  ┌──────────────────────────────────────────┐  │  │   │
│  │  │  │  Step 2: SummarizerAgent                 │  │  │   │
│  │  │  │  - LLM summarization with structure      │  │  │   │
│  │  │  │  - JSON output formatting                │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  TaskExtractionJob (Agens.Job + Function Call) │  │   │
│  │  │  - Extract tasks, deadlines, decisions         │  │   │
│  │  │  - TaskExtractionTool (Agens.Tool) for struct  │  │   │
│  │  │  - Link to source messages                     │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └─────────────┬────────────────────────────────────────┘   │
│                │                                             │
│  ┌─────────────▼────────────────────────────────────────┐   │
│  │  Messaging.AI.RAG (Vector Store & Retriever)        │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  EmbeddingService                              │  │   │
│  │  │  - Generate embeddings (OpenAI)                │  │   │
│  │  │  - Async background job (Oban)                 │  │   │
│  │  │  - Cache in Redis                              │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  VectorStore (SQLite vec0 extension)           │  │   │
│  │  │  - Per-thread vector databases                 │  │   │
│  │  │  - Cosine similarity search                    │  │   │
│  │  │  - Top-k retrieval with recency bias           │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────┐  │   │
│  │  │  Retriever & ContextBuilder                    │  │   │
│  │  │  - Semantic search across messages             │  │   │
│  │  │  - Build LLM context from results              │  │   │
│  │  │  - Merge with recent messages                  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └─────────────┬────────────────────────────────────────┘   │
└────────────────┼────────────────────────────────────────────┘
                 │
    ┌────────────┴────────────┐
    │                         │
┌───▼────────┐        ┌───────▼──────────┐
│  OpenAI    │        │  Anthropic       │
│  - GPT-4   │        │  - Claude 3.5    │
│  - Turbo   │        │    Sonnet/Haiku  │
│  - Embed   │        │                  │
│    3-small │        │                  │
└────────────┘        └──────────────────┘

┌─────────────────────────────────────────┐
│  Per-Thread SQLite Database             │
│  Path: threads/{thread_id}.db           │
│  ┌─────────────────────────────────┐   │
│  │  messages table                 │   │
│  │  - id, content, timestamp       │   │
│  │  - embedding BLOB (3072 floats) │   │
│  └─────────────────────────────────┘   │
│  ┌─────────────────────────────────┐   │
│  │  message_embeddings (vec0)      │   │
│  │  - Virtual table for similarity │   │
│  │  - Cosine distance search       │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│  Redis Cache                            │
│  - Translation cache (7-day TTL)        │
│  - Embedding cache (permanent)          │
│  - Feature flag checks                  │
└─────────────────────────────────────────┘
```

### 2.2 RAG Architecture Deep Dive

**Why RAG (Retrieval Augmented Generation)?**

Traditional LLM limitations:
- ❌ Limited context window (8K-128K tokens)
- ❌ Can't access real-time conversation data
- ❌ Generic responses without user-specific context
- ❌ Hallucinations when asked about specific past conversations

RAG solution:
- ✅ Retrieve only relevant messages (top-k semantic search)
- ✅ Build focused context for LLM (no token waste)
- ✅ Ground responses in actual conversation history
- ✅ Cross-language search (embeddings capture semantics, not keywords)

**Per-Thread Vector Storage Strategy:**

```
Why per-thread databases?
┌────────────────────────────────────────────────────────────┐
│  Benefit            │ Description                          │
├─────────────────────┼──────────────────────────────────────┤
│  Privacy Isolation  │ Each thread's embeddings in separate │
│                     │ DB file. Delete thread = delete all  │
│                     │ vectors atomically                   │
├─────────────────────┼──────────────────────────────────────┤
│  Scalability        │ No single DB bottleneck. Sharding    │
│                     │ is natural - 1000 threads = 1000 DBs │
├─────────────────────┼──────────────────────────────────────┤
│  Data Co-location   │ Embeddings live next to source       │
│                     │ messages. Single file backup/restore │
├─────────────────────┼──────────────────────────────────────┤
│  Query Speed        │ Search only relevant thread's vectors│
│                     │ Not entire user's message history    │
├─────────────────────┼──────────────────────────────────────┤
│  Simplicity         │ No separate vector DB to manage.     │
│                     │ SQLite handles everything            │
└─────────────────────┴──────────────────────────────────────┘
```

**SQLite vec0 Extension vs Alternatives:**

| Feature | sqlite-vec | Pgvector | Pinecone |
|---------|-----------|----------|----------|
| Setup Complexity | ✅ Zero config | ⚠️ Requires PostgreSQL | ⚠️ External service |
| Sharding Support | ✅ Native (per-thread files) | ❌ Complex partitioning | ✅ Managed |
| Query Latency | ✅ Local disk (<50ms) | ⚠️ Network hop (100-200ms) | ⚠️ API call (200-500ms) |
| Cost | ✅ Free | 💰 DB hosting | 💰💰 Per-query pricing |
| Scale Limit | ⚠️ 100M vectors per file | ✅ Billions | ✅ Billions |
| Privacy | ✅ Local storage | ⚠️ Centralized DB | ❌ Cloud service |

**Decision:** Use sqlite-vec for MVP. Natural fit with existing per-thread sharding. Can migrate to Pgvector if single-thread scale exceeds 10M messages (unlikely).

### 2.3 Embedding Strategy

**Model Selection: OpenAI text-embedding-3-large**

```
Comparison:
┌──────────────────┬─────────────┬──────────┬────────────┬─────────┐
│ Model            │ Dimensions  │ Cost     │ Speed      │ Quality │
├──────────────────┼─────────────┼──────────┼────────────┼─────────┤
│ text-embed-3     │ 1536        │ $0.02/1M │ 50ms/msg   │ ⭐⭐⭐⭐  │
│ -small (OpenAI)  │             │ tokens   │            │         │
├──────────────────┼─────────────┼──────────┼────────────┼─────────┤
│ text-embed-3     │ 3072        │ $0.13/1M │ 70ms/msg   │ ⭐⭐⭐⭐⭐ │
│ -large (OpenAI)  │             │ tokens   │            │         │
├──────────────────┼─────────────┼──────────┼────────────┼─────────┤
│ all-MiniLM-L6-v2 │ 384         │ Free     │ 20ms/msg   │ ⭐⭐⭐   │
│ (local)          │             │ (CPU)    │ (local)    │         │
└──────────────────┴─────────────┴──────────┴────────────┴─────────┘
```

**Decision:** Use `text-embedding-3-large` for highest quality. 3072 dimensions provide superior semantic understanding for multilingual search. Critical for International Communicator persona. Cost increase justified by better cross-language retrieval accuracy.

**Storage Requirements:**
```
3072 floats × 4 bytes = 12288 bytes (12KB) per message
1000 messages = 12MB
10,000 messages = 120MB
100,000 messages (heavy thread) = 1.2GB

SQLite handles this efficiently with WAL mode. 2x storage vs small model but significantly better quality.
```

**Embedding Generation Workflow:**

```elixir
# When message is created:
1. Insert message into messages table (no embedding yet)
2. Enqueue background job: GenerateEmbeddingJob
3. Return success to client (don't block)

# Background job (Oban):
defmodule Messaging.AI.GenerateEmbeddingJob do
  use Oban.Worker, queue: :embeddings, max_attempts: 3

  def perform(%{message_id: message_id, thread_id: thread_id}) do
    message = Messaging.get_message(message_id)

    # Check cache first
    case Redis.get("embed:#{hash(message.content)}") do
      nil ->
        # Generate new embedding
        embedding = EmbeddingService.generate(message.content)
        Redis.set("embed:#{hash(message.content)}", embedding)
      cached ->
        embedding = cached
    end

    # Store in vector table
    VectorStore.insert(thread_id, message_id, embedding)

    :ok
  end
end
```

### 2.4 Vector Search Strategy

**Cosine Similarity with Recency Bias:**

```elixir
defmodule Messaging.AI.Retriever do
  @doc """
  Semantic search with recency bias.

  Strategy:
  1. Pure vector search: Top 20 by cosine similarity
  2. Boost recent messages (last 7 days get +0.1 to score)
  3. Rerank and take top 10
  4. Return in chronological order for LLM context
  """
  def retrieve(thread_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    recency_boost = Keyword.get(opts, :recency_boost, 0.1)
    recency_window_days = Keyword.get(opts, :recency_days, 7)

    # 1. Generate query embedding
    query_embedding = EmbeddingService.embed(query)

    # 2. Vector search (top 20)
    candidates = VectorStore.search(
      thread_id,
      query_embedding,
      limit: limit * 2
    )

    # 3. Apply recency bias
    cutoff = DateTime.utc_now()
              |> DateTime.add(-recency_window_days, :day)

    reranked = Enum.map(candidates, fn result ->
      boost = if result.timestamp > cutoff, do: recency_boost, else: 0
      %{result | score: result.score + boost}
    end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(limit)

    # 4. Return chronologically (oldest first for LLM context)
    Enum.sort_by(reranked, & &1.timestamp)
  end
end
```

**Context Building for LLM:**

```elixir
defmodule Messaging.AI.ContextBuilder do
  @doc """
  Build focused context for LLM from retrieved messages.

  Strategy:
  - Include sender names for attribution
  - Format timestamps for temporal context
  - Deduplicate if same message in multiple results
  - Limit total tokens to fit LLM context window
  """
  def build_context(retrieved_messages, opts \\ []) do
    max_tokens = Keyword.get(opts, :max_tokens, 4000)

    messages = retrieved_messages
    |> deduplicate_by_id()
    |> Enum.map(&format_message/1)
    |> limit_tokens(max_tokens)

    """
    Relevant conversation history:

    #{Enum.join(messages, "\n\n")}
    """
  end

  defp format_message(msg) do
    timestamp = format_timestamp(msg.timestamp)
    "[#{timestamp}] #{msg.sender_name}: #{msg.content}"
  end

  defp limit_tokens(messages, max_tokens) do
    # Rough estimate: 4 chars = 1 token
    limit_chars = max_tokens * 4

    messages
    |> Enum.reduce_while({[], 0}, fn msg, {acc, total} ->
      msg_length = String.length(msg)
      if total + msg_length <= limit_chars do
        {:cont, {[msg | acc], total + msg_length}}
      else
        {:halt, {acc, total}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end
end
```

---

## 3. Required AI Features (International Communicator)

### Feature 1: Real-Time Translation with Cultural Context

**User Story:**
> "As an international communicator, I want to translate messages instantly with cultural context hints so I can understand not just the words but the intended meaning and avoid cultural misunderstandings."

**Acceptance Criteria:**
1. ✅ Automatically detect source language (95%+ accuracy)
2. ✅ Translate to target language in <5s (P95 latency)
3. ✅ Identify idioms, slang, and cultural phrases
4. ✅ Provide context explanations (e.g., "In Japanese business culture, this implies urgency")
5. ✅ Suggest alternative phrasings for better cross-cultural communication
6. ✅ Cache translations for 7 days to reduce costs
7. ✅ Support 10+ languages: EN, ES, FR, DE, HI, JA, ZH, PT, AR, RU

**Implementation:**

```elixir
defmodule Messaging.AI.TranslationChain do
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.ChatModels.ChatOpenAI

  @translation_prompt """
  You are a professional translator with deep cultural awareness.

  Your task:
  1. Detect the source language
  2. Translate to the target language
  3. Identify any idioms, slang, cultural phrases, or urgency markers
  4. Provide cultural context explanations
  5. Suggest alternative phrasings if the original might cause misunderstandings

  Respond in JSON format:
  {
    "source_language": "detected language code",
    "translation": "translated text",
    "confidence": 0.95,
    "cultural_notes": [
      {
        "phrase": "original phrase",
        "type": "idiom | formality | urgency | slang",
        "explanation": "cultural context",
        "suggestion": "alternative phrasing if needed"
      }
    ]
  }
  """

  def translate(text, target_lang, opts \\ []) do
    cache_key = "trans:#{hash(text)}:#{target_lang}"

    # Check cache first
    case Messaging.AI.Cache.get(cache_key) do
      nil ->
        result = perform_translation(text, target_lang, opts)
        Messaging.AI.Cache.put(cache_key, result, ttl: :timer.hours(168)) # 7 days
        result
      cached ->
        cached
    end
  end

  defp perform_translation(text, target_lang, opts) do
    model = ChatOpenAI.new!(%{
      model: "gpt-4-turbo",
      temperature: 0.3,
      response_format: %{type: "json_object"}
    })

    user_prompt = """
    Translate the following text to #{target_lang}.

    Text: #{text}
    """

    {:ok, chain} = LLMChain.new(%{llm: model, verbose: true})
    |> LLMChain.add_message(Message.new_system!(@translation_prompt))
    |> LLMChain.add_message(Message.new_user!(user_prompt))
    |> LLMChain.run()

    parse_translation_response(chain)
  end

  defp parse_translation_response(chain) do
    response = LLMChain.last_message(chain).content

    case Jason.decode(response) do
      {:ok, data} ->
        {:ok, %Messaging.AI.TranslationResult{
          source_language: data["source_language"],
          translation: data["translation"],
          confidence: data["confidence"],
          cultural_notes: parse_cultural_notes(data["cultural_notes"])
        }}
      {:error, _} ->
        {:error, :invalid_response}
    end
  end
end
```

**API Endpoint:**

```elixir
defmodule MessagingWeb.AIController do
  use MessagingWeb, :controller
  alias Messaging.AI.TranslationChain

  def translate(conn, %{"text" => text, "target_lang" => lang}) do
    user = conn.assigns.user

    # Feature flag check
    unless Messaging.Accounts.has_feature?(user, :ai_translation) do
      conn
      |> put_status(403)
      |> json(%{error: "AI translation requires Pro or Enterprise tier"})
    else
      case TranslationChain.translate(text, lang) do
        {:ok, result} ->
          json(conn, %{
            translation: result.translation,
            source_language: result.source_language,
            confidence: result.confidence,
            cultural_notes: result.cultural_notes
          })
        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Translation failed: #{reason}"})
      end
    end
  end
end
```

**Cost Analysis:**
- Average message: 50 tokens input + 100 tokens output = 150 tokens
- GPT-4-turbo: $10/1M input + $30/1M output = $0.0005 + $0.003 = **$0.0035 per translation**
- With 7-day cache hit rate of 30%: **$0.0025 effective cost**
- 100 translations/day = **$0.25/day = $7.50/month per active user**

### Feature 2: Cultural Context Analysis

**User Story:**
> "As someone working with international teams, I want to understand cultural nuances in messages so I can respond appropriately and avoid misunderstandings caused by different communication styles."

**Acceptance Criteria:**
1. ✅ Detect formality level (casual, business, formal)
2. ✅ Identify urgency markers across cultures (e.g., "ASAP" in India vs Japan)
3. ✅ Flag potential misunderstandings (e.g., directness interpreted as rudeness)
4. ✅ Provide culture-specific communication tips
5. ✅ Suggest rephrasing for target audience

**Implementation:**

```elixir
defmodule Messaging.AI.FormalityChain do
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  @formality_prompt """
  You are a cross-cultural communication expert.

  Analyze the message for:
  1. Formality level (casual, business, formal)
  2. Urgency markers and their cultural interpretation
  3. Potential cultural misunderstandings
  4. Communication style (direct vs indirect)

  Respond in JSON:
  {
    "formality": "casual | business | formal",
    "urgency": {
      "level": "low | medium | high",
      "markers": ["phrase that indicates urgency"],
      "cultural_interpretation": "how this might be interpreted in different cultures"
    },
    "potential_issues": [
      {
        "phrase": "concerning phrase",
        "issue": "why it might cause misunderstanding",
        "cultures_affected": ["JA", "DE"],
        "suggestion": "how to rephrase"
      }
    ],
    "communication_style": "direct | indirect"
  }
  """

  def analyze_tone(text, source_culture, target_culture) do
    model = ChatOpenAI.new!(%{
      model: "gpt-4-turbo",
      temperature: 0.2,
      response_format: %{type: "json_object"}
    })

    user_prompt = """
    Analyze this message from someone in #{source_culture} culture
    who is communicating with someone in #{target_culture} culture:

    "#{text}"
    """

    {:ok, chain} = LLMChain.new(%{llm: model})
    |> LLMChain.add_message(Message.new_system!(@formality_prompt))
    |> LLMChain.add_message(Message.new_user!(user_prompt))
    |> LLMChain.run()

    parse_tone_analysis(chain)
  end
end
```

### Feature 3: Formality Adjustment Suggestions

**User Story:**
> "As a freelancer working with clients from different cultures, I want to adjust my message formality to match business norms in their culture so I can build better professional relationships."

**Acceptance Criteria:**
1. ✅ Detect current message formality
2. ✅ Suggest adjusted versions (more formal / more casual)
3. ✅ Explain why adjustment is recommended
4. ✅ Preserve original meaning while adjusting tone
5. ✅ Support culture-specific formality conventions

**Implementation:**

```elixir
defmodule Messaging.AI.FormalityAdjuster do
  @adjustment_prompt """
  You are a professional business communication coach.

  Given a message and target formality level, provide:
  1. Original message analysis
  2. Adjusted version maintaining meaning
  3. Explanation of changes
  4. Cultural appropriateness notes

  Response format:
  {
    "original_formality": "casual",
    "adjusted_message": "professionally adjusted text",
    "changes_made": ["changed 'hey' to 'hello'", ...],
    "cultural_notes": "In Japanese business culture, this level of formality...",
    "appropriateness_score": 0.9
  }
  """

  def adjust_formality(text, target_level, target_culture) do
    # Implementation similar to translation chain
    # Uses structured prompt with JSON output
  end
end
```

### Feature 4: Slang and Idiom Explanations

**User Story:**
> "As someone communicating in my second language, I want explanations of slang and idioms so I can understand informal messages and respond appropriately."

**Acceptance Criteria:**
1. ✅ Detect slang terms and idioms in real-time
2. ✅ Provide clear explanations in user's preferred language
3. ✅ Suggest equivalent expressions in target language
4. ✅ Show usage examples
5. ✅ Flag regional variations (UK vs US English, Latin American vs Spain Spanish)

**Implementation:**

```elixir
defmodule Messaging.AI.IdiomDetector do
  @idiom_prompt """
  You are a linguist specializing in informal language.

  Identify and explain:
  1. Slang terms
  2. Idioms and colloquialisms
  3. Cultural references
  4. Regional language variations

  For each, provide:
  - Literal translation
  - Actual meaning
  - Cultural context
  - Equivalent in target language
  - Usage example

  JSON format:
  {
    "detected_expressions": [
      {
        "original": "break a leg",
        "type": "idiom",
        "literal": "damage your leg bone",
        "actual_meaning": "good luck",
        "context": "theatrical tradition",
        "target_equivalent": "¡Mucha mierda!" (Spanish),
        "usage_example": "Break a leg on your presentation!"
      }
    ]
  }
  """

  def detect_and_explain(text, source_lang, target_lang) do
    # Check cache for common idioms first
    cache_key = "idiom:#{hash(text)}:#{source_lang}:#{target_lang}"

    case Cache.get(cache_key) do
      nil -> perform_detection(text, source_lang, target_lang)
      cached -> cached
    end
  end
end
```

### Feature 5: Multilingual Semantic Search (RAG-Powered)

**User Story:**
> "As a team member working across languages, I want to search conversations in English and find relevant messages in Spanish or Japanese so I don't miss important information due to language barriers."

**Acceptance Criteria:**
1. ✅ Search across all languages in a thread
2. ✅ Query in one language, find results in any language
3. ✅ Return results ranked by semantic relevance
4. ✅ Show translations of results in user's preferred language
5. ✅ Latency <500ms for 1000-message threads

**Implementation:**

```elixir
defmodule Messaging.AI.SemanticSearch do
  alias Messaging.AI.{EmbeddingService, VectorStore, Retriever}

  @doc """
  Semantic search across multilingual messages.

  How it works:
  1. Generate embedding for search query
  2. Embeddings capture semantic meaning, not language
  3. Vector search finds similar messages regardless of language
  4. Optionally translate results to user's preferred language
  """
  def search(thread_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    translate_to = Keyword.get(opts, :translate_to)

    # 1. Generate query embedding
    query_embedding = EmbeddingService.embed(query)

    # 2. Vector search in thread
    results = Retriever.retrieve(thread_id, query, limit: limit)

    # 3. Optionally translate results
    if translate_to do
      translate_results(results, translate_to)
    else
      results
    end
  end

  defp translate_results(results, target_lang) do
    Enum.map(results, fn result ->
      # Only translate if message is in different language
      if result.language != target_lang do
        {:ok, translation} = TranslationChain.translate(result.content, target_lang)
        %{result | translated_content: translation.translation}
      else
        result
      end
    end)
  end
end
```

**API Endpoint:**

```elixir
defmodule MessagingWeb.AIController do
  def search_semantic(conn, %{"thread_id" => thread_id, "query" => query} = params) do
    user = conn.assigns.user

    unless Messaging.Accounts.has_feature?(user, :semantic_search) do
      conn
      |> put_status(403)
      |> json(%{error: "Semantic search requires Enterprise tier"})
    else
      opts = [
        limit: Map.get(params, "limit", 10),
        translate_to: Map.get(params, "translate_to")
      ]

      results = SemanticSearch.search(thread_id, query, opts)

      json(conn, %{
        results: Enum.map(results, &format_search_result/1),
        query: query
      })
    end
  end

  defp format_search_result(result) do
    %{
      message_id: result.id,
      content: result.content,
      translated_content: result.translated_content,
      sender: result.sender_name,
      timestamp: result.timestamp,
      relevance_score: result.score
    }
  end
end
```

---

## 4. Advanced AI: Intelligent Processing

### Feature 6: Multi-Step Task Extraction

**User Story:**
> "As a project coordinator, I want to automatically extract action items and deadlines from conversations so I don't miss commitments and can track progress easily."

**Acceptance Criteria:**
1. ✅ Extract tasks with >75% accuracy
2. ✅ Detect deadlines and dates (including relative: "by Friday", "next week")
3. ✅ Identify assignees when mentioned
4. ✅ Link extracted tasks to source messages
5. ✅ Provide confidence scores
6. ✅ Support multiple languages

**Implementation with LangChain Function Calling:**

```elixir
defmodule Messaging.AI.TaskExtractionChain do
  alias LangChain.Function

  @task_extraction_function %{
    name: "extract_tasks",
    description: "Extract action items, tasks, and deadlines from conversation",
    parameters_schema: %{
      type: "object",
      properties: %{
        tasks: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              description: %{type: "string"},
              deadline: %{type: "string", description: "ISO 8601 date or null"},
              assignee: %{type: "string", description: "Person assigned or null"},
              source_message_id: %{type: "string"},
              confidence: %{type: "number", minimum: 0, maximum: 1},
              category: %{
                type: "string",
                enum: ["action_item", "decision", "deadline", "question"]
              }
            },
            required: ["description", "source_message_id", "confidence", "category"]
          }
        }
      },
      required: ["tasks"]
    }
  }

  def extract_tasks(thread_id, opts \\ []) do
    # 1. Retrieve recent messages or use RAG for focused extraction
    messages = get_messages_for_extraction(thread_id, opts)

    # 2. Build context
    context = build_extraction_context(messages)

    # 3. Run LangChain with function calling
    function = Function.new!(@task_extraction_function)

    model = ChatOpenAI.new!(%{
      model: "gpt-4-turbo",
      temperature: 0.2,
      functions: [function]
    })

    {:ok, chain} = LLMChain.new(%{llm: model})
    |> LLMChain.add_message(Message.new_system!("""
      You are an AI assistant that extracts structured information from conversations.
      Focus on:
      - Action items (who should do what)
      - Decisions made by the group
      - Deadlines and time-sensitive commitments
      - Open questions that need answers

      Be precise. Only extract clear, actionable items.
      Include confidence scores (1.0 = certain, <0.7 = uncertain).
    """))
    |> LLMChain.add_message(Message.new_user!(context))
    |> LLMChain.run()

    # 4. Parse function call result
    parse_extracted_tasks(chain)
  end

  defp get_messages_for_extraction(thread_id, opts) do
    use_rag = Keyword.get(opts, :use_rag, true)

    if use_rag do
      # Use RAG to find messages likely containing tasks
      query = "action items tasks deadlines decisions to-do commitments"
      Retriever.retrieve(thread_id, query, limit: 50)
    else
      # Just get recent messages
      Messaging.Threads.get_recent_messages(thread_id, limit: 100)
    end
  end

  defp build_extraction_context(messages) do
    """
    Extract all action items, decisions, deadlines, and open questions from this conversation:

    #{Enum.map_join(messages, "\n\n", &format_message_for_extraction/1)}
    """
  end

  defp format_message_for_extraction(msg) do
    """
    [Message ID: #{msg.id}]
    [#{format_timestamp(msg.timestamp)}] #{msg.sender_name}: #{msg.content}
    """
  end
end
```

**API Endpoint:**

```elixir
defmodule MessagingWeb.AIController do
  def extract_tasks(conn, %{"thread_id" => thread_id} = params) do
    user = conn.assigns.user

    unless Messaging.Accounts.has_feature?(user, :task_extraction) do
      conn
      |> put_status(403)
      |> json(%{error: "Task extraction requires Pro or Enterprise tier"})
    else
      opts = [
        use_rag: Map.get(params, "use_rag", true),
        min_confidence: Map.get(params, "min_confidence", 0.7)
      ]

      case TaskExtractionChain.extract_tasks(thread_id, opts) do
        {:ok, tasks} ->
          json(conn, %{
            tasks: tasks,
            total: length(tasks)
          })
        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Extraction failed: #{reason}"})
      end
    end
  end
end
```

### Feature 7: RAG-Enhanced Thread Summarization

**User Story:**
> "As someone who missed a day of conversations, I want an AI-generated summary of what I missed so I can quickly catch up without reading 200 messages."

**Acceptance Criteria:**
1. ✅ Summarize up to 100 messages in <10s
2. ✅ Capture key decisions, action items, and topics
3. ✅ Highlight unresolved questions
4. ✅ Identify sentiment shifts or conflicts
5. ✅ Link summary points to source messages
6. ✅ Support multilingual threads

**Implementation:**

```elixir
defmodule Messaging.AI.SummarizationChain do
  @doc """
  RAG-enhanced summarization strategy:

  1. Use vector search to find "important" messages:
     - Queries: "decisions", "action items", "deadlines", "questions"
  2. Combine with recent messages (last 20)
  3. Deduplicate and sort chronologically
  4. Build focused context for LLM
  5. Generate summary with structured sections
  """
  def summarize_thread(thread_id, opts \\ []) do
    # 1. RAG retrieval for important messages
    important_messages = retrieve_important_messages(thread_id)

    # 2. Get recent messages for temporal context
    recent_messages = Messaging.Threads.get_recent_messages(thread_id, limit: 20)

    # 3. Merge and deduplicate
    all_messages = merge_and_deduplicate(important_messages, recent_messages)

    # 4. Build context
    context = ContextBuilder.build_context(all_messages, max_tokens: 4000)

    # 5. Run summarization chain
    model = ChatAnthropic.new!(%{
      model: "claude-3-5-haiku-20241022",  # Cheaper and faster for summaries
      temperature: 0.3,
      max_tokens: 1000
    })

    {:ok, chain} = LLMChain.new(%{llm: model})
    |> LLMChain.add_message(Message.new_system!(@summarization_prompt))
    |> LLMChain.add_message(Message.new_user!(context))
    |> LLMChain.run()

    parse_summary_response(chain)
  end

  defp retrieve_important_messages(thread_id) do
    queries = [
      "decisions made agreements reached",
      "action items tasks todo",
      "deadlines dates timeframes",
      "questions unanswered unclear",
      "problems issues concerns"
    ]

    Enum.flat_map(queries, fn query ->
      Retriever.retrieve(thread_id, query, limit: 10)
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.timestamp)
  end

  @summarization_prompt """
  You are an AI assistant that creates concise, actionable summaries of conversations.

  Your summary should include:

  1. **Key Topics Discussed** (2-3 sentences)
  2. **Decisions Made** (bulleted list with links to source messages)
  3. **Action Items** (who, what, when - with message IDs)
  4. **Deadlines Mentioned** (dates and commitments)
  5. **Unresolved Questions** (things still needing clarification)
  6. **Overall Sentiment** (collaborative, tense, productive, etc.)

  Format your response as JSON:
  {
    "key_topics": "brief overview",
    "decisions": [
      {"summary": "...", "message_id": "..."}
    ],
    "action_items": [
      {"task": "...", "assignee": "...", "deadline": "...", "message_id": "..."}
    ],
    "deadlines": [
      {"description": "...", "date": "...", "message_id": "..."}
    ],
    "unresolved_questions": ["question 1", "question 2"],
    "sentiment": "collaborative",
    "participant_count": 5,
    "message_count": 87
  }
  """
end
```

### Feature 8: Structured Data Extraction

**User Story:**
> "As a team coordinator, I want to automatically extract dates, locations, and contact information from messages so I can quickly add them to my calendar or contacts without manual copying."

**Acceptance Criteria:**
1. ✅ Extract dates and times with timezone awareness
2. ✅ Identify locations (addresses, meeting places)
3. ✅ Extract contact information (emails, phone numbers)
4. ✅ Detect URLs and categorize them (docs, videos, etc.)
5. ✅ Support multiple formats (ISO dates, natural language: "next Tuesday at 3pm")

**Implementation:**

```elixir
defmodule Messaging.AI.StructuredDataExtractor do
  @extraction_function %{
    name: "extract_structured_data",
    description: "Extract dates, locations, contacts, and URLs from messages",
    parameters_schema: %{
      type: "object",
      properties: %{
        entities: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              type: %{
                type: "string",
                enum: ["date", "location", "contact", "url", "other"]
              },
              value: %{type: "string"},
              context: %{type: "string"},
              message_id: %{type: "string"},
              confidence: %{type: "number"}
            },
            required: ["type", "value", "message_id", "confidence"]
          }
        }
      }
    }
  }

  def extract(thread_id, entity_types \\ :all) do
    # Similar to task extraction but focused on structured entities
    messages = Messaging.Threads.get_recent_messages(thread_id, limit: 50)

    function = Function.new!(@extraction_function)

    model = ChatOpenAI.new!(%{
      model: "gpt-4-turbo",
      functions: [function]
    })

    # Build context and run chain
    # Parse results and return structured entities
  end
end
```

---

## 5. Database Schema for Vector Storage

### 5.1 Enhanced Messages Table

```sql
-- Per-thread database: threads/{thread_id}.db

-- Add embedding column to existing messages table
ALTER TABLE messages ADD COLUMN embedding BLOB;
ALTER TABLE messages ADD COLUMN embedding_model TEXT DEFAULT 'text-embedding-3-large';
ALTER TABLE messages ADD COLUMN embedding_generated_at INTEGER;

-- Index for finding messages without embeddings (for background job)
CREATE INDEX idx_messages_no_embedding
ON messages(id)
WHERE embedding IS NULL;

-- Keep existing indexes
CREATE INDEX idx_messages_timestamp ON messages(timestamp);
CREATE INDEX idx_messages_sender ON messages(sender_id);
```

### 5.2 Vector Virtual Table

```sql
-- Virtual table using vec0 extension for vector operations
-- This is created per-thread when first embedding is generated

CREATE VIRTUAL TABLE message_embeddings USING vec0(
  message_id TEXT PRIMARY KEY,
  embedding float[3072]
);

-- Query example: Find top 10 similar messages
-- SELECT
--   message_id,
--   distance
-- FROM message_embeddings
-- WHERE embedding MATCH ?
--   AND k = 10
-- ORDER BY distance;
```

### 5.3 Embedding Metadata Cache

```sql
-- Main database: users.db or global.db
-- Track embedding generation status across all threads

CREATE TABLE embedding_status (
  thread_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  status TEXT DEFAULT 'pending', -- pending, processing, completed, failed
  attempts INTEGER DEFAULT 0,
  last_attempt_at INTEGER,
  error TEXT,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (thread_id, message_id)
);

CREATE INDEX idx_embedding_status_pending
ON embedding_status(status, created_at)
WHERE status = 'pending';
```

---

## 6. Module Structure (Agens-Based Architecture)

```
backend/lib/messaging/ai/
├── agents/                          # Agens.Agent implementations
│   ├── translator_agent.ex          # Specialized translation agent
│   ├── summarizer_agent.ex          # RAG-aware summarization agent
│   ├── rag_retriever_agent.ex       # Semantic search & retrieval
│   └── analyst_agent.ex             # Task & data extraction agent
│
├── jobs/                            # Agens.Job multi-step workflows
│   ├── translation_job.ex           # Translation Job (2-step: translate + cultural)
│   ├── summarization_job.ex         # Summarization Job (RAG + LLM)
│   ├── task_extraction_job.ex       # Task extraction Job
│   └── formality_adjustment_job.ex  # Formality analysis & adjustment
│
├── tools/                           # Agens.Tool implementations
│   ├── semantic_search_tool.ex      # Implements Agens.Tool for RAG
│   ├── function_caller_tool.ex      # Structured output tool for function calls
│   ├── cultural_context_tool.ex     # Cultural knowledge tool
│   └── task_extractor_tool.ex       # Task extraction via function calling
│
├── rag/                             # RAG components (unchanged)
│   ├── embedding_service.ex         # Generate embeddings (OpenAI API)
│   ├── vector_store.ex              # SQLite vec0 operations
│   ├── retriever.ex                 # Semantic search and ranking
│   └── context_builder.ex           # Build LLM context from results
│
├── providers/                       # LLM provider abstractions
│   ├── openai_provider.ex           # OpenAI API wrapper
│   ├── anthropic_provider.ex        # Anthropic API wrapper
│   └── serving_adapter.ex           # Adapter for Agens.Serving
│
├── cache/                           # Caching layer (unchanged)
│   ├── translation_cache.ex         # Redis cache for translations
│   ├── embedding_cache.ex           # Embedding deduplication
│   └── search_cache.ex              # Cache popular searches
│
├── jobs_oban/                       # Background jobs (Oban)
│   ├── generate_embedding_job.ex    # Async embedding generation
│   ├── batch_embed_job.ex           # Batch process multiple messages
│   └── cleanup_cache_job.ex         # Expire old cache entries
│
├── models/                          # Data structures (unchanged)
│   ├── translation_result.ex
│   ├── tone_analysis.ex
│   ├── thread_summary.ex
│   ├── extracted_task.ex
│   └── search_result.ex
│
└── utils/                           # Shared utilities (unchanged)
    ├── token_counter.ex             # Estimate token usage
    ├── cost_tracker.ex              # Track API costs
    └── language_detector.ex         # Language detection helpers
```

**Agens Integration Points:**
- `Agens.Supervisor` in supervision tree (OTP-native)
- `Agens.Serving` for OpenAI/Anthropic API wrapping
- `Agens.Agent` for specialized task agents
- `Agens.Job` for multi-step workflows
- `Agens.Tool` for function calling & custom tools

---

## 7. API Endpoints

### 7.1 Translation

```
POST /api/v1/ai/translate

Request:
{
  "text": "Let's touch base next week",
  "target_lang": "es",
  "source_culture": "US",
  "target_culture": "ES"
}

Response:
{
  "translation": "Hablemos la próxima semana",
  "source_language": "en",
  "confidence": 0.95,
  "cultural_notes": [
    {
      "phrase": "touch base",
      "type": "idiom",
      "explanation": "Informal American business expression meaning 'have a brief meeting or conversation'",
      "suggestion": "In Spanish business context, more formal phrasing recommended"
    }
  ],
  "cached": false,
  "processing_time_ms": 1247
}
```

### 7.2 Tone Analysis

```
POST /api/v1/ai/analyze-tone

Request:
{
  "text": "Can you send that ASAP?",
  "source_culture": "US",
  "target_culture": "JP"
}

Response:
{
  "formality": "casual",
  "urgency": {
    "level": "high",
    "markers": ["ASAP"],
    "cultural_interpretation": "In US context, ASAP is common and not overly urgent. In Japanese business culture, this directness might be perceived as impolite. Consider: '可能な限り早くお送りいただけますでしょうか' (Could you send it as soon as conveniently possible?)"
  },
  "potential_issues": [
    {
      "phrase": "Can you send that",
      "issue": "Direct request without honorifics",
      "cultures_affected": ["JP", "KR"],
      "suggestion": "Add polite phrasing: 'Would it be possible for you to send that when you have a moment?'"
    }
  ],
  "communication_style": "direct"
}
```

### 7.3 Thread Summarization

```
POST /api/v1/ai/summarize-thread

Request:
{
  "thread_id": "thread_abc123",
  "include_action_items": true,
  "include_sentiment": true
}

Response:
{
  "summary": {
    "key_topics": "Team discussed Q4 launch timeline, budget allocation, and marketing strategy. Main concern was resource availability.",
    "decisions": [
      {
        "summary": "Launch date set for November 15, 2025",
        "message_id": "msg_001",
        "timestamp": 1698019200000
      }
    ],
    "action_items": [
      {
        "task": "Finalize budget spreadsheet",
        "assignee": "Sarah",
        "deadline": "2025-10-30",
        "message_id": "msg_045"
      }
    ],
    "deadlines": [
      {
        "description": "Marketing assets needed",
        "date": "2025-11-01",
        "message_id": "msg_067"
      }
    ],
    "unresolved_questions": [
      "Should we hire additional QA resources?",
      "What's the backup plan if partner delays?"
    ],
    "sentiment": "productive",
    "participant_count": 5,
    "message_count": 87,
    "generated_at": 1698019800000
  },
  "processing_time_ms": 8234
}
```

### 7.4 Semantic Search

```
GET /api/v1/ai/search-semantic?thread_id=thread_abc123&query=budget&limit=10&translate_to=en

Response:
{
  "results": [
    {
      "message_id": "msg_045",
      "content": "El presupuesto total es de $50,000",
      "translated_content": "The total budget is $50,000",
      "sender": "Carlos",
      "timestamp": 1698018000000,
      "relevance_score": 0.92,
      "language": "es"
    }
  ],
  "query": "budget",
  "total_results": 7,
  "processing_time_ms": 234
}
```

### 7.5 Task Extraction

```
POST /api/v1/ai/extract-tasks

Request:
{
  "thread_id": "thread_abc123",
  "use_rag": true,
  "min_confidence": 0.7
}

Response:
{
  "tasks": [
    {
      "description": "Review and approve marketing budget",
      "deadline": "2025-10-30T17:00:00Z",
      "assignee": "Sarah",
      "source_message_id": "msg_045",
      "confidence": 0.91,
      "category": "action_item"
    },
    {
      "description": "Decision: Launch on November 15",
      "deadline": null,
      "assignee": null,
      "source_message_id": "msg_001",
      "confidence": 1.0,
      "category": "decision"
    }
  ],
  "total": 2,
  "processing_time_ms": 3456
}
```

---

## 8. Cost Optimization Strategies

### 8.1 Caching Architecture

**Translation Cache:**
```elixir
defmodule Messaging.AI.TranslationCache do
  use Messaging.AI.Cache

  @ttl :timer.hours(168)  # 7 days

  def get(text, target_lang) do
    key = cache_key(text, target_lang)
    Redis.get(key)
  end

  def put(text, target_lang, result) do
    key = cache_key(text, target_lang)
    Redis.setex(key, @ttl, Jason.encode!(result))
  end

  defp cache_key(text, lang) do
    hash = :crypto.hash(:sha256, text) |> Base.encode16()
    "trans:#{hash}:#{lang}"
  end
end
```

**Expected cache hit rates:**
- Common phrases: 60-70% hit rate
- Unique messages: 10-20% hit rate
- Overall: 30-40% hit rate after warmup
- **Cost savings: 30-40% reduction**

**Embedding Cache:**
```elixir
defmodule Messaging.AI.EmbeddingCache do
  # Embeddings are permanent (never expire)
  # Cache by content hash to deduplicate identical messages

  def get(content) do
    key = "embed:#{hash(content)}"
    case Redis.get(key) do
      nil -> nil
      cached -> decode_embedding(cached)
    end
  end

  def put(content, embedding) do
    key = "embed:#{hash(content)}"
    Redis.set(key, encode_embedding(embedding))
  end
end
```

**Embedding deduplication savings:**
- Quoted messages: 5-10% deduplication
- Repeated phrases: 2-5% deduplication
- **Cost savings: 5-15% reduction**

### 8.2 Batch Processing

```elixir
defmodule Messaging.AI.BatchEmbedJob do
  use Oban.Worker, queue: :embeddings, max_attempts: 3

  @doc """
  Process embeddings in batches of 10 for cost efficiency.

  OpenAI allows up to 2048 inputs per request.
  Batching 10 messages:
  - Reduces API calls by 90%
  - Same total cost but better throughput
  - Handles rate limiting better
  """
  def perform(%{thread_id: thread_id}) do
    # Get pending messages without embeddings
    pending = get_pending_messages(thread_id, limit: 10)

    if length(pending) > 0 do
      # Batch generate embeddings
      texts = Enum.map(pending, & &1.content)
      embeddings = EmbeddingService.batch_generate(texts)

      # Store in parallel
      Enum.zip(pending, embeddings)
      |> Enum.each(fn {msg, embedding} ->
        VectorStore.insert(thread_id, msg.id, embedding)
      end)
    end

    :ok
  end
end
```

### 8.3 Model Selection by Task

```elixir
defmodule Messaging.AI.ModelSelector do
  @doc """
  Choose appropriate model based on task complexity and cost.
  """
  def select_model(task_type) do
    case task_type do
      :translation ->
        # High quality needed
        "gpt-4-turbo"

      :summarization ->
        # Fast and cheap, good enough quality
        "claude-3-5-haiku-20241022"

      :task_extraction ->
        # Needs function calling
        "gpt-4-turbo"

      :tone_analysis ->
        # Cheap model fine for simple classification
        "gpt-3.5-turbo"
    end
  end
end
```

**Cost comparison per 1000 requests:**

| Task | Model | Cost | Rationale |
|------|-------|------|-----------|
| Translation | GPT-4-turbo | $3.50 | Quality critical, rare |
| Summarization | Claude Haiku | $0.50 | Fast, cheap, good enough |
| Task extraction | GPT-4-turbo | $3.50 | Function calling required |
| Tone analysis | GPT-3.5-turbo | $0.50 | Simple classification |
| Embeddings | text-embed-3-large | $0.13 | High quality multilingual semantic understanding |

### 8.4 Rate Limiting and Quotas

```elixir
defmodule Messaging.AI.RateLimiter do
  @doc """
  Per-user rate limits based on tier:
  - Free: No AI features
  - Pro: 100 requests/day
  - Enterprise: Unlimited
  """
  def check_rate_limit(user_id, feature) do
    key = "ratelimit:#{user_id}:#{feature}"
    limit = get_user_limit(user_id, feature)

    current = Redis.incr(key)
    Redis.expire(key, :timer.hours(24))

    if current <= limit do
      :ok
    else
      {:error, :rate_limit_exceeded}
    end
  end

  defp get_user_limit(user_id, feature) do
    user = Messaging.Accounts.get_user(user_id)

    case {user.tier, feature} do
      {:pro, :translation} -> 100
      {:pro, :summarization} -> 20
      {:enterprise, _} -> :unlimited
      _ -> 0
    end
  end
end
```

---

## 9. Performance Targets & Monitoring

### 9.1 Latency Targets

| Operation | P50 | P95 | P99 | Notes |
|-----------|-----|-----|-----|-------|
| Translation | <2s | <5s | <8s | Includes cache check + API call |
| Summarization | <5s | <10s | <15s | For 100 messages |
| Task extraction | <3s | <7s | <12s | RAG retrieval + LLM |
| Semantic search | <200ms | <500ms | <1s | Vector search only |
| Embedding generation | <1s | <2s | <3s | Per message, async |

### 9.2 Cost Tracking

```elixir
defmodule Messaging.AI.CostTracker do
  @doc """
  Track costs per request for budgeting and analysis.
  """
  def record_cost(user_id, feature, tokens_used, model) do
    cost = calculate_cost(tokens_used, model)

    # Log to database
    Messaging.Analytics.log_ai_usage(%{
      user_id: user_id,
      feature: feature,
      model: model,
      tokens_input: tokens_used.input,
      tokens_output: tokens_used.output,
      cost_usd: cost,
      timestamp: DateTime.utc_now()
    })

    # Update user's monthly spend
    increment_monthly_spend(user_id, cost)
  end

  defp calculate_cost(tokens, model) do
    pricing = get_model_pricing(model)
    input_cost = tokens.input * pricing.input_per_1m / 1_000_000
    output_cost = tokens.output * pricing.output_per_1m / 1_000_000
    input_cost + output_cost
  end
end
```

### 9.3 Monitoring Dashboards

**Key Metrics to Track:**

1. **Usage Metrics:**
   - Requests per feature per day
   - Active users per tier
   - Cache hit rates
   - Average tokens per request

2. **Performance Metrics:**
   - Latency percentiles (P50, P95, P99)
   - Error rates by feature
   - Vector search performance
   - Background job queue depth

3. **Cost Metrics:**
   - Daily/monthly spend by provider
   - Cost per user
   - Cost per feature
   - Budget alerts (>$X per day)

4. **Quality Metrics:**
   - Translation confidence scores
   - Task extraction accuracy (user feedback)
   - Search relevance (click-through rates)
   - User satisfaction (ratings)

**Phoenix LiveDashboard Integration:**

```elixir
# lib/messaging_web/telemetry.ex
defmodule MessagingWeb.Telemetry do
  def metrics do
    [
      # AI Request Metrics
      counter("messaging.ai.translation.requests.total"),
      counter("messaging.ai.summarization.requests.total"),
      distribution("messaging.ai.translation.duration",
        unit: {:native, :millisecond}
      ),

      # Cost Metrics
      counter("messaging.ai.cost.total_usd"),
      distribution("messaging.ai.tokens.input"),
      distribution("messaging.ai.tokens.output"),

      # Cache Metrics
      counter("messaging.ai.cache.hits"),
      counter("messaging.ai.cache.misses"),

      # Vector Search Metrics
      distribution("messaging.ai.vector_search.duration"),
      distribution("messaging.ai.vector_search.results_count")
    ]
  end
end
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

```elixir
# test/messaging/ai/translation_chain_test.exs
defmodule Messaging.AI.TranslationChainTest do
  use Messaging.DataCase, async: false
  import Mox

  setup :verify_on_exit!

  describe "translate/3" do
    test "translates text with cultural context" do
      # Mock OpenAI API response
      expect(OpenAIMock, :chat_completion, fn _params ->
        {:ok, %{
          "choices" => [%{
            "message" => %{
              "content" => Jason.encode!(%{
                "source_language" => "en",
                "translation" => "Hablemos la próxima semana",
                "confidence" => 0.95,
                "cultural_notes" => [
                  %{
                    "phrase" => "touch base",
                    "type" => "idiom",
                    "explanation" => "Informal American business expression"
                  }
                ]
              })
            }
          }]
        }}
      end)

      {:ok, result} = TranslationChain.translate("Let's touch base next week", "es")

      assert result.translation == "Hablemos la próxima semana"
      assert result.source_language == "en"
      assert result.confidence == 0.95
      assert length(result.cultural_notes) == 1
    end

    test "uses cache for repeated translations" do
      # First call hits API
      {:ok, _result} = TranslationChain.translate("Hello", "es")

      # Second call hits cache (no API mock needed)
      {:ok, cached} = TranslationChain.translate("Hello", "es")

      assert cached.translation == "Hola"
    end
  end
end
```

### 10.2 Integration Tests

```elixir
# test/messaging_web/controllers/ai_controller_test.exs
defmodule MessagingWeb.AIControllerTest do
  use MessagingWeb.ConnCase

  describe "POST /api/v1/ai/translate" do
    test "translates message successfully for Pro user", %{conn: conn} do
      user = insert(:user, tier: :pro)
      conn = auth_conn(conn, user)

      params = %{
        "text" => "Hello world",
        "target_lang" => "es"
      }

      conn = post(conn, ~p"/api/v1/ai/translate", params)

      assert %{
        "translation" => translation,
        "confidence" => confidence
      } = json_response(conn, 200)

      assert is_binary(translation)
      assert confidence > 0.7
    end

    test "rejects Free tier users", %{conn: conn} do
      user = insert(:user, tier: :free)
      conn = auth_conn(conn, user)

      conn = post(conn, ~p"/api/v1/ai/translate", %{"text" => "Hello", "target_lang" => "es"})

      assert %{"error" => error} = json_response(conn, 403)
      assert error =~ "Pro or Enterprise tier"
    end
  end
end
```

### 10.3 RAG Pipeline Tests

```elixir
# test/messaging/ai/rag/retriever_test.exs
defmodule Messaging.AI.RetrieverTest do
  use Messaging.DataCase

  setup do
    thread = insert(:thread)

    # Insert messages with embeddings
    messages = [
      insert(:message, thread_id: thread.id, content: "We decided on November 15 launch"),
      insert(:message, thread_id: thread.id, content: "Budget approved: $50,000"),
      insert(:message, thread_id: thread.id, content: "Sarah will handle marketing")
    ]

    # Generate and store embeddings
    Enum.each(messages, fn msg ->
      embedding = EmbeddingService.generate(msg.content)
      VectorStore.insert(thread.id, msg.id, embedding)
    end)

    %{thread: thread, messages: messages}
  end

  test "retrieves semantically similar messages", %{thread: thread} do
    results = Retriever.retrieve(thread.id, "launch date decision", limit: 3)

    assert length(results) == 3

    # First result should be the launch date message
    assert List.first(results).content =~ "November 15"
    assert List.first(results).score > 0.8
  end

  test "applies recency bias to recent messages", %{thread: thread} do
    # Insert a recent message with moderate similarity
    recent = insert(:message,
      thread_id: thread.id,
      content: "Launch timeline looking good",
      timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    )

    embedding = EmbeddingService.generate(recent.content)
    VectorStore.insert(thread.id, recent.id, embedding)

    results = Retriever.retrieve(thread.id, "launch",
      limit: 3,
      recency_boost: 0.2
    )

    # Recent message should rank higher due to recency bias
    assert Enum.any?(results, fn r -> r.id == recent.id end)
  end
end
```

### 10.4 Multi-Language Tests

```elixir
# test/messaging/ai/multilingual_test.exs
defmodule Messaging.AI.MultilingualTest do
  use Messaging.DataCase

  test "semantic search across languages" do
    thread = insert(:thread)

    # Insert messages in different languages
    messages = [
      insert(:message, content: "The budget is $50,000", language: "en"),
      insert(:message, content: "El presupuesto es de $50,000", language: "es"),
      insert(:message, content: "予算は5万ドルです", language: "ja")
    ]

    # Generate embeddings for all
    Enum.each(messages, fn msg ->
      embedding = EmbeddingService.generate(msg.content)
      VectorStore.insert(thread.id, msg.id, embedding)
    end)

    # Search in English
    results = SemanticSearch.search(thread.id, "budget amount", limit: 3)

    # Should find messages in all languages
    assert length(results) == 3
    languages = Enum.map(results, & &1.language) |> Enum.sort()
    assert languages == ["en", "es", "ja"]
  end
end
```

---

## 11. Deployment & Infrastructure

### 11.1 Dependencies

**Elixir Dependencies (mix.exs):**
```elixir
defp deps do
  [
    # Existing deps
    {:phoenix, "~> 1.7.0"},
    {:ecto_sql, "~> 3.10"},

    # AI & Multi-Agent Orchestration (Agens)
    {:agens, "~> 0.1.3"},                # Multi-agent framework (OTP-native)
    {:openai, "~> 0.5.0"},               # OpenAI API client
    {:httpoison, "~> 2.0"},              # HTTP client for LLM providers
    {:jason, "~> 1.4"},                  # JSON encoding/decoding
    {:req, "~> 0.4.0"},                  # Modern HTTP client

    # Vector database
    {:exqlite, "~> 0.13.0"},             # SQLite driver
    {:ecto_sqlite, "~> 0.9.0"},          # Ecto SQLite adapter
    # sqlite-vec extension loaded at runtime

    # Background jobs
    {:oban, "~> 2.15"},

    # Caching
    {:redix, "~> 1.2"},
    {:cachex, "~> 3.6"},

    # Utilities
    {:hammox, "~> 0.5.0", only: :test},  # Better mocking with Mox
    {:mox, "~> 1.0", only: :test}
  ]
end
```

**Key Dependencies:**
- **agens**: Multi-agent framework with OTP support (replaces LangChain)
- **exqlite + ecto_sqlite**: SQLite support for per-thread databases
- **openai**: OpenAI API client for embeddings and LLM calls
- **oban**: Background job processing for async embedding generation
- **cachex/redix**: Caching layer for translations and embeddings

### 11.2 Configuration

**config/config.exs:**
```elixir
config :messaging, Messaging.AI,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  embedding_model: "text-embedding-3-large",
  embedding_dimensions: 3072,
  default_llm: "gpt-4-turbo",
  cache_ttl: :timer.hours(168), # 7 days
  max_tokens_context: 4000

config :messaging, Messaging.AI.RateLimiter,
  pro_daily_limit: 100,
  enterprise_daily_limit: :unlimited

config :messaging, Oban,
  queues: [
    embeddings: 10,  # Parallel embedding generation
    ai_processing: 5 # AI chain processing
  ]
```

### 11.3 Environment Variables

```bash
# .env.production
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
REDIS_URL=redis://localhost:6379/0

# Feature flags
ENABLE_AI_TRANSLATION=true
ENABLE_RAG_SEARCH=true
ENABLE_TASK_EXTRACTION=true

# Monitoring
SENTRY_DSN=https://...
HONEYBADGER_API_KEY=...

# Cost limits
AI_DAILY_BUDGET_USD=100
AI_MONTHLY_BUDGET_USD=3000
```

### 11.4 Database Setup

**SQLite vec0 Extension:**
```bash
# Install sqlite-vec extension
# https://github.com/asg017/sqlite-vec

# On macOS:
brew install sqlite-vec

# Or download precompiled extension
wget https://github.com/asg017/sqlite-vec/releases/latest/download/vec0.dylib
```

**Load extension in Elixir:**
```elixir
defmodule Messaging.VectorStore do
  def init_connection(db_path) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    # Load vec0 extension
    vec_lib = Application.get_env(:messaging, :vec0_path, "./vec0.dylib")
    Exqlite.Sqlite3.execute(conn, "SELECT load_extension('#{vec_lib}')")

    {:ok, conn}
  end
end
```

### 11.5 Monitoring Setup

**Prometheus Metrics Export:**
```elixir
# lib/messaging_web/telemetry.ex
defmodule MessagingWeb.Telemetry do
  def init_metrics do
    Telemetry.Metrics.counter("messaging.ai.requests.total",
      tags: [:feature, :tier]
    )

    Telemetry.Metrics.distribution("messaging.ai.duration",
      unit: {:native, :millisecond},
      tags: [:feature]
    )

    Telemetry.Metrics.sum("messaging.ai.cost.total_usd",
      tags: [:feature, :model]
    )
  end
end
```

---

## 12. Implementation Phases (Agens-Based)

### Phase 1: Foundation (Week 1-2)

**Tasks:**
1. Set up Agens dependency and Supervisor in OTP tree
2. Configure OpenAI provider with Agens.Serving adapter
3. Install and test sqlite-vec extension
4. Create database migrations for vector columns
5. Implement EmbeddingService with OpenAI API
6. Set up Redis cache infrastructure
7. Create Oban jobs for async embedding generation
8. Initialize Agens agents (translator, summarizer, retriever)

**Deliverables:**
- Working embedding generation pipeline
- Vector storage in SQLite
- Background job processing

### Phase 2: Core AI Features - Agens Jobs (Week 3-4)

**Tasks:**
1. Implement TranslationJob (Agens.Job with 2 steps + TranslationAgent)
2. Build CulturalContextTool (Agens.Tool) for idiom detection
3. Create FormalityAnalysisJob for tone analysis
4. Implement SemanticSearchTool (Agens.Tool) for RAG
5. Add API endpoints and controllers
6. Feature flag integration
7. Wire up Agens agents to serving infrastructure

**Deliverables:**
- TranslationJob working end-to-end (Agens)
- CulturalContextTool producing idiom explanations
- Basic semantic search via RAG tool
- All agents integrated with OpenAI serving

### Phase 3: RAG Enhancement with Agens (Week 5)

**Tasks:**
1. Implement RAGRetrieverAgent with recency bias
2. Build ContextBuilder for LLM input
3. Create SummarizationJob with RAG (Agens.Job + Agent)
4. Optimize vector search performance
5. Add caching for search results
6. Integrate retrieval agent into summarization job steps

**Deliverables:**
- RAG-enhanced summarization (via Agens SummarizationJob)
- Fast semantic search (<500ms)
- Comprehensive test coverage for all jobs

### Phase 4: Advanced Features - Function Calling (Week 6-7)

**Tasks:**
1. Implement TaskExtractionTool (Agens.Tool) with function calling
2. Build TaskExtractionJob using the tool
3. Add StructuredDataExtractor via additional tools
4. Create multi-step agent workflows (Agens conditions)
5. Integrate with iOS client
6. End-to-end testing with Agens job execution

**Deliverables:**
- TaskExtractionJob working (Agens function calling)
- Full AI feature set operational
- iOS integration complete
- Jobs execute with proper error handling and recovery

### Phase 5: Optimization & Production (Week 8)

**Tasks:**
1. Performance optimization and profiling
2. Cost analysis and optimization
3. Monitoring and alerting setup
4. Documentation and runbooks
5. Load testing

**Deliverables:**
- Production-ready system
- Cost per user <$0.05/day
- All latency targets met
- Comprehensive documentation

---

## 13. Success Metrics

### 13.1 Technical Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Translation accuracy | >85% | User satisfaction surveys |
| Search precision | >80% | Click-through rate on results |
| Task extraction accuracy | >75% | User corrections needed |
| Latency (translation) | <5s P95 | Prometheus metrics |
| Latency (search) | <500ms P95 | Prometheus metrics |
| Cache hit rate | >30% | Redis stats |
| Uptime | >99.5% | Uptime monitoring |

### 13.2 Business Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cost per active user | <$0.05/day | Cost tracking logs |
| Pro tier conversion | >20% | Analytics |
| Feature usage rate | >60% | Telemetry |
| User satisfaction | >4/5 stars | In-app ratings |
| Support tickets (AI bugs) | <5% of total | Support system |

### 13.3 Quality Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| False positive rate (tasks) | <10% | User feedback |
| Cultural note relevance | >80% | User ratings |
| Multi-language search quality | >75% | User feedback |
| Summarization completeness | >90% | Expert review |

---

## 14. Risk Mitigation

### 14.1 Technical Risks

| Risk | Impact | Likelihood | Mitigation |
|------|---------|-----------|-----------|
| OpenAI API outages | High | Low | Fallback to Anthropic; cache aggressively |
| Vector search performance | Medium | Medium | Optimize indexes; limit thread size; paginate results |
| Embedding cost explosion | High | Medium | Aggressive caching; batch processing; monitor daily spend |
| Translation accuracy issues | Medium | Medium | Confidence scores; user feedback; model comparison |

### 14.2 Cost Overruns

**Budget Alerts:**
```elixir
defmodule Messaging.AI.BudgetMonitor do
  def check_daily_spend do
    today_spend = calculate_today_spend()
    daily_limit = Application.get_env(:messaging, :ai_daily_budget_usd)

    if today_spend > daily_limit * 0.8 do
      alert_ops_team("AI spend at 80% of daily budget: $#{today_spend}")
    end

    if today_spend > daily_limit do
      # Emergency brake
      disable_ai_features_temporarily()
      alert_ops_team("AI spend exceeded daily budget! Features disabled.")
    end
  end
end
```

### 14.3 Privacy Concerns

- Embeddings stored locally (per-thread isolation)
- Optional on-device processing for privacy tier (future)
- User data never sent to AI providers without consent
- Clear opt-out mechanism
- GDPR-compliant data retention (delete embeddings with messages)

---

## 15. Future Enhancements

### 15.1 On-Device AI (Post-MVP)

```elixir
# Support for local models
defmodule Messaging.AI.LocalProvider do
  @doc """
  Use MLX Swift on iOS or ONNX on backend for privacy mode.

  Benefits:
  - Zero API cost
  - No data leaves device/server
  - Faster for simple tasks

  Trade-offs:
  - Lower quality than GPT-4
  - Limited to smaller models (<7B parameters)
  - Requires GPU resources
  """
  def translate_local(text, target_lang) do
    # Use local Llama 3.2 3B model
    # Runs on iPhone 15+ or server GPU
  end
end
```

### 15.2 Multi-Modal Support

- Image translation (OCR + translate)
- Voice message transcription + translation
- Video subtitle generation

### 15.3 Advanced Workflow Automation

- N8N integration for external tool syncing
- Export to Notion, Trello, Google Calendar
- Slack/Telegram notifications for deadlines

### 15.4 Fine-Tuned Models

- Train custom model on user's communication style
- Personalized formality adjustments
- Better cultural context for specific industries

---

## Appendix A: Glossary

- **RAG:** Retrieval Augmented Generation - using search to provide context to LLMs
- **Embedding:** Vector representation of text (3072 floats for text-embedding-3-large)
- **Cosine Similarity:** Measure of vector similarity (1.0 = identical, 0 = unrelated)
- **LangChain:** Framework for building LLM applications with chains
- **sqlite-vec:** SQLite extension for vector operations (vec0 virtual table)
- **Function Calling:** LLM feature for structured output (OpenAI/Anthropic)
- **Oban:** Background job processing for Elixir/Phoenix

---

## Appendix B: References

**Documentation:**
- [LangChain Elixir](https://hexdocs.pm/langchain/)
- [OpenAI API](https://platform.openai.com/docs/api-reference)
- [Anthropic API](https://docs.anthropic.com/claude/reference)
- [sqlite-vec](https://github.com/asg017/sqlite-vec)
- [Oban](https://hexdocs.pm/oban/Oban.html)

**Cost Calculators:**
- [OpenAI Pricing](https://openai.com/pricing)
- [Anthropic Pricing](https://www.anthropic.com/pricing)

**Vector Search:**
- [Understanding Vector Databases](https://www.pinecone.io/learn/vector-database/)
- [RAG Best Practices](https://www.anthropic.com/index/retrieval-augmented-generation)

---

**Document End**

This PRD is ready to be parsed by Taskmaster for task generation.
