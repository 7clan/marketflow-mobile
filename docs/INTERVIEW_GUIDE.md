# MarketFlow Interview Guide

Everything below is about **this repository** — every file mentioned exists
and every number is real. Questions are grouped by topic; each has a
*simple answer* (say this first), a *deeper technical answer* (the real
mechanism, classes and numbers), and *files to review*.

Read [README.md](../README.md) first, then [docs/ARCHITECTURE.md](ARCHITECTURE.md).

---

## A. Project overview (4 questions)

### 1. What is MarketFlow, in one sentence?

**Simple:** A Flutter marketplace app — product feed with filters/sorting,
search, favorites, cart, checkout and order history — built as a
production-discipline portfolio project.

**Deeper:** What makes it more than a tutorial: a layered architecture
(domain/data/presentation) with strict dependency direction, Riverpod 3
controllers with concurrency protection (stale-response guards, optimistic
rollback, restore-race fixes), a typed error taxonomy, and a 215-test suite
over a *real* in-process HTTP backend — so interceptors, timeouts,
cancellation and malformed responses are exercised for real, not simulated.

**Files:** `README.md`, `PROJECT_SPEC.md`, `lib/main.dart`, `lib/app.dart`

### 2. What are the screens and the user flow?

**Simple:** Splash → Login/Register → five tabs: Shop (feed), Categories,
Favorites, Cart, Profile. Full-screen pushes above the shell: product
detail, search, checkout, orders, order detail.

**Deeper:** The shell is a `StatefulShellRoute.indexedStack` with five
`StatefulShellBranch`es — each tab preserves its own scroll/state through an
IndexedStack; detail/checkout routes use the root navigator so they cover
the tab bar. Product detail accepts the tapped `Product` via `route.extra`
to prime the UI instantly before the detail fetch lands.

**Files:** `lib/presentation/router/app_router.dart`,
`lib/presentation/screens/shell/home_shell.dart`

### 3. Which packages does it use and why?

**Simple:** Riverpod (state/DI), GoRouter (navigation), Dio (HTTP),
flutter_secure_storage (token), shared_preferences (cart/favorites
cache/theme/recents), cached_network_image (images), intl (formatting).

**Deeper:** Riverpod for compile-safe DI and rebuild scoping (`select`)
without BuildContext; GoRouter for a declarative, redirectable route table
with preserved tab state; Dio because interceptors are first-class —
`AuthInterceptor` injects tokens and reports 401s, `CancelToken` powers
search cancellation; cached_network_image because a scrolling grid of
600×600 remote images needs disk caching plus decode-width control.
No code generation for models — the tolerant `fromJson` in
`lib/data/models/` is deliberate and tested.

**Files:** `pubspec.yaml`, `lib/data/models/json_reader.dart`

### 4. How big is the app and its test suite?

**Simple:** 89 source files (~11.5k lines) and 24 test files (~4.3k lines)
with 215 tests: 74 core unit, 63 data/repository, 55 state, 22 widget, 1
integration. Analyzer clean, format clean, CI on GitHub Actions.

**Deeper:** The pyramid is weighted at the seams that actually produced
bugs: transport mapping (26 error-mapper tests), controller state
transitions (pagination, debounce, optimistic updates, restore races) and
screen state rendering. Four real bugs were found and fixed by this suite —
two of them concurrency bugs (provider-cycle deadlock on 401, cart restore
clobbering) that only appear when real network timing meets real state
lifecycles.

**Files:** `test/`, `.github/workflows/flutter_ci.yml`, `docs/TESTING.md`

---

## B. Riverpod (9 questions)

### 5. Which Riverpod provider types does the app use, and when?

**Simple:** `AsyncNotifierProvider` for async flows (auth, feed, orders),
`NotifierProvider` for synchronous state (search, filters, favorites, cart,
checkout, theme), `FutureProvider.autoDispose` for plain reads (categories,
product detail, order detail), and plain `Provider` for DI (config, Dio
client, repositories).

**Deeper:** `AsyncNotifier` gives loading/error/data states for the three
screens that fetch; `Notifier` fits state that mutates synchronously with
explicit commands; autoDispose keeps screen-scoped payloads out of memory;
providers are the composition root — `infrastructure_providers.dart`
constructs the ApiClient and all five repositories, so tests override
providers instead of mocking singletons.

**Files:** `lib/presentation/providers/` (all 14 files)

### 6. How is authentication state modeled?

**Simple:** An `AsyncNotifierProvider<AuthController, AuthState>` where
`AuthState` is sealed — `AuthAuthenticated(user)` or
`AuthUnauthenticated()` — with `AsyncValue` covering restore/login loading.

**Deeper:** `build()` calls `ref.keepAlive()` (auth must survive losing
listeners during navigation), **subscribes to the repository's
`userChanges` stream** so every session transition (login, register,
logout, expiry) mirrors into state from one source of truth, then awaits
`restoreSession()`. `login`/`register` rethrow `AppException`s to the
*caller* for inline form errors while the shared state tracks only the
session. The 401-expiry path (`handleSessionExpired`) discards the local
session; the stream mirrors the sign-out.

**Files:** `lib/presentation/providers/auth_controller.dart`,
`lib/data/repositories/auth_repository_impl.dart`

### 7. Why does the auth controller subscribe to a stream instead of setting state after login?

**Simple:** Because session transitions come from more places than the
login form: register, restore, logout, and token expiry fired by the
interceptor on *any* request.

**Deeper:** The repository owns the session and exposes
`Stream<User?> userChanges` (a broadcast `StreamController`). Whoever
changes the session (including the Dio 401 interceptor wiring calling
`discardLocalSession()`), the controller's subscription mirrors it. This
avoids the classic alternative — every caller mutating controller state —
and it's what fixed the provider-cycle deadlock: state flows one way, out
of the repository.

**Files:** `lib/data/repositories/auth_repository_impl.dart`,
`lib/presentation/providers/auth_controller.dart`

### 8. How does the filter → feed rebuild chain work?

**Simple:** The feed `AsyncNotifier` *watches* the filter `Notifier`; any
filter/sort change re-runs the feed's `build()` (page 1).

**Deeper:** `FilterState` is a value type (`==`/`hashCode` over category,
min/max price, inStockOnly, sort) with a sentinel-`copyWith` so "clear the
category" is distinguishable from "didn't touch it". Because the feed
watches it, invalidation is automatic — no imperative "refresh now" calls
scattered through the UI. The in-flight page request from the *old* filter
drops itself via the request sequence number (Q20).

**Files:** `lib/presentation/providers/filter_controller.dart`,
`lib/presentation/providers/product_feed_controller.dart`

### 9. How do you avoid rebuilding the whole screen when one thing changes?

**Simple:** `ref.watch(provider.select((s) => …))` — watch the slice you
render.

**Deeper:** `FavoriteButton` selects `state.isFavorite(product.id)` so a
favorite toggle rebuilds exactly one heart, not every card's; `HomeShell`
selects `cart.itemCount` for the badge; the feed listens to only
`favorites.error` for rollback SnackBars; `favoriteProductsProvider` watches
only the favorites *ids*. Rebuild scope is the difference between O(cards)
and O(1) work per interaction.

**Files:** `lib/presentation/widgets/favorite_button.dart`,
`lib/presentation/screens/shell/home_shell.dart`,
`lib/presentation/providers/favorite_products_provider.dart`

### 10. Which providers are keepAlive and which autoDispose — and why?

**Simple:** App-global state (auth, cart, favorites, filters, search,
recents, theme) is keepAlive; screen-scoped data (feed, orders, categories,
product detail, favorite products) is not; checkout is autoDispose *on
purpose* so the flow restarts clean.

**Deeper:** The cart badge must live wherever the user navigates; filters
must persist while browsing other tabs; the recents list survives
re-entering search. Conversely, order history re-fetches on entry (statuses
should be fresh), `productDetailProvider.family` frees each product when
its screen closes, and checkout restarting at the address step after a
completed order is the *correct* UX, not a bug.

**Files:** each provider's `build()` (see `docs/STATE_MANAGEMENT.md` for
the full table)

### 11. How do tests override the provider graph?

**Simple:** Override the infrastructure providers — a started mock host plus
in-memory session/cart/favorites sources — and build a `ProviderContainer`.

**Deeper:** `createTestApp()` (test/helpers) reproduces `main()`'s wiring
with injectable seams; widget tests swap in hand-written repository *fakes*
with call counters and `Completer` gates via
`createFakeRepositoryContainer()` + `UncontrolledProviderScope`. Riverpod's
provider auto-retry is controllable per test. No singleton mocks, no
`mockito` — the seams are the architecture.

**Files:** `test/helpers/app_container.dart`,
`test/helpers/fake_repositories.dart`

### 12. What is the sentinel `copyWith` pattern and why is it everywhere?

**Simple:** A `static const _unset = Object()` default lets `copyWith`
distinguish "argument not provided" from "explicitly set this nullable
field to null".

**Deeper:** `copyWith(categoryId: null)` *clearing* the category filter
would be impossible with the usual `categoryId ?? this.categoryId`. The
same pattern guards nullable `error` fields on
`ProductFeedState`/`SearchState`/`CartState`/`FavoritesState` (clearing an
error ≠ keeping it). Each class documents it inline.

**Files:** `lib/presentation/providers/filter_controller.dart` (and 6 more
state classes)

### 13. Tell me about the provider-cycle deadlock bug.

**Simple:** The first session-expiry wiring called the auth *controller*
from the Dio layer — but during session restore the controller was still
awaiting inside `build()`, so the cycle deadlocked.

**Deeper:** Root cause: `apiClientProvider` would have had to read a
controller that was, transitively, reading the client. Fix (commit
`be23db5`): the expiry wiring lives in `authRepositoryProvider` — an
`InterceptorsWrapper.onError` checks `401 + Authorization header present`
and calls `repository.discardLocalSession()`; app state flows out through
`userChanges`, which the controller already subscribes to. The lesson:
never route framework callbacks into a provider that is still
constructing; own the side effect at the layer that owns the data.

**Files:** `lib/presentation/providers/infrastructure_providers.dart`
(the comment there documents the full rationale)

---

## C. Dio & networking (6 questions)

### 14. Why Dio over `http` or `dart:io`?

**Simple:** Interceptors, typed exceptions, timeouts and cancellation as
first-class features — the four things a production client needs.

**Deeper:** `AuthInterceptor` (token injection + 401 detection) is an
`Interceptor` subclass; `CancelToken` powers search cancellation; connect 8
s / receive 12 s / send 10 s timeouts come from `AppConfig` so the mock
server's latency injection actually triggers them; `DioException` types map
cleanly onto the error taxonomy. `ApiClient` wraps Dio with typed
`getObject/getArray/postObject/deleteObject` so the envelope contract
stays in one class.

**Files:** `lib/core/network/api_client.dart`,
`lib/core/config/app_config.dart`

### 15. What does the auth interceptor actually do?

**Simple:** Adds `Authorization: Bearer <token>` to outgoing requests when a
token exists, and reports 401s-that-had-a-token to an `onUnauthorized`
callback.

**Deeper:** `onRequest` awaits a `tokenProvider()` callback (injected —
trivially fakeable; in the app it reads secure storage) and never lets a
token-lookup failure break traffic. `onError` fires `onUnauthorized` only
for `401 && hadToken && !authEndpoint` — a failed login attempt must not
sign the user out. The callback design also avoids the interceptor knowing
anything about Riverpod.

**Files:** `lib/core/network/auth_interceptor.dart`

### 16. How are timeouts configured and tested?

**Simple:** `AppConfig` sets connect 8 s, receive 12 s, send 10 s; tests
raise the mock server's latency above the receive timeout and assert
`TimeoutException`.

**Deeper:** Because the backend is a real server, latency injection
(`conditions.latencyMinMs/latencyMaxMs`) genuinely delays responses —
`product_repository_test.dart` ("a response slower than receiveTimeout
surfaces TimeoutException") exercises the real Dio timeout path, not a
simulated throw. `ErrorMapper` treats `connectionTimeout`, `sendTimeout`,
`receiveTimeout` and `transformTimeout` identically.

**Files:** `lib/core/config/app_config.dart`,
`lib/core/errors/error_mapper.dart`, `test/data/product_repository_test.dart`

### 17. How does request cancellation work in this app?

**Simple:** Search passes a `CancelToken` to the repository; committing a
new query cancels the previous request and bumps a sequence number.

**Deeper:** `_cancelInFlight()` increments `_requestSeq` (so a late
response drops itself even if cancellation races) and calls
`token.cancel()`. The repository's `CancelledException` is swallowed by
the search controller — cancellation is not an error, it's supersession.
Tests prove the network effect with `server.handledRequestCount` (the
server counts what it actually served).

**Files:** `lib/presentation/providers/search_controller.dart`,
`test/state/search_controller_test.dart`

### 18. Walk me through the error mapping pipeline.

**Simple:** Repositories wrap every call in `_guard`; anything that isn't
already an `AppException` goes through `ErrorMapper.map`, which converts
`DioException`s by type/status into the sealed `AppException` hierarchy.

**Deeper:** Timeout/connection/badCertificate → `Timeout`/`Network`;
`cancel` → `Cancelled`; `badResponse` by status: 400/422 (+`errors` map) →
`Validation`/`BadRequest`, 401/403/404/409 (+`items` ids) → the matching
type, ≥500 → `Server(statusCode)`. The subtle branch:
`DioExceptionType.unknown` is *unwrapped* — Dio nests adapter-level causes,
so a wrapped `FormatException` becomes `MalformedResponseException` and a
wrapped connection error becomes `NetworkException`. Already-mapped
exceptions pass through untouched (single-catch ergonomics, no
double-wrapping).

**Files:** `lib/core/errors/error_mapper.dart` (26 tests:
`test/core/error_mapper_test.dart`)

### 19. How does the client enforce the response envelope?

**Simple:** `ApiClient._payloadOf` requires the body to be a JSON map
containing `data`; typed getters then require the payload's *shape*
(object vs array).

**Deeper:** A missing envelope or wrong payload type throws
`MalformedResponseException` with the received runtimeType in the cause —
so a backend contract drift fails loudly at the boundary, not with a cast
error deep in a model. The malformed-injection test (server answers 200
with non-JSON) proves the decoder path too.

**Files:** `lib/core/network/api_client.dart`,
`lib/data/models/json_reader.dart`

---

## D. The API architecture / mock backend (5 questions)

### 20. Why an in-process HTTP server instead of a fake Dio adapter?

**Simple:** So the entire HTTP pipeline — interceptors, timeouts,
cancellation, status codes, JSON decoding — is exercised *for real*.

**Deeper:** `MockMarketplaceServer` binds a real `dart:io` `HttpServer` to
`127.0.0.1` on an ephemeral port; `MarketApiHost` owns its lifecycle
(idempotent start, stop on scope disposal). A connection-refused error
produced by a real socket is the same failure class production delivers.
The tradeoff (learned the hard way, see Q42) is that real sockets don't
work inside `testWidgets`' fake-async zone — hence the two-pattern test
strategy.

**Files:** `lib/data/datasources/mock_marketplace_server.dart`,
`lib/data/datasources/market_api_host.dart`

### 21. How is the backend deterministic?

**Simple:** Fixed seed `Random(20260101)`, fixed catalog spec, fixed order
time ladder — 66 products, 6 categories, byte-stable prices.

**Deeper:** Prices = base ± 8 % seeded jitter clamped to [4.99, 2000] — the
Aurora earbuds are **always \$124.15**, asserted in the integration test.
Stock is 0 on every 17th product, `isAvailable` false on every 31st;
`listedAt` climbs 6 h per product from 2025-10-01 (deterministic `newest`
sort). Latency itself is deterministic: a 6-step cycle through 150–300 ms.
`resetData()` re-seeds everything between tests.

**Files:** `lib/data/datasources/mock_marketplace_server.dart`
(`_seed`, `_buildCatalog`), `test/integration/golden_path_test.dart`

### 22. What failure injection does the backend support?

**Simple:** `BackendConditions`: adjustable latency, one-shot malformed-JSON
response, `forceStatusNext(count, code)`, and always-409 checkout, plus a
served-request counter.

**Deeper:** `forceStatusNext(2, 500)` makes exactly the next two requests
answer 500 — perfect for retry tests. `malformedNext` answers HTTP 200 with
a non-JSON body while keeping content-type JSON, so the client decoder
genuinely chokes. `handledRequestCount` lets tests assert *how many* network
calls a controller made — the debounce and cancellation proofs are
server-side counting, not client-side introspection.

**Files:** `lib/data/datasources/mock_marketplace_server.dart`
(`BackendConditions`), `docs/API.md`

### 23. What does the wire contract look like?

**Simple:** Success = `{"data": ...}` with 200/201; failure =
`{"error": {code, message, errors?, items?}}` with 400/401/403/404/409/422/5xx.

**Deeper:** `errors` carries field→messages for 422 (register, address,
cart quantities); `items` carries product ids for 409 out-of-stock. Routes:
`auth/register|login|me`, `categories`, `products` (+ query params:
page/pageSize≤100/sort/category/q/minPrice/maxPrice/inStock), `products/:id`,
`favorites` + `favorites/:id` (POST/DELETE), `checkout`, `orders`,
`orders/:id`. Checkout recomputes totals server-side with the *same*
pricing function the client uses and decrements stock.

**Files:** `docs/API.md`, `lib/data/repositories/*_impl.dart`

### 24. How would you swap in a real backend?

**Simple:** Override `appConfigProvider` with
`const AppConfig(baseUrl: 'https://api.marketflow.dev/v1')` — that's it.

**Deeper:** The repositories only know relative paths + the envelope; the
host provider is never started in that build; `MarketApiHost.baseUrl`
throws a `StateError` with a fix-it hint if misread before start, so a
half-wired bootstrap fails loudly. Secure storage, SharedPreferences, and
every controller remain untouched — the seam is the config provider.

**Files:** `lib/core/config/app_config.dart`,
`lib/presentation/providers/infrastructure_providers.dart`, `lib/main.dart`

---

## E. Feed & pagination (3 questions)

### 25. How is pagination implemented?

**Simple:** Server-side paging (20/page, `page`/`pageSize`, `hasMore`,
`totalItems`); the controller appends pages on scroll with guards against
duplicates.

**Deeper:** `ProductFeedController.build()` loads page 1 and watches
filters; `loadNextPage()` early-returns on `!hasMore`/`isLoadingMore`/no
data, sets `isLoadingMore`, awaits page N+1 and *appends* (items are never
replaced). The screen triggers it from a `NotificationListener` 600 px
before the list end, so pages arrive before the user hits the bottom. The
footer renders progress / retry / end-of-catalog states.

**Files:** `lib/presentation/providers/product_feed_controller.dart`,
`lib/presentation/screens/feed/product_feed_screen.dart`

### 26. What is stale-response protection and why do you need it?

**Simple:** A sequence number per feed restart; in-flight responses compare
their captured number and drop themselves if the query changed under them.

**Deeper:** `_requestSeq` increments in `build()`; `loadNextPage` captures
`seq` before awaiting and checks `seq != _requestSeq` after — on both the
success *and* error paths. Without it, changing the filter while page 2 of
the old query is in flight would append Electronics results into the
Beauty feed — with 150–300 ms latency that race is routine, not exotic.
`product_feed_controller_test.dart` has the regression test
("a stale load-more response (filter changed mid-flight) is discarded").

**Files:** `lib/presentation/providers/product_feed_controller.dart`,
`test/state/product_feed_controller_test.dart`

### 27. How do load-more failures differ from refresh failures in the UI?

**Simple:** Refresh errors become the provider's `AsyncError` (full-screen
error view); load-more errors land in `ProductFeedState.error` (in-list
retry footer, list stays visible).

**Deeper:** That split is deliberate state design: replacing the whole grid
with an error because page 3 failed would throw away 40 loaded items and
the user's scroll position. The screen's `switch (feed)` pattern renders
`AsyncValue(hasValue: false)` → skeleton, `AsyncError` → `ErrorView`,
value → content; the footer renders the in-list error + Retry.

**Files:** `lib/presentation/providers/product_feed_controller.dart`
(state docs), `lib/presentation/screens/feed/product_feed_screen.dart`

---

## F. Search (2 questions)

### 28. How is search debounced and kept fresh?

**Simple:** 300 ms debounce; on commit, cancel the previous request
(`CancelToken`) and bump a sequence number; superseded results drop
themselves.

**Deeper:** The query text updates state *instantly* (the field feels
live) while only the committed search hits the network. Two protections
stack: cancellation (server stops working) and the seq guard (a response
that slips past the cancel can't overwrite newer state). `clear()` cancels
both the pending debounce and the in-flight request. Tests assert network
call counts via `handledRequestCount`, including "empty query resets to
idle without a network call".

**Files:** `lib/presentation/providers/search_controller.dart`,
`lib/core/utils/debouncer.dart`, `test/state/search_controller_test.dart`

### 29. What UX states does search render?

**Simple:** Idle (recent searches), searching (results skeleton), results,
empty, and error with retry.

**Deeper:** `SearchState` carries `query`, `results`, `isSearching`,
`error` plus derived `hasQuery`/`isEmpty`; the empty state only shows when
nothing failed. Recent searches are their own persisted `Notifier`
(`marketflow.recent_searches`, capped at 8, deduped front-insert) — purely
presentation convenience, independent of the stateless search itself.

**Files:** `lib/presentation/providers/search_controller.dart`,
`lib/presentation/providers/recent_searches_provider.dart`,
`lib/presentation/screens/search/search_screen.dart`

---

## G. Cart (5 questions)

### 30. How are cart totals computed?

**Simple:** They're always *derived* — `CartState.totals` is a getter over
the pure function `computeCartTotals(items)`; nothing is stored.

**Deeper:** Flat \$8.99 shipping below \$99, free at/above, 8.5 % tax,
each rounded to cents (`(v*100).round()/100`). The mock server recomputes
order totals with the same function, so review numbers equal recorded
numbers by construction — the integration test asserts 2 × \$124.15 →
subtotal \$248.30, free shipping, total \$269.41 end to end.

**Files:** `lib/domain/entities/cart_totals.dart`,
`lib/presentation/providers/cart_controller.dart`

### 31. How does cart persistence work?

**Simple:** Mutations update in-memory state synchronously and persist via
fire-and-forget `unawaited(_persist(...))` to SharedPreferences.

**Deeper:** Storage is JSON under `marketflow.cart` via
`SharedPreferencesCartLocalDataSource`; a single corrupt entry is skipped
(not fatal — tested), a non-array payload throws `CacheException`. A
persistence failure surfaces as `CartState.error` *without* reverting the
in-memory cart — the user's action stands; the error is informational.
Stepper taps render on the same frame because IO never blocks the
interaction path.

**Files:** `lib/presentation/providers/cart_controller.dart`,
`lib/data/datasources/shared_preferences_cart_local_data_source.dart`

### 32. Tell me about the cart restore race bug.

**Simple:** On startup the cart restores from storage asynchronously; if
the user added an item before restore landed, the stale snapshot silently
reverted their action.

**Deeper:** Fix (commit `2f24900`): `_mutationSeq` bumps on every
mutation; `_restore()` captures it before awaiting and **drops the stale
snapshot** if a mutation landed mid-restore — the mutation's own persist
already re-wrote storage, so applying restore would only lose data.
`cart_controller_test.dart` covers both restore paths
("a pre-populated storage restores the cart on startup" and the
mid-restore-mutation case).

**Files:** `lib/presentation/providers/cart_controller.dart`,
`test/state/cart_controller_test.dart`

### 33. How are quantity bounds enforced?

**Simple:** Quantities are deduped by product and clamped to
`1..min(stock, 99)` with per-line messages ("Only 3 left in stock.",
"Maximum 99 per order.").

**Deeper:** The bound comes from `_maxQuantityFor(product)` — live stock
when in stock, else the per-order max; clamping happens on both add and
`updateQuantity`, and the message keys by product id in
`CartState.validationMessages` so it renders inline under the affected
line. Out-of-stock products can't be added at all (message instead). The
server independently rejects out-of-bounds quantities with 422 — client
clamps are UX, server rules are truth.

**Files:** `lib/presentation/providers/cart_controller.dart`,
`lib/domain/entities/cart_item.dart` (`maxQuantity = 99`)

### 34. Why are per-line prices frozen at add time?

**Simple:** Each `CartItem` stores the `Product` snapshot it was added
with, so a later price/stock change doesn't silently rewrite the cart.

**Deeper:** That makes the cart stable while browsing, and checkout
conflicts (price/stock moved too far) surface as the server's 409
`out_of_stock` rather than mid-cart surprises. The tradeoff is staleness —
handled by the server being the final validator at checkout. Frozen
snapshots are asserted by the test "per-line prices are frozen at add
time".

**Files:** `lib/domain/entities/cart_item.dart`,
`test/state/cart_controller_test.dart`

---

## H. Favorites & optimistic updates (4 questions)

### 35. How do optimistic favorites work?

**Simple:** Toggle the heart immediately, send the request, and roll back
to the captured previous state if the server rejects it — with the error
message surfaced.

**Deeper:** `addFavorite`/`removeFavorite` capture `previous = state`, apply
the id change, await the repository, persist the new id set to the cache on
success; on `AppException` restore `previous` + set `error`. The hosting
screen (`ref.listen(favoritesControllerProvider.select((s) => s.error))`)
shows a SnackBar explaining the rollback and clears the error — the
controller has already restored state, the user needs the *why*. The
widget test drives this end-to-end through a failing fake.

**Files:** `lib/presentation/providers/favorites_controller.dart`,
`test/state/favorites_controller_test.dart`,
`test/widget/product_card_test.dart`

### 36. Why is there a local favorites cache *and* a server list?

**Simple:** The cache (SharedPreferences id set) renders hearts instantly
on cold start; the server sync (after sign-in) is the truth.

**Deeper:** `_hydrateFromCache()` runs in `build()` so the first feed frame
already shows correct hearts; `syncFromServer()` replaces ids
authoritatively and rewrites the cache. A cache failure is swallowed — it's
an optimization, never a dependency. Sign-out clears the ids. Note the
sync trigger covers two cases: an auth *transition* (the `ref.listen`) and
"controller first watched *after* auth was already established" (the
current-value check, deferred to a microtask because state can't be set
synchronously during build).

**Files:** `lib/presentation/providers/favorites_controller.dart`,
`lib/data/datasources/shared_preferences_favorites_cache.dart`

### 37. Tell me about the stale-notifier-writes bug in favorites.

**Simple:** If the favorites controller rebuilt (auth transition) while a
toggle was in flight, the *old* notifier instance would write state through
its disposed ref.

**Deeper:** Fix (commit `9226ccb`): every post-await write is guarded by
`ref.mounted` — in `syncFromServer`, `addFavorite`, `removeFavorite`. The
same guard appears in `favoriteProductsProvider._fetchMissing`. This is
the Riverpod equivalent of the classic `if (!mounted) return` in
StatefulWidget — with providers it's *easier* to forget because the
notifier looks long-lived.

**Files:** `lib/presentation/providers/favorites_controller.dart`,
`lib/presentation/providers/favorite_products_provider.dart`

### 38. How does the favorites tab avoid refetching everything?

**Simple:** `favoriteProductsProvider` keeps product snapshots in a map and
fetches only ids it has never seen — in parallel.

**Deeper:** It watches `favoritesControllerProvider.select((s) => s.ids)`;
on change it drops snapshots for unfavorited ids, computes the *missing*
ids, `Future.wait`s their fetches, and materializes the list. Toggling a
heart updates the list from the snapshot with zero network round-trips;
remove+re-add never refetches. Pull-to-refresh (`reload()`) drops the cache
deliberately.

**Files:** `lib/presentation/providers/favorite_products_provider.dart`

---

## I. Checkout (2 questions)

### 39. How is checkout modeled?

**Simple:** A five-state machine: `editingAddress → reviewing → submitting
→ success | failure(error, failureStep)`.

**Deeper:** `CheckoutStep` enum with labels; `submitAddress` validates
locally with the shared `Validators` (same rules the server enforces);
invalid fields stay on the form with `fieldErrors` keyed to *the same names
the server's 422 uses* — so server validation lands on the same form
fields. On success: cart cleared, `orderId` recorded. On `ValidationException`:
back to the form. On other errors: `failure` with `failureStep: reviewing`
so Retry re-submits; `reset()` restarts clean. Deliberately **no
keepAlive** — a finished checkout must not linger.

**Files:** `lib/presentation/providers/checkout_controller.dart`,
`test/state/checkout_controller_test.dart`

### 40. How are out-of-stock conflicts handled?

**Simple:** The server answers 409 with the conflicting product ids; the
client surfaces a `ConflictException` and the failure step offers retry.

**Deeper:** `ErrorMapper` extracts `items` from the error envelope into
`ConflictException.conflictingItems`. The mock server computes real stock
conflicts (and `failCheckoutWithOutOfStock` forces the state for demos).
Quantity bounds are also validated server-side (422 with field errors).
Purchased units genuinely decrement server stock — asserted by
`order_repository_test.dart`.

**Files:** `lib/core/errors/error_mapper.dart`,
`lib/presentation/providers/checkout_controller.dart`,
`lib/data/datasources/mock_marketplace_server.dart` (`_handleCheckout`)

---

## J. Testing (6 questions)

### 41. What does the test suite look like?

**Simple:** 215 tests: core 74 (pure units), data 63 (models +
repositories over real HTTP), state 55 (controllers, real HTTP), widget 22
(fakes), integration 1 (golden path login→order).

**Deeper:** Group-by-group: `test/core` proves the error-mapper table (26),
validators (33), formatters (9), debouncer (6); `test/data` proves every
route + failure class over a real started server; `test/state` proves
controller transitions incl. the race regressions; `test/widget` proves
screen state tables + a11y contracts; `test/integration/golden_path_test.dart`
drives the exact controller surface the screens call, asserting
deterministic catalog math (subtotal 248.30 / total 269.41).

**Files:** `docs/TESTING.md`, `test/`

### 42. What is the fake-async zone lesson?

**Simple:** `testWidgets` runs in a fake-async zone where real sockets
never deliver — so real-HTTP tests must be plain `test()`, and widget tests
must use fakes.

**Deeper:** Two effects: `Future.delayed` never fires without advancing
time, and — the subtle one — an HttpClient/Dio instance *created inside the
fake zone* never completes a real round-trip (probes: POSTs hang or answer
empty 400s; the same calls work fine from a real zone). The integration
test therefore runs as a plain `test()` in the real zone and its docstring
records the decision verbatim; widget tests get `FakeRepository` overrides
through `UncontrolledProviderScope`. This was the single biggest testing
lesson of the project — agents repeatedly hit the wall before it was
root-caused.

**Files:** `test/integration/golden_path_test.dart` (docstring),
`test/helpers/fake_repositories.dart`

### 43. How do you test fire-and-forget async work?

**Simple:** Small real-time settles: `TestAppScope.settle()` (60 ms with
server latency zeroed) for state tests; explicit 50/200/800 ms delays in
the integration test at the known fire-and-forget points.

**Deeper:** Cart persistence, favorites cache writes and the auth stream
mirror all continue after their trigger returns; awaiting the controller
method isn't enough. The state helper zeroes server latency so one frame
of real time suffices; the integration test's 800 ms covers the 300 ms
debounce *plus* the request. In fake-async widget tests, the pattern is
`pump()` + `pump(120ms)` pairs after taps (Dio delivers via zone timers
even against fakes).

**Files:** `test/helpers/app_container.dart`,
`test/integration/golden_path_test.dart`, `test/widget/product_card_test.dart`

### 44. Which real bugs did the tests catch?

**Simple:** Four: raw Dio 401 during session restore surfacing as an app
error; the provider-cycle deadlock on 401 mid-restore; favorites stale
notifier writes after rebuild; cart restore clobbering a mid-restore
mutation.

**Deeper:** Each has a fix commit (`29e1aa2`, `be23db5`, `9226ccb`,
`2f24900`) and a regression test that failed before it. Two are
concurrency bugs that require real timing to reproduce — the strongest
argument for testing repositories/controllers over real HTTP rather than
canned fakes. Details and code pointers: [ARCHITECTURE.md](ARCHITECTURE.md#the-four-real-bugs-the-test-suite-caught).

**Files:** `docs/ARCHITECTURE.md`, `git log` (the four fix commits)

### 45. How do widget tests interact with providers?

**Simple:** An `UncontrolledProviderScope` wrapping the pumped screen, with
a container built over fake repositories that count calls and gate
responses.

**Deeper:** `FakeFavoritesRepository` records `addCalls`/`removeCalls` (so
"tapping the heart toggles the favorite state" asserts the domain layer was
actually reached); `FakeProductRepository.getProductsGate` is a
`Completer<void>` that holds page 1 in flight so the loading-state test can
assert skeleton rendering deterministically. Fakes live in one helpers file
and implement the *domain interfaces* — which is why the layered
architecture pays for itself in tests.

**Files:** `test/helpers/fake_repositories.dart`,
`test/widget/product_feed_screen_test.dart`

---

## K. Performance (4 questions)

### 46. What are the main list/grid performance techniques?

**Simple:** Builder-based lazy lists everywhere (`SliverGrid.builder` for
the feed, `ListView.builder` for the rest), server-side pagination (20
items/page), and a 600 px scroll pre-load trigger.

**Deeper:** Builders construct only visible cells (the feed widget test
asserts the laziness); pagination bounds first paint and the items list;
the pre-load extent fetches page N+1 before the user reaches the end; the
controller's guards make scroll storms harmless. Combined with cached
images, scrolling work is constant regardless of catalog size.

**Files:** `lib/presentation/screens/feed/product_feed_screen.dart`,
`docs/PERFORMANCE.md`

### 47. How is image memory controlled?

**Simple:** `cached_network_image` with `memCacheWidth` sized to the render
target: 500 for grid cards, 220 for list thumbnails, 800 for the gallery.

**Deeper:** A 600×600 image decodes to ~1.4 MB of bitmap; a grid of six
~1.4 MB bitmaps is ~8 MB pinned, growing with scroll. `memCacheWidth` makes
the decoder downscale *at decode time* to the rendered size, so the memory
profile stays flat; the disk cache eliminates refetching on scroll-back;
placeholders are flat `ColoredBox`es (no layout thrash) with icon error
widgets for offline.

**Files:** `lib/presentation/widgets/product_card.dart`,
`lib/presentation/screens/product/product_detail_screen.dart`

### 48. Where does rebuild cost get minimized?

**Simple:** `const` widgets everywhere, `select()`-scoped watches, and
autoDisposing screen-scoped providers.

**Deeper:** Const canonicalizes instances (zero-allocation rebuilds, and
the framework can skip identical subtrees); `select` turns an O(cards)
favorite-toggle rebuild into O(1); autoDispose returns memory when screens
close. Skeletons are fully const, including their layout.

**Files:** `lib/presentation/widgets/skeleton.dart`,
`lib/presentation/widgets/favorite_button.dart`

### 49. How is *perceived* performance handled?

**Simple:** Layout-matching skeletons instead of spinners; instant query
text; optimistic hearts; instant cart badge.

**Deeper:** `SkeletonProductCard` mirrors the real card's structure so the
user sees where content lands; the test asserts the *absence* of a
`CircularProgressIndicator`. Search updates the field text on every
keystroke while only committing the network call after 300 ms. Favorites
flip the heart in the same frame as the tap. All four states (loading,
empty, error, data) are designed, not accidental — each screen renders the
full table.

**Files:** `lib/presentation/widgets/skeleton.dart`,
`test/widget/product_feed_screen_test.dart`

---

## L. Accessibility (2 questions)

### 50. How do you *prove* the 48 dp touch target?

**Simple:** A widget test walks the semantics tree and asserts the
accessible tap rectangle is ≥ 48×48.

**Deeper:** `product_card_test.dart` finds the node labeled "…to
favorites" via `renderViews.first.owner?.semanticsOwner?.rootSemanticsNode`
(non-deprecated access) and `visitChildren`, then checks `node.rect` — the
*semantics geometry* (Material pads the 40 dp icon to 48 dp), not the
visual size. Decorations (the discount badge) are excluded from the a11y
tree entirely.

**Files:** `test/widget/product_card_test.dart`,
`lib/presentation/widgets/favorite_button.dart`

### 51. How do screen readers experience errors, loading and large text?

**Simple:** Live regions announce the login error banner, checkout
banners, and skeletons ("Loading" once); validation renders as `errorText`;
2.0× text never overflows.

**Deeper:** `SkeletonAnnouncer` wraps skeleton areas in a polite live
region while `ExcludeSemantics` hides the blocks — one announcement, not
gray-rectangle spam. Forms use autofill hints (`email`, `password`, full
address set) for password managers. The 2.0× strategy is structural: the
card's image is the `Expanded` element, texts wrap/ellipsize, screens
scroll — verified by the 360 dp / `TextScaler.linear(2.0)` no-overflow
tests. The password reveal stays visible while fixing a failing
validation, a small but real detail.

**Files:** `lib/presentation/widgets/skeleton.dart`,
`lib/presentation/widgets/app_text_form_field.dart`,
`test/widget/login_screen_test.dart`, `docs/ACCESSIBILITY.md`

---

## M. Architecture & errors (3 questions)

### 52. Describe the layering and its dependency rule.

**Simple:** presentation → application/state → domain ← data, with
networking/error/config in `core/` consumed by data only; domain imports
nothing outward.

**Deeper:** Entities are pure Dart with value semantics; repository
interfaces live in domain, implementations in data (`_guard` converts every
failure to `AppException`); screens never import Dio, JSON or storage keys.
The consequence: the mock→production swap is one provider override, and
test fakes implement domain interfaces directly.

**Files:** `docs/ARCHITECTURE.md`, `lib/domain/`, `lib/data/repositories/`

### 53. What does the AppException hierarchy give you?

**Simple:** One sealed type per failure class, each with a user-safe
`message`, optional machine `code`, `cause` and `stackTrace` for logging.

**Deeper:** `Validation` carries field→messages for inline form errors;
`Conflict` carries the out-of-stock product ids; `Cancelled` exists so
superseded searches aren't rendered as errors; `Server` keeps the status
code. Widgets render `exception.message` — never `toString()` — and since
the class is sealed, exhaustive switches are compiler-checked.

**Files:** `lib/core/errors/app_exception.dart`

### 54. Why do widgets never see raw error text?

**Simple:** The repository layer is a boundary: `_guard` maps everything
through `ErrorMapper` before it can escape.

**Deeper:** Backend messages are surfaced *only* because the mock backend
guarantees they're user-safe (the contract is documented in the server
class); otherwise the typed fallback copy wins. This is the pipeline that
turns "DioException: connection timeout …" into "The server is taking too
long to respond. Please try again." — and it's covered by 26 mapper tests.

**Files:** `lib/data/repositories/product_repository_impl.dart`
(`_guard`), `lib/core/errors/error_mapper.dart`

---

## N. Routing (2 questions)

### 55. How does the auth redirect work?

**Simple:** A `GoRouter.redirect` runs on every navigation: restoring →
splash, unauthenticated → `/login`, authenticated arriving on auth/splash
routes → `/shop`.

**Deeper:** The subtle part is *when* it re-runs: `refreshListenable` is an
`_AuthRefresh` ChangeNotifier listening to `authControllerProvider` that
notifies **only when the resolved value changes** — the transient
`AsyncLoading` frames during a login request must not rebuild the navigator
mid-interaction. `auth.isLoading || auth.hasError` (restore in flight or
failed) holds the user on splash, which renders progress then an error +
retry.

**Files:** `lib/presentation/router/app_router.dart`

### 56. Why a StatefulShellRoute instead of five pushed routes?

**Simple:** Tabs must preserve their state (scroll position, loaded feed)
when the user switches — `StatefulShellRoute.indexedStack` keeps each
branch alive in an IndexedStack.

**Deeper:** Five branches (shop, categories, favorites, cart, profile) each
own a navigator; detail/checkout routes declare the root navigator key so
they cover the tab bar. This also composes with keepAlive policy: global
providers survive tab switches while screen-scoped providers dispose with
their branch's lifecycle. Product detail passes the tapped `Product` as
`extra` for an instant first frame before the fetch.

**Files:** `lib/presentation/router/app_router.dart`,
`lib/presentation/screens/shell/home_shell.dart`

---

## O. Release & CI (1 question)

### 57. How is the Android release built, and what does CI enforce?

**Simple:** One universal 3-ABI APK (`flutter build apk --release
--target-platform android-arm,android-arm64,android-x64`) plus an AAB; CI
runs format-check → analyze → all 215 tests on push/PR to main.

**Simple→details:** Universal (not arm64-only, not split-per-abi) because
the main artifact must install on any device and be shareable as one file;
ABIs verified post-build with `unzip -l … | grep lib/`. Signing is honestly
documented: debug-signed here (no upload keystore in the environment),
with the real key.properties/gradle recipe documented for Play. The
workflow pins Flutter 3.47.5 stable with cache. iOS is documented as
scaffolded but **not verified** (Linux, no Xcode) — no false claims.

**Files:** `docs/RELEASE.md`, `.github/workflows/flutter_ci.yml`
