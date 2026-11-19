# Numelixa Updates — Backend Audit and Integration Gate

Audit date: 2026-11-20
Android repository: `manager-cpu6/Numelixa-app` (`main`)
Backend inspected read-only: `manager-cpu6/Virt-num` (`main`)

## Decision

The native application can be prepared for an Updates client, but the requested channel platform cannot be truthfully enabled against the current verified production API. No channel, membership, post, media, analytics, block-list, or global Updates feature-control routes were found in the backend repository tree. The Android repository also contains no Updates implementation or channel API client.

**Fail closed:** do not show fabricated channels/posts/counts, do not claim subscriptions or publishing succeeded, and do not enable an Updates navigation entry until the server exposes an authenticated feature-state contract. Do not infer that the feature is enabled from an API timeout.

This document is an integration specification, not a claim that any proposed route already exists. No production backend files were changed as part of this audit.

## Existing verified backend capabilities

| Capability | Existing route | Verified behavior |
|---|---|---|
| User notifications | `GET /api/notifications` | Requires authenticated user; returns that user's latest 50 notification records with `id`, `title`, `message`, `createdAt`, `readAt`, and unread count. |
| Mark notifications read | `POST /api/notifications` | Requires authenticated user; marks one notification read by ID or marks all unread notifications read. |
| Admin broadcast | `GET/POST /api/admin/notifications` | Uses server-side `requireAdmin()`; admin can inspect recent admin-sent notifications/device counts and send a plain title/message broadcast to all users or one user. |
| FCM device registration | `POST /api/notifications/register` | Requires authenticated user, stores Android device token linked to the user and device metadata. |
| Global app notification preferences | `GET/PATCH /api/mobile/notification-preferences` | Authenticated per-user `appEnabled` and `emailEnabled` booleans. |

These are notification primitives only. They do not implement channels, channel memberships, media posts, channel-level preferences, blocking, per-post analytics, or an Updates feature kill switch.

## Missing production backend capabilities

The following are not present in the inspected route tree and must not be called from the app as if they existed:

- Authoritative global Updates state, maintenance state, and server-enforced route/action gate.
- Channel directory/detail/create/update/delete/activate/deactivate.
- Channel logos and cover image upload/storage lifecycle.
- Server-authoritative verification badge control.
- Subscribe/unsubscribe and membership uniqueness.
- Real subscriber count and separate public display override.
- Channel notification preferences and blocked channels.
- Post list/detail/create/update/delete/publish/pin/unpin.
- Image upload, media metadata, thumbnails, storage authorization, and deletion.
- Actual and unique post view analytics with server-side deduplication.
- Admin overview and channel/post analytics.
- Post-published FCM fanout scoped to active channel members and preferences.
- Notification deep-link resolution for channel/post identifiers.
- Pagination cursors and media delivery/cache policy.

## Required API contract — proposal only, not implemented

The backend owner should expose a versioned, authenticated API. Route names below are proposed design names only and must be reconciled with the existing server conventions before implementation.

### Feature state

- Read an authoritative `updatesEnabled`, `maintenanceMode`, and notification-enabled state.
- Admin-only mutation for global enable/disable.
- Server must reject all Updates read/write actions for ordinary users while globally disabled; admin management access must remain possible.
- App must fail closed when feature state cannot be established. Preserve cached content only if the server explicitly marks it safe for offline display; never allow offline admin mutations.

### Channels and memberships

- Paginated public channel directory and channel detail.
- Authenticated subscribe/unsubscribe with a unique (user, channel) membership constraint and idempotent semantics.
- Authenticated channel notification preference update.
- Block/unblock only if product policy defines how block interacts with membership; server must atomically stop notification eligibility.
- Actual membership count computed from membership records. Public display override stored separately, writable only by server-authorized admins and never used for delivery or analytics.

### Posts and media

- Paginated published posts by feed/channel, stable cursor ordering.
- Admin-only create/edit/delete/publish/pin operations.
- Upload authorization and media finalization endpoints using the chosen storage provider; server validates MIME type, byte size, image decoding, dimensions, ownership, and malware/content policy as appropriate.
- Store media metadata and thumbnail/original variants; do not proxy arbitrary user-supplied URLs.
- View event endpoint with server-side deduplication and privacy-conscious retention. Actual counts and optional public display overrides must be separate.

### Analytics and administration

- Admin-only overview, channel statistics, post statistics, and media statistics.
- Server derives actual subscriber/view counts. Public display overrides are presentation-only fields.
- Every admin mutation must authorize from the authenticated server-side identity, not a Flutter-supplied role flag.
- Audit log for privileged changes, including actor, target, operation, timestamp, and safe before/after metadata.

### Push notifications

- Publish events only after a post is successfully committed.
- Select recipients from active channel memberships and current per-user/channel preferences on the server.
- Exclude blocked channels, unsubscribed users, disabled channels, globally disabled Updates, and globally/per-user disabled notifications.
- Use stable event IDs and idempotency keys to prevent duplicate sends.
- Push payload should contain opaque channel/post IDs and a short safe preview; do not put OTPs or sensitive account data in lock-screen previews.
- On tap, the app must re-fetch the authorized post and must not trust a payload URL or expose private media.

## Suggested data invariants

Use the backend's established database and ID conventions rather than blindly adopting a new schema.

- Channel slug unique after normalization.
- Membership unique on (userId, channelId).
- Blocked state and membership/notification eligibility must have one documented, atomic rule.
- Actual subscriber count is derived from memberships; public count override is a separate field and mode.
- Actual view analytics are append-only/deduplicated server-side; public display override is separate.
- Post media belongs to a post/channel and is only served under the server's visibility policy.
- Deleted/deactivated channels and posts have defined retention behavior; do not silently delete analytics or media.
- All timestamps are server-generated UTC values.
- Every privileged write has server-side authorization and audit logging.

## Android integration requirements

1. Add a typed Updates API repository only after the backend contract and response schemas are finalized.
2. Fetch global feature state before exposing Updates navigation or deep links. Unknown/error state means hidden and inaccessible, not enabled.
3. Use the existing `ApiClient` so bearer tokens remain on the configured HTTPS origin and secure storage remains unchanged.
4. Use stable IDs and cursor pagination; deduplicate requests and view events.
5. Keep admin controls hidden for non-admin UX, but rely on server authorization for every mutation.
6. Keep channel subscriptions, blocked channels, unread state, and notification preferences server-authoritative.
7. Use existing Firebase/FCM registration only as a delivery transport; it does not itself provide channel membership or targeting.
8. Add tests for global shutdown, unauthorized admin actions, duplicate membership, request retries, pagination, view deduplication, notification eligibility, and offline/unknown feature state.

## Release gate

Do not ship a visible/operational Updates feature until all of the following exist and are verified:

- Published API schemas and server-side authorization.
- Feature-state endpoint and server-side global shutdown enforcement.
- Channel and membership persistence.
- Post and media storage lifecycle.
- Analytics and count separation.
- Notification targeting and idempotency.
- Integration tests against a non-production backend environment.
- Flutter tests and a successful Android release build.

## Audit scope and limitations

The repository trees and relevant route source files were inspected read-only. This confirms the absence of Updates-specific routes in the current inspected backend tree; it does not prove that no undocumented external service exists. No secrets were accessed or copied. No backend, website, Vercel, Firebase configuration, or unrelated project was modified.
