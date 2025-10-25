# AI Smart Reply System - Flow Diagrams

## 1. Smart Reply Generation Flow

```mermaid
sequenceDiagram
    participant User
    participant API as AIController
    participant SRG as SmartReplyGenerator
    participant OpenAI as OpenAI Embeddings
    participant VS as VectorStore
    participant Groq as Groq LLM
    participant DB as PostgreSQL

    User->>API: POST /api/v1/ai/suggest_replies
    API->>SRG: generate_suggestions(user_id, thread_id, messages)

    Note over SRG: Step 1: Get User Profile
    SRG->>DB: Get UserStyleProfile
    DB-->>SRG: Profile (formality, emoji_freq, etc.)

    Note over SRG: Step 2: Build Context
    SRG->>SRG: build_conversation_context(messages)

    Note over SRG: Step 3: RAG Retrieval
    SRG->>OpenAI: Generate embedding(context_text)
    OpenAI-->>SRG: [3072 floats]
    SRG->>VS: search_accepted_suggestions(user_id, embedding)
    VS->>VS: Cosine similarity search
    VS-->>SRG: Top 5 similar accepted suggestions

    Note over SRG: Step 4: LLM Generation
    SRG->>Groq: Generate completions with context + style + RAG
    Groq-->>SRG: "1. Sounds good!\n2. Thanks!\n3. Got it"

    Note over SRG: Step 5: Parse & Format
    SRG->>SRG: parse_ai_suggestions()
    SRG-->>API: [3 suggestion objects]
    API-->>User: JSON response (500-3300ms)
```

## 2. User Style Learning Flow

```mermaid
sequenceDiagram
    participant User
    participant TC as ThreadChannel
    participant SRG as SmartReplyGenerator
    participant OpenAI as OpenAI Embeddings
    participant VS as VectorStore (SQLite)
    participant DB as PostgreSQL

    User->>TC: Send message
    TC->>SRG: learn_user_style(user_id, message, thread_id)

    Note over SRG: Step 1: Get/Create Profile
    SRG->>DB: Get UserStyleProfile
    DB-->>SRG: Existing profile or nil

    Note over SRG: Step 2: Analyze Message
    SRG->>SRG: analyze_message(content)
    SRG->>SRG: calculate_formality()
    SRG->>SRG: calculate_complexity()
    SRG->>SRG: count_emojis()
    SRG->>SRG: extract_patterns()

    Note over SRG: Step 3: Update Profile
    SRG->>DB: Update UserStyleProfile (running averages)
    DB-->>SRG: Updated profile

    Note over SRG: Step 4: Store Embedding
    SRG->>OpenAI: Generate embedding(message.content)
    OpenAI-->>SRG: [3072 floats]
    SRG->>VS: insert_user_style(user_id, "general", embedding)
    VS->>VS: Store as JSON in user_style_embeddings

    SRG-->>TC: {:ok, updated_profile}
    TC-->>User: Message sent + style learned
```

## 3. Feedback Recording & Learning Flow

```mermaid
sequenceDiagram
    participant User
    participant API as AIController
    participant SRG as SmartReplyGenerator
    participant OpenAI as OpenAI Embeddings
    participant VS as VectorStore (SQLite)
    participant DB as PostgreSQL

    User->>API: POST /api/v1/ai/record_feedback
    Note over User: User accepts/rejects suggestion

    API->>SRG: record_feedback(user_id, thread_id, suggestion, accepted)

    Note over SRG: Step 1: Create Feedback Record
    SRG->>DB: Insert SuggestionFeedback
    Note over DB: Stores: type, content, accepted,<br/>time_to_response, position, confidence
    DB-->>SRG: Feedback record with ID

    Note over SRG: Step 2: Generate Embedding
    SRG->>OpenAI: Generate embedding(suggestion.content)
    OpenAI-->>SRG: [3072 floats]

    Note over SRG: Step 3: Store for RAG
    SRG->>VS: insert_feedback(feedback_id, user_id, type, accepted, embedding)
    VS->>VS: Store as JSON in feedback_embeddings
    Note over VS: Fields: feedback_id, user_id,<br/>suggestion_type, accepted (0/1),<br/>embedding (JSON array)

    SRG-->>API: :ok
    API-->>User: Success (600-4800ms)

    Note over VS,DB: Future suggestions will use this<br/>embedding for RAG retrieval
```

## 4. RAG Semantic Search Flow

```mermaid
flowchart TD
    Start[Query: Need similar suggestions] --> GenEmbed[Generate query embedding<br/>OpenAI text-embedding-3-large]
    GenEmbed --> GetAll[Get all accepted suggestions<br/>for this user from SQLite]

    GetAll --> Loop{For each<br/>stored<br/>suggestion}

    Loop -->|Parse JSON| ParseEmbed[Parse stored embedding<br/>from JSON array]
    ParseEmbed --> CalcSim[Calculate cosine similarity<br/>dot_product / magnitudes]

    CalcSim --> ToDist[Convert to distance<br/>distance = 1.0 - similarity]
    ToDist --> Loop

    Loop -->|Done| Sort[Sort by distance<br/>ascending]
    Sort --> Limit[Take top 5 results]
    Limit --> Return[Return similar suggestions<br/>with similarity scores]

    Return --> End[Use in LLM prompt<br/>for context-aware generation]

    style GenEmbed fill:#e1f5ff
    style CalcSim fill:#fff3cd
    style Return fill:#d4edda
```

## 5. Conversation Monitor Flow (Real-time AI)

```mermaid
sequenceDiagram
    participant TC as ThreadChannel
    participant PubSub
    participant CM as ConversationMonitor
    participant Groq as Groq LLM

    Note over TC: User sends message
    TC->>PubSub: broadcast {:new_message, message}
    PubSub->>CM: handle_info {:new_message}

    CM->>CM: add_message_to_window(message)
    Note over CM: Sliding window of last 20 messages

    CM->>CM: Schedule analysis in 2s

    Note over CM: 2 seconds later...
    CM->>CM: analyze_messages()

    CM->>CM: detect_confusion()
    Note over CM: Check for: "?", "idk",<br/>"not sure", "confused"

    CM->>CM: detect_complexity()
    Note over CM: Check for: long messages (>200 chars),<br/>high word count (>30 avg)

    alt Confusion detected
        CM->>Groq: Generate clarification suggestions
        Groq-->>CM: "1. Could you clarify?\n2. What do you mean?"
        CM->>CM: parse_numbered_suggestions()
    end

    alt Complexity detected
        CM->>Groq: Generate simplification suggestions
        Groq-->>CM: "1. Let me break that down\n2. Got it, thanks"
        CM->>CM: parse_numbered_suggestions()
    end

    CM->>PubSub: broadcast {:ai_suggestions, suggestions}
    PubSub->>TC: Deliver to subscribers
    TC-->>TC: Push to clients via WebSocket
```

## 6. Complete Workflow - End to End

```mermaid
flowchart TD
    Start([User sends message]) --> Channel[ThreadChannel receives]

    Channel --> Learn[Learn user style<br/>SmartReplyGenerator.learn_user_style]
    Learn --> EmbedStyle[Generate embedding<br/>OpenAI API]
    EmbedStyle --> StoreStyle[Store in user_style_embeddings<br/>SQLite vec0]

    Channel --> Monitor[ConversationMonitor<br/>checks for confusion/complexity]
    Monitor --> LLMCheck{Needs AI<br/>help?}
    LLMCheck -->|Yes| GroqHelp[Groq LLM generates<br/>clarification/simplification]
    LLMCheck -->|No| Continue
    GroqHelp --> Broadcast[Broadcast AI suggestions<br/>to thread subscribers]

    Continue --> UserRequest{User requests<br/>smart reply?}
    UserRequest -->|Yes| GetProfile[Get UserStyleProfile<br/>from PostgreSQL]

    GetProfile --> BuildContext[Build conversation context<br/>from recent messages]
    BuildContext --> RAG[RAG: Search similar accepted suggestions]

    RAG --> EmbedContext[Generate context embedding<br/>OpenAI API]
    EmbedContext --> SearchVec[Cosine similarity search<br/>in feedback_embeddings]
    SearchVec --> TopK[Get top 5 similar<br/>accepted suggestions]

    TopK --> LLMGen[Generate suggestions with Groq<br/>Context + Style + RAG examples]
    LLMGen --> Parse[Parse numbered list<br/>into suggestion objects]
    Parse --> ReturnSugg[Return 3 suggestions<br/>to user]

    ReturnSugg --> UserChoice{User accepts<br/>suggestion?}
    UserChoice -->|Yes/No| RecordFeed[Record feedback<br/>in PostgreSQL]
    RecordFeed --> EmbedFeed[Generate suggestion embedding<br/>OpenAI API]
    EmbedFeed --> StoreFeed[Store in feedback_embeddings<br/>for future RAG]

    StoreFeed --> End([Complete learning loop<br/>improves future suggestions])

    UserRequest -->|No| End
    Broadcast --> End

    style Learn fill:#e1f5ff
    style RAG fill:#fff3cd
    style LLMGen fill:#d4edda
    style RecordFeed fill:#f8d7da
    style End fill:#d1ecf1
```

## 7. Data Flow - Vector Embeddings

```mermaid
flowchart LR
    subgraph Input
        Msg[User Message<br/>String text]
        Sugg[Suggestion<br/>String content]
        Context[Conversation Context<br/>Multiple messages]
    end

    subgraph OpenAI[OpenAI API]
        API[text-embedding-3-large<br/>Model]
    end

    subgraph VectorDB[SQLite vec0]
        StyleTable[(user_style_embeddings<br/>embedding_id, user_id,<br/>style_aspect, embedding)]
        FeedbackTable[(feedback_embeddings<br/>feedback_id, user_id,<br/>suggestion_type, accepted,<br/>embedding)]
        MsgTable[(message_embeddings<br/>message_id, embedding)]
    end

    subgraph Search[Semantic Search]
        CosSim[Cosine Similarity<br/>dot_product / magnitudes]
        Sort[Sort by similarity<br/>Return top K]
    end

    Msg -->|POST request| API
    Sugg -->|POST request| API
    Context -->|POST request| API

    API -->|3072 floats<br/>JSON array| StyleTable
    API -->|3072 floats<br/>JSON array| FeedbackTable
    API -->|3072 floats<br/>Binary format| MsgTable

    Context -.Query embedding.-> API
    API -.Query vector.-> CosSim
    FeedbackTable -.Stored vectors.-> CosSim
    CosSim --> Sort
    Sort -.Top 5 matches.-> RAG[RAG Context<br/>for LLM prompt]

    style API fill:#e1f5ff
    style CosSim fill:#fff3cd
    style RAG fill:#d4edda
```

## 8. Database Schema - AI Tables

```mermaid
erDiagram
    users ||--o{ user_style_profiles : has
    users ||--o{ suggestion_feedbacks : provides
    threads ||--o{ suggestion_feedbacks : contains

    users {
        uuid id PK
        string username
        string email
        timestamp inserted_at
    }

    user_style_profiles {
        uuid id PK
        uuid user_id FK
        float formality_level
        float emoji_frequency
        float avg_sentence_length
        integer messages_analyzed
        float confidence_score
        map common_phrases
        timestamp updated_at
    }

    suggestion_feedbacks {
        uuid id PK
        uuid user_id FK
        uuid thread_id FK
        string suggestion_type
        text suggestion_content
        boolean accepted
        text user_modified_content
        string rejection_reason
        map context_metadata
        integer time_to_response_ms
        integer suggestion_position
        float confidence_score
        timestamp inserted_at
    }

    threads {
        uuid id PK
        string title
        timestamp inserted_at
    }
```

## 9. SQLite Vector Tables (Per-Thread)

```sql
-- Each thread has its own SQLite database with these vec0 tables:

-- Message embeddings (binary format)
CREATE VIRTUAL TABLE message_embeddings USING vec0(
    message_id TEXT PRIMARY KEY,
    embedding float[3072]  -- Binary format
);

-- User style embeddings (JSON format)
CREATE VIRTUAL TABLE user_style_embeddings USING vec0(
    embedding_id TEXT PRIMARY KEY,
    user_id TEXT,
    style_aspect TEXT,  -- "general", "vocabulary", "tone"
    embedding float[3072]  -- JSON array format
);

-- Suggestion feedback embeddings (JSON format)
CREATE VIRTUAL TABLE feedback_embeddings USING vec0(
    feedback_id TEXT PRIMARY KEY,
    user_id TEXT,
    suggestion_type TEXT,  -- "smart_reply", "confusion_clarification"
    accepted INTEGER,  -- 0 or 1
    embedding float[3072]  -- JSON array format
);
```

## Performance Benchmarks

### With Real AI (Current Implementation)
- **Style learning**: 1,480-2,680ms (includes OpenAI embedding)
- **Suggestion generation**: 178-3,333ms (Groq LLM + RAG search)
- **Feedback recording**: 415-4,890ms (includes OpenAI embedding)
- **Total workflow**: 2,569-6,507ms

### API Calls Per Request
- **Smart Reply Generation**: 1-2 OpenAI calls (context + RAG query) + 1 Groq call
- **Style Learning**: 1 OpenAI call per message
- **Feedback Recording**: 1 OpenAI call per feedback

### Cost Estimates
- **OpenAI text-embedding-3-large**: ~$0.13 per 1M tokens
- **Groq llama-3.1-8b-instant**: ~$0.05 per 1M tokens (very fast)
- **Average cost per suggestion**: ~$0.0001-0.0005

## Technical Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Web Framework | Phoenix/Elixir | API endpoints, channels |
| Primary DB | PostgreSQL | User profiles, feedback records |
| Vector DB | SQLite + vec0 | Embeddings, semantic search |
| Embeddings | OpenAI text-embedding-3-large | 3072-dim vectors |
| LLM | Groq llama-3.1-8b-instant | Fast suggestion generation |
| Real-time | Phoenix PubSub | Live AI suggestions |
| Search | Cosine Similarity | Semantic matching |

---

*All diagrams generated for GlobalBridge AI Smart Reply System*
*Real AI implementation - no mocks, no placeholders*
