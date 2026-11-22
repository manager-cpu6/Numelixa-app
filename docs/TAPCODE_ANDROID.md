# Numelixa TapCode — Android Autofill

TapCode is an opt-in Android Autofill service integrated into the existing Flutter app.

## Data flow

1. The signed-in app loads the user's own orders through the existing authenticated `GET /api/v1/orders` route.
2. The Activations screen sends only active order IDs and valid 4–8 digit codes to the native plugin. The existing server-side `POST /api/v1/orders/code` route remains the manual refresh path.
3. The plugin stores a short-lived encrypted cache using AES-GCM with a non-exportable Android Keystore key. The cache contains order ID, service, phone label, OTP and expiry only; it does not contain supplier credentials or the account bearer token.
4. User-scoped FCM code messages can update an already-cached order from the foreground or Flutter's background message handler. A push cannot create a new order association.
5. Android calls the Autofill service only after the user has selected Numelixa in Android settings and a receiving app requests Autofill. The service returns datasets only for fields explicitly marked `smsOTPCode` or `smsOTPCode1`–`smsOTPCode8`.
6. The user chooses a suggestion. The service does not inspect or control other apps, and it never uses Accessibility.

## Android requirements

- Android 8.0 (API 26) or newer for the Autofill Framework.
- In Numelixa: Settings → TapCode → Enable TapCode.
- In Android's Autofill settings: select **Numelixa TapCode** as the preferred Autofill service.
- Android 13+ notification permission is requested through the app's existing notification flow; no new runtime permission is introduced for Autofill itself.

## Compatibility and limitations

Autofill is offered only when a receiving app exposes the Android SMS OTP autofill hint. Many apps do not expose it, and some use custom digit fields that do not expose per-character hints. Those apps must use the existing Copy Code fallback. No app-specific compatibility, including WhatsApp, is claimed without real-device testing.

The current cache is populated when the user opens or refreshes Activations. Background FCM can update only an order association already cached from that authenticated order list. If an order has not yet been synchronized on the device, its push cannot create a new association; open Activations once to establish it.

Codes are retained only until the earlier of the server order expiry and ten minutes after the code timestamp. Logout/session invalidation clears the native OTP cache. Disabling TapCode clears the cache immediately. The optional auto-copy preference applies only to foreground OTP notifications and is off by default.

## Verification status

CI analysis, tests and APK build are required before release. A successful CI build verifies compilation but does not prove a receiving third-party app exposes compatible Autofill fields. Physical-device tests are still required for Android settings selection, real Autofill suggestion rendering, app background delivery and target-app compatibility.
