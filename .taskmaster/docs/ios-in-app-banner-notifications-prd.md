# PRD: iOS In-App Banner Notifications (Non–System Push)

Author: Platform Team
Status: Draft
Target Release: 0.9.x
Last Updated: 2025-10-22

## Summary

Implement in-app banner notifications for the iOS client that surface timely alerts (e.g., new message received) within the application UI without relying on iOS system-level push notifications (APNs). This enables a robust notification UX in development and environments without an Apple Developer account or APNs provisioning. The feature is fully switchable via an environment variable so we can independently ship and test both in-app and system notifications.

## Goals

- Show ephemeral, tappable banners when notable events occur (primarily new messages) while the app is active (foreground).
- Avoid iOS permission prompts and APNs dependencies; no Apple Developer account required.
- Respect conversation-level settings (mute, DND) and user-level app settings.
- Provide reliable navigation on banner tap to the relevant conversation/thread.
- Add analytics for impressions, taps, dismissals, and time-to-open.
- Enable configuration via an environment variable switch shared with the system push implementation.

## Non-Goals

- Background delivery while the app is not active (requires system push).
- Replacing system notifications in production. This feature complements APNs but does not supersede it.
- Implementing server-driven in-app messaging campaigns beyond basic event-to-banner mapping.

## User Stories

- As a user actively using the app, when I receive a new message in a different thread, I see a small banner at the top with sender and snippet; tapping takes me to that thread.
- As a user, I can dismiss a banner if I don’t want to navigate right now.
- As a user, if I’m already viewing the relevant thread, I don’t need a banner for my own thread (optional subtle haptic instead).
- As a user, if a conversation is muted, I don’t receive banners for it.

## Experience & UX

- Placement: Top-of-screen banner, overlays app content, avoids obstructing critical UI (status/navigation bars).
- Duration: Auto-dismiss after 4–6s; pause the timer while user long-presses or swipes partially.
- Interaction:
  - Tap: Navigate to conversation/thread and mark as seen.
  - Swipe up or X: Dismiss.
  - Optional: Swipe down reveals quick actions (Mark Read, Reply) if present.
- Multiple banners: Queue incoming events; show one at a time. Coalesce rapid events from the same thread (e.g., “3 new messages”).
- Visuals: Follow iOS HIG; rounded corners, blur background, light/dark themes, avatar + title + snippet.
- Accessibility: VoiceOver announcement, large text support, sufficient contrast, and hit target sizes.

## Functional Requirements

1. Banner presentation
   - Display when app is foreground active.
   - Suppress banners if user is already focused on the same thread (configurable).
   - Respect conversation mute/DND settings.
2. Event sources
   - Realtime messages via Phoenix/WebSocket integration.
   - Optional: Local events (mentions, invites) if modeled.
3. Queueing and coalescing
   - Maintain a FIFO queue; coalesce events from the same thread within 2s window.
4. Navigation
   - On tap, route to the thread detail view; ensure id and routing are available.
5. Analytics
   - Track impression, tap, dismiss, and dwell duration.
6. Configuration
   - Controlled by `IOS_NOTIFICATIONS_MODE` env var.
7. Theming and localization
   - Support light/dark modes and localized strings.

## Configuration & Environment

- Env var: `IOS_NOTIFICATIONS_MODE`
  - Values: `BANNER` | `SYSTEM` | `AUTO` (optional)
  - For in-app banners, set `IOS_NOTIFICATIONS_MODE=BANNER`.
  - Suggested defaults:
    - Debug: `BANNER`
    - Release: `SYSTEM` (configured in system push PRD)
- Location to configure:
  - Xcode Scheme → Run → Arguments → Environment Variables
  - Read in code via `ProcessInfo.processInfo.environment["IOS_NOTIFICATIONS_MODE"]`

Implementation note: Do not request notification authorization when in `BANNER` mode. All banner functionality must work without `UNUserNotificationCenter` permission.

## Technical Design

Components (SwiftUI):

- `InAppBannerCenter` (new)
  - In-memory queue of `BannerItem` models (id, title, subtitle/snippet, threadId, avatarUrl, timestamp, priority).
  - Present/dismiss lifecycle and timers; coalescing policy.
  - Public API:
    - `present(from event: NotificationEvent)`
    - `dismiss(id:)`
    - `clear()`
- `InAppBannerView` (new)
  - Visual presentation using SwiftUI; gestures (tap, swipe), animations.
  - Adaptive layout; avatar, sender, snippet, time.
- `InAppBannerContainer` (new)
  - Root overlay container attached to the app’s root view to host banners (ZStack overlay).
- `NotificationConfig` (new)
  - Reads `IOS_NOTIFICATIONS_MODE` and exposes `enum NotificationMode { case banner, system }`.
  - Shared by both PRDs; used to branch logic cleanly.

Event mapping:

- Source: `PhoenixChannelManager.onMessage(conversationId:)` → create `NotificationEvent.messageReceived` with metadata.
- Filter: If current visible thread == event.threadId and `suppressOwnThread = true`, skip.
- Mute: If thread muted, skip.
- Present: `InAppBannerCenter.present(event)`.

Navigation:

- On tap, send `NotificationCenter` (Foundation) event or use a shared Navigator/Router to push the appropriate thread view.
- Ensure deep-link style navigation works from any tab/screen.

App lifecycle:

- On app foregrounding, no banner history replay. Instead rely on unread counts within the UI. Optionally present a summary banner (“You have 5 unread messages”) if desired.

Haptics:

- Light impact on show and success haptic on tap (configurable, disabled for VoiceOver announcements overlap).

## Data Model

- `BannerItem`
  - `id: UUID`
  - `threadId: UUID`
  - `title: String` (e.g., sender or thread title)
  - `subtitle: String` (message snippet)
  - `avatarURL: URL?`
  - `count: Int` (for coalescing)
  - `timestamp: Date`
  - `actions: [BannerAction]` (optional)

## Telemetry & Analytics

- Log events: `banner_impression`, `banner_tap`, `banner_dismiss`, `banner_coalesce`, with properties `{ threadId, count, latencyMs }`.
- Dashboard: Track CTR, average dwell time, coalescing effectiveness.

## Accessibility & Localization

- VoiceOver: Announce “New message from <sender>: <snippet>. Tap to open.”
- Large text: Content scales without clipping.
- Localization keys for all strings; RTL layout validated.

## Performance

- Render within 16ms frame budget; pre-measure text to avoid layout thrash.
- Limit queue length (e.g., max 5 pending) to prevent overload.

## Security & Privacy

- No APNs token handling here.
- Do not include PII beyond what is already on-screen elsewhere; respect mute/DND.

## Error Handling

- If presentation fails (view not mounted), log and drop.
- If navigation fails, log error and keep app state stable (no crash).

## Testing Strategy

- Unit tests
  - Queueing/coalescing logic in `InAppBannerCenter`.
  - Mode config parsing in `NotificationConfig`.
- UI tests
  - Snapshot tests for light/dark modes and dynamic type.
  - Interaction tests for tap, swipe dismiss.
- Integration tests
  - Simulate message events through Phoenix mocks and assert banner presentation and navigation.

## Rollout & Release Plan

- Default `BANNER` in Debug; allow switching via scheme.
- Ship behind `IOS_NOTIFICATIONS_MODE` gate; no impact on system push code paths.
- Add a developer setting toggle in a hidden debug menu to switch modes at runtime (optional, reads env on launch).

## Dependencies

- Existing Phoenix/WebSocket message stream.
- No Apple Developer account required.

## Risks & Mitigations

- Risk: Banner interrupts critical flows → Mitigation: Dismissible UI, small footprint, rate limiting.
- Risk: Over-notifying → Mitigation: Respect mute/DND, coalesce bursts.

## Acceptance Criteria

- When `IOS_NOTIFICATIONS_MODE=BANNER` and a new message arrives in a different thread, a banner appears within 300ms, is tappable to navigate, and auto-dismisses in 4–6s.
- When viewing the same thread and suppression is enabled, no banner appears.
- Banners respect mute/DND; analytics events captured.
- No iOS permission prompt appears when using banner mode.

## Open Questions

- Should we show banners while a full-screen video call is active? Default: suppress.
- Do we need a summary banner for multiple threads? Default: no; rely on unread UI.

