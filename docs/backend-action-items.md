# Backend Action Items

**Date:** 2025-10-24
**Source:** iOS API Integration Analysis

---

## 🚨 Required Backend Changes

### 1. Remove Tier-Based Rate Limits

**Current State:**
- Free tier: 50 AI requests per day
- Pro tier: 500 AI requests per day
- Enterprise tier: Unlimited

**Requested Change:**
Remove tier-based rate limiting entirely from backend.

**Rationale:**
- Adds unnecessary complexity
- Not needed for current product strategy
- iOS will auto-retry on 429 responses

**Backend Files to Update:**
- Rate limiting configuration
- Feature flags definitions
- Tier limits in database/code

**Priority:** Medium
**Effort:** 1-2 hours

---

## ✅ No Other Backend Changes Required

All other API endpoints and functionality match iOS requirements perfectly:
- ✅ Authentication (OAuth + traditional)
- ✅ WebSocket channels (thread + user)
- ✅ AI endpoints
- ✅ CDC sync
- ✅ Feature flags
- ✅ Read receipts
- ✅ Message edit/delete

---

## 📝 iOS Frontend Decisions

For backend team awareness:

### Authentication
**Decision:** iOS uses OAuth-only
**Impact:** Traditional auth endpoints (`/api/auth/signup`, `/api/auth/login`) will remain unused by iOS client

### CDC Sync
**Decision:** WebSocket-only
**Impact:** REST CDC endpoints (`/api/v1/sync/pull`, `/api/v1/sync/push`) will remain unused by iOS client as primary sync method (may be used as fallback in future)

### Feature Flags
**Decision:** Sync on every app launch
**Impact:** `/api/v1/features` endpoint will be called frequently (cache with appropriate headers if needed)

---

## 🔄 Future Considerations

### Rate Limiting Alternative
If rate limiting is needed in the future, consider:
- Global limits (not tier-based)
- Per-endpoint limits (e.g., AI endpoints only)
- Usage-based alerts instead of hard limits

### API Optimization
Consider adding:
- ETag support for feature flags endpoint (reduce bandwidth)
- Cache-Control headers for frequently accessed endpoints

---

**Last Updated:** 2025-10-24
**Owner:** Backend Team
