# Numelixa Android (Flutter)

Standalone native Flutter application. This repository is isolated from `Virt-num`; it does not modify the website or its backend.

## Current scope
- Native Flutter UI (no WebView)
- Dark Numelixa theme and bottom navigation
- Secure-storage dependency for future token-based auth
- Firebase Messaging integration with foreground/background handlers and Android 13 notification permission
- GitHub Actions release APK/AAB build workflow

## Required GitHub Actions secrets
- `FIREBASE_GOOGLE_SERVICES_JSON_BASE64`: base64-encoded Firebase Android `google-services.json` for the correct Firebase project and applicationId.
- Optional signing: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

No secrets belong in source control or inside Dart source.

## Important backend integration note
The existing Numelixa web authentication must be reviewed before claiming mobile login compatibility. A native app must not treat a browser cookie as a secure mobile API token. FCM registration is intentionally routed through a configurable backend endpoint; the existing backend currently requires its own authenticated session and must be extended with a supported mobile token/session contract before this app can securely link a token to a user. Do not configure a fake success response.

## Build locally
Install Flutter stable and Android SDK, then:
```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=NUMELIXA_API_BASE=https://www.numelixa.com
```

The release workflow writes Firebase config from a GitHub secret before building. Until a real Firebase Android config and backend mobile-auth contract are supplied/verified, builds can be validated but live per-user push delivery cannot be truthfully certified.
