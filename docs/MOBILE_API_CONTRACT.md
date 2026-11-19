# Numelixa Mobile API Contract Audit

**Scope:** Descriptive audit only. The website/backend repository was inspected read-only and was not modified.  
**Base URL:** `https://www.numelixa.com`.

## 1. Native authentication and session lifecycle

All Android requests made by the current ApiClient include `x-numelixa-client: android-app`. Authenticated requests also include `Authorization: Bearer <mobile-session-token>`.

| Method | Route | Request / behavior |
|---|---|---|
| POST | `/api/auth/login` | JSON `{email,password}`; with native-client header returns `accessToken` and user |
| POST | `/api/auth/signup` | JSON `{name,email,password}`; with native-client header returns token and user; email verification is still required |
| POST | `/api/auth/phone/request` | JSON `{phone,name?,purpose}`; sends SMS OTP if phone sign-in is enabled |
| PUT | `/api/auth/phone/request` | Requests voice OTP if voice verification is enabled |
| POST | `/api/auth/phone/verify` | JSON `{phone,code,name?}`; native header returns mobile session token and user |
| GET | `/api/auth/google/config` | Returns configured public Web OAuth client ID |
| POST | `/api/auth/google/native/credential` | JSON `{credential: Google ID token}`; verifies Google token and returns a short-lived one-time ticket |
| POST | `/api/auth/google/native/complete` | JSON `{ticket}`; with native header consumes ticket and returns mobile session token |
| GET | `/api/me` | Validates the Bearer session and returns the current user |
| POST | `/api/auth/logout` | With `x-numelixa-client: android-app` and Bearer token, revokes the current mobile session |

The backend stores only a SHA-256 hash of each opaque mobile session token. Mobile sessions are created with a 30-day expiry. Google native tickets expire after three minutes and are consumed once. Browser cookie sessions remain separate.

**Legacy compatibility:** the app still exposes API-key sign-in for existing developer accounts. A developer API key is a long-lived secret, not a mobile session token; the mobile logout route revokes mobile sessions, not developer keys. This path remains a security risk on user-controlled devices and should be retired or redesigned after owner approval.

## 2. Profile, password and device security

| Method | Route | Verified behavior |
|---|---|---|
| PUT | `/api/mobile/profile/avatar` | Authenticated profile image upload; PNG/JPEG/WebP data URL, max 450 KB |
| POST | `/api/mobile/security/password/start` | Sends a 6-digit password-change code; 60-second request cooldown; code expires after 10 minutes |
| POST | `/api/mobile/security/password/confirm` | JSON `{code,newPassword}`; code must be six digits and password at least 8 characters |
| GET | `/api/mobile/devices` | Lists active sessions grouped by device; current device is identified from the Bearer token |
| DELETE | `/api/mobile/devices` | JSON `{deviceId,sessionId}`; revokes only the authenticated user's device/session |

Device removal also disables linked push tokens when removing the whole device identity. The backend scopes session queries/deletions to the authenticated user.

## 3. Public developer API

See [DEVELOPER_API_REFERENCE.md](DEVELOPER_API_REFERENCE.md) for the public REST API v1, API key management, order lifecycle, webhook signatures, examples and verified error codes.

Public API base: `https://www.numelixa.com/api/v1`.

The app-specific catalogue paths are distinct from public developer routes:
- `GET /api/catalog/services`
- `GET /api/catalog/countries?service=<service>`

## 4. Wallet, orders and receipts

| Method | Route | Verified behavior |
|---|---|---|
| GET | `/api/v1/balance` | USD balance, currency and accountId |
| GET | `/api/v1/orders?limit=100` | Authenticated user's order list |
| GET | `/api/v1/orders/{id}` | Single order scoped to the authenticated user |
| POST | `/api/v1/orders` | Purchase; JSON supports `service` and `countryCode` (backend also accepts `country`) |
| POST | `/api/v1/orders/code` | JSON `{orderId}`; check SMS |
| POST | `/api/v1/orders/cancel` | JSON `{orderId}`; cancel eligible waiting order |
| GET | `/api/v1/transactions` | Up to 100 ledger transactions, including credit/debit/refund types |
| GET | `/api/wallet/receipt?reference=<reference>` | Receipt lookup used by the app |

Order list/detail responses include price and currency in USD, status, phone, service, country, SMS/code fields and expiry metadata. Treat OTP and full SMS content as sensitive.

The wallet transaction endpoint is a ledger, not a complete payment-provider history. A unified list of pending/failed payment requests is not verified and requires backend work.

## 5. Notifications and support

| Method | Route | Verified behavior |
|---|---|---|
| GET | `/api/notifications` | User notifications and unread count |
| POST | `/api/notifications` | Mark one notification read with `{id}`; empty body marks all unread read |
| POST | `/api/notifications/register` | Authenticated FCM token registration with token, platform and optional deviceId/appVersion |
| GET | `/api/support` | Latest active support ticket for the authenticated user and canSubmit |
| POST | `/api/support` | Create a support ticket |

Support POST accepts `channel` (`email`, `whatsapp`, `telegram`), `contact`, `subject` (4–120 characters) and `message` (15–3000 characters). Ticket records are created in the existing support database collection. No frontend-only ticket simulation is used.

## 6. API transport and client-side protections

- ApiClient uses the HTTPS Numelixa base URL and now refuses non-HTTPS schemes.
- API requests do not follow redirects, preventing Authorization credentials from being forwarded to a redirect destination.
- Native session tokens are stored using `flutter_secure_storage`.
- Authentication callback errors no longer log raw exception contents.
- Local notifications are configured with private lock-screen visibility.
- OTP copying occurs only after an explicit user action.

## 7. Contracts requiring additional backend confirmation

1. Unified payment history for pending, failed, rejected and refunded payment-provider attempts.
2. Full Sifalo, Binance and Ethiopia payment route schemas, idempotency and status transitions.
3. Account deletion API and machine-readable deletion confirmation.
4. Device-wide FCM unlink contract beyond the existing logout/device-removal behavior.
5. Numeric API rate-limit quotas and reset headers.
6. Mobile session refresh/rotation beyond the current 30-day token expiry.
7. Formal API versioning and backwards-compatibility policy.

No website or backend code was modified for this mobile repository task.
