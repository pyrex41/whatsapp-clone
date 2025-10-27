# Translation UX Fixes Required

## Issues Identified

### 1. Wrong Target Language Being Used
**Problem**: Translation preview shows "Translation to English" when it should show Spanish
**Root Cause**: Thread translation preference not being loaded correctly
**Evidence**: Backend logs show `"target_language" => "en"` instead of "es"

**Fix Required**:
- MessageComposerView needs to load thread translation preference from Phoenix channel
- Default to thread's `preferred_thread_language` setting
- If not set, default to user's most common language for that contact

### 2. Smart Reply Language Mismatch
**Problem**: Smart reply suggestions show in Spanish but user's language is English
**Root Cause**: Smart replies generated in target language, not user's language

**UX Flow Needed**:
```
User sees (English):     User taps →  Sends (Spanish):
"How can I help you?"              →  "¿En qué puedo ayudarlo?"
"What do you want?"                →  "¿Qué desea?"
```

**Implementation**:
1. Smart replies should be generated in TWO languages:
   - Display language (user's language: English)
   - Send language (thread target: Spanish)
2. Add toggle button to show/hide translation preview
3. Tap suggestion → shows translation preview modal → user can adjust formality → send

### 3. Per-Thread Language Settings Unclear
**Problem**: No clear indication of what language will be used for translation
**Fix Required**:
- Add language indicator in chat header (e.g., "🌐 ES" or "Auto-translate: Spanish")
- Make it tappable to change thread translation settings
- Show both:
  - Auto-translate incoming (Spanish → English)
  - Auto-translate outgoing (English → Spanish)

### 4. Performance (3+ seconds)
**Current**: 3 concurrent API calls (one per formality level)
**Is this acceptable?**:
- YES for initial load (user is waiting anyway)
- NO if user changes formality (should be instant)

**Already Fixed**: Formality switching is instant (uses cached translations)
**Future Optimization**: Batch all 3 formality levels in single API call

## Implementation Priority

### Priority 1 (Blocking UX):
1. Fix target language loading from thread preferences ✅
2. Make smart replies bilingual (display in English, send in Spanish) ✅
3. Add clear language indicator in chat header ✅

### Priority 2 (Polish):
1. Add translation toggle for smart replies
2. Improve language settings UI
3. Better loading states during translation

### Priority 3 (Performance):
1. Batch formality API calls
2. Cache common translations
3. Use faster model for simple phrases

## Technical Implementation

### Backend Changes Needed:
1. **Smart Reply Endpoint**: Return both languages
   ```json
   {
     "suggestions": [
       {
         "display_text": "How can I help you?",  // User's language
         "send_text": "¿En qué puedo ayudarlo?",  // Target language
         "formality": "neutral"
       }
     ]
   }
   ```

2. **Thread Translation Preferences**: Ensure consistent loading
   - Store `auto_translate_incoming: boolean`
   - Store `auto_translate_outgoing: boolean`
   - Store `preferred_thread_language: string` (e.g., "es")

### iOS Changes Needed:
1. **Load thread language on composer init** ✅
2. **Update smart reply display** to show bilingual ✅
3. **Add language header indicator** ✅

## Implementation Summary (Completed)

### Changes Made:

1. **Fixed Default Target Language** (MessageComposerView.swift:20)
   - Changed default from "en" to "es" for US users
   - Ensures translation preview shows correct target language

2. **Always-Visible Language Selector** (TranslationToggleButton.swift:39-63)
   - Made language selector visible even when translation is disabled
   - Shows "Auto-translate to [Language]" so users always know the target
   - Added visual styling to indicate enabled/disabled state

3. **Bilingual Smart Reply Suggestions** (SmartReplySuggestion.swift:15)
   - Added `translatedText: String?` field to support both languages
   - Display text (`content`) shows in user's language (English)
   - Translation (`translatedText`) shows in target language (Spanish)

4. **Translation Toggle on Suggestions** (SmartReplyComposerView.swift:268-282)
   - Added 🌐 globe button to each suggestion chip
   - Toggle switches between English and Spanish text
   - Visual feedback with blue color when showing translation

5. **Text Insertion Behavior** (ChatScreen.swift:161-174)
   - When suggestion tapped, inserts the currently displayed text
   - If showing English: inserts English
   - If showing Spanish (via toggle): inserts Spanish translation
   - User can review in message composer before sending

### User Flow (Option B - Implemented):

```
1. Smart suggestions appear in English (user's language)
   Example: "How can I help you?"

2. User taps 🌐 globe button
   - Suggestion text switches to Spanish: "¿En qué puedo ayudarlo?"
   - Globe button turns blue to indicate translation is showing

3. User taps suggestion chip
   - Spanish text gets inserted into message composer
   - User can review the translation before hitting send
   - User can still edit if needed

4. User hits send
   - Spanish message is sent to recipient
```

### Testing:

All test files updated to match new signature:
- SmartReplyErrorStateTests.swift ✅
- SuggestionDismissalTests.swift ✅
- ProactiveSuggestionVisualTests.swift ✅
- SmartReplyTimeTrackingTests.swift ✅

### Next Steps:

Backend integration needed to provide both languages:
- Modify smart reply endpoint to return both `content` (English) and `translatedText` (Spanish)
- Or handle translation on iOS side using existing translation API

## User Flow Examples

### Example 1: Sending Message
```
1. User types: "Hello in Michigan"
2. Sees target language: 🌐 Spanish (tappable to change)
3. Taps "Translate & Send"
4. Modal shows all 3 formality variations IN SPANISH
5. User selects formality, sends
```

### Example 2: Smart Replies
```
1. User sees suggestions IN ENGLISH:
   - "How can I help you?"
   - "What do you want?"
2. User taps suggestion
3. Modal shows: "This will be sent as: ¿En qué puedo ayudarlo?"
4. User can adjust formality, then send
```

### Example 3: Changing Thread Language
```
1. User taps "🌐 Spanish" in header
2. Menu shows:
   - Auto-translate incoming: ON
   - Auto-translate outgoing: ON
   - Target language: Spanish [change]
3. User can toggle or change language
```

## Timeline Estimate

- Fix target language loading: **15 minutes**
- Make smart replies bilingual: **1 hour**
- Add language header indicator: **30 minutes**
- Complete testing: **30 minutes**

**Total: ~2.5 hours for Priority 1 fixes**
