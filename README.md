# Numelixa Android (Flutter)

Standalone native Flutter application in `manager-cpu6/Numelixa-app`. It does not use WebView and this repository does not change the website project.

## Implemented mobile functionality

- Native dark Numelixa shell and secure API-key sign-in.
- Server-validated bearer credential stored with `flutter_secure_storage`; session restoration revalidates against `GET /api/me`.
- Typed repository for existing balance, services, countries, orders, order details, SMS polling, cancellation, transactions, notification list/read and password-reset request routes.
- Live service and country catalog screens; no fabricated balances, orders, stock or SMS values.
- Foreground FCM presentation, token refresh, authenticated device registration, one-time Android notification permission prompt and basic notification routing.
- GitHub Actions workflow for analyze/test, debug APK, release APK and AAB artifacts.
- Optional Firebase configuration and release signing via GitHub Actions secrets.

## Existing backend contracts inspected

The accessible `manager-cpu6/Virt-num` source confirms:

- `POST /api/auth/login`: email/password login, but it creates an HttpOnly `numelixa_session` cookie and returns only `{ok, role}`; it does not issue a mobile access or refresh token.
- `POST /api/auth/signup`: creates an account, creates a cookie session and sends email verification; no mobile token is returned.
- `POST /api/auth/forgot`: sends a password-reset link; it does not return a reset token for an app-native reset flow.
- `POST /api/auth/logout`: clears the cookie session and redirects; not a JSON bearer-token revocation endpoint.
- `GET /api/me`: returns the authenticated user.
- `GET /api/developer/keys?reveal=1`: reveals the existing user's API key for an already-authenticated website session.
- `GET /api/v1/balance`, `GET /api/v1/orders`, `GET /api/v1/orders/:id`, `POST /api/v1/orders`, `POST /api/v1/orders/code`, `POST /api/v1/orders/cancel`, `GET /api/v1/transactions`.
- `GET /api/catalog/services` and `GET /api/catalog/countries?service=...`.
- `GET /api/notifications`, `POST /api/notifications` (mark one/all read), and `POST /api/notifications/register`. Device registration uses `requireUser()`, which accepts a valid Numelixa API key as a Bearer credential and associates the token with that user.
- The backend does not expose a native access-token refresh contract. The API key is a long-lived bearer secret, not an expiring access token.

The app uses the real existing bearer/API-key authentication path instead of capturing website cookies. Users can connect with an API key from the existing developer-key screen. This is a real but less convenient bridge, not a replacement for native email/password login.

## Backend contract still required for full native login

The website repository must remain untouched unless separately approved. To support native email/password and Google sign-in without browser cookies, the backend needs a JSON mobile-session exchange that returns a short-lived access token and preferably a rotating refresh token, plus refresh/revoke endpoints. The current login/signup/google-native-complete routes do not return those credentials. No backend changes were made.

For full SMS/transaction notification tap details, backend payloads should include a stable `type` and `orderId` where relevant. Current app routing opens Orders, Wallet or Notifications based on those fields.

## GitHub Actions secrets

Required for FCM builds:
- `FIREBASE_GOOGLE_SERVICES_JSON_BASE64`: base64-encoded Firebase `google-services.json` containing package `com.numelixa.app`.

Optional production signing:
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

If no signing keystore is supplied, the release APK uses the debug signing key and is for testing only. Never use that artifact for a Play Store release. If Firebase config is absent, CI builds can compile but live FCM delivery is not available.

## Build locally

Install Flutter stable and Android SDK:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=NUMELIXA_API_BASE=https://www.numelixa.com
flutter build apk --release --dart-define=NUMELIXA_API_BASE=https://www.numelixa.com
flutter build appbundle --release --dart-define=NUMELIXA_API_BASE=https://www.numelixa.com
```

Artifacts are uploaded by the workflow as `numelixa-android-builds`.
