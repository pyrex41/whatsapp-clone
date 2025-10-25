# Product Requirements Document: AI Features iOS Implementation

## Document Information
- **Version**: 1.0
- **Date**: 2025-01-XX
- **Status**: Approved
- **Platform**: iOS (Swift/SwiftUI)
- **Backend**: Phoenix/Elixir (Already Implemented)

## Executive Summary

Implement comprehensive AI features in the GlobalBridge iOS app to match the existing backend capabilities:
- **Smart Reply**: AI-generated message suggestions with style learning
- **Real-time Monitoring**: Proactive AI help for confusion/complexity
- **Smart Translation**: Auto-detect with user preferences and batch optimization
- **Style Learning**: Personalized suggestions based on user writing patterns
- **Feedback Loop**: Continuous improvement through user interactions

## Background & Context

### Backend Implementation (Completed)
The backend AI system is fully operational with:
- Smart reply generation using Groq LLM (llama-3.1-8b-instant)
- RAG-based suggestion retrieval with OpenAI embeddings (text-embedding-3-large)
- User style profiling stored in PostgreSQL
- SQLite vector storage for semantic search
- Real-time conversation monitoring via Phoenix PubSub
- Batch translation service optimized for low latency

### Backend API Endpoints Available
```
POST /api/v1/ai/suggest_replies       # Get smart reply suggestions
POST /api/v1/ai/record_feedback       # Record user feedback
GET  /api/v1/ai/conversation_insights # Get acceptance stats
POST /api/v1/ai/translate            # Translate text
POST /api/v1/ai/summarize_thread     # Summarize conversation
POST /api/v1/ai/search_semantic      # Semantic message search
POST /api/v1/ai/extract_tasks        # Extract actionable tasks
POST /api/v1/ai/analyze_tone         # Tone analysis
```

### Phoenix Real-time Events
```elixir
# Broadcast from ConversationMonitor
{:ai_suggestions, suggestions}  # Proactive suggestions
{:new_message, message}          # Triggers style learning
```

## User Stories

### US-1: Smart Reply Suggestions
**As a user**, I want to see AI-generated reply suggestions while typing so that I can respond quickly with contextually appropriate messages.

**Acceptance Criteria:**
- [ ] Suggestions appear inline in the message composer
- [ ] 1-3 suggestions displayed based on conversation context
- [ ] Tap suggestion to insert into composer (not auto-send)
- [ ] Suggestions update as conversation evolves
- [ ] Loading state shows while fetching from backend
- [ ] Suggestions match my writing style (formality, emoji usage)

### US-2: Style Learning & Personalization
**As a user**, I want the AI to learn my writing style so that suggestions feel natural and personal.

**Acceptance Criteria:**
- [ ] App learns from every message I send
- [ ] Style profile includes formality, emoji frequency, sentence length
- [ ] Can view my style profile in settings
- [ ] Confidence score improves over time (target: >0.7 after 50 messages)
- [ ] Can disable style learning for privacy
- [ ] Can clear my style profile

### US-3: Feedback Loop
**As a user**, I want to accept, reject, or modify suggestions so that the AI improves over time.

**Acceptance Criteria:**
- [ ] Tapping suggestion records acceptance with timestamp
- [ ] Swiping away suggestion records rejection
- [ ] Modifying suggestion before sending records the change
- [ ] Can optionally provide rejection reason
- [ ] Feedback immediately improves future suggestions via RAG

### US-4: Real-time Monitoring
**As a user**, I want proactive AI suggestions when the conversation becomes confusing or complex.

**Acceptance Criteria:**
- [ ] AI detects confusion markers ("?", "idk", "not sure")
- [ ] AI detects complexity (long messages, high word count)
- [ ] Clarification suggestions appear as subtle toast
- [ ] Can dismiss proactive suggestions
- [ ] Can disable monitoring per thread
- [ ] Visual distinction between manual and proactive suggestions

### US-5: Smart Auto-Translation
**As a user**, I want messages in foreign languages automatically translated to my preferred language.

**Acceptance Criteria:**
- [ ] Set preferred language in settings
- [ ] Foreign messages auto-translate on receive
- [ ] Translation appears below original in message bubble
- [ ] Can toggle "Show Original" / "Show Translation"
- [ ] Per-contact language overrides (e.g., always Spanish with Maria)
- [ ] Per-thread translation toggle
- [ ] Confidence badge shown if <80%

### US-6: Translation Preferences
**As a user**, I want fine-grained control over translation behavior.

**Acceptance Criteria:**
- [ ] Global preferred language setting
- [ ] Global auto-translate toggle
- [ ] Per-thread override: "Auto-translate to [language]"
- [ ] Per-contact override stored and remembered
- [ ] Manual translation via long-press menu
- [ ] Batch translate all messages in thread on first open

### US-7: AI Insights & Analytics
**As a user**, I want to see how the AI is learning and performing.

**Acceptance Criteria:**
- [ ] View acceptance rate by suggestion type
- [ ] View style profile metrics (formality, emoji frequency, etc.)
- [ ] See conversation monitoring state per thread
- [ ] Export my AI data (style profile, feedback history)
- [ ] Privacy controls clearly visible

## Technical Architecture

### Core Services Layer

#### SmartReplyService.swift
**Responsibilities:**
- Fetch suggestions from `/api/v1/ai/suggest_replies`
- Cache suggestions (60s TTL per thread)
- Record feedback via `/api/v1/ai/record_feedback`
- Trigger style learning on message send
- Manage loading and error states

**Key Methods:**
```swift
func fetchSuggestions(threadId: UUID, count: Int) async throws -> [SmartReplySuggestion]
func recordFeedback(suggestion: SmartReplySuggestion, accepted: Bool, modified: String?) async throws
func getUserStyleProfile(userId: UUID) async throws -> UserStyleProfile
```

#### ConversationMonitorService.swift
**Responsibilities:**
- Subscribe to Phoenix AI suggestion broadcasts
- Handle `{:ai_suggestions, suggestions}` events
- Maintain sliding window of last 20 messages
- Dispatch proactive suggestions to UI

**Key Methods:**
```swift
func startMonitoring(threadId: UUID)
func stopMonitoring(threadId: UUID)
func handleAISuggestionBroadcast(_ suggestions: [SmartReplySuggestion])
```

#### SmartTranslationService.swift
**Responsibilities:**
- Auto-detect message language on receive
- Translate to user's preferred language
- Batch-translate smart reply suggestions
- Manage translation preferences (global, per-contact, per-thread)
- Cache translations (3600s TTL)

**Key Methods:**
```swift
func translateMessage(_ message: Message, to targetLang: String) async throws -> TranslationResult
func batchTranslateSuggestions(_ suggestions: [String], to targetLang: String) async throws -> [String]
func shouldAutoTranslate(message: Message, preferences: TranslationPreferences) -> Bool
func getPreferredLanguage(for contactId: UUID) -> String
```

### Models Layer

#### SmartReplySuggestion.swift
```swift
struct SmartReplySuggestion: Identifiable, Codable {
    let id = UUID()
    let type: String // "smart_reply", "confusion_clarification", "complexity_simplification"
    let content: String
    let confidence: Double // 0.0-1.0
    let position: Int // 1, 2, 3
    let context: SuggestionContext
    let timestamp: Date

    var isProactive: Bool {
        type != "smart_reply"
    }
}

struct SuggestionContext: Codable {
    let matchedStyle: Bool
    let lastMessageId: UUID
    let formalityLevel: Double
    let aiGenerated: Bool
}
```

#### UserStyleProfile.swift
```swift
struct UserStyleProfile: Codable {
    let userId: UUID
    let formalityLevel: Double // 0.0=casual, 1.0=formal
    let emojiFrequency: Double // emojis per message
    let avgSentenceLength: Double // words per sentence
    let messagesAnalyzed: Int
    let confidenceScore: Double // 0.0-1.0
    let lastUpdatedAt: Date

    var isHighConfidence: Bool {
        confidenceScore > 0.7
    }
}
```

#### TranslationPreferences.swift
```swift
struct TranslationPreferences: Codable {
    let preferredLanguage: String // ISO 639-1 code
    let autoTranslateEnabled: Bool
    let contactOverrides: [UUID: String] // contactId -> language
    let threadOverrides: [UUID: String] // threadId -> language

    static var `default`: TranslationPreferences {
        TranslationPreferences(
            preferredLanguage: Locale.current.language.languageCode?.identifier ?? "en",
            autoTranslateEnabled: true,
            contactOverrides: [:],
            threadOverrides: [:]
        )
    }
}
```

#### SuggestionFeedback.swift
```swift
struct SuggestionFeedback: Codable {
    let suggestionId: UUID
    let accepted: Bool
    let modifiedContent: String?
    let rejectionReason: String?
    let timeToResponseMs: Int?
    let timestamp: Date
}
```

### UI Components

#### SmartReplyComposerView.swift
**Location:** `Features/Chat/SmartReplyComposerView.swift`

**Responsibilities:**
- Display 1-3 suggestion chips inline above/in text field
- Handle tap-to-insert interaction
- Show loading shimmer while fetching
- Display translation toggle for suggestions
- Swipe-to-dismiss gesture for rejection

**Visual Design:**
```
┌─────────────────────────────────────┐
│ [Message Thread]                    │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ ✨ Got it! 👍   Thanks!   Cool  │ │ ← Suggestion chips
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ Type a message...         [🌐] │ │ ← Composer
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

#### SuggestionChipView.swift
**Location:** `Features/Chat/SuggestionChipView.swift`

**Responsibilities:**
- Render individual suggestion as tappable chip
- Show confidence indicator (subtle)
- Distinguish proactive vs manual (icon/color)
- Haptic feedback on tap
- Swipe gesture for dismissal

#### TranslationBubbleView.swift
**Location:** `Features/Chat/TranslationBubbleView.swift`

**Responsibilities:**
- Overlay translation below original message
- Toggle between original/translated
- Show confidence badge if <80%
- Fade-in animation for auto-translated messages

**Visual Design:**
```
┌─────────────────────────────┐
│ Hola! ¿Cómo estás?         │ ← Original
│ ┌───────────────────────┐   │
│ │ Hello! How are you?   │   │ ← Translation
│ │ [95%] 🌐              │   │ ← Confidence
│ └───────────────────────┘   │
└─────────────────────────────┘
```

#### AIInsightsSheet.swift
**Location:** `Features/Chat/AIInsightsSheet.swift`

**Responsibilities:**
- Display conversation insights (acceptance stats)
- Show user style profile metrics
- Learning progress visualization
- Privacy controls (disable, clear, export)
- Monitoring state per thread

### State Management

#### AppAction.swift - New Actions
```swift
enum AppAction {
    // Existing actions...

    // Smart Reply
    case fetchSmartReplies(threadId: UUID, count: Int)
    case smartRepliesReceived(threadId: UUID, suggestions: [SmartReplySuggestion])
    case smartReplyFetchFailed(threadId: UUID, error: AIServiceError)
    case smartReplyAccepted(threadId: UUID, suggestion: SmartReplySuggestion)
    case smartReplyRejected(threadId: UUID, suggestion: SmartReplySuggestion, reason: String?)
    case smartReplyModified(threadId: UUID, original: SmartReplySuggestion, modified: String)

    // Real-time Monitoring
    case aiSuggestionBroadcast(threadId: UUID, suggestions: [SmartReplySuggestion])
    case startConversationMonitoring(threadId: UUID)
    case stopConversationMonitoring(threadId: UUID)

    // Translation
    case translateMessage(messageId: UUID, targetLang: String)
    case translationReceived(messageId: UUID, result: TranslationResult)
    case translationFailed(messageId: UUID, error: AIServiceError)
    case updateTranslationPreferences(TranslationPreferences)
    case toggleAutoTranslate(threadId: UUID)
    case setContactLanguage(contactId: UUID, language: String)

    // Style Profile
    case styleProfileUpdated(UserStyleProfile)
    case fetchStyleProfile(userId: UUID)
    case clearStyleProfile(userId: UUID)

    // Insights
    case showAIInsights(threadId: UUID)
    case hideAIInsights
}
```

#### AppState.swift - New Properties
```swift
struct AppState: Equatable {
    // Existing properties...

    // Smart Reply
    var smartReplySuggestions: [UUID: [SmartReplySuggestion]] = [:] // threadId -> suggestions
    var suggestionLoadingState: [UUID: Bool] = [:] // threadId -> isLoading
    var suggestionErrors: [UUID: AIServiceError] = [:] // threadId -> error

    // Style Learning
    var userStyleProfile: UserStyleProfile?
    var styleProfileLoading: Bool = false

    // Translation
    var translationPreferences: TranslationPreferences = .default
    var messageTranslations: [UUID: TranslationResult] = [:] // messageId -> translation
    var translationLoadingState: [UUID: Bool] = [:] // messageId -> isLoading

    // Monitoring
    var monitoredThreads: Set<UUID> = [] // threads with active monitoring

    // UI State
    var aiInsightsVisible: Bool = false
    var aiInsightsThreadId: UUID?
}
```

#### AppReducer.swift - Smart Reply Logic
```swift
// Example reducer logic
case .fetchSmartReplies(let threadId, let count):
    var state = state
    state.suggestionLoadingState[threadId] = true
    state.suggestionErrors[threadId] = nil

    return (state, .run { send in
        do {
            let suggestions = try await SmartReplyService.shared.fetchSuggestions(
                threadId: threadId,
                count: count
            )
            await send(.smartRepliesReceived(threadId: threadId, suggestions: suggestions))
        } catch let error as AIServiceError {
            await send(.smartReplyFetchFailed(threadId: threadId, error: error))
        }
    })
```

### Phoenix Channel Integration

#### PhoenixChannelManager+AI.swift
**Location:** `Core/Networking/Phoenix/PhoenixChannelManager+AI.swift`

**Responsibilities:**
- Subscribe to AI suggestion broadcasts for active threads
- Handle incoming `{:ai_suggestions, suggestions}` events
- Dispatch events to AppState via actions
- Trigger style learning on message send

**Key Methods:**
```swift
extension PhoenixChannelManager {
    func subscribeToAISuggestions(threadId: UUID) {
        // Join thread channel if not already joined
        // Listen for "ai_suggestions" events
        // Parse and dispatch to AppState
    }

    func triggerStyleLearning(userId: UUID, message: Message, threadId: UUID) {
        // Backend learns asynchronously via learn_user_style/3
        // No response needed, fire-and-forget
    }
}
```

## Implementation Phases

### Phase 1: Smart Reply Foundation (Week 1)
**Goal:** Basic smart reply suggestions working end-to-end

**Tasks:**
1. Create `SmartReplyService.swift` with API integration
2. Add `SmartReplySuggestion` and related models
3. Extend `AppState` and `AppAction` for smart reply
4. Build `SmartReplyComposerView` with inline chips
5. Implement tap-to-insert behavior
6. Add loading and error states
7. Wire up feedback recording (accept/reject)

**Deliverable:** User can see and use AI suggestions in chat

### Phase 2: Style Learning & Feedback (Week 2)
**Goal:** Personalized suggestions that improve over time

**Tasks:**
1. Auto-trigger style learning on message send
2. Create `UserStyleProfile` model and service methods
3. Build `AIStyleProfileView` in settings
4. Show confidence scores in suggestion chips
5. Track time-to-response for feedback quality
6. Implement suggestion modification tracking
7. Add "Learning from your messages" indicator

**Deliverable:** Suggestions become personalized, users can view their style profile

### Phase 3: Real-time Monitoring (Week 3)
**Goal:** Proactive AI suggestions for confusion/complexity

**Tasks:**
1. Create `ConversationMonitorService.swift`
2. Extend `PhoenixChannelManager` for AI events
3. Subscribe to `{:ai_suggestions}` broadcasts in active threads
4. Visual distinction for proactive suggestions (icon, color)
5. Add dismissal interaction for proactive suggestions
6. Per-thread monitoring toggle in settings
7. Handle edge cases (rapid messages, monitoring start/stop)

**Deliverable:** Users receive proactive help during confusing conversations

### Phase 4: Smart Translation (Week 4)
**Goal:** Auto-translate foreign messages with user preferences

**Tasks:**
1. Create `SmartTranslationService.swift`
2. Add `TranslationPreferences` model and storage
3. Build `TranslationPreferencesView` in settings
4. Auto-detect message language on receive
5. Auto-translate if != user's preferred language
6. Create `TranslationBubbleView` for message overlay
7. Implement per-contact language overrides
8. Batch-translate smart reply suggestions
9. Add translation toggle in thread settings

**Deliverable:** Foreign messages automatically translate, full user control

### Phase 5: UI Polish & Insights (Week 5)
**Goal:** Refined UX and comprehensive insights

**Tasks:**
1. Add shimmer loading states for suggestions
2. Implement swipe-to-dismiss gestures
3. Build `AIInsightsSheet.swift` bottom sheet
4. Add translation confidence badges
5. Haptic feedback on suggestion accept
6. Accessibility labels for all AI features
7. Animation for proactive suggestion appearance
8. Empty states for no suggestions
9. Error recovery UI (retry, fallback)

**Deliverable:** Polished, production-ready AI experience

## Performance Requirements

### API Latency Targets
- **Smart Reply Fetch**: <2 seconds (p95)
- **Translation**: <1 second (p95)
- **Style Learning**: Fire-and-forget, no blocking
- **Feedback Recording**: <500ms (p95)

### Caching Strategy
- **Suggestions**: 60 second TTL per thread
- **Translations**: 3600 second TTL
- **Style Profile**: 300 second TTL
- **Cache Invalidation**: On new message in thread

### Network Optimization
- Batch translate all smart replies in one API call
- Debounce suggestion fetches (500ms after typing stops)
- Prefetch suggestions when thread opens
- Cancel pending requests on navigation away
- Offline queue for feedback recording

### UI Responsiveness
- Show loading state within 100ms of request
- Optimistic UI updates where possible
- Non-blocking background tasks for all AI operations
- Smooth 60fps animations for suggestion appearance/dismissal

## Data Privacy & Security

### User Data Handling
- **Style Learning**: Only user's own messages analyzed
- **Storage**: Style profile stored in backend PostgreSQL (encrypted at rest)
- **Sharing**: User data never shared between users
- **Transparency**: Clear indicator when learning is active

### User Controls
- **Disable Learning**: Toggle in settings, stops all style analysis
- **Clear Profile**: Delete all learned style data
- **Export Data**: Download JSON of style profile and feedback history
- **Per-thread Controls**: Disable AI features per conversation

### API Security
- All requests authenticated with Auth0 Bearer token
- Rate limiting enforced by backend (per user tier)
- Input validation on both client and server
- Sensitive data (messages) never logged

## Success Metrics

### User Engagement
- **Suggestion Acceptance Rate**: Target >50%
- **Feature Adoption**: % of users who enable AI features
- **Daily Active Usage**: AI interactions per active user
- **Retention Impact**: Retention lift for AI users vs non-users

### Performance Metrics
- **API Success Rate**: >99.5%
- **Cache Hit Rate**: >80% for translations
- **Style Confidence**: >0.7 after 50 messages
- **Real-time Latency**: <500ms from backend event to UI update

### Quality Metrics
- **Translation Accuracy**: Manual review of sample translations
- **Suggestion Relevance**: User survey scores (1-5 scale)
- **False Positive Rate**: <10% for proactive suggestions
- **User Satisfaction**: NPS score for AI features

## Testing Strategy

### Unit Tests
**Service Layer:**
- `SmartReplyServiceTests`: API integration, caching, error handling
- `TranslationServiceTests`: Batch translation, preference logic
- `ConversationMonitorServiceTests`: Phoenix event handling

**Model Layer:**
- `StyleProfileTests`: Confidence calculation, model serialization
- `TranslationPreferencesTests`: Override logic, default values

### Integration Tests
**End-to-End Flows:**
- `SmartReplyFlowTests`: Fetch → Display → Accept → Feedback loop
- `MonitoringIntegrationTests`: Phoenix events → State updates → UI
- `TranslationFlowTests`: Auto-detect → Translate → Cache → Display

**State Management:**
- `AppReducerAITests`: All AI actions reduce state correctly
- `PhoenixAIIntegrationTests`: Channel events dispatch actions

### UI Tests
**Component Behavior:**
- Suggestion chip tap-to-insert
- Translation overlay toggle
- AI insights sheet interactions
- Swipe-to-dismiss gestures

**Accessibility:**
- VoiceOver navigation for all AI features
- Dynamic Type support for suggestion text
- Semantic labels for all interactive elements

### Manual Testing Checklist
- [ ] Suggestions appear in all supported themes
- [ ] Works correctly on all iPhone sizes (SE, Pro, Pro Max)
- [ ] Smooth performance with 100+ message thread
- [ ] Graceful degradation when backend is slow/unavailable
- [ ] Translation works for all supported languages
- [ ] Style learning improves suggestions over time
- [ ] Proactive suggestions don't interrupt user flow
- [ ] Privacy controls actually disable features

## Documentation Requirements

### Code Documentation
- DocC comments for all public APIs
- Architecture decision records (ADRs) for key choices
- Inline comments for complex business logic

### User Documentation
- Settings screen help text for each AI feature
- Onboarding tooltip for first smart reply
- FAQ section in app for AI features

### Developer Documentation
- README update with AI architecture overview
- API integration guide for backend endpoints
- Debugging guide for AI-related issues

## Risks & Mitigations

### Risk 1: Backend API Changes
**Impact:** High
**Probability:** Medium
**Mitigation:** Version API endpoints, maintain backward compatibility, monitor backend changes

### Risk 2: Poor Suggestion Quality
**Impact:** High
**Probability:** Medium
**Mitigation:** Implement feedback loop, monitor acceptance rates, A/B test prompts

### Risk 3: Performance Degradation
**Impact:** Medium
**Probability:** Medium
**Mitigation:** Aggressive caching, request debouncing, background processing, performance monitoring

### Risk 4: Privacy Concerns
**Impact:** High
**Probability:** Low
**Mitigation:** Clear user controls, transparent data handling, easy opt-out, regular privacy audits

### Risk 5: Translation Accuracy
**Impact:** Medium
**Probability:** Medium
**Mitigation:** Show confidence scores, allow manual override, feedback mechanism

## Open Questions

1. **Suggestion Personalization**: Should we allow users to "train" the AI with example phrases?
2. **Offline Mode**: How should AI features degrade when offline? Cache last suggestions?
3. **Cross-device Sync**: Should style profile sync across user's devices via backend?
4. **Language Detection**: Should we show detected language to user for transparency?
5. **Suggestion Limits**: Should free tier users have limited AI suggestions per day?

## Appendix

### Backend Architecture Reference
See: `globalbridge_backend/docs/ai-flow-diagrams.md`

### API Endpoint Specifications
See: `globalbridge_backend/lib/globalbridge_backend_web/controllers/ai_controller.ex`

### Existing iOS AI Code
- `Core/Services/AI/AIService.swift` - Existing translation/summarization
- `Core/AI/Models/` - Existing AI models
- `Core/Services/AI/BackendTranslationService.swift` - Translation implementation

---

**Document Owner**: iOS Team
**Backend Contact**: Backend Team (AI endpoints already implemented)
**Last Updated**: 2025-01-XX
**Next Review**: After Phase 1 completion
