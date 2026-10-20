# Numelixa Mobile API Contract Audit

Audit source: the accessible `manager-cpu6/Virt-num` repository on `main`. This document is descriptive only; the website/backend repository has not been modified.

Base URL: `https://www.numelixa.com`

## Authentication actually implemented

The backend's `lib/auth.ts` accepts:
- `Authorization: Bearer <Numelixa API key>` (verified with `authenticateApiKey`)
- `X-API-Key: <Numelixa API key>`
- Otherwise, the `numelixa_session` browser cookie.

The native app uses the bearer API-key path; it does not use WebView or browser cookies. API keys are account credentials and must be stored only in Android secure storage.

The existing email/password endpoint `POST /api/auth/login` validates credentials and calls `createSession`, which creates a database session and sets an HttpOnly cookie. It does **not** return a native access token or refresh token. `POST /api/auth/logout` clears that cookie/session; it is not a mobile token-revocation contract. `POST /api/auth/signup` creates/reuses an account, starts email verification and also sets a browser cookie, but does not return a bearer credential. `POST /api/auth/forgot` sends a password reset link; `POST /api/auth/reset` consumes a reset token from the link.

Therefore, email/password sign-in, mobile registration, and native refresh-token handling cannot safely be completed entirely client-side. A supported API-key credential can authenticate existing accounts, but acquiring a new key currently depends on the existing account/developer-key flow. Do not pretend the cookie endpoints issue mobile tokens.

## Verified existing endpoints

| Feature | Method and path | Auth | Contract notes |
|---|---|---|---|
| Current user/profile | `GET /api/me` | Bearer API key or session | Returns `{ ok, user, pricing, paymentProvider }`; user fields include id, email, name, role and coins. |
| Balance | `GET /api/v1/balance` | Bearer API key or session | Returns `{ ok, balance, currency, accountId }`. |
| Services | `GET /api/catalog/services` | Public | Live provider catalog; can return 503 when provider is unavailable. |
| Countries and stock/pricing | `GET /api/catalog/countries?service=<service>` | Public | Returns live countries with `stock.count`, `stock.sellCoins`, and `stock.usdPrice`. |
| Purchase number | `POST /api/v1/orders` | Bearer API key or session | JSON body: `{ "service": "...", "countryCode": "..." }`. Requires verified email, sufficient coins, live stock and provider success. |
| List orders | `GET /api/v1/orders?limit=25&status=waiting` | Bearer API key or session | `status` is optional; response has an `orders` array. |
| Order detail | `GET /api/v1/orders/<id>` | Bearer API key or session | Only returns orders belonging to the authenticated user. |
| Check SMS | `POST /api/v1/orders/code` | Bearer API key or session | JSON body: `{ "orderId": "..." }`; may return waiting, received, or refund status. |
| Cancel order | `POST /api/v1/orders/cancel` | Bearer API key or session | JSON body: `{ "orderId": "..." }`; cancellation rules depend on provider and order age. |
| Transactions | `GET /api/v1/transactions` | Bearer API key or session | Returns up to 100 user coin transactions. |
| Notification center | `GET /api/notifications` | Bearer API key or session | Returns user-specific notifications and unread count. |
| Mark notification read | `POST /api/notifications` | Bearer API key or session | Body `{ "id": "..." }` marks one notification read; empty body marks all unread read. |
| Register Android FCM token | `POST /api/notifications/register` | Bearer API key or session | JSON body supports `token`, `platform`, optional `deviceId`, `appVersion`. Requires an email account and configured MongoDB. Returns `registered:true, linked:true` only after storage succeeds. |
| Login | `POST /api/auth/login` | Public | Body `{ "email": "...", "password": "..." }`; sets browser cookie, no native access/refresh token. |
| Registration | `POST /api/auth/signup` | Public | Body `{ "name": "...", "email": "...", "password": "..." }`; verification required, no native token returned. |
| Forgot password | `POST /api/auth/forgot` | Public | Body `{ "email": "..." }`; sends reset link. |
| Reset password | `POST /api/auth/reset` | Public reset token | Body `{ "token": "...", "newSecret": "..." }`. |

## Contracts that are genuinely missing

1. **Native login exchange:** add a dedicated backend endpoint that verifies email/password (and suspension/verification/security rules) and returns a short-lived access token plus refresh token, or a documented secure mobile token. Do not return the raw database session or rely on browser cookies.
2. **Refresh and revoke:** token refresh, refresh-token rotation/reuse detection, and authenticated native logout/revocation endpoints.
3. **FCM unlink on logout:** a user-authenticated endpoint to disable/unlink a device token, or an explicit documented behavior that safely revokes device association. The existing registration endpoint links tokens but does not expose a mobile unlink operation.
4. **User settings:** no dedicated end-user settings read/update contract was found in the inspected API routes.
5. **Native registration result:** signup currently does not return a native token/key; mobile signup should be connected after the native auth exchange exists.

No backend changes were made as part of this audit.


## Android app-update endpoint required by the standalone app

The app performs a best-effort, non-blocking check against `GET /api/app-update?platform=android&packageId=com.numelixa.app&version=<versionName>&versionCode=<buildNumber>`. If the route is absent or the request fails, app startup continues normally. Response may be the update object directly or `{ "enabled": true, "updateAvailable": true, "update": { ... } }`.

Fields: `versionName`, `versionCode`, `apkUrl` (direct HTTPS APK URL), `apkSizeBytes`, `sha256`, `releaseNotes`, `isActive`, `isMandatory`, `allowSkip`. The app downloads with byte progress, verifies SHA-256 when provided, and opens Android's package installer. Android still requires user confirmation and may ask permission to install unknown apps.

**Backend/admin work still required:** the website/backend repository must implement authenticated admin publish/withdraw/mandatory/optional controls, persist release metadata, host the APK at a stable HTTPS URL, and send FCM notifications when requested. This mobile-only repository cannot create those server endpoints/admin controls. Keep package ID `com.numelixa.app` and sign every update with the exact same release keystore.
