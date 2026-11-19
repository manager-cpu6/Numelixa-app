# Numelixa API Reference — Verified Contracts

**Status:** source-audited reference for the mobile client.  
**Base URL:** `https://www.numelixa.com`  
**Last source review:** 20 November 2026.

This reference documents only routes and fields verified in the accessible Numelixa backend source and mobile repository. It is not a claim that every endpoint is a public or stable developer API. The authenticated routes accept the server's supported Bearer credential: a Numelixa API key or a valid mobile session token. Keep credentials on a trusted server; never ship a production API key in a public client.

## 1. Overview and quick start

Use HTTPS and send JSON for request bodies.

```http
Accept: application/json
Authorization: Bearer YOUR_NUMELIXA_CREDENTIAL
Content-Type: application/json
```

A credential can be either an API key accepted by `authenticateApiKey` or a valid opaque mobile session token. The mobile token is stored hashed by the backend and has a finite expiry; the exact refresh/rotation contract is not available as a documented public API.

## 2. Authentication

### Verified
- `GET /api/me` returns the current authenticated user and account pricing information.
- Backend `getUser()` accepts `Authorization: Bearer <API key or valid mobile session>`, `X-API-Key`, or the website session cookie.
- Website `POST /api/auth/login` and `POST /api/auth/signup` create browser cookie sessions; do not assume those routes return a mobile token.
- `POST /api/auth/forgot` sends a password-reset link. `POST /api/auth/reset` consumes a reset token with `newSecret`.

### Not verified / requires confirmation
A public developer API key-creation endpoint, access-token refresh, refresh-token rotation, mobile token revocation, OAuth public contract, and API-key scopes are not documented in the inspected routes. Do not invent these flows.

## 3. Account and balance

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/api/me` | Required | Current user, pricing and payment-provider metadata |
| GET | `/api/v1/balance` | Required | `balance`, `currency`, `accountId` |

Example response fields for balance are `balance`, `currency`, and `accountId`; numeric representation should be treated as server-owned.

## 4. Services, countries and pricing

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/api/catalog/services` | Public | Live service catalog |
| GET | `/api/catalog/countries?service={service}` | Public | Country availability for a selected service |

Country records may include `name`, `id` / `code`, `callingCode` / `dialCode`, `stock.count`, `stock.sellCoins`, and `stock.usdPrice`. The catalogue is live and can change. A provider outage may return HTTP 503. Prices and stock shown before purchase are not a guarantee of final allocation; the server validates current availability at order creation.

## 5. Number acquisition and order lifecycle

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| POST | `/api/v1/orders` | Required | Create an activation |
| GET | `/api/v1/orders?limit=25&status=waiting` | Required | List the current user's orders; `status` is optional |
| GET | `/api/v1/orders/{id}` | Required | Read one of the current user's orders |
| POST | `/api/v1/orders/code` | Required | Check SMS for an order |
| POST | `/api/v1/orders/cancel` | Required | Request cancellation |

### Create an order

Request JSON:

```json
{
  "service": "whatsapp",
  "countryCode": "usa"
}
```

The backend requires an eligible verified account, sufficient wallet credits, live stock and provider success. It can reject a request when any of those conditions is not met.

### Check SMS

Request JSON:

```json
{ "orderId": "YOUR_ORDER_ID" }
```

The verified route can return a waiting, received, or refund-related result. The exact complete response schema is not specified here; clients should tolerate additional fields and missing optional fields.

### Cancel an order

Request JSON:

```json
{ "orderId": "YOUR_ORDER_ID" }
```

Use **POST `/api/v1/orders/cancel`**. Cancellation is subject to provider and order-age rules. A refund must only be displayed after the backend confirms the relevant outcome.

## 6. Transactions and receipts

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/api/v1/transactions` | Required | Up to 100 wallet ledger transactions |
| GET | `/api/wallet/receipt?reference={reference}` | Required | Verified receipt lookup used by the app |

The transaction list is a wallet ledger, not a complete payment-provider event history. Pending and failed payment records are not established as part of `/api/v1/transactions` by the inspected contract. A separate unified payment-history endpoint and schema require backend confirmation.

## 7. Notifications and device registration

| Method | Route | Authentication | Verified behavior |
|---|---|---|---|
| GET | `/api/notifications` | Required | User notifications and unread count |
| POST | `/api/notifications` | Required | Mark one notification read using `{ "id": "..." }`; empty body marks all unread read |
| POST | `/api/notifications/register` | Required | Register an Android FCM token |

Registration accepts `token`, `platform`, and optional `deviceId` / `appVersion`. The backend returns `registered: true` and `linked: true` only after successful storage. A public mobile unlink endpoint was not verified.

## 8. Support tickets

The website backend source includes authenticated support ticket routes:
- `GET /api/support`: returns the latest active ticket (if any) and `canSubmit`.
- `POST /api/support`: creates a support ticket for the signed-in user.

The POST body accepts:
`channel` (`email`, `whatsapp`, or `telegram`), `contact`, `subject` (4–120 chars), and `message` (15–3000 chars). A successful response includes `ok` and a ticket with `id`, `status`, and `createdAt`. The endpoint requires a valid user session/API credential. Never include passwords, OTPs, or payment card details in a ticket.

## 9. Payment integrations used by the Android client — confirmation required

The current Flutter repository calls the following routes for payment discovery, creation and status checks:
- `GET /api/payments/sifalo/status`
- `POST /api/payments/sifalo/create`
- `GET /api/payments/sifalo/verify?orderId=...`
- `GET /api/payments/binance/networks`
- `POST /api/payments/binance/create`
- `GET /api/payments/binance/status?orderId=...`
- `GET /api/payments/ethiopia/methods`
- `POST /api/payments/ethiopia/create`
- `GET /api/payments/ethiopia/status?orderId=...`

These calls are present in the mobile repository, but their backend route implementations and full request/response schemas were not part of the completed source audit for this reference. Treat them as **requiring backend confirmation** before building a third-party integration. Do not infer webhook payloads or provider behavior from client usage alone.

## 10. Errors and retries

The Android client maps common HTTP outcomes to user-safe messages (including re-authentication for 401, permission denial for 403, and temporary service failure for 5xx). The backend's complete error schema and all status-code guarantees are not documented in the inspected API contract. Clients should:
- check HTTP status before trusting a response;
- handle non-JSON and empty responses;
- avoid retrying non-idempotent purchase/payment creation blindly;
- preserve an order/payment reference and query its status before retrying;
- never treat a timeout as proof of failure or success.

## 11. Rate limits, webhooks and security

- **Rate limits:** numeric limits and headers were not verified. Ask the API owner for the current policy.
- **Webhooks:** no public developer webhook registration, signature format, event catalogue or retry contract was verified. Requires backend confirmation.
- **API key management:** the existing developer portal is `https://www.numelixa.com/developers`; the inspected app/backend source does not establish a public key-creation API contract.
- **Transport:** use HTTPS only.
- **Secrets:** keep API keys and mobile session tokens out of source control, logs, analytics, crash reports and client-side web code.
- **SMS/OTP:** treat received verification codes and full SMS bodies as sensitive. Do not include them in support requests or telemetry.
- **Clipboard:** copy only after an explicit user action and avoid persisting copied OTPs.
- **Authorization:** order detail and account data are scoped to the authenticated user by the backend.

## 12. Integration examples

The following examples demonstrate the verified order-list request. Replace the placeholder with a credential supplied through a server-side secret manager. Never hard-code a real key.

### cURL

```bash
curl --fail-with-body 'https://www.numelixa.com/api/v1/orders?limit=25' \
  -H 'Accept: application/json' \
  -H 'Authorization: Bearer YOUR_NUMELIXA_CREDENTIAL'
```

### JavaScript (fetch)

```js
const response = await fetch(
  'https://www.numelixa.com/api/v1/orders?limit=25',
  { headers: { Accept: 'application/json', Authorization: `Bearer ${process.env.NUMELIXA_API_KEY}` } }
);
if (!response.ok) throw new Error(`Numelixa API returned HTTP ${response.status}`);
const data = await response.json();
console.log(data.orders);
```

### Node.js (built-in fetch)

```js
import 'dotenv/config';

const url = new URL('/api/v1/balance', 'https://www.numelixa.com');
const response = await fetch(url, {
  headers: {
    Accept: 'application/json',
    Authorization: `Bearer ${process.env.NUMELIXA_API_KEY}`,
  },
});
if (!response.ok) throw new Error(`HTTP ${response.status}`);
const balance = await response.json();
console.log(balance.balance, balance.currency);
```

### Python (requests)

```python
import os
import requests

response = requests.get(
    "https://www.numelixa.com/api/v1/orders",
    params={"limit": 25},
    headers={
        "Accept": "application/json",
        "Authorization": f"Bearer {os.environ['NUMELIXA_API_KEY']}",
    },
    timeout=20,
)
response.raise_for_status()
print(response.json().get("orders", []))
```

### PHP (cURL)

```php
<?php
$ch = curl_init('https://www.numelixa.com/api/v1/balance');
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 20,
    CURLOPT_HTTPHEADER => [
        'Accept: application/json',
        'Authorization: Bearer ' . getenv('NUMELIXA_API_KEY'),
    ],
]);
$body = curl_exec($ch);
$status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
if ($body === false || $status < 200 || $status >= 300) {
    throw new RuntimeException('Numelixa API request failed: HTTP ' . $status);
}
$data = json_decode($body, true, 512, JSON_THROW_ON_ERROR);
print_r($data);
curl_close($ch);
```

## 13. Open questions for the API owner

The following items must be confirmed before they can be documented as supported public contracts:
1. Exact rate limits, quota headers and retry guidance.
2. Public webhook registration, event names, signatures and delivery retries.
3. API key creation, rotation, revocation, scopes and last-used metadata.
4. Unified payment history including pending, failed, rejected and refunded states.
5. Full payment-provider request/response schemas for the payment routes listed above.
6. Mobile token refresh, rotation and revocation endpoints.
7. Account deletion request API and retention/confirmation workflow.
8. Official API versioning and backwards-compatibility policy.
