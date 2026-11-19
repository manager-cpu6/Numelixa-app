# Numelixa API Reference — Verified Contracts

**Status:** source-audited reference for the mobile client.  
**Base URL:** `https://www.numelixa.com`  
**Last source review:** 20 November 2026.

This reference documents only routes and fields verified in the accessible Numelixa backend source and mobile repository. It is not a claim that every endpoint is a public or stable developer API. The authenticated routes accept the server's supported Bearer credential: a Numelixa API key or a valid mobile session token. Keep credentials on a trusted server; never ship a production API key in a public client.

## 1. Public Developer API v1 — quick start

**Public API base:** `https://www.numelixa.com/api/v1`  
Use HTTPS and JSON. Protected public developer routes require a Numelixa API key in the Bearer header:

```http
Accept: application/json
Authorization: Bearer YOUR_NUMELIXA_API_KEY
Content-Type: application/json
```

The Android app also uses mobile-specific endpoints outside this public API base. Those app-only routes are called out separately below; do not assume that every app route is part of the public developer API.

## 2. Authentication and API keys

The public developer API accepts `Authorization: Bearer <Numelixa API key>`; the backend also accepts `X-API-Key`.

API keys are created automatically for accounts. The verified management routes are:
- `GET /api/developer/keys`: list key metadata and ensure an account key exists.
- `GET /api/developer/keys?reveal=1`: reveal the active key when the stored key can be securely copied.
- `DELETE /api/developer/keys?id=<keyId>`: revoke the selected key and automatically generate a replacement.
- `POST /api/developer/keys`: not supported; manual creation returns HTTP 405.

Keep API keys in a server-side secret manager. Do not place them in an Android APK, browser JavaScript, source control, analytics or logs. A mobile app uses its own opaque mobile-session token; do not embed an API key in the distributed app.

## 3. Services, countries and stock

These public developer API routes require authentication:

| Method | Route | Verified behavior |
|---|---|---|
| GET | `/api/v1/services` | Live service catalog |
| GET | `/api/v1/countries?service=<service>` | Countries with currently available stock and USD price |
| GET | `/api/v1/stock?country=<country>&service=<service>` | Availability, count, price and currency for one service/country |

The country list includes only entries with available stock. Stock responses include `available`, `count`, `country`, `service`, `price` and `currency`. Provider configuration failures may return 503. Inventory and price can change at any time.

The Android app separately uses `GET /api/catalog/services` and `GET /api/catalog/countries?service=<service>` for its live mobile catalogue. Those are app catalog routes, not the public v1 developer paths above.

## 5. Number acquisition and order lifecycle

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| POST | `/api/v1/orders` | Required | Create an activation |
| GET | `/api/v1/orders?limit=25&status=waiting` | Required | List the current user's orders; status is optional |
| GET | `/api/v1/orders/{id}` | Required | Read one order owned by the authenticated user |
| POST | `/api/v1/orders/code` | Required | Check SMS for an order |
| POST | `/api/v1/orders/cancel` | Required | Cancel an eligible waiting order |

### Create an order

Request JSON:

```json
{ "country": "usa", "service": "whatsapp" }
```

The purchase handler accepts `country` and also `countryCode` for compatibility. A successful response includes `order.id`, `order.number`, `order.price`, `order.expiresIn` and `order.stockAfter`. The server requires an eligible verified account, sufficient USD wallet balance, live stock and provider success.

### List and retrieve orders

`GET /api/v1/orders?limit=25&status=waiting` returns an `orders` array with `id`, `service`, `country`, `countryCode`, `phone`, `price`, `currency`, `status`, `code`, `fullSms`, `expiresAt`, `createdAt` and `completedAt`. Optional fields may be null. The detail route returns the same order data for one order.

### Check SMS

Request JSON:

```json
{ "orderId": "YOUR_ORDER_ID" }
```

The v1 route delegates to the existing order-code handler and can return the latest received code/status. Treat `code` and `fullSms` as sensitive.

### Cancel an order

Request JSON:

```json
{ "orderId": "YOUR_ORDER_ID" }
```

Use **POST `/api/v1/orders/cancel`**. The backend only permits waiting orders and returns `status: cancelled`, `refundedUsd` and `currency` when the cancellation and refund succeed. Provider rules may reject an early or unsupported cancellation.

## 6. Account, balance, transactions and receipts

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/api/v1/account` | Required | Account identity, email, name, verification state, balance and currency |
| GET | `/api/v1/balance` | Required | Balance, currency and accountId |
| GET | `/api/v1/transactions` | Required | Up to 100 wallet ledger transactions |
| GET | `/api/wallet/receipt?reference=<reference>` | Required | Mobile receipt lookup |

The transaction ledger includes transaction `type`, `amountUsd`, `balanceAfterUsd`, `currency`, `reference`, `description` and `createdAt`. It is not a unified list of pending or failed payment-provider requests.

## 7. Notifications and device registration

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/api/notifications` | Required | User notifications and unread count |
| POST | `/api/notifications` | Required | Mark one notification read using `{ "id": "..." }`; empty body marks all unread read |
| POST | `/api/notifications/register` | Required | Register an Android FCM token |

Registration accepts `token`, `platform`, and optional `deviceId` / `appVersion`. The backend returns linked/registered success only after storage. A separate mobile unlink endpoint was not verified.


