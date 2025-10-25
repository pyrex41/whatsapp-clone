# AI iOS Tasks - Review & Recommendations

## Summary
**Current:** 30 tasks attempting full implementation
**Recommendation:** Restructure into MVP (18 tasks) + Later Phases (defer 12 tasks)

## Critical Changes Needed

### 1. SPLIT AppReducer (Task 10)
**Problem:** Task 10 blocks everything by depending on ALL services (7,8,9)
**Solution:** Split into 3 tasks:
```
10a. Update AppReducer for SmartReply (depends: 5,6,7)
10b. Update AppReducer for Monitoring (depends: 10a,8)
10c. Update AppReducer for Translation (depends: 10a,9)
```

### 2. ADD ChatScreen Integration
**Problem:** SmartReplyComposerView built (Task 12) but never integrated
**Solution:** Add new task after 12:
```
12a. Wire SmartReplyComposerView to ChatScreen (depends: 12, 10a)
     - Replace MessageComposerView with SmartReplyComposerView
     - Pass store state to composer
     - Dispatch fetchSmartReplies when chat opens
```

### 3. ADD Testing Milestone Tasks
**Problem:** No way to verify features work
**Solution:** Add milestone tasks after each phase:
```
MILESTONE-1: Test Foundation (after task 6)
   - Verify models serialize/deserialize
   - Verify state updates correctly
   - Verify actions are created properly

MILESTONE-2: Test Smart Reply End-to-End (after task 16)
   - Manual test: Open chat, see suggestions
   - Manual test: Tap suggestion, message inserted
   - Manual test: Send message, feedback recorded
   - Integration test: Full flow with mock backend

MILESTONE-3: Test Style Learning (after task 22)
   - Manual test: Send 10 messages, check profile
   - Manual test: Suggestions improve over time
```

### 4. ADD Infrastructure Tasks
**Problem:** Missing foundational pieces
**Solution:** Insert before task 7:
```
6a. Setup AIServiceCache enhancements (depends: 5)
    - Add suggestion caching (60s TTL)
    - Add translation caching (3600s TTL)
    - Add style profile caching (300s TTL)

6b. Add AI Feature Flags (depends: 5)
    - Create AIFeatureFlags enum
    - Add toggles: smartReplyEnabled, styleLearning, realTimeMonitoring, autoTranslate
    - Wire to FeatureFlags.swift

6c. Add AI Error Handling Utilities (depends: 5)
    - Extend AIServiceError with user-friendly messages
    - Add retry logic helpers
    - Add error recovery strategies
```

### 5. FIX Dependencies

#### Fix Task 13 (SuggestionChipView)
```diff
- dependencies: [1, 12]
+ dependencies: [1]  # Should be independent of composer
```

#### Fix Task 14 (Tap-to-Insert)
```diff
- dependencies: [12, 13, 7]
+ dependencies: [12, 13, 7, 6]  # Needs AppAction to dispatch
```

#### Fix Task 17 (Style Learning)
```diff
- dependencies: [11, 2]
+ dependencies: [11, 2, 7]  # Needs SmartReplyService to learn
```

### 6. ADJUST Priorities

#### Increase Priority (important for trust/transparency):
```diff
Task 19 (Confidence scores):
- priority: "low"
+ priority: "medium"  # Users need to trust suggestions

Task 22 (Learning indicator):
- priority: "low"
+ priority: "medium"  # Transparency is important
```

#### Decrease Priority (defer to Phase 4):
```diff
Tasks 27-30 (Translation):
- priority: "high/medium"
+ priority: "low"  # Defer entire translation to later phase
```

## Recommended Task Reorganization

### PHASE 1: Foundation & Core Models (MVP Batch 1)
**Goal:** Build infrastructure and test it
**Tasks:** 1, 2, 3, 4, 5, 6, 6a, 6b, 6c, MILESTONE-1
**Duration:** 3-4 days
**Deliverable:** Can create AI models and manage state

### PHASE 2: Smart Reply Service (MVP Batch 2)
**Goal:** Backend integration working
**Tasks:** 7, 10a, 15
**Duration:** 2-3 days
**Deliverable:** Can fetch suggestions from backend

### PHASE 3: Smart Reply UI (MVP Batch 3)
**Goal:** Users see suggestions
**Tasks:** 12, 13, 12a, 14, 15
**Duration:** 3-4 days
**Deliverable:** Suggestions appear in chat, can tap to use

### PHASE 4: Feedback Loop (MVP Batch 4)
**Goal:** Complete learning cycle
**Tasks:** 16, 20, 21, MILESTONE-2
**Duration:** 2-3 days
**Deliverable:** Feedback recorded, suggestions improve

### PHASE 5: Style Learning (MVP Batch 5)
**Goal:** Personalization working
**Tasks:** 17, 18, 19, 22, MILESTONE-3
**Duration:** 2-3 days
**Deliverable:** Suggestions match user style

### MVP COMPLETE: ~15-20 days
**Working features:**
- Smart reply suggestions
- Style learning
- Feedback loop
- Basic UI

---

### PHASE 6: Real-time Monitoring (Defer)
**Tasks:** 8, 10b, 11, 23, 24, 25, 26
**Duration:** 4-5 days
**Deliverable:** Proactive AI suggestions

### PHASE 7: Translation (Defer)
**Tasks:** 9, 10c, 27, 28, 29, 30
**Duration:** 5-6 days
**Deliverable:** Auto-translate messages

## Specific Task Modifications

### DELETE Tasks (Too granular, combine into others):
- **Task 20** (Time-to-response) → Merge into Task 16 (Feedback Recording)
- **Task 21** (Modification tracking) → Merge into Task 16 (Feedback Recording)

### ADD New Tasks:

#### Task 6a: Setup AIServiceCache
```json
{
  "id": "6a",
  "title": "Setup AIServiceCache for AI Features",
  "description": "Enhance AIServiceCache with caching strategies for suggestions, translations, and style profiles",
  "priority": "high",
  "dependencies": [5],
  "details": "Add suggestion caching (60s TTL per thread), translation caching (3600s TTL), style profile caching (300s TTL). Implement cache invalidation on new messages."
}
```

#### Task 6b: Add AI Feature Flags
```json
{
  "id": "6b",
  "title": "Add AI Feature Flags",
  "description": "Create feature flags for gradual AI rollout",
  "priority": "high",
  "dependencies": [5],
  "details": "Add AIFeatureFlags enum with: smartReplyEnabled, styleLearning, realTimeMonitoring, autoTranslate. Wire to existing FeatureFlags.swift"
}
```

#### Task 6c: Add AI Error Handling
```json
{
  "id": "6c",
  "title": "Add AI Error Handling Utilities",
  "description": "Create error handling helpers for AI features",
  "priority": "medium",
  "dependencies": [5],
  "details": "Extend AIServiceError with user-friendly messages. Add retry logic helpers. Add graceful degradation strategies."
}
```

#### Task 10a/10b/10c: Split AppReducer
```json
{
  "id": "10a",
  "title": "Update AppReducer for SmartReply Actions",
  "description": "Add reducer logic for smart reply actions only",
  "priority": "high",
  "dependencies": [5, 6, 7],
  "details": "Handle fetchSmartReplies, smartRepliesReceived, smartReplyAccepted, smartReplyRejected. Use .run for async operations."
}
{
  "id": "10b",
  "title": "Update AppReducer for Monitoring Actions",
  "description": "Add reducer logic for monitoring actions",
  "priority": "high",
  "dependencies": ["10a", 8],
  "details": "Handle aiSuggestionBroadcast, startConversationMonitoring, stopConversationMonitoring."
}
{
  "id": "10c",
  "title": "Update AppReducer for Translation Actions",
  "description": "Add reducer logic for translation actions",
  "priority": "low",
  "dependencies": ["10a", 9],
  "details": "Handle translateMessage, translationReceived, updateTranslationPreferences."
}
```

#### Task 12a: Wire to ChatScreen
```json
{
  "id": "12a",
  "title": "Integrate SmartReplyComposerView into ChatScreen",
  "description": "Replace MessageComposerView with SmartReplyComposerView in ChatScreen",
  "priority": "high",
  "dependencies": [12, "10a"],
  "details": "Update ChatScreen.swift to use SmartReplyComposerView. Pass store state. Dispatch fetchSmartReplies on thread open. Handle suggestion state updates."
}
```

#### Milestone Tasks
```json
{
  "id": "M1",
  "title": "MILESTONE: Test Foundation",
  "description": "Verify all foundation pieces work correctly",
  "priority": "high",
  "dependencies": [6, "6a", "6b", "6c"],
  "testStrategy": "Unit tests for models, state, actions. Integration tests for state updates."
}
{
  "id": "M2",
  "title": "MILESTONE: Test Smart Reply End-to-End",
  "description": "Verify smart reply works from API to UI",
  "priority": "high",
  "dependencies": [16, "12a"],
  "testStrategy": "Manual: Open chat, see suggestions, tap, send. Integration: Mock backend flow."
}
{
  "id": "M3",
  "title": "MILESTONE: Test Style Learning",
  "description": "Verify style learning improves suggestions",
  "priority": "high",
  "dependencies": [22],
  "testStrategy": "Manual: Send 10 messages, check profile shows data. Verify suggestions change."
}
```

## Dependency Graph Issues

### Current Bottlenecks:
1. **Task 5** → blocks 6 tasks (correct)
2. **Task 10** → blocks 10 tasks (BAD - too many)
3. **Task 12** → blocks 4 tasks (OK)

### After Splitting Task 10:
1. **Task 10a** → blocks only SmartReply tasks (GOOD)
2. **Task 10b** → blocks only Monitoring tasks (GOOD)
3. **Task 10c** → blocks only Translation tasks (GOOD)

## Final Recommendations

### Option 1: MVP Only (18 tasks)
**Include:** 1-7, 10a, 12-16, 18-19, 22, 6a, 6b, 12a, M1, M2, M3
**Defer:** 8-9, 10b-10c, 11, 17, 20-21, 23-30
**Timeline:** 15-20 days
**Deliverable:** Working smart reply with style learning

### Option 2: MVP + Monitoring (25 tasks)
**Include:** All from Option 1 + 8, 10b, 11, 23-26, M4
**Defer:** 9, 10c, 27-30 (Translation)
**Timeline:** 20-25 days
**Deliverable:** Smart reply + proactive suggestions

### Option 3: Everything (37 tasks with additions)
**Include:** All 30 + 7 new tasks
**Timeline:** 30-35 days
**Deliverable:** Complete AI implementation

## Immediate Actions

1. **Run:** `task-master update --from=10 --prompt="Split Task 10 into 10a (SmartReply reducer), 10b (Monitoring reducer), 10c (Translation reducer). Only 10a should be high priority."`

2. **Run:** `task-master add-task --prompt="Task 6a: Setup AIServiceCache for suggestions (60s), translations (3600s), profiles (300s)" --research`

3. **Run:** `task-master add-task --prompt="Task 6b: Add AI feature flags for gradual rollout" --research`

4. **Run:** `task-master add-task --prompt="Task 12a: Wire SmartReplyComposerView to ChatScreen, dispatch fetchSmartReplies" --research`

5. **Run:** `task-master add-task --prompt="Milestone M1: Test foundation with unit tests for models, state, actions" --research`

6. **Run:** `task-master update-task --id=13 --prompt="Remove dependency on task 12, make it independent"`

7. **Run:** `task-master update-task --id=19 --prompt="Change priority from low to medium - confidence scores important for user trust"`

8. **Run:** `task-master update --from=27 --prompt="Change all translation tasks (27-30) to low priority, defer to Phase 4"`

---

**Recommendation:** Start with **Option 1 (MVP Only - 18 tasks)** to get working smart replies quickly, then add monitoring/translation in separate phases.
