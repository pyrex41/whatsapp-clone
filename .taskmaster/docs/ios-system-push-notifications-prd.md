# PRD: iOS System Push Notifications (APNs)

Author: Platform Team
Status: Draft
Target Release: 0.9.x
Last Updated: 2025-10-22

## Summary

Implement first-class iOS system push notifications using Apple Push Notification service (APNs). This includes device token registration, backend integration for token storage and push delivery, user notification handling (foreground and background), navigation on tap, and badge management. Because APNs requires an Apple Developer account and provisioning, this feature must be separately gated behind an environment variable, with graceful fallback to in-app banners during development.

## Goals

- Register device for remote notifications and obtain APNs device token.
- Handle notification presentation in foreground (banner/sound/badge) and background delivery.
- Navigate to the relevant thread when the user taps the notification.
- Manage badge counts and synchronization with unread state.
- Define a consistent payload contract with the backend.
- Allow switching between `SYSTEM` and `BANNER` modes via env var.

## Non-Goals

- In-app banner UI (covered by separate PRD). However, system mode may still use in-app banners for foreground suppression or missing entitlements.
- Building a push provider service from scratch here (assumes backend integration exists or will be implemented in parallel).

## Prerequisites

- Apple Developer Program account (Team ID, access to Certificates, Identifiers & Profiles).
- Xcode project with Push Notifications capability and Background Modes → Remote notifications enabled.
- App ID with Push Notifications entitlement.
- Backend push provider supporting APNs token-based auth (recommended) or certificate-based legacy.

## Configuration & Environment

- Env var: `IOS_NOTIFICATIONS_MODE`
  - Values: `SYSTEM` | `BANNER` | `AUTO` (optional)
  - For APNs, set `IOS_NOTIFICATIONS_MODE=SYSTEM`.
  - `AUTO` behavior (optional): Try `SYSTEM`, fall back to `BANNER` if registration fails or entitlements missing.
- Location to configure:
  - Xcode Scheme → Run → Arguments → Environment Variables
  - Accessed via `ProcessInfo.processInfo.environment["IOS_NOTIFICATIONS_MODE"]`

Note: In CI and release builds, prefer `SYSTEM`. In local development without a developer account, use `BANNER`.

## Payload Contract (APNs → App)

JSON payload (aps + custom):

```json
{
  "aps": {
    "alert": {
      "title": "<thread_or_sender_title>",
      "body": "<message_snippet>"
    },
    "badge": <int>,
    "sound": "default",
    "category": "MESSAGE_CATEGORY"
  },
  "type": "message",
  "conversation_id": "<uuid-string>",
  "message_id": "<uuid-string>",
  "sender_id": "<string>",
  "sent_at": "<iso8601>"
}
```

Requirements:

- `conversation_id` and `message_id` are required for navigation and de-duplication.
- `category=MESSAGE_CATEGORY` enables quick actions (Reply, Mark as Read).
- Payload must be ≤ 4KB.

## Technical Design

App integration:

- `NotificationConfig` (shared with banner PRD)
  - Parses `IOS_NOTIFICATIONS_MODE` to `.system` or `.banner`.
- `NotificationManager` (existing)
  - Request authorization only when mode is `.system`.
  - Register for remote notifications and capture device token.
  - Implement `UNUserNotificationCenterDelegate`:
    - `willPresent` (foreground): present as banner/sound/badge. Optionally suppress in-app duplication if banner mode is active.
    - `didReceive` (tap): parse `userInfo`, route to thread.
- AppDelegate hooks
  - `didRegisterForRemoteNotificationsWithDeviceToken` → `NotificationManager.setDeviceToken(_:)`.
  - `didFailToRegisterForRemoteNotificationsWithError` → fallback behavior if `AUTO`.
- Badge handling
  - Increment/clear using `UIApplication.shared.applicationIconBadgeNumber`.
  - Sync unread counts with local DB on app open.

Backend integration:

- Device token registration endpoint: `POST /api/push/devices`
  - Request: `{ platform: "ios", device_token: "<hex>", app_version: "<string>", user_id: "<string>" }`
  - Auth: Bearer token (Auth0 access token).
  - Response: 200 OK on idempotent update.
- Push send contract: Backend uses APNs token-based auth (Team ID, Key ID, .p8 key) to send to device tokens.

Foreground behavior:

- If app is foreground and `IOS_NOTIFICATIONS_MODE=SYSTEM`, present OS banner via `willPresent` options `[.banner, .sound, .badge]`.
- If `IOS_NOTIFICATIONS_MODE=BANNER`, do not request authorization; rely on in-app banners only.

Fallbacks:

- If `SYSTEM` but entitlements missing or registration fails:
  - Log warning and either:
    - If `AUTO`, switch to banner mode for the session.
    - If `SYSTEM`, keep disabled with clear log to developer.

## Permissions & Entitlements

- Xcode Capabilities:
  - Push Notifications (enabled)
  - Background Modes → Remote notifications
- Info.plist:
  - Provide `NSUserNotificationsUsageDescription` string.

## Analytics & Telemetry

- Log `push_token_registered`, `push_will_present`, `push_tap`, `push_registration_failed`, with properties `{ error, mode }`.
- Monitor tap-through rate, foreground presentation rate, registration failure rate.

## Accessibility & Localization

- OS-level banners inherit system accessibility settings.
- Ensure quick action labels are localized.

## Performance

- Minimal app-side CPU; avoid heavy parsing in delegate methods.
- Keep navigation on tap under 300ms (cold start aside).

## Security & Privacy

- Store device token in Keychain or memory; avoid logging full token in production logs.
- Send device token only over HTTPS with user auth.
- Do not include sensitive content in notification body if user has “Hide Previews.”

## Error Handling

- If token registration fails, retry with backoff; report to telemetry.
- If payload missing `conversation_id`, still present but navigate to inbox fallback.

## Testing Strategy

- Simulator push:
  - `xcrun simctl push booted <bundle-id> payload.apns`
- Unit tests
  - Parse `userInfo` and map to navigation/action.
  - Mode parsing and fallback logic.
- Integration tests
  - Mock device token registration flow.

## Rollout & Release Plan

- Default `SYSTEM` for Release once developer account and entitlements are configured; otherwise `BANNER` in Debug.
- Feature gate via `IOS_NOTIFICATIONS_MODE`.
- Staged rollout: 1% → 10% → 100% (App Store phased release or feature flag if applicable).

## Dependencies

- Apple Developer Account for APNs.
- Backend push service integration and token registration endpoint.

## Risks & Mitigations

- Risk: Registration failures block notifications → Mitigation: `AUTO` fallback to banner, telemetry alerts.
- Risk: Payload growth >4KB → Mitigation: enforce payload size and offload details to in-app fetch.

## Acceptance Criteria

- With `IOS_NOTIFICATIONS_MODE=SYSTEM`, app requests permission, registers device token, and receives a simulator push showing an OS banner in foreground with correct title/body, and tapping navigates to the thread.
- Badge increments on delivery and clears on viewing messages.
- If developer account/entitlement not present, failure is handled without crash; optional `AUTO` falls back to banners.

## Open Questions

- Should we implement silent pushes (content-available) to prefetch messages? Default: not in initial release.
- How to handle per-conversation notification settings vs global iOS settings? Initial: respect in-app mute flags; iOS overrides remain user-controlled.

