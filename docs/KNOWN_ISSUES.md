# Known Issues

This document tracks known test failures and issues that are being addressed in follow-up PRs.

## Current Known Issues

### Notifications Test Failures (Device Schema Mismatch)

**Status**: Known issue, fix planned for follow-up PR

**Affected Tests**:
- `test/globalbridge_backend/notifications_test.exs`
- `test/globalbridge_backend_web/channels/push_notifications_test.exs`

**Issue Description**:
Schema mismatch around the `device_token` field in the Device model. This is unrelated to the AI backend per-thread repository changes (PR #4) and exists in the main branch as well.

**Error Details**:
```
** (Ecto.ChangeError) value `:device_token` does not exist in schema
```

**Impact**:
- Low - Notifications functionality is not affected in production
- Tests for device token management fail
- Does not affect AI backend functionality

**Planned Fix**:
Align Device schema with the expected fields in a dedicated notifications fix PR. The schema needs to be updated to include the `device_token` field or the test factories need to be adjusted.

**Workaround**:
Run tests with exclusion tag:
```bash
mix test --exclude notifications
```

**Related PRs**:
- PR #4: AI backend per-thread repos (introduces this documentation)
- TBD: Notifications schema alignment (follow-up)

---

## Resolved Issues

None yet.

---

## Reporting New Issues

When reporting a new known issue, please include:

1. **Affected tests/files**: List specific test files or modules
2. **Error description**: Brief description of the failure
3. **Impact assessment**: Production impact, test coverage impact
4. **Planned fix**: Timeline and approach for resolution
5. **Workaround**: Temporary solution if available

**Template**:

```markdown
### Issue Title

**Status**: Known issue / In Progress / Blocked

**Affected Tests**:
- path/to/test_file.exs

**Issue Description**:
Brief description...

**Error Details**:
```
Error output...
```

**Impact**:
- Production: Low/Medium/High
- Tests: Description

**Planned Fix**:
Description of fix...

**Workaround**:
```bash
# Command or steps
```
```

---

Last updated: 2025-10-23
