# Documentation Index

This directory contains product requirements, design documents, and technical specifications for GlobalBridge Messenger.

---

## 📱 iOS Frontend Documentation

### Primary Documents

| Document | Description | Status |
|----------|-------------|--------|
| [ios-ai-frontend-prd-updated.md](../.taskmaster/docs/ios-ai-frontend-prd-updated.md) | **Current iOS Frontend PRD** - Reflects actual backend implementation and iOS status | ✅ Current (v2.0) |
| [ios-prd-update-summary.md](./ios-prd-update-summary.md) | Summary of changes made to iOS PRD | ✅ Up-to-date |
| [ios-prd-backend-sync-analysis.md](./ios-prd-backend-sync-analysis.md) | Detailed analysis comparing original PRD with backend | ✅ Complete |

### Reference Documents

| Document | Description | Status |
|----------|-------------|--------|
| [ios-ai-frontend-prd.md](../.taskmaster/docs/ios-ai-frontend-prd.md) | **Original iOS PRD** (for reference only) | 📦 Archived (v1.0) |

---

## 🔧 Backend Documentation

| Document | Description | Location |
|----------|-------------|----------|
| AI Backend PRD | Core backend AI implementation | `.taskmaster/docs/ai-backend-prd.md` |
| API Documentation | Auto-generated OpenAPI/Swagger | **To be generated** |

---

## 🗂️ Document Relationships

```
iOS Frontend PRD (Updated v2.0)
│
├─► Backend Sync Analysis
│   └─► Documents gaps between PRD v1.0 and backend
│
├─► Update Summary
│   └─► Changes from v1.0 to v2.0
│
├─► Backend API Documentation (OpenAPI)
│   └─► Source of truth for API endpoints
│
└─► Original PRD (v1.0)
    └─► Reference only - outdated
```

---

## 🚀 Quick Start for New Developers

### iOS Developers:
1. Read [ios-ai-frontend-prd-updated.md](../.taskmaster/docs/ios-ai-frontend-prd-updated.md) (v2.0)
2. Review [ios-prd-update-summary.md](./ios-prd-update-summary.md) for recent changes
3. Import backend API documentation (OpenAPI spec) when available
4. Check current implementation status in PRD Section 10.2

### Backend Developers:
1. Read `.taskmaster/docs/ai-backend-prd.md`
2. Generate OpenAPI documentation for iOS team
3. Review [ios-prd-backend-sync-analysis.md](./ios-prd-backend-sync-analysis.md) for API requirements

### Full-Stack / Integration:
1. Read both iOS and Backend PRDs
2. Use API documentation as integration contract
3. Review sync analysis for data flow understanding

---

## 📝 Document Maintenance

### Update Frequency:
- **iOS PRD:** Updated at end of each development phase
- **Backend PRD:** Updated when AI features change
- **API Docs:** Auto-generated on backend changes (CI/CD)
- **Sync Analysis:** Updated when major architectural changes occur

### Version Control:
- PRD versions tracked in document headers
- Major changes require update summary document
- Old versions archived but kept for reference

---

## 🔗 External Resources

- **Backend API (Dev):** http://localhost:4000
- **Backend API (Prod):** https://globalbridge-backend.fly.dev
- **Auth0 Dashboard:** https://manage.auth0.com/dashboard
- **GitHub Repository:** https://github.com/[org]/globalbridge
- **Postman Workspace:** [To be created]

---

## 📞 Questions?

- **iOS Questions:** Contact iOS team lead
- **Backend Questions:** Contact backend team lead
- **Architecture Questions:** Contact project architect
- **API Documentation:** Refer to OpenAPI spec (to be generated)

---

**Last Updated:** 2025-10-24
**Documentation Owner:** Project Lead
