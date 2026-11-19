# Numelixa Android Security Review

**Scope:** Read-only review of the current mobile repository and relevant existing backend route contracts. No backend or website files were changed.  
**Review date:** 20 November 2026.

## Controls verified

| Area | Verified implementation |
|---|---|
| Session storage | Native access token is stored using `flutter_secure_storage`; it is not stored in SharedPreferences or app logs |
| Session validation | App restores session through `GET /api/me`; invalid/expired 401 or 403 clears the local token |
| Logout | ApiClient sends `x-numelixa-client: android-app`; backend `POST /api/auth/logout` calls `revokeMobileSession` for the Bearer token |
| Device sessions | App reads/removes sessions through authenticated `/api/mobile/devices`; backend scopes deletion to the authenticated user's device/session |
| Password management | App uses existing authenticated password-change start/confirm endpoints; no frontend-only password replacement was introduced |
| Biometric lock | Uses Android LocalAuthentication; this is an additional local gate, not a replacement for server authorization |
| API transport | ApiClient defaults to `https://www.numelixa.com`; now refuses non-HTTPS URLs and does not follow HTTP redirects with authorization headers |
| Device metadata | Device ID and device/platform/app-version metadata are sent for session/device management; avoid adding more fingerprinting fields without review |
| Deep links | Google callback handling accepts only the expected `com.numelixa.app://auth/callback` scheme/host/path and forwards the one-time ticket to the backend completion route; arbitrary notification URLs are not executed |
| Clipboard | OTP copy is performed only through an explicit user action; no automatic clipboard write was added |
| Notifications | FCM and local notifications use dedicated category icons; notification visibility is now explicitly private for lock-screen display |
| Support | Ticket submissions use the existing authenticated `/api/support` route; app does not fabricate ticket state |
| Logging | Removed raw Google callback exception logging because it could contain one-time authentication details |

## Changes made during this review

1. ApiClient rejects any non-HTTPS API base before sending credentials.
2. ApiClient creates requests with redirect following disabled and returns a safe redirect error rather than forwarding credentials to another URL.
3. Added unit tests for cleartext URL rejection and redirect non-following.
4. Removed raw exception text from Google callback restoration logs.
5. Set notification visibility to private in both foreground and background local-notification paths.

## Risks that remain / owner decisions

1. **Legacy API-key sign-in in the app:** the sign-in UI still allows a user to paste a developer API key. The key is stored in secure storage, but it is still a long-lived developer credential on a user-controlled device. The mobile logout endpoint revokes mobile session tokens, not developer API keys. This legacy path should be removed or explicitly approved and redesigned; it was not silently removed to avoid breaking existing sign-in behavior.
2. **OTP lock-screen behavior:** notification visibility is set to private, but the exact redaction behavior depends on Android lock-screen settings and OEM implementation. Verify on physical Android devices with a secure lock screen.
3. **SMS retention:** the app receives full SMS data in authenticated order responses and notification payloads. Confirm backend retention and app-side deletion policy; avoid logging or analytics capture.
4. **App permissions / manifest:** the repository file connector did not resolve the Android manifest path in this review, so the final merged manifest and exact runtime permission set still need inspection in a Flutter build environment.
5. **Network certificate pinning:** no certificate pinning is configured. HTTPS and redirect rejection are present; decide whether pinning is appropriate for the app's operational and certificate-rotation model.
6. **Account deletion:** no user-facing authenticated deletion API was verified. The app links to the official deletion policy and support process instead of faking a delete operation.
7. **Developer webhook delivery:** the backend currently makes a short synchronous delivery attempt and does not automatically retry failures. Keep polling/reconciliation and monitor delivery status.

## Security test status

Added `test/api_client_security_test.dart` for:
- refusing cleartext HTTP without making a request;
- not following a 302 redirect while an Authorization header is present.

These tests have **not yet been executed** because this environment has Java but no Flutter or Dart SDK. They must run in the repository's Android CI or a Flutter development environment before release approval.
