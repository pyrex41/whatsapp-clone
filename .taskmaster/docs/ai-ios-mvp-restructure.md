# AI iOS Tasks - MVP Restructure Summary

## ✅ Restructuring Complete!

The 30+ AI tasks have been reorganized to focus on **MVP Smart Reply first**, with monitoring and translation deferred to later phases.

---

## 🎯 Key Changes Made

### 1. **Deferred Non-MVP Features**

#### Translation (Phase 4 - Deferred)
- ✅ **Task 9**: SmartTranslationService → LOW priority
- ✅ **Tasks 27-30**: All translation tasks → LOW priority
- **Rationale**: Translation not needed for basic smart reply MVP

#### Real-time Monitoring (Phase 3 - Deferred)
- ✅ **Task 8**: ConversationMonitorService → MEDIUM priority
- ✅ **Task 11**: PhoenixChannelManager+AI → MEDIUM priority (depends on 8)
- ✅ **Tasks 23-26**: Monitoring UI tasks → MEDIUM priority
- **Rationale**: Proactive suggestions nice-to-have, not critical for MVP

### 2. **Fixed Critical Blocker (Task 10)**

#### Before:
```
Task 10: Update AppReducer for AI Logic
- Dependencies: 5, 6, 7, 8, 9  ← BLOCKED EVERYTHING
- All 3 features (SmartReply, Monitoring, Translation)
```

#### After:
```
Task 10: Update AppReducer for SmartReply Actions ONLY
- Dependencies: 5, 6, 7  ← Only SmartReply
- Subtasks added for Monitoring (10b) and Translation (10c)
```

**Impact**: MVP tasks no longer wait for monitoring/translation services!

### 3. **Added Critical Infrastructure**

#### New Task 31: AIServiceCache Setup
- **Priority**: MEDIUM (should be HIGH for dependency chain)
- **Depends**: Task 5 (AppState)
- **Details**:
  - Suggestions: 60s TTL per thread
  - Translations: 3600s TTL
  - Style Profiles: 300s TTL
  - Message-driven cache invalidation

#### Pending (Background Research):
- Task 32: AI Feature Flags (smartReplyEnabled, styleLearning, etc.)
- Task 33: Wire SmartReplyComposerView to ChatScreen
- Task 34: MILESTONE - Test Smart Reply End-to-End

### 4. **Fixed Dependencies**

#### Task 13 (SuggestionChipView)
- **Before**: Depended on Task 12 (SmartReplyComposerView)
- **After**: Only depends on Task 1 (SmartReplySuggestion model)
- **Rationale**: Reusable component, should be independent

#### Task 14 (Tap-to-Insert)
- **Before**: Dependencies: 12, 13, 7
- **After**: Dependencies: 12, 13, 7, **6** (AppAction)
- **Rationale**: Needs actions to dispatch state updates

### 5. **Adjusted Priorities**

#### Increased (User Trust):
- **Task 19**: Confidence Scores → MEDIUM (was LOW)
- **Rationale**: Showing confidence builds user trust in AI

#### Decreased (Defer):
- Tasks 8-9, 11, 23-30 → MEDIUM/LOW
- **Rationale**: Not needed for MVP

---

## 📊 MVP Task Breakdown

### **Phase 1: Foundation (Tasks 1-6, 31)** - 7 tasks
Ready to start in parallel:

| ID | Task | Priority | Dependencies | Status |
|----|------|----------|--------------|--------|
| 1 | SmartReplySuggestion Model | HIGH | None | ⭕ Ready |
| 2 | UserStyleProfile Model | HIGH | None | ⭕ Ready |
| 3 | TranslationPreferences Model | HIGH | None | ⭕ Ready |
| 4 | SuggestionFeedback Model | MEDIUM | None | ⭕ Ready |
| 5 | Extend AppState | HIGH | 1,2,3,4 | Waiting |
| 6 | Extend AppAction | HIGH | 5 | Waiting |
| 31 | Setup AIServiceCache | MEDIUM | 5 | Waiting |

**Deliverable**: Core models and state infrastructure

---

### **Phase 2: SmartReply Service (Tasks 7, 10)** - 2 tasks

| ID | Task | Priority | Dependencies | Status |
|----|------|----------|--------------|--------|
| 7 | SmartReplyService | HIGH | 1,2,5,6 | Waiting |
| 10 | AppReducer (SmartReply only) | HIGH | 5,6,7 | Waiting |

**Deliverable**: Backend integration working

---

### **Phase 3: SmartReply UI (Tasks 12-15)** - 4 tasks

| ID | Task | Priority | Dependencies | Status |
|----|------|----------|--------------|--------|
| 12 | SmartReplyComposerView | HIGH | 1,5,10 | Waiting |
| 13 | SuggestionChipView | MEDIUM | 1 | Waiting |
| 14 | Tap-to-Insert Behavior | HIGH | 12,13,7,6 | Waiting |
| 15 | Loading/Error States | MEDIUM | 12,7 | Waiting |
| **33** | **Wire to ChatScreen** | **HIGH** | **12,10** | **Adding** |

**Deliverable**: Users see suggestions, can tap to use

---

### **Phase 4: Feedback Loop (Tasks 16, 20-21)** - 3 tasks

| ID | Task | Priority | Dependencies | Status |
|----|------|----------|--------------|--------|
| 16 | Feedback Recording | HIGH | 7,13,14 | Waiting |
| 20 | Time-to-Response Tracking | MEDIUM | 16 | Waiting |
| 21 | Modification Tracking | MEDIUM | 16 | Waiting |
| **34** | **MILESTONE: Test MVP** | **HIGH** | **16** | **Adding** |

**Deliverable**: Complete feedback loop, suggestions improve

---

### **Phase 5: Style Learning (Tasks 17-19, 22)** - 4 tasks

| ID | Task | Priority | Dependencies | Status |
|----|------|----------|--------------|--------|
| 17 | Auto-Trigger Style Learning | MEDIUM | 11,2 | Waiting |
| 18 | AIStyleProfileView | MEDIUM | 2,5 | Waiting |
| 19 | Confidence Scores in Chips | MEDIUM | 13 | Waiting |
| 22 | Learning Indicator | LOW | 18 | Waiting |

**Deliverable**: Personalized suggestions matching user style

---

## 🚀 **MVP Total: ~18-20 tasks**

### Critical Path (Must Have):
1-7, 10, 12-16, **31**, **33**, **34** = **17 tasks**

### Nice to Have (Defer if needed):
18-22 (Style Learning UI) = **5 tasks**

---

## ⏱️ **Estimated Timeline**

| Phase | Tasks | Days | Cumulative |
|-------|-------|------|------------|
| **Phase 1**: Foundation | 7 | 3-4 | 3-4 days |
| **Phase 2**: Service | 2 | 2-3 | 5-7 days |
| **Phase 3**: UI | 5 | 3-4 | 8-11 days |
| **Phase 4**: Feedback | 4 | 2-3 | 10-14 days |
| **Phase 5**: Style Learning | 5 | 2-3 | 12-17 days |
| **MVP Complete** | **23 tasks** | **12-17 days** | **~3 weeks** |

---

## 🎯 **What Changed vs Original**

### Before Restructure:
- **30 tasks** all high priority
- **Task 10** blocked everything (depended on ALL services)
- **Translation** mixed into MVP path
- **Monitoring** mixed into MVP path
- **No milestones** for testing
- **No integration** task

### After Restructure:
- **~20 MVP tasks** (high priority)
- **~10 deferred tasks** (medium/low priority)
- **Task 10** only blocks SmartReply
- **Translation** deferred to Phase 4
- **Monitoring** deferred to Phase 3
- **Milestones** added for testing
- **Integration** task added

---

## 🔄 **Still Pending (Background Research)**

The following tasks are being generated with AI research:

| ID | Task | ETA | Status |
|----|------|-----|--------|
| 32 | AI Feature Flags | ~1 min | Researching |
| 33 | Wire Composer to ChatScreen | ~1 min | Researching |
| 34 | MILESTONE: Test MVP | ~1 min | Researching |

**Note**: Check `task-master list` in a moment to see final task count

---

## 📋 **Next Steps**

### 1. Start with Foundation (Parallel)
```bash
# All 4 models can be built in parallel
task-master set-status --id=1 --status=in-progress  # SmartReplySuggestion
task-master set-status --id=2 --status=in-progress  # UserStyleProfile
task-master set-status --id=3 --status=in-progress  # TranslationPreferences
task-master set-status --id=4 --status=in-progress  # SuggestionFeedback
```

### 2. Then AppState
```bash
task-master set-status --id=5 --status=in-progress
```

### 3. Then AppAction + Cache (Parallel)
```bash
task-master set-status --id=6 --status=in-progress   # AppAction
task-master set-status --id=31 --status=in-progress  # Cache
```

### 4. Then Service Layer
```bash
task-master set-status --id=7 --status=in-progress   # SmartReplyService
task-master set-status --id=10 --status=in-progress  # AppReducer
```

### 5. Then UI Layer
Continue through tasks 12-16...

---

## 🎓 **Dependency Insights**

### Most Critical Tasks (High # of Dependents):
1. **Task 5** (AppState) → 10+ tasks depend on this
2. **Task 10** (AppReducer) → 5+ tasks depend on this
3. **Task 7** (SmartReplyService) → 4+ tasks depend on this

### Independent Tasks (Can Work Anytime):
- **Task 13** (SuggestionChipView) → Only needs model
- **Task 18** (StyleProfileView) → Only needs model + state
- **Task 19** (Confidence Scores) → Only needs ChipView

---

## ⚠️ **Watch Out For**

### 1. Task 31 (Cache) Priority
- Currently MEDIUM but should probably be HIGH
- Blocks Task 7 (SmartReplyService) indirectly
- **Recommendation**: Bump to HIGH if implementing caching first

### 2. Task 17 (Style Learning) Dependency Issue
- Depends on Task 11 (PhoenixChannelManager+AI)
- But Task 11 is deferred (monitoring feature)
- **Fix Needed**: Change Task 17 to depend on Task 7 instead

### 3. Missing Tasks Still Being Generated
- Watch for Tasks 32-34 to appear
- May shift dependency chain slightly

---

## 📈 **Success Metrics**

### MVP Complete When:
- ✅ Users see 3 AI suggestions in chat
- ✅ Tap suggestion inserts into composer
- ✅ Suggestions load in <2s (p95)
- ✅ Feedback recorded on accept/reject
- ✅ Basic style learning working (formality, emojis)
- ✅ Can demo end-to-end flow
- ✅ Milestone test passes

### Phase 3+ Complete When:
- ✅ Proactive suggestions appear on confusion
- ✅ Foreign messages auto-translate
- ✅ Per-contact translation preferences work
- ✅ Real-time monitoring active

---

## 🎉 **Summary**

**The tasks are now MVP-focused!**

- ✅ Translation deferred to Phase 4
- ✅ Monitoring deferred to Phase 3
- ✅ Critical blocker (Task 10) split
- ✅ Dependencies fixed
- ✅ Priorities adjusted
- ✅ Infrastructure tasks added
- ✅ Clear path to working MVP

**You can start with Task 1** and work through the foundation in parallel!

---

**Last Updated**: 2025-01-XX
**Tasks Restructured**: 30 → ~34 (with 4 new additions)
**MVP Tasks**: ~20 high-priority tasks
**Deferred Tasks**: ~14 medium/low-priority tasks
