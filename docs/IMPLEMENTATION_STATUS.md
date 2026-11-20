# Mobile Platform Implementation Status

**Repository:** `manager-cpu6/Numelixa-app`  
**Branch:** `main`  
**App version in pubspec:** `1.0.31+32`  
**Status date:** 20 November 2026.

## Implemented in this mobile-only change set

- Account is simplified to user identity, admin entry for authorized admins, and only three support actions: private verified Support Team chat, Support Ticket, and WhatsApp.
- Removed the in-app Developer Center and API documentation screens; developer resources remain on the public website.
- Fixed numeric provider suffix normalization and popular-service ranking. Service logos now load PNG favicons from known official brand domains rather than SVG assets that Flutter's standard Image widget cannot decode.

- Account support shortcuts: direct private Support Team chat with the official blue verified mark, dedicated Support Ticket entry, and direct WhatsApp support.
- Removed the in-app Developer Center entry from the Android Account screen; the public website developer portal is outside this app-only repository change.
- Service catalog now prioritizes available popular services (WhatsApp, Telegram, TikTok, Instagram, Facebook, Google, Gmail and YouTube) while retaining the complete live API catalog. Corrected numeric service suffix normalization.

- Wallet: searchable ledger, All/Added/Spent/Refunds filters, transaction details, verified receipt action, and clear disclosure that pending/failed payment-provider events are not returned by the current ledger endpoint.
- Orders: search, Active/Completed/Cancelled/Failed filters, server-provided USD price, expiry countdown refreshed by the existing 15-second poll, SMS copy/refresh and cancellation.
- Order cancellation now uses the verified `POST /api/v1/orders/cancel` contract with `orderId`; the prior `DELETE /api/orders` call was incorrect.
- Account: clearer Account Information, Security & Devices, Help & Resources and App Preferences groups; duplicate Help Team Chat and WhatsApp entries were consolidated into Support Center; Legal Center added.
- Support: authenticated ticket GET/POST using the existing backend contract, active-ticket submission guard, Help Team Chat, WhatsApp, official support email, official Help Center and troubleshooting.
- For Clients: onboarding, service/country selection, SMS/activation guidance, refund information, account help and FAQ.
- For Partners: business/API/technical/reseller enquiry categories, verified `support@numelixa.com` copy/email actions, and no unsupported affiliate promise.
- Developer Center: searchable in-app API reference with navigation drawer, mobile topic chips, breadcrumbs, copyable cURL/JavaScript/Node.js/Python/PHP examples, public API v1 routes, API keys, webhooks, status codes and troubleshooting.
- Legal Center: direct links to current Terms, Privacy, Refund, Cookie, Rules & Acceptable Use and Account Deletion policies; published policy text was not changed.
- Security: HTTPS-only API requests, redirect refusal, removal of raw auth callback exception logging, private local-notification visibility, legacy API-key sign-in warning and security tests.
- Shared theme refinements applied to Help Team Chat, Support Admin, Notification Preferences and payment receipt.

## Files changed in this implementation

- `lib/screens/app_shell.dart`
- `lib/services/numelixa_repository.dart`
- `lib/services/api_client.dart`
- `lib/services/auth_service.dart`
- `lib/main.dart`
- `lib/services/notification_service.dart`
- `lib/screens/help_team_screen.dart`
- `lib/screens/support_admin_screen.dart`
- `lib/screens/notification_preferences_screen.dart`
- `lib/widgets/payment_receipt_dialog.dart`
- `pubspec.yaml`
- `README.md`
- `docs/DEVELOPER_API_REFERENCE.md`
- `docs/MOBILE_API_CONTRACT.md`
- `docs/LEGAL_POLICY_AUDIT.md`
- `docs/ANDROID_SECURITY_REVIEW.md`
- `test/api_client_security_test.dart`

## Validation actually performed

- Confirmed source-level delimiters/string structure for modified Dart files using a static structural scan.
- Confirmed the cancellation repository call matches the backend route and request body.
- Confirmed the official support ticket routes and field constraints against the backend source.
- Confirmed official policy routes and the published support email against the website source (read-only).
- Confirmed the latest GitHub commit/status and queried available workflow-run data.

## Validation not performed

This runtime does not have Flutter, Dart, Gradle or Android SDK installed; only Java 21 is available. Therefore the following were **not run**:
- `flutter analyze`
- `flutter test`
- `flutter build apk --release`
- Android package/signature/Firebase/Google OAuth verification on a built APK
- Physical-device navigation, accessibility and lock-screen notification testing

The latest GitHub combined status returned a Vercel check failure caused by a build-rate-limit link, not an Android build result. No Android workflow run or APK artifact was returned. No APK is claimed as generated.

## Backend / owner requirements still open

1. Make the existing cancellation backend provider-aware: the verified `/api/v1/orders/cancel` route currently imports the 5SIM-specific cancel function rather than the active-provider `cancel` wrapper. With TigerSMS orders this may reject otherwise eligible cancellations. The mobile app now calls the correct v1 route but cannot fix this backend behavior without a backend change.
2. Add a unified authenticated payment-history endpoint for pending, completed, failed, rejected and refunded provider attempts, including a stable schema and idempotency/reference behavior.
3. Publish and verify full Sifalo, Binance and Ethiopia payment request/response contracts before documenting them for third-party developers.
4. Confirm numeric API rate quotas and reset headers.
5. Decide whether to retire the legacy API-key sign-in path from the Android app; signing out does not revoke a developer API key.
6. Confirm remote FCM lock-screen redaction and Android permission manifest on physical devices.
7. Provide a machine-readable account deletion API only if the owner wants in-app deletion; until then the app links to the published policy and support channel.
8. Confirm mobile session refresh/rotation beyond the current 30-day expiry.
9. Confirm affiliate programme availability before advertising an affiliate application flow.

No website repository, backend API implementation, Vercel configuration or unrelated project was modified.
