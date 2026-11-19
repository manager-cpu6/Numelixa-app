# Numelixa API Reference — Source-Verified

**Public REST base:** `https://www.numelixa.com/api/v1`  
**Review date:** 20 November 2026.  
**Scope:** Public developer API contracts and selected mobile app routes verified against accessible Numelixa backend source. This document does not claim every mobile payment route is a public developer API.

## 1. Quick start and authentication

Use HTTPS and JSON. Public developer endpoints require a Numelixa API key:

```http
Accept: application/json
Authorization: Bearer YOUR_NUMELIXA_API_KEY
Content-Type: application/json
```

The backend also accepts `X-API-Key`. Keep keys on a trusted server; never embed them in an APK, browser JavaScript, public repository, analytics or logs. The native app uses a separate opaque mobile-session token, not a developer API key.

### API key management (authenticated account routes)

| Method | Route | Behavior |
|---|---|---|
| GET | `/api/developer/keys` | List key metadata and ensure an account key exists |
| GET | `/api/developer/keys?reveal=1` | Reveal active key when secure copy is available |
| DELETE | `/api/developer/keys?id=<keyId>` | Revoke selected key and automatically generate replacement |
| POST | `/api/developer/keys` | Not supported; returns HTTP 405 |

Keys are created automatically for accounts; manual key creation is disabled. Treat the replacement key returned after revocation as a secret and store it securely.

## 2. Account and balance

| Method | Route | Authentication | Verified response |
|---|---|---|---|
| GET | `/account` | Required | `{ok, account: {id, email, name, verified, balance, currency}}` |
| GET | `/balance` | Required | `{ok, balance, currency, accountId}` |

The public account and balance values are calculated from the account wallet and current Numelixa pricing settings. The server is the source of truth.

## 3. Services, countries, stock and pricing

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/services` | Required | Live service catalog |
| GET | `/countries?service=<service>` | Required | Countries with available stock and USD price |
| GET | `/stock?country=<country>&service=<service>` | Required | Availability, count, price and currency for one service/country |

The stock response includes `available`, `count`, `country`, `service`, `price` and `currency`. The countries route filters out unavailable countries. Provider configuration or upstream failures may return 503/502. Inventory and prices can change between lookup and purchase; the purchase route re-quotes before charging.

## 4. Number acquisition and order lifecycle

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| POST | `/orders` | Required | Purchase a number and create an activation |
| GET | `/orders?limit=25&status=waiting` | Required | List the authenticated user's orders |
| GET | `/orders/{id}` | Required | Retrieve one order owned by the authenticated user |
| POST | `/orders/code` | Required | Check SMS for an order |
| POST | `/orders/cancel` | Required | Cancel an eligible waiting order |

### Create an order

Request:

```json
{ "country": "usa", "service": "whatsapp" }
```

The backend also accepts `countryCode` for compatibility. A successful response includes `order.id`, `order.number`, `order.price`, `order.expiresIn` and `order.stockAfter`. Purchase requires an eligible verified account, sufficient wallet balance, available stock and provider success.

### List and retrieve orders

The list response includes an `orders` array with `id`, `service`, `country`, `countryCode`, `phone`, `price`, `currency`, `status`, `code`, `fullSms`, `expiresAt`, `createdAt` and `completedAt`. Optional values can be null. The list limit is clamped by the server (1–100).

### Check SMS

Request:

```json
{ "orderId": "YOUR_ORDER_ID" }
```

The v1 route delegates to the existing order-code handler and can return the latest received code/status. Treat `code` and `fullSms` as sensitive; do not log or forward them to third parties.

### Cancel an order

Request:

```json
{ "orderId": "YOUR_ORDER_ID" }
```

Only waiting orders are eligible. On confirmed cancellation the response includes `status: cancelled`, `refundedUsd` and `currency`. Provider rules can reject cancellation. A refund should be considered complete only after the server confirms it.

## 5. Wallet transactions and receipts

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/transactions` | Required | Up to 100 wallet ledger entries |
| GET | `/api/wallet/receipt?reference=<reference>` | Required | Receipt lookup used by the mobile app |

Transaction entries include `id`, `type`, `amountUsd`, `balanceAfterUsd`, `currency`, `reference`, `description` and `createdAt`. This ledger includes credits, debits and refunds, but it is not a complete payment-provider history. A unified endpoint for pending/failed payment attempts has not been verified.

## 6. Webhooks

Webhook configuration uses authenticated `/api/developer/webhook`:

| Method | Route | Behavior |
|---|---|---|
| GET | `/api/developer/webhook` | Read endpoint configuration and last delivery status |
| PUT | `/api/developer/webhook` | Save a public HTTPS URL and enable/disable delivery |
| DELETE | `/api/developer/webhook` | Remove webhook configuration |
| POST | `/api/developer/webhook` | Attempt a signed test event |

A signing secret is returned only when the webhook is first created. The backend accepts only public HTTPS URLs and rejects local/private addresses.

Verified event types:
- `order.created`
- `order.code_received`
- `order.cancelled`

The JSON payload contains `id`, `type`, `createdAt` and `data`. Headers include `X-Numelixa-Event`, `X-Numelixa-Event-Id`, `X-Numelixa-Timestamp` and `X-Numelixa-Signature`. Signature is HMAC-SHA256 over the timestamp, a period, and the exact raw JSON body; header format is `sha256=HEX`. Verify the raw body, compare signatures in constant time, reject stale timestamps, and store event IDs to prevent duplicate processing.

Delivery is attempted synchronously with a short timeout. The inspected delivery implementation does not automatically retry failed requests. Check delivery status in the dashboard and keep polling/reconciliation as a fallback. Ordinary read-only GET requests do not emit webhook events.

## 7. Errors, status codes and retries

The official developer reference documents these common outcomes:

| HTTP status | Meaning |
|---|---|
| 200 / 201 | Successful request |
| 400 | Invalid input or missing parameters |
| 401 | API key missing, invalid or revoked |
| 402 | Insufficient wallet balance |
| 403 | Permission or account restriction |
| 404 | Order or resource not found |
| 409 | Stock, price or order-state conflict |
| 429 | Rate limit exceeded |
| 500 | Unexpected server error |
| 502 / 503 | Temporary upstream/service unavailability |

Common error body:

```json
{ "ok": false, "error": "Human-readable error message" }
```

Use timeouts and bounded retries with exponential backoff for safe reads. Never blindly retry a purchase or payment after a timeout; first query order/account history to avoid creating a duplicate order. Numeric rate quotas and response headers are not specified in the inspected source.

## 8. Support tickets

The backend support routes accept the same authenticated Bearer mobile session/API credential:
- `GET /api/support`: returns the latest active ticket (if any) and `canSubmit`.
- `POST /api/support`: creates a ticket for the authenticated user.

The POST body accepts `channel` (`email`, `whatsapp`, or `telegram`), `contact`, `subject` (4–120 characters) and `message` (15–3000 characters). Success returns `ok` and a ticket with `id`, `status` and `createdAt`. Never include passwords, OTP codes or payment card details.

## 9. Mobile app routes (not the public developer API)

The Android app also uses these verified app-specific endpoints:
- `GET /api/me` for session validation and current user.
- `GET /api/catalog/services` and `GET /api/catalog/countries?service=<service>` for mobile catalogue data.
- `GET /api/notifications`, `POST /api/notifications`, and `POST /api/notifications/register` for notifications and FCM registration.
- `GET /api/mobile/devices` and `DELETE /api/mobile/devices` for the signed-in user's active device sessions.
- `POST /api/auth/logout` with header `X-Numelixa-Client: android-app` to revoke the current mobile session.
- `POST /api/support` and `GET /api/support` for authenticated support tickets.

These routes are verified in the backend source but are not advertised here as a general third-party public API.

## 10. Payment routes requiring further confirmation

The Flutter repository calls Sifalo, Binance and Ethiopia payment endpoints. Their backend implementations, full schemas, idempotency behavior and user-facing payment-history contract still require a separate route-by-route review before third-party publication. Do not infer webhook payloads or provider behavior from app code alone.

## 11. Security checklist

- Use HTTPS only.
- Store API keys and mobile tokens in a trusted secret store.
- Never embed developer API keys in a distributed Android app.
- Do not log access tokens, API keys, full SMS content or OTP codes.
- Verify webhook HMAC signatures against the exact raw body and reject stale timestamps.
- Persist webhook event IDs and make handlers idempotent.
- Do not blindly retry order/payment creation after a timeout.
- Scope all order and account lookups to the authenticated user.

## 12. Items requiring API-owner confirmation

1. Numeric rate quotas, reset windows and rate-limit headers.
2. A unified payment history including pending, failed, rejected and refunded provider attempts.
3. Full Sifalo, Binance and Ethiopia payment request/response contracts.
4. Mobile token refresh/rotation and account-wide session revocation contracts.
5. Account deletion API and programmatic deletion confirmation.
6. Formal API versioning and backwards-compatibility policy.
