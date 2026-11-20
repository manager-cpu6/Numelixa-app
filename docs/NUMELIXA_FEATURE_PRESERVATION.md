# Numelixa Android feature-preservation inventory

This is a source-level inventory for the feature branch. “Present in code” does not mean a live production integration has been verified. Runtime checks against the production services and a physical Android device are still required.

## Screen and navigation inventory

| Area | Existing implementation | Classification | Preservation action |
|---|---|---|---|
| Startup and updates | Splash, app update service, download/update prompt | Existing in code; runtime verification required | Kept |
| Authentication | Email/password, Google sign-in, email verification, forgot/reset password, login approval | Existing in code; provider configuration requires verification | Kept |
| Home | Balance, quick actions, support and resource entry points | Existing; redesigned | Expanded with real-order recent services, notification preview and Updates preview |
| Numbers/catalog | Service catalog, search, country picker, live stock and pricing, purchase | Existing in code; provider inventory requires verification | Kept |
| Active numbers | Active activation list, SMS polling and cancellation | Existing in code; provider behavior requires verification | Kept |
| Orders | Order list, status, SMS/code retrieval, cancellation/refund display | Existing in code; provider behavior requires verification | Kept |
| Wallet | Balance, transactions, receipts, local payment, Ethiopia payment, crypto deposit | Existing in code; payment-provider credentials/webhooks require verification | Kept |
| Account/profile | Avatar upload, user identity, support entry points | Existing in code; expanded | Numelixa ID, copy ID, referral, security, developer and legal sections exposed |
| Support | Private Help Team Chat, Support Ticket, WhatsApp support | Existing in code; support operations require verification | Kept |
| Admin | User, payment, referral and support administration | Existing in code; admin permissions require live verification | Kept; Updates and partner enquiry shortcuts added |
| Notifications | FCM registration, native channels, notification routing and preferences | Existing in code; FCM credentials/device permission require verification | Kept; Updates channel and route added |
| Security | Biometric lock, password change, devices and session revocation | Existing backend/client contracts | Settings and device screens exposed |
| Developer/API | API access and developer documentation | Existing web portal/API; app entry point added | Kept |
| Legal | Terms, privacy, refund, cookie, acceptable-use and account deletion links | Existing website content | Canonical web routes linked |
| Updates | New channel directory, posts, membership, block/mute and media | Implemented on this feature branch; backend integration requires deployment and runtime verification | Added as conditional sixth tab |

## Current navigation

- Home
- Numbers
- Updates (only when the global server setting is enabled and the user has not hidden it)
- Orders
- Wallet
- Account

The shell uses an IndexedStack to retain tab state. When Updates visibility changes, the selected index is adjusted to keep the same destination selected where possible.

## Account inventory

- Profile avatar and upload: existing endpoint/UI.
- Full name and email: existing account data.
- Email verification state: displayed from the signed-in user record.
- Numelixa ID and copy: displayed when the server provides publicId/numelixaId.
- Referral rewards: existing web route linked.
- Help Team Chat: existing native screen linked.
- Support Ticket: existing native screen linked.
- WhatsApp support: configured support destination linked.
- Developer Portal and API documentation: existing web routes linked.
- Legal Center, Terms, Privacy, Refunds, Cookies, Acceptable Use and Account Deletion: canonical web routes linked.
- Device sessions, sign out other devices, password change, biometric lock and notification preferences: native screens added or exposed using existing contracts.
- Edit-profile endpoint and account deletion API are not fabricated; profile fields remain read-only where no verified mutation contract exists, and account deletion links to the official request process.

## Updates feature contract

Backend endpoints are in the Virt-num repository. The Flutter client uses:
- GET /api/updates
- GET /api/updates/preferences
- GET /api/updates/channels/{slug}?page={n}
- POST /api/updates/channels/{slug}/membership
- DELETE /api/updates/channels/{slug}/membership
- POST /api/updates/channels/{slug}/block
- POST /api/updates/channels/{slug}/views
- GET /api/updates/blocked
- DELETE /api/updates/blocked

Actual views are unique per authenticated user per UTC day. The UI records a view when a post card is built into the lazy feed, not for every refresh. Public display overrides remain separate from actual analytics.

The user’s hide setting is stored server-side and is separate from the global administrator setting. Subscriptions and blocks are preserved when Updates is hidden or globally closed.

## Known limitations / verification required

- No physical Android device test has been completed in this branch session.
- FCM delivery depends on valid Firebase server credentials, registered tokens and Android notification permission.
- Video playback uses the bundled video_player dependency; real MP4/WebM playback must be tested on-device and against deployed media.
- Provider stock, number purchase, SMS polling, cancellation/refund, Ethiopia payment, local checkout and crypto payment require end-to-end provider tests.
- Profile editing is not exposed because no verified profile-update endpoint was found in the current contract.
- Account deletion remains an official web request flow; no new destructive API was invented.
- Updates post scheduling, reactions, sharing and reporting are not exposed because their backend contracts are not implemented.
- No APK is considered releasable until the current CI release build and signing/update verification pass.
