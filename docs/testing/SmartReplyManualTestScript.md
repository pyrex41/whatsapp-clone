# Smart Reply MVP - Manual Test Script

**Task:** #31 - E2E Test Smart Reply MVP
**Date:** 2025-10-25
**Tester:** _________________
**Build:** _________________
**Device:** _________________

## Purpose

Validate the full Smart Reply flow end-to-end through manual testing to ensure the MVP meets all acceptance criteria before release.

## Scope

**In Scope:**
- Smart Reply MVP: Auto-fetch suggestions on thread open
- Tap-to-insert interaction
- Send message with feedback recording
- Error handling and retry
- Cache behavior within 60s

**Out of Scope:**
- Proactive (real-time) suggestions (Task 26)
- Per-thread AI monitoring toggle (Task 26)

## Prerequisites

- [ ] App built with latest code including Smart Reply implementation
- [ ] Backend API accessible (staging or production)
- [ ] Valid authentication token
- [ ] Test account with existing threads
- [ ] Ability to toggle network connectivity (for offline testing)

---

## Test Scenarios

### Scenario 1: Auto-Fetch on Thread Open

**Objective:** Verify Smart Reply bar appears with suggestions when opening a thread.

**Steps:**
1. Launch the app and log in
2. Navigate to thread list
3. Open an existing thread with recent messages
4. Start timer when thread view appears

**Expected Results:**
- [ ] Smart Reply bar appears within **1.5 seconds** of thread opening
- [ ] Bar displays **2-3 suggestion chips**
- [ ] Chips show relevant suggestion text
- [ ] Confidence badges visible on chips (green/blue/orange dots)
- [ ] No layout jank or flickering during load

**Pass/Fail:** ⬜ PASS  ⬜ FAIL

**Notes:**
```
_____________________________________________________________________________
_____________________________________________________________________________
```

---

### Scenario 2: Tap-to-Insert Interaction

**Objective:** Verify tapping a chip inserts text into the composer.

**Steps:**
1. Ensure Smart Reply bar is visible with suggestions
2. Note the text of the first chip
3. Tap the first suggestion chip
4. Observe composer text field

**Expected Results:**
- [ ] Composer populates **exactly** with chip text
- [ ] Cursor positioned at end of text
- [ ] Chips hide or remain (depending on design decision)
- [ ] No delay between tap and text appearance (<100ms)
- [ ] Send button becomes enabled

**Pass/Fail:** ⬜ PASS  ⬜ FAIL

**Notes:**
```
_____________________________________________________________________________
_____________________________________________________________________________
```

---

### Scenario 3: Send Message - Accepted Feedback

**Objective:** Verify sending unmodified suggestion records "accepted" feedback.

**Steps:**
1. Tap a suggestion chip to populate composer
2. **Do NOT modify the text**
3. Tap Send button
4. Observe message sending

**Expected Results:**
- [ ] Message appears immediately in chat (optimistic UI)
- [ ] Feedback recorded as `decision=accepted` (verify via backend logs if possible)
- [ ] `suggestionId` included in feedback
- [ ] `timeToResponseMs` recorded (time from chip display to send)
- [ ] No `modifiedContent` field in feedback
- [ ] Composer clears after sending

**Pass/Fail:** ⬜ PASS  ⬜ FAIL

**Backend Verification (if available):**
```
Feedback payload check:
- decision: accepted
- suggestionId: ____________________
- timeToResponseMs: ____________________
- modifiedContent: null
```

**Notes:**
```
_____________________________________________________________________________
_____________________________________________________________________________
```

---

### Scenario 4: Send Message - Modified Feedback

**Objective:** Verify modifying suggestion before sending records "modified" feedback.

**Steps:**
1. Tap a suggestion chip to populate composer
2. **Modify the text** (e.g., add ", thanks!" to the end)
3. Note the final modified text
4. Tap Send button

**Expected Results:**
- [ ] Message sends with modified text
- [ ] Feedback recorded as `decision=modified`
- [ ] `modifiedContent` field contains the final sent text
- [ ] `suggestionId` matches the original chip
- [ ] `timeToResponseMs` recorded

**Pass/Fail:** ⬜ PASS  ⬜ FAIL

**Backend Verification (if available):**
```
Feedback payload check:
- decision: modified
- suggestionId: ____________________
- modifiedContent: "____________________"
- timeToResponseMs: ____________________
```

**Notes:**
```
_____________________________________________________________________________
_____________________________________________________________________________
```

---

### Scenario 5: Offline Error Path

**Objective:** Verify graceful error handling when network is unavailable.

**Steps:**
1. **Enable airplane mode** or disable Wi-Fi/cellular
2. Open a thread
3. Observe Smart Reply bar behavior

**Expected Results:**
- [ ] Non-blocking error state appears in Smart Reply bar
- [ ] Error message is clear and user-friendly
- [ ] Retry button is visible and labeled
- [ ] Normal message sending still works (composer not disabled)
- [ ] Tapping retry attempts to re-fetch suggestions

**Pass/Fail:** ⬜ PASS  ⬜ FAIL

**Error Message Observed:**
```
_____________________________________________________________________________
```

**Notes:**
```
_____________________________________________________________________________
_____________________________________________________________________________
```

---

### Scenario 6: Cache Behavior (60s TTL)

**Objective:** Verify suggestions are cached for 60 seconds to avoid redundant network calls.

**Steps:**
1. Open a thread and observe Smart Reply bar load (first fetch)
2. Navigate **away** from the thread (back to thread list)
3. Wait **10-30 seconds** (within 60s TTL)
4. Navigate **back** to the same thread
5. Observe Smart Reply bar behavior

**Expected Results:**
- [ ] Smart Reply bar repopulates **instantly** (no loading state)
- [ ] Same suggestions appear (cache hit)
- [ ] Background refresh may be deferred
- [ ] No visible delay or network spinner

**Pass/Fail:** ⬜ PASS  ⬜ FAIL

**Additional Test (Cache Expiry):**
1. Repeat steps 1-2
2. Wait **more than 60 seconds**
3. Navigate back to the thread

**Expected Results (Expiry):**
- [ ] Smart Reply bar shows loading state
- [ ] New network fetch occurs
- [ ] Fresh suggestions may differ from previous

**Pass/Fail:** ⬜ PASS  ⬜ FAIL

**Notes:**
```
_____________________________________________________________________________
_____________________________________________________________________________
```

---

## Additional Checks

### Accessibility
- [ ] VoiceOver reads chip text and confidence levels
- [ ] Chips have descriptive labels (e.g., "Suggestion: Thanks! High confidence, 95%")
- [ ] Swipe gestures work with VoiceOver enabled
- [ ] Hit targets are ≥44pt for all interactive elements

### Visual & UX
- [ ] Chips render correctly on all screen sizes (iPhone SE, Pro Max, iPad)
- [ ] Text truncates properly if suggestion is long
- [ ] Confidence badges align correctly
- [ ] No visual jank during chip transitions
- [ ] Dark mode support looks correct

### Performance
- [ ] Suggestion fetch completes within 1.5s on good network
- [ ] No dropped frames during chip animations
- [ ] Memory usage remains stable after multiple fetches
- [ ] App remains responsive during background fetch

---

## Test Summary

**Total Tests:** 6 core scenarios + additional checks
**Passed:** _____
**Failed:** _____
**Blocked:** _____

**Overall Status:** ⬜ PASS  ⬜ FAIL  ⬜ BLOCKED

---

## Issues Found

| # | Severity | Description | Steps to Reproduce | Expected | Actual |
|---|----------|-------------|-------------------|----------|--------|
| 1 |          |             |                   |          |        |
| 2 |          |             |                   |          |        |
| 3 |          |             |                   |          |        |

---

## Sign-Off

**Tester Signature:** ___________________
**Date:** ___________________
**Approved By:** ___________________
**Date:** ___________________

---

## Appendix: Debug Commands

### Simulate Offline (DEBUG builds only)
```swift
// In Xcode console or DEBUG menu:
NetworkMonitor.shared.simulateOffline()
```

### Force Cache Clear
```swift
SmartReplyService.shared.clearAllCache()
```

### View Logs
Filter Xcode console for:
- `[SMART_REPLY_SERVICE]` - Service operations
- `[SMART_REPLY]` - General smart reply logs
- `[AI]` - AI-related logs

---

## References

- **Task Spec:** `.taskmaster/tasks/tasks.json` - Task #31
- **API Docs:** Backend API documentation for `/api/v1/ai/suggest_replies` and `/api/v1/ai/record_feedback`
- **Code:** `clients/ios/GlobalBridge/Core/Services/AI/SmartReplyService.swift`
- **UI:** `clients/ios/GlobalBridge/UI/Views/AI/SmartReplyComposerView.swift`
