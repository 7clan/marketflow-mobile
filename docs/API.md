# MarketFlow API (Mock Marketplace Protocol)

The app talks to a **deterministic in-process HTTP backend**:
`lib/data/datasources/mock_marketplace_server.dart` — a real
`dart:io` `HttpServer` on `127.0.0.1` + an ephemeral port, owned by
`MarketApiHost` (`market_api_host.dart`) and started in `main()`. The wire
contract below is deliberately a plain REST/JSON protocol: swapping in a real
backend means overriding `appConfigProvider` with its origin — nothing else
changes.

Base URL: `http://127.0.0.1:<ephemeral port>` (resolved from the running
host; `AppConfig.localServer(port)`).

## Conventions

### Envelopes

Success — always HTTP 2xx with `{"data": ...}`:

```json
{ "data": <payload: object | array | scalar> }
```

Failure — `{"error": {...}}`:

```json
{
  "error": {
    "code": "out_of_stock",
    "message": "Some items in your cart are no longer available.",
    "errors": { "email": ["An account with this email already exists."] },
    "items": ["p05", "p12"]
  }
}
```

- `errors` (422 only): field → list of messages; maps onto form
  `errorText` in the app.
- `items` (409 only): the conflicting product ids →
  `ConflictException.conflictingItems`.
- `ApiClient._payloadOf` enforces the envelope client-side; a body missing
  `data` throws `MalformedResponseException`.

### Auth

`Authorization: Bearer <token>` on every authenticated route (favorites,
checkout, orders, `/auth/me`). Tokens are opaque strings (`tok-demo-1`,
`tok-11`, …) issued at login/register and stored client-side in secure
storage. There is no expiry timer: the server rejects unknown tokens with
401 and the client treats that as session expiry.

### Status code semantics

| Status | Meaning | Client mapping (`ErrorMapper`) | App behavior |
| --- | --- | --- | --- |
| 200 / 201 | success (201 = created: register, favorite add, checkout) | — | — |
| 400 | malformed request (invalid JSON, unknown sort, bad params, unknown product id, bad payment method) | `BadRequestException` (field errors → `ValidationException`) | banner / inline |
| 401 | missing/rejected token; wrong credentials on login | `UnauthorizedException` | login: banner "Invalid email or password."; elsewhere: session expiry → sign-out |
| 403 | reserved (never produced by the seed; mapping is tested) | `ForbiddenException` | banner |
| 404 | unknown route / product / order | `NotFoundException` | error view with retry |
| 409 | checkout stock conflict | `ConflictException` + `items` | failure step, retry |
| 422 | validation (register fields, empty cart, address, quantity bounds) | `ValidationException.fieldErrors` | inline field errors |
| 500+ | forced / unexpected server error | `ServerException(statusCode)` | error view with retry |
| — | client timeout (connect 8 s / receive 12 s / send 10 s) | `TimeoutException` | "server taking too long" copy |
| — | connection refused / offline | `NetworkException` | "check your internet" copy |
| — | malformed 200 body | `MalformedResponseException` | "unexpected response" copy |

## Routes

### `POST /auth/register`

Body: `{"name": "...", "email": "...", "password": "..."}`

- 201 → `{ "data": { "token": "tok-11", "user": { "id", "name", "email", "memberSince" } } }`
- 422 `validation` — field errors: name < 2 chars, invalid email, password <
  8 chars, **or email already registered** (all under `errors`).
- 400 `invalid_json` — non-JSON / non-object body.

Emails are normalized (trim + lowercase) before storage.

### `POST /auth/login`

Body: `{"email": "...", "password": "..."}`

- 200 → `{ "data": { "token", "user" } }`
- 401 `invalid_credentials` "Invalid email or password." (same response for
  unknown email and wrong password — no account enumeration)
- 400 `bad_request` if email/password missing or not strings.

### `GET /auth/me` 🔒

- 200 → `{ "data": { "id", "name", "email", "memberSince" } }`
- 401 `unauthorized` — token missing or unknown. The client uses this at
  startup to **verify** a restored session; 401 ⇒ clean sign-out.

### `GET /categories`

- 200 → `{ "data": [ { "id": "c1", "name": "Electronics", "productCount": 11 }, … ] }`

### `GET /products`

Query parameters — **all** of them:

| Param | Type | Default | Notes |
| --- | --- | --- | --- |
| `page` | int ≥ 1 | 1 | 400 if < 1 or non-numeric |
| `pageSize` | int 1..100 | 20 | 400 if > 100 |
| `sort` | enum | `relevance` | `relevance`, `newest`, `price_asc`, `price_desc`, `rating` — unknown value ⇒ 400 |
| `category` | string | — | category id, e.g. `c1` |
| `q` | string | — | trimmed, lowercased; matches title, description, category name |
| `minPrice` | double | — | inclusive; 400 if non-numeric |
| `maxPrice` | double | — | inclusive; 400 if `minPrice > maxPrice` |
| `inStock` | `true`/`false`/`1`/`0` | — | keeps only `stock > 0 && isAvailable` |

- 200 → `{ "data": { "items": [Product…], "page": 1, "pageSize": 20,
  "totalPages": 4, "totalItems": 66, "hasMore": true } }`
- Relevance with a query scores: title contains (+100), title startsWith
  (+50), description contains (+10) + popularity·0.001; queryless relevance
  sorts by `rating × ln(reviewCount + 1)`; ties break by id (deterministic).
- `newest` uses the seeded `listedAt` ladder (6 h apart, from 2025-10-01).

Product shape:

```json
{
  "id": "p01",
  "title": "Aurora Wireless Noise-Cancelling Earbuds",
  "description": "…",
  "price": 124.15,
  "compareAtPrice": 147.5,          // nullable, ~35% of products
  "imageUrls": ["https://picsum.photos/seed/mf-p01/600/600", "…", "…"],
  "rating": 4.7,                     // 3.0–4.9, one decimal
  "reviewCount": 1832,               // 3–2802
  "stock": 87,                       // deterministic; 0 on every 17th product
  "categoryId": "c1",
  "sellerName": "Northgate Audio",
  "isAvailable": true                // stock > 0 && not deliberately disabled
}
```

### `GET /products/:id`

- 200 → `{ "data": Product }`
- 404 `not_found` "Unknown product."

### `GET /favorites` 🔒

- 200 → `{ "data": [Product…] }` (the favorited products, full objects)

### `POST /favorites/:id` 🔒

- 201 → `{ "data": { "productId": "p05", "favorited": true } }`
- 404 if the product id is unknown. Idempotent (re-adding is a no-op).

### `DELETE /favorites/:id` 🔒

- 200 → `{ "data": { "productId": "p05", "favorited": false } }`
- 404 if the product id is unknown.

### `POST /checkout` 🔒

Body:

```json
{
  "items":  [ { "productId": "p01", "quantity": 2 } ],
  "address": { "fullName", "street", "city", "state", "zip", "country", "phone" },
  "paymentMethod": "card"            // or "cod"
}
```

Responses:

- 201 → `{ "data": Order }` — status `pending`, totals **recomputed
  server-side** with the same pricing rules as the client (flat \$8.99
  shipping, free ≥ \$99, 8.5 % tax), `estimatedDelivery = placedAt + 4 d 6 h`.
  Successful checkout **decrements stock** server-side and flips
  `isAvailable` off at zero.
- 422 `validation` — empty `items`, missing/invalid `address` (per-field
  errors: fullName ≥ 2, street ≥ 4, city ≥ 2, state ≥ 2, zip ≥ 3, phone ≥ 7),
  or quantity outside `1..99`.
- 400 — `bad_payment_method` (unsupported string), `unknown_product` (item
  not in the catalog), `bad_request` (non-object item), `invalid_json`.
- 409 `out_of_stock` with `items: [ids]` — a requested product is
  unavailable or `stock < quantity`. (Also forced for **every** checkout when
  `conditions.failCheckoutWithOutOfStock` is on.)

Order shape: `{ "id": "o1004", "status": "pending", "items": [CartItem…],
"subtotal", "shipping", "tax", "total", "address", "placedAt",
"estimatedDelivery" }`.

### `GET /orders` 🔒

- 200 → `{ "data": [Order…] }` — **newest first**.

### `GET /orders/:id` 🔒

- 200 → `{ "data": Order }`
- 404 `not_found` "Unknown order."

## Failure injection — `BackendConditions`

Mutate `server.conditions` (from a test, or a debug hook) to *experience*
failure classes without infrastructure:

| Knob | Type | Effect |
| --- | --- | --- |
| `latencyMinMs` / `latencyMaxMs` | int | artificial per-request latency (defaults **150–300 ms**, deterministic 6-step cycle; set both to 0 in tests). Raise above the client's 12 s receive timeout to exercise `TimeoutException` |
| `forceStatusNext(count, code)` | method | the next `count` requests answer HTTP `code` (e.g. `forceStatusNext(1, 500)`); `clearForcedStatus()` cancels |
| `malformedNext` | bool (one-shot) | the **next** request answers HTTP 200 with a body that is not JSON (content-type still `application/json`, so the client's decoder genuinely chokes) |
| `failCheckoutWithOutOfStock` | bool | every checkout answers 409 listing the requested ids, regardless of real stock |
| `isHealthy` / `reset()` | — | whether any condition is active / restore defaults |
| `handledRequestCount` | getter | requests served since (re)seed — lets tests assert how many network calls a controller actually made (debounce + cancellation proofs) |

`resetData()` re-seeds catalog, users, favorites, orders, id sequences and
conditions — use between tests. `start()` is idempotent; `close()` is safe
twice.

## Seeded catalog facts (deterministic)

- **66 products**, 11 per category, ids `p01`…`p66` in spec order.
- **6 categories**: `c1` Electronics, `c2` Home & Kitchen, `c3` Sports,
  `c4` Fashion, `c5` Books, `c6` Beauty — each `productCount: 11`.
- Prices derive from base prices ± 8 % jitter with the fixed seed
  `Random(20260101)` — e.g. **`p01` Aurora Wireless Noise-Cancelling
  Earbuds = \$124.15** every single run (asserted in the integration test).
- `compareAtPrice` set for ~35 % of products (deterministic).
- Stock is 0 on every 17th product (`index % 17 == 4` → `p04`, `p21`, …);
  `isAvailable` additionally false on every 31st.
- Sellers: 3 per category (e.g. `c1`: Northgate Audio, Voltaic Labs,
  Pixel & Byte).
- Images: `https://picsum.photos/seed/mf-<id>[/b|/c]/600/600` — 3 per
  product (seeded and stable, offline-tolerant via the error placeholder).
- **Demo account** (pre-registered): `demo@marketflow.dev` /
  `Password123` — user `u1` **Dana Mercado**, member since 2025-03-12,
  token `tok-demo-1`, favorites `p05`, `p12`, `p27`, and two orders:
  - `o1001` — **delivered** — 1 × `p03` + 2 × `p10` — placed 2026-01-02
    10:00 UTC
  - `o1002` — **shipped** — 1 × `p15` — placed 2026-01-09 14:30 UTC
- New orders get ids from `o1004` upward and `placedAt` from a fixed
  7-minute ladder starting 2026-01-15 10:00 UTC.
- All state (users, favorites, orders, stock) is in-memory only; a process
  restart re-seeds everything.

## Client-side protocol details

- Timeouts: connect 8 s, receive 12 s, send 10 s (`AppConfig`); default page
  size 20.
- `ApiClient` exposes `getObject`/`getArray`/`postObject`/`deleteObject`,
  all accepting a `CancelToken` (used by search cancellation).
- `AuthInterceptor` adds the bearer header when a token exists and reports
  401-with-token (outside auth endpoints) through `onUnauthorized`.
- Repository impls translate every non-`AppException` via `ErrorMapper.map`
  (`_guard`), so transport details never leave `data/`.
