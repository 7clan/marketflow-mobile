# Architecture

MarketFlow uses a **layered architecture** with one dependency direction:
presentation → application/state → domain ← data. The domain defines *what*
the app is; data and presentation define *how*. Cross-cutting concerns
(networking, error mapping, theme) live in `core/` and are consumed by `data/`
only — screens never import Dio, JSON or SharedPreferences.

```
┌──────────────────────────────────────────────────────────────────────┐
│ presentation/                                                        │
│   screens/   15 feature screens (Material 3)                         │
│   widgets/   11 shared building blocks (cards, steppers, skeletons)  │
│   providers/ 14 Riverpod files — app state + DI composition root     │
│   router/    app_router.dart — GoRouter + auth redirect + 5-tab shell │
└───────────────┬──────────────────────────────────────────────────────┘
                │ watches providers / calls controller methods
┌───────────────▼──────────────────────────────────┐
│ application/state  (lib/presentation/providers)   │
│   AsyncNotifier: auth, feed, orders               │
│   Notifier:        search, filters, favorites,    │
│                    cart, checkout, recents, theme │
└───────────────┬──────────────────────────────────┘
                │ depends only on interfaces
┌───────────────▼──────────────┐  ┌───────────────────────────────────┐
│ domain/                      │◄─│ data/                             │
│  entities/  (10, pure Dart)  │  │  models/       9, tolerant fromJson│
│  repositories/ (5 interfaces)│  │  repositories/ 5 impls             │
└──────────────────────────────┘  │  datasources/  8                   │
                                  │    mock_marketplace_server.dart    │
                                  │    secure_session_local_data_source│
                                  │    shared_preferences_cart/favorites│
                                  └───────┬───────────────────────────┘
                                          │ real HTTP (Dio)
                                  ┌───────▼───────────────────────────┐
                                  │ core/                             │
                                  │  network/ ApiClient + AuthInterceptor│
                                  │  errors/   ErrorMapper → AppException│
                                  │  config/   AppConfig (timeouts,    │
                                  │             pageSize, baseUrl)     │
                                  └───────────────────────────────────┘
```

## The dependency rule

- `domain/` imports nothing from `data/` or `presentation/`. Entities
  (`Product`, `CartItem`, `Order`, `Address`, `User`, `AuthSession`,
  `Category`, `CartTotals`, `PaginatedResult`, `ProductFilter`) are pure Dart
  with value semantics; repository interfaces are abstract.
- `data/` implements the domain interfaces. It knows Dio, JSON and storage —
  nothing about widgets or Riverpod.
- `presentation/` watches providers and forwards user intent. Screens never
  see a `DioException`, a `Map<String, dynamic>` or a storage key.

Consequence: the repository seam is the only place transport details exist.
The mock backend swap below touches `main.dart` + one provider override and
nothing else.

## Layer contents (actual files)

### `core/` — cross-cutting infrastructure

| File | Role |
| --- | --- |
| `lib/core/config/app_config.dart` | `AppConfig`: `baseUrl`, connect 8 s / receive 12 s / send 10 s timeouts, `pageSize = 20`; `AppConfig.localServer(port)` factory |
| `lib/core/errors/app_exception.dart` | sealed hierarchy: `Network`, `Timeout`, `Unauthorized`, `Forbidden`, `NotFound`, `BadRequest`, `Validation` (field errors), `Conflict` (conflicting ids), `Server`, `Cancelled`, `MalformedResponse`, `Cache`, `Unknown` — each with a user-safe `message` |
| `lib/core/errors/error_mapper.dart` | the *only* place Dio/parse errors become `AppException`s (see error flow) |
| `lib/core/network/api_client.dart` | typed Dio wrapper: unwraps the `{"data": ...}` envelope, guarantees payload shape, `CancelToken` passthrough |
| `lib/core/network/auth_interceptor.dart` | bearer injection + 401-with-token expiry reporting (callback-injected) |
| `lib/core/theme/app_theme.dart` | Material 3 light + dark from one brand seed |
| `lib/core/utils/` | `validators` (pure), `formatters` (intl), `debouncer` |

### `domain/` — entities + contracts

10 entities and 5 repository interfaces
(`AuthRepository`, `ProductRepository`, `FavoritesRepository`,
`CartRepository`, `OrderRepository`) in `lib/domain/`. Notably
`lib/domain/entities/cart_totals.dart` contains the **pure pricing function**
`computeCartTotals()` — flat \$8.99 shipping, free ≥ \$99, 8.5 % tax — which
the mock server mirrors so the reviewed totals equal the recorded order
totals.

### `data/` — implementations

- **`datasources/mock_marketplace_server.dart`** — deterministic
  in-process HTTP backend (see next section).
- **`datasources/market_api_host.dart`** — `MarketApiHost`: lifecycle owner
  (bind once, idempotent start, stop on scope disposal) + `startMockApiHost()`
  helper.
- **`datasources/secure_session_local_data_source.dart`** — token+user JSON in
  `flutter_secure_storage` (`marketflow.session`), in-memory mirror, corrupt
  data → signed-out, never a crash.
- **`datasources/shared_preferences_cart_local_data_source.dart`** — cart JSON
  under `marketflow.cart`; a single corrupt entry is skipped, not fatal.
- **`datasources/shared_preferences_favorites_cache.dart`** — favorite id
  cache for instant cold start.
- **`models/`** — 9 model classes with tolerant `fromJson` (numeric strings
  coerced, nullable fields defaulted, malformed shapes throw
  `MalformedResponseException`).
- **`repositories/`** — 5 impls. Each wraps every call in `_guard()`:
  `AppException`s pass through, everything else is run through
  `ErrorMapper.map`. No transport error can escape the layer.

### `presentation/` — state + UI

- **`providers/`** — see [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md).
  `infrastructure_providers.dart` is the composition root: it builds the
  `ApiClient`, all five repositories, the storage seams, and wires session
  expiry.
- **`router/app_router.dart`** — one `GoRouter` (see routing section).
- **`screens/`** — one folder per feature; screens map provider state to
  widgets (`switch (feed) { AsyncValue(hasValue: false) => skeleton, ... }`)
  and forward intent to controllers.
- **`widgets/`** — `ProductCard`, `FavoriteButton`, `QuantityStepper`,
  `PriceText`, `RatingStars`, `Skeleton*`, `ErrorView`, `EmptyView`,
  `AppTextFormField`, `SearchField`, `StatusChip`.

## The in-process HTTP backend

`MockMarketplaceServer` (1,240 lines) is a real `dart:io` `HttpServer` bound
to `127.0.0.1` on an **ephemeral port**. The app's Dio client talks to it
over genuine HTTP, so **timeouts, interceptors, cancellation, status codes
and JSON decode errors are exercised for real** — no fake transport.

```
main() ──► MarketApiHost().start()          (bind 127.0.0.1:0)
        ──► ProviderScope(overrides: mockApiHostProvider)
                     │
                     ▼
        appConfigProvider → AppConfig.localServer(port)
                     │
                     ▼
        apiClientProvider → Dio(BaseOptions(baseUrl, timeouts))
                     │
                     ▼
        5 repository providers → controllers → screens
```

Why this design:

1. **Realism.** A `DioException` produced by an actual refused connection,
   actual 150–300 ms latency and an actual malformed body is the same failure
   class production will deliver. Tests assert against reality, not mocks of
   it.
2. **Determinism.** Seeded `Random(20260101)`, fixed order-time epoch, no
   `DateTime.now()` — the catalog (66 products / 6 categories) and prices are
   byte-stable between runs (the earbuds are always \$124.15), so
   `expect(product.price, 124.15)` is a legitimate assertion.
3. **Production swap.** The wire contract (envelope, routes, error codes) is
   a plain REST API. Pointing `appConfigProvider` at
   `https://api.marketflow.dev/v1` is the entire change; `main.dart` then
   simply never starts the host.

`MarketApiHost.baseUrl` throws a `StateError` with a fix-it hint if read
before `start()` — misconfiguration fails loudly.

Runtime failure injection: `server.conditions` (`BackendConditions`) exposes
`latencyMinMs/latencyMaxMs`, one-shot `malformedNext`,
`forceStatusNext(count, code)` and `failCheckoutWithOutOfStock`, plus
`handledRequestCount` so tests can assert *how many* network calls a
controller actually made (debounce/cancellation proofs).
[API.md](API.md) documents the full protocol.

## Error flow

Every failure path in the app converges on one pipeline:

```
DioException / FormatException / TypeError / storage failure
        │  (repository _guard)
        ▼
ErrorMapper.map()                          lib/core/errors/error_mapper.dart
  connectionTimeout|sendTimeout|receiveTimeout  → TimeoutException
  connectionError|badCertificate               → NetworkException
  cancel                                        → CancelledException
  badResponse 400/422 (+field errors)           → ValidationException / BadRequestException
  401                                           → UnauthorizedException  (server message kept)
  403 / 404 / 409 (+ items)                     → Forbidden / NotFound / ConflictException
  ≥500                                          → ServerException (statusCode)
  DioException.unknown (nested cause unwrapped) → Network/Timeout/Malformed
  FormatException | TypeError                   → MalformedResponseException
        │
        ▼
AppException.message    — user-safe copy, surfaces in ErrorView / banners / errorText
AppException.code       — machine code (e.g. 'out_of_stock') for logging/tests
ValidationException.fieldErrors — maps straight onto form fields
ConflictException.conflictingItems — the out-of-stock product ids
```

Two details worth calling out:

- **The backend message wins when present.** The mock server guarantees its
  messages are user-safe ("Invalid email or password.",
  "Some items in your cart are no longer available."), so `ErrorMapper`
  surfaces them; everything else falls back to typed copy. Widgets never
  render `error.toString()`.
- **Cancellation is a first-class state.** `CancelledException` is caught by
  the search controller (superseded query) rather than shown as an error.

## Routing structure

`lib/presentation/router/app_router.dart`:

| Route | Screen | Notes |
| --- | --- | --- |
| `/` | `SplashScreen` | session restore, error + retry |
| `/login`, `/register` | auth screens | no transition |
| `/shop` `/categories` `/favorites` `/cart` `/profile` | shell branches | `StatefulShellRoute.indexedStack` — each tab keeps its own state |
| `/product/:id` | `ProductDetailScreen` | root navigator (covers tab bar); `extra: Product` snapshot primes the UI |
| `/search`, `/checkout`, `/orders`, `/orders/:id` | full-screen pushes | root navigator |

The `redirect` encodes the auth decision table on *every* navigation:

- auth `isLoading` or `hasError` (restore in flight / failed) → hold on `/`
  (splash renders progress, then error + retry);
- unauthenticated → `/login` (unless already there);
- authenticated arriving on `/login`, `/register` or `/` → `/shop`.

Re-evaluation is driven by `_AuthRefresh`, a `ChangeNotifier` that listens to
`authControllerProvider` but **notifies only when the resolved value
changes** — the transient `AsyncLoading` frames during a login request must
not rebuild the navigator mid-interaction.

## The four real bugs the test suite caught

The suite was not written to pass; it was written to find problems — and it
found four, each fixed with a targeted commit:

| # | Bug (as found by tests) | Fix | Commit |
| --- | --- | --- | --- |
| 1 | **Raw Dio 401 during session restore surfaced as an app error.** `restoreSession()` calls `GET /auth/me` with a stored token; when the token had expired, a *raw* `DioException` (not yet mapped) escaped the repository's `UnauthorizedException` branch. | `AuthRepositoryImpl.restoreSession` also catches `DioException` and recognizes `statusCode == 401` → clear local session, emit signed-out (clean sign-out, not an error screen). `29e1aa2` | |
| 2 | **Provider-cycle deadlock when a 401 fires mid-restore.** The first wiring ran the session-expiry callback from `apiClientProvider` into the auth *controller* — but the controller's `build()` was still awaiting restore, so the cycle deadlocked. | Session expiry is wired inside `authRepositoryProvider` (the repository is the session owner): an `InterceptorsWrapper` on the shared Dio calls `repository.discardLocalSession()`, and app state flows out through the repository's `userChanges` stream. The controller subscribes to the stream; no provider reads the controller during construction. `be23db5` | |
| 3 | **Favorites stale notifier writes.** If the favorites controller was rebuilt (auth transition) while a toggle request was in flight, the old notifier instance wrote state through its disposed `ref` — a crash / lost update. | Every post-await write is guarded by `ref.mounted` in `FavoritesController` (`syncFromServer`, `addFavorite`, `removeFavorite`). `9226ccb` | |
| 4 | **Cart async restore clobbered mutations.** The cart is restored from storage asynchronously; if the user added an item before restore landed, the restore snapshot silently reverted their action. | `CartController._restore` records `_mutationSeq` at start and drops the stale snapshot if a mutation happened mid-restore (the mutation's own persist already re-wrote storage). `2f24900` | |

Bug #1 and #2 are why `authRepositoryProvider` (not `apiClientProvider`)
owns the 401 wiring — see the code comment in
`lib/presentation/providers/infrastructure_providers.dart` for the full
rationale. This is also the best interview material in the repo: two of the
four bugs are *concurrency* bugs that only appear when real network timing
meets real state lifecycles.

## Why layered + in-process backend (design decisions)

- **Repository interfaces** make the mock/production swap and test fakes
  (`test/helpers/fake_repositories.dart`) trivial — controllers depend on
  contracts, not implementations.
- **Real HTTP instead of a fake Dio adapter** — the CareRoute-style adapter
  approach mocks the failure classes; MarketFlow prefers to *actually produce
  them* (see [TESTING.md](TESTING.md) for the fake-async zone lesson this
  forced us to learn).
- **`AppConfig` timeouts** exist because the mock server's latency injection
  (`latencyMinMs` up to seconds) makes timeout handling *observable*, not
  theoretical.
