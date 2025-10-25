# GlobalBridge Backend - Comprehensive Codebase Overview

## Part 1: Transaction Endpoints

### Current State: No Dedicated Transaction Endpoints
The backend does **NOT** currently implement traditional transaction endpoints. The router shows only the following API endpoints in `/api/v1/`:

**Available API Endpoints:**

1. **Feature Management**
   - `GET /api/v1/features` - List feature flags
   - `GET /api/v1/features/:feature` - Get specific feature
   - `PUT /api/v1/features/tier` - Update user feature tier

2. **Sync/CDC Operations** (CDC = Change Data Capture)
   - `POST /api/v1/sync/pull` - Pull changes from server
   - `POST /api/v1/sync/push` - Push local changes to server

3. **Thread Management**
   - `GET /api/v1/threads` - List threads

4. **AI Features** (Rate-limited per-user)
   - `POST /api/v1/ai/translate` - Translate text
   - `POST /api/v1/ai/analyze_tone` - Analyze message tone
   - `POST /api/v1/ai/summarize_thread` - Generate thread summary
   - `POST /api/v1/ai/search_semantic` - Semantic search
   - `POST /api/v1/ai/extract_tasks` - Extract tasks from thread
   - `POST /api/v1/ai/vec_health` - Check vector database health

### Router File Location
`/Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend/lib/globalbridge_backend_web/router.ex`

**Key Router Features:**
- Rate limiting: 100 requests/60s for general API, 5 requests/60s for auth
- CORS support with security headers
- Auth pipeline with Guardian JWT
- AI-specific rate limiting via `GlobalbridgeBackendWeb.Plugs.RateLimitAI`
- Thread cache plugin via `GlobalbridgeBackendWeb.Plugs.ThreadCache`

### Controllers
Located in: `/Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend/lib/globalbridge_backend_web/controllers/`

**Available Controllers:**
- `ai_controller.ex` - AI endpoints (translate, analyze_tone, summarize_thread, search_semantic, extract_tasks, vec_health)
- `auth_controller.ex` - Authentication (signup, login, refresh, OAuth, logout, password change, public key management)
- `bootstrap_controller.ex` - Initial client data
- `feature_controller.ex` - Feature flag management
- `sync_controller.ex` - CDC sync operations (pull/push)
- `thread_controller.ex` - Thread listing

### Context Modules (Business Logic)
Located in: `/Users/reuben/gauntlet/whatsapp-clone/globalbridge_backend/lib/globalbridge_backend/contexts/`

**Available Contexts:**
- `auth.ex` - User authentication, credentials, password management
- `contacts.ex` - Contact management and search
- `messages.ex` - Message operations
- `messaging.ex` - Messaging services
- `threads.ex` - Thread lifecycle and participant management

**Key Threads Context Methods:**
- `list_threads/1` - List user's threads
- `get_thread/1`, `get_thread!/1` - Fetch thread
- `create_thread/1`, `update_thread/2`, `delete_thread/1`
- `archive_thread/1`, `unarchive_thread/1` - Archive operations
- `mute_thread/1`, `unmute_thread/1` - Notification control
- `add_participant/3`, `remove_participant/2` - Participant management
- `list_participants/1` - Get thread participants
- `get_thread_for_direct_message/2` - DM lookup
- `list_user_threads/2` - Get user's threads with filters

---

## Part 2: Agentic Logic - Agens Framework Integration

### Overview
The backend uses the **Agens multi-agent framework** for AI-powered language processing, translation, summarization, and task extraction. The architecture is built around:

1. **Serving** - OpenAI API abstraction (routes to OpenAI/Groq/XAI)
2. **Agents** - Specialized AI workers (language detection, translation, idiom analysis, summarization)
3. **Jobs** - Multi-step orchestration workflows
4. **Tools** - Agent utilities (cultural context analysis, task extraction)

### Architecture Initialization

**Application Startup** (`application.ex`):
```
1. Agens.Supervisor starts multi-agent framework
2. Cachex cache initialized (:ai_cache)
3. GlobalbridgeBackend.AI.AgensSetup.start_components() - Sets up all agents/jobs
4. GlobalbridgeBackend.AI.Telemetry.setup() - Telemetry monitoring
5. AI Cost Tracking and Budget Monitoring services
6. Rate Limit Monitoring
```

**Key AI Components Initialized:**
- OpenAI Serving (GenServer)
- Language Detection Agent
- Translator Agent
- Idiom Analyzer Agent
- Summarizer Agent
- Translation Job
- Embedding services and semantic search

### Agent Architecture

#### 1. **Serving Layer** - OpenAI Serving (`openai_serving.ex`)
GenServer that handles API calls to language models.

**Capabilities:**
- Multi-provider support: OpenAI, Groq (via llama-3.1-70b-versatile), XAI (Grok)
- Context-aware model routing based on prompt keywords
- Automatic provider selection (groq for llama/mixtral, xai for grok-*)

**Model Selection Logic:**
```
- Summarization context → SUMMARIZER_MODEL (default: grok-2-1212)
- Translation context → TRANSLATION_MODEL (default: llama-3.1-70b-versatile)
- Language detection → OPENAI_MODEL (default: llama-3.1-70b-versatile)
- Default fallback → llama-3.1-70b-versatile
```

**API Calls:**
- Groq: `https://api.groq.com/openai/v1/chat/completions`
- XAI (Grok): `https://api.x.ai/v1/chat/completions`
- OpenAI: Uses openai-elixir library

#### 2. **Language Detection Agent** (`agents/language_detection_agent.ex`)
**Purpose:** Identify source language of input text

**Configuration:**
- Serving: `:openai_serving`
- Identity: "You are a language detection expert"
- Output format: `"Detected language: <language>"`
- Uncertainty handling: Defaults to English

**Workflow Integration:** Used in TranslationJob as first step

#### 3. **Translator Agent** (`agents/translator_agent.ex`)
**Purpose:** Translate text with confidence scores and cultural context

**Configuration:**
- Serving: `:openai_serving`
- Tool: `CulturalContextTool` (analyzes cultural elements)
- Identity: "Expert translator specializing in culturally appropriate translations"
- Output format:
  ```
  Translation: <translated text>
  Confidence: <0.0-1.0>
  ```

**Confidence Score Factors:**
- Text complexity
- Availability of cultural context
- Presence of idioms or challenging phrases
- Translation fidelity

**Edge Case Handling:**
- Same source/target language → Returns original text, confidence 1.0
- Empty text → Returns empty, confidence 1.0
- Uncertain idioms → Lower confidence (0.5 or below)

**Direct API:** `translate(text, source_lang, target_lang)`

#### 4. **Idiom Analyzer Agent** (`agents/idiom_analyzer_agent.ex`)
**Purpose:** Detect and analyze idioms, cultural phrases, and expressions

**Configuration:**
- Model: Groq llama-3.1-70b-versatile (~$0.59/1M tokens)
- Serving: `:openai_serving` (routed to Groq)
- Temperature: 0.1 (low for consistency)
- Output: JSON array of idioms

**Output Structure:**
```json
[
  {
    "source_phrase": "Break a leg",
    "explanation": "A theatrical idiom meaning 'good luck'",
    "target_equivalent": "¡Mucha mierda!",
    "cultural_context": "Theater tradition of wishing performers good luck"
  }
]
```

**Features:**
- Empty array returned if no idioms found
- Validates output structure
- Extracts JSON from code blocks or plain text
- Trims whitespace and validates fields

**Direct API:** `analyze(text, source_language, target_language, opts)`

#### 5. **Summarizer Agent** (`agents/summarizer_agent.ex`)
**Purpose:** Generate structured conversation summaries

**Configuration:**
- Model: Grok-2-1212 (cost-optimized)
- Serving: `:openai_serving`
- Temperature: 0.1 (for consistency)
- Output: Structured JSON

**Output Structure:**
```json
{
  "summary": "2-3 sentence overview",
  "decisions": ["List of decisions made"],
  "action_items": ["List with assignees if mentioned"],
  "key_points": ["Important facts or information"],
  "participants": ["Main participants"],
  "confidence_score": 0.95
}
```

**Analysis Focus:**
- Main topics and themes
- Decisions made or agreements
- Action items and responsibilities
- Important facts and data
- Questions and resolutions
- Plan/direction changes
- Key participants and contributions

**Direct API:** `summarize(context, thread_id, opts)`

#### 6. **RAG Retriever Agent** (`agents/rag_retriever_agent.ex`)
**Purpose:** Retrieve relevant messages using semantic search for summarization

**Capabilities:**
- Semantic search on message embeddings (using sqlite-vec)
- Cosine similarity ranking
- Recency bias application
- Context building for LLM processing

**Search Query Generation:**
- Decision-focused: "decisions agreements choices conclusions"
- Action-focused: "action items tasks responsibilities commitments"
- Problem-focused: "problems issues solutions fixes resolutions"
- Summary-focused: "key points important information main topics"
- Meeting-focused: "meeting discussion agenda outcomes next steps"

**Direct API:** `retrieve(thread_id, objective, opts)`

**Options:**
- `limit`: Max messages to retrieve (default: 20)
- `recency_bias`: Apply recency bias (default: true)
- `recency_weight`: Recency weight (default: 0.3)
- `max_context_length`: Max context length for LLM (default: 8000)

### Jobs - Multi-Agent Orchestration

#### 1. **Translation Job** (`jobs/translation_job.ex`)
**Purpose:** End-to-end translation with idiom analysis

**Sequential Workflow:**
```
Step 1: Language Detection Agent
  → Detect source language
  → Output: "Detected language: <language>"

Step 2: Translator Agent
  → Translate with cultural context
  → Output: "Translation: <text>\nConfidence: <score>"

Step 3: Idiom Analyzer Agent
  → Analyze idioms in source text
  → Output: JSON array of idioms
```

**Final Response:**
```json
{
  "translation": "translated text",
  "confidence": 0.95,
  "cultural_notes": [idiom_objects],
  "source_language": "English",
  "target_language": "Spanish"
}
```

**Entry Point:** `translate_with_idioms(text, target_language, opts)`

**Response Assembly:** Parses job results and extracts:
- Source language from "Detected language:" format
- Translation and confidence from "Translation:" format
- Idioms from JSON array output

#### 2. **Summarization Job** (`jobs/summarization_job.ex`)
**Purpose:** Retrieve and summarize thread conversations

**Two-Step Workflow:**
```
Step 1: RAGRetrieverAgent.retrieve(thread_id, objective, opts)
  → Retrieve relevant messages with recency bias
  → Output: %{results: [...], context: "..."}

Step 2: SummarizerAgent.summarize(context, thread_id, opts)
  → Generate structured summary from context
  → Output: Summary with decisions, action items, etc.
```

**Configuration Options:**
- `max_messages`: Maximum messages to retrieve (default: 20)
- `recency_bias`: Apply recency bias (default: true)
- `recency_weight`: Recency weight (default: 0.3)
- `max_context_length`: Max context length (default: 8000)

**Entry Points:**
- `summarize_thread(thread_id, objective, opts)` - Full job
- `summarize_direct(thread_id, objective, opts)` - Direct agent calls

#### 3. **Other Jobs**
- `batch_embed_job.ex` - Batch embedding generation
- `cleanup_cache_job.ex` - Cache maintenance
- `generate_embedding_job.ex` - Single embedding generation

### Tools - Agent Utilities

#### 1. **Cultural Context Tool** (`tools/cultural_context_tool.ex`)
**Agens Tool Implementation** - Provides cultural analysis for translations

**Tool Lifecycle:**
1. `pre(input)` - Prepare text for cultural analysis
2. `instructions()` - Guide language model on usage
3. `to_args(result)` - Parse LM output to arguments
4. `execute(args)` - Perform analysis
5. `post(result)` - Format result for next step

**Output Format:**
```json
{
  "cultural_elements": ["list", "of", "elements"],
  "translation_notes": "specific guidance",
  "target_culture_adaptations": ["adaptations"]
}
```

#### 2. **Task Extraction Tool** (`tools/task_extraction_tool.ex`)
**Purpose:** Extract tasks, deadlines, and decisions from conversation context

**Extraction Types:**

**Task Items:**
```elixir
%{
  id: String,
  description: String,
  assignee: String | nil,
  priority: String,
  status: String,
  confidence: float,
  source_message_id: String,
  extracted_at: DateTime
}
```

**Deadline Items:**
```elixir
%{
  id: String,
  description: String,
  due_date: String | nil,
  related_task_id: String | nil,
  confidence: float,
  source_message_id: String,
  extracted_at: DateTime
}
```

**Decision Items:**
```elixir
%{
  id: String,
  description: String,
  outcome: String,
  participants: [String],
  confidence: float,
  source_message_id: String,
  extracted_at: DateTime
}
```

**Workflow:**
1. Generate query embedding
2. RAG retrieval with recency bias
3. Build context from messages
4. Extract items from context

**Entry Point:** `extract_from_thread(thread_id, query, opts)`

### AI Support Services

#### 1. **Embedding Service** (`embedding_service.ex`)
Generates vector embeddings for semantic search

#### 2. **Semantic Search** (`semantic_search.ex`)
Performs similarity search on message embeddings using sqlite-vec

#### 3. **RAG Retriever** (`rag_retriever.ex`)
Wrapper for semantic search with context building

#### 4. **Vector Store** (`vector_store.ex`)
Manages vector storage and operations

#### 5. **Cache** (`cache.ex`)
Translation and embedding caching with TTL

#### 6. **Cost Tracker** (`cost_tracker.ex`)
Tracks AI API costs per user

#### 7. **Budget Monitor** (`budget_monitor.ex`)
Monitors user budgets and enforces limits

#### 8. **Cost Optimizer** (`cost_optimizer.ex`)
Optimizes model selection for cost

#### 9. **Authorization** (`authorization.ex`)
Handles user/thread access control for AI operations

### AI Controller - Request Handling

**File:** `controllers/ai_controller.ex`

**Endpoints:**

1. **POST /api/v1/ai/translate**
   - Input: `text` (max 10k chars), `target_language`, `source_language` (optional)
   - Output: translation, confidence, cultural_notes, source/target languages
   - Uses: Simple translation via Groq API (bypasses Agens for now)
   - Idiom analysis via IdiomAnalyzerAgent

2. **POST /api/v1/ai/analyze_tone**
   - Input: `text` (max 10k chars), `language` (optional)
   - Output: tone, confidence, emotions, language
   - Currently returns placeholder responses (TODO: implement full tone analysis)

3. **POST /api/v1/ai/summarize_thread**
   - Input: `thread_id` (UUID), `max_length` (optional, default 200)
   - Uses: SummarizationJob for RAG + summarization
   - Output: summary, thread_id, max_length

4. **POST /api/v1/ai/search_semantic**
   - Input: `query` (max 1k chars), `thread_id` (optional), `limit` (1-50), `recency_bias`, `translate`
   - Uses: SemanticSearch for embeddings
   - Output: query, results array, total_results, thread_id

5. **POST /api/v1/ai/extract_tasks**
   - Input: `thread_id` (UUID), `query` (optional)
   - Uses: TaskExtractionTool with RAG retrieval
   - Output: extraction (tasks, deadlines, decisions), thread_id, query

6. **POST /api/v1/ai/vec_health**
   - Input: `thread_id` (UUID)
   - Checks: vec0 extension availability, embeddings table, row count
   - Output: vec_extension_available, embeddings_table_exists, embeddings_count

**Error Handling:**
- Input validation via AIValidator
- Thread access authorization checks
- Safe error responses (no internal details leaked)
- Exception handling with logging

### Agent State Management

**Initialization** (`agens_setup.ex`):
```elixir
start_components() do
  # Start OpenAI Serving (router to OpenAI/Groq/XAI)
  Serving.start(:openai_serving_config)
  
  # Start Language Detection Agent
  Agent.start(LanguageDetectionAgent.config())
  
  # Start Translator Agent
  Agent.start(TranslatorAgent.config())
  
  # Start Idiom Analyzer Agent
  Agent.start(IdiomAnalyzerAgent.config())
  
  # Start Summarizer Agent
  Agent.start(SummarizerAgent.config())
  
  # Start Translation Job
  Job.start(TranslationJob.job_config())
end
```

**State Persistence:**
- GenServer state in OpenAI Serving
- ETS cache for thread repos (initialized before supervisor)
- Cachex for translation/embedding cache
- Oban for background job persistence (not in test)

### Multi-Agent Coordination & Workflows

**Translation Workflow Example:**
```
1. AIController.translate() receives request
2. Calls simple_translate() via Groq API (direct, not Agens job)
3. Also calls IdiomAnalyzerAgent.analyze() for cultural analysis
4. Returns enriched response with cultural_notes

Alternative (Full Agens Job):
1. TranslationJob.translate_with_idioms() initiates job
2. LanguageDetectionAgent identifies source language
3. TranslatorAgent translates with CulturalContextTool
4. IdiomAnalyzerAgent analyzes idioms in source text
5. Response assembled with cultural_notes
```

**Summarization Workflow:**
```
1. AIController.summarize_thread() receives request
2. SummarizationJob.summarize_thread() initiates
3. RAGRetrieverAgent generates search query and retrieves messages
4. Context built from retrieved messages
5. SummarizerAgent generates structured summary
6. Response returned to client
```

**Task Extraction Workflow:**
```
1. AIController.extract_tasks() receives request
2. TaskExtractionTool.extract_from_thread() processes
3. Generate embedding for extraction query
4. RAG search with recency bias
5. Extract tasks, deadlines, decisions from context
6. Return extraction_result with metadata
```

### Cost Optimization Strategy

**Model Selection by Task:**
- **Language Detection:** llama-3.1-70b-versatile (~$0.05-0.2/1M tokens)
- **Translation:** llama-3.1-70b-versatile (~$0.2/1M tokens)
- **Idiom Analysis:** llama-3.1-70b-versatile (~$0.59/1M tokens)
- **Summarization:** grok-2-1212 (XAI, high speed)

**Cost Tracking:**
- Per-user API call tracking
- Budget monitoring with limits
- Cost optimization suggestions
- Telemetry metrics collection

### Error Handling & Resilience

**Validation:**
- AIValidator module for input sanitization
- Thread access authorization checks
- UUID validation
- Language code validation

**Error Recovery:**
- Fallback to empty results if retrieval fails
- Default confidence scores if parsing fails
- Graceful degradation (empty cultural_notes, etc.)
- Detailed logging for debugging

**Security:**
- User ID extraction from JWT (Guardian)
- Thread access verification before AI operations
- No internal error details in API responses
- Rate limiting per user per endpoint

---

## Summary

### Transaction System
No traditional transaction endpoints exist. The API focuses on:
- Thread/message management
- CDC sync operations
- Feature flags
- AI-powered language features

### Agentic System
Comprehensive multi-agent AI framework using Agens:
- **5 Core Agents:** Language detection, translation, idiom analysis, summarization, RAG retrieval
- **2 Main Jobs:** Translation workflow, Summarization workflow
- **Multi-Provider Support:** OpenAI, Groq, XAI (Grok)
- **Cost Optimization:** Model selection per task
- **Vector-based Search:** sqlite-vec for semantic search
- **Structured Outputs:** JSON-based results from all agents
- **Tool Integration:** Cultural context and task extraction tools
- **State Management:** GenServer + ETS + Cachex + Oban

The system is designed for cost-effective, multi-step AI operations with emphasis on translation and conversation analysis for a messaging platform.
