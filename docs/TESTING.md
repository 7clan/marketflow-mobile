# Testing

**215 tests, all passing** (`flutter test`, ~30 s on this machine). The suite
is organized as a pyramid weighted toward the seams where this codebase
actually produced bugs: transport error mapping, controller state
transitions (pagination, debounce, optimistic updates, restore races) and
screen state rendering.

```
test/
  core/         4 files,  74 tests   pure units: error mapping, validators,
                                     debouncer, formatters
  data/         5 files,  63 tests   models + repositories over REAL HTTP
  state/        6 files,  55 tests   Riverpod controllers over REAL HTTP
  widget/       5 files,  22 tests   screens/widgets with FAKE repositories
  integration/  1 file,    1 test    golden path over the full real stack
  helpers/      3 files             app_container, fake_repositories, mock_api
```

## Group-by-group map

### `test/core/` — pure units (74 tests)

| File | Tests | Proves |
| --- | --- | --- |
| `error_mapper_test.dart` | 26 | every `DioException` shape (timeout ×3, connection error, cancel, bad certificate, unknown-wrapping-cause) and every status (400/401/403/404/409/422/500/503/3xx) maps to the right `AppException`; `AppException`s pass through; `FormatException`/`TypeError` → `MalformedResponseException`; non-map error bodies tolerated |
| `validators_test.dart` | 33 | email/phone/zip/name/street/city/state/password acceptance **and rejection** tables (e.g. plus-addressing accepted; semicolons in names rejected) |
| `formatters_test.dart` | 9 | currency (whole/fractional/thousands), compact K/M suffixes, `MMM d, yyyy`, 12-hour clock |
| `debouncer_test.dart` | 6 | fires once after the quiet period; reschedules before firing; cancel drops the pending action; different delays honored |

These are pure functions — no mocks, no IO, exhaustive tables.

### `test/data/` — models + repositories over real HTTP (63 tests)

| File | Tests | Proves |
| --- | --- | --- |
| `product_model_test.dart` | 15 | tolerant `fromJson` (numeric strings coerced, nullable `compareAtPrice`, string booleans) and strict failures (non-numeric price, non-string image entries → `MalformedResponseException`); `fromDomain → toDomain` round-trips |
| `product_repository_test.dart` | 17 | page 1 = first 20 of 66; page 2 is a different slice; final page remainder + `hasMore: false`; every filter param (category, price bounds, inStock hides zero-stock/unavailable, unknown term → empty); every sort order (priceAsc/Desc, rating, newest); single product fetch; 404 → `NotFoundException`; **timeout** (latency raised above `receiveTimeout`) → `TimeoutException`; **malformed 200** → `MalformedResponseException` |
| `auth_repository_test.dart` | 10 | login persists the session and emits through `userChanges`; unknown email → `UnauthorizedException`; register creates an account; duplicate email → `ValidationException` with field errors; `restoreSession` verifies via `/auth/me`, **clears the session on 401** (the raw-DioException bug), returns null when nothing stored; logout clears; the 6 seeded categories with counts |
| `order_repository_test.dart` | 12 | checkout creates a **pending** order with server-priced totals; **stock decrements server-side**; empty cart / invalid address → `ValidationException`; out-of-stock → `ConflictException` with the ids; order list is **newest-first**; single order by id; unknown order → `NotFoundException`; the demo account's 2 seeded orders |
| `cart_local_data_source_test.dart` | 9 | cart JSON under `marketflow.cart`; single corrupt entry skipped, not fatal; non-array payload → `CacheException`; save/load/clear contract mirrored by the in-memory double |

Mechanics: `test/helpers/mock_api.dart` starts a **real**
`MockMarketplaceServer` with latency zeroed and hands back a wired
`ApiClient` (`startMockApi()`); failures are injected by mutating
`server.conditions` per test.

### `test/state/` — controllers over real HTTP (55 tests)

| File | Tests | Proves |
| --- | --- | --- |
| `auth_controller_test.dart` | 8 | cold start unauthenticated; login → `AuthAuthenticated` + persisted `tok-demo-1`; failed login stays unauthenticated and **rethrows**; logout clears; persisted session restored on startup; **expired (rejected) token signs out instead of erroring**; `userChanges` mirror; `user`/`isAuthenticated` extension reads |
| `product_feed_controller_test.dart` | 10 | page 1 loads 20 of 66; `loadNextPage` appends without repeats; stops at last page; refresh resets to page 1; filter change re-runs page 1 narrowed; sort change re-orders; failed load-more **keeps the list** and surfaces the error; **stale load-more response (filter changed mid-flight) is discarded** |
| `cart_controller_test.dart` | 16 | dedupe on add; per-order max 99 clamp with message; stock clamp with message; `updateQuantity` clamps / removes at ≤ 0; out-of-stock never added; every mutation persists; pre-populated storage restores on startup; **storage restoring an empty cart leaves state empty**; empty cart zero totals; free shipping ≥ 99; clear empties + removes persisted cart |
| `favorites_controller_test.dart` | 10 | sign-in syncs ids; **failed add rolls back**; failed remove rolls back; failed sync keeps previous ids + surfaces error; signed-out cold start shows no cached ids; signing out clears ids; caching is idempotent; sync twice idempotent |
| `search_controller_test.dart` | 5 | empty query resets to idle **without a network call** (`handledRequestCount` assertions); debounced commit; failed search surfaces error and refresh recovers; **clearing mid-debounce cancels the pending search entirely** |
| `checkout_controller_test.dart` | 6 | invalid address blocks with per-field errors; valid address advances to review; empty cart → failure; successful checkout creates a pending order, clears the cart, and the order **immediately appears in history**; retry path; `backToEditing` clears errors |

Mechanics: `test/helpers/app_container.dart` `createTestApp()` — the exact
`main()` wiring (host + in-memory session/cart/favorites seams) as an
injectable `ProviderContainer`; zero server latency; a `settle()` helper
(`Future.delayed(60ms)`) flushes `unawaited(...)` background work; Riverpod's
provider auto-retry is controllable per test.

### `test/widget/` — screens with fakes (22 tests)

| File | Tests | Proves |
| --- | --- | --- |
| `login_screen_test.dart` | 6 | empty submit → per-field inline `errorText`; malformed email rejected inline; **wrong credentials surface a mapped error banner**; the banner **is exposed to assistive technology** (live region); fields + submit expose semantics; password field obscured with a labeled toggle |
| `product_card_test.dart` | 6 | renders title/price/rating/compare-at/discount badge; **one a11y label covering the card tap target**; heart toggle is optimistic (fills instantly, `addCalls`/`removeCalls` recorded); **the favorite button meets the 48 dp touch target** (semantics-geometry walk); no overflow at 360 dp; **no overflow at 2.0× text scale** |
| `cart_screen_test.dart` | 4 | renders line/title/unit/quantity/totals; stepper + at 1 stays disabled / − tap increments; validation messages render inline; empty cart shows the empty view, not the checkout button |
| `product_feed_screen_test.dart` | 2 | first page renders **skeleton cards, not a spinner** (gated `Completer` holds page 1 in flight); completing the load swaps skeletons for real products; the skeleton area announces "Loading" once |
| `error_view_test.dart` | 4 | title/message/retry render; retry tap invokes the callback once; retry hidden without a callback; **the message is exposed to assistive technology** |

Mechanics: `test/helpers/fake_repositories.dart` — complete in-memory
repository fakes with call counters and `Completer` gates; widget tests pump
`UncontrolledProviderScope` + `MaterialApp`. **No sockets anywhere here** —
see the zone lesson below for why.

### `test/integration/golden_path_test.dart` — 1 test

The complete application pipeline against the **real** in-process backend,
the **real** Dio pipeline and the real repositories:
session restore → login → feed (66 items) → pagination (40 items) → category
filter → debounced search ("wireless", earbuds \$124.15) → add 2 × earbuds
(subtotal \$248.30, free shipping, 8.5 % tax, **total \$269.41**) → cart
persistence → empty-address rejection → valid checkout → **pending order in
history below the 2 seeded ones**. Every controller method invoked is exactly
the one the corresponding screen's button tap calls — widget-level rendering
stays covered by the widget tests, so the two groups together cover the full
stack.

## The fake-async zone lesson (the most important thing in this file)

`testWidgets` runs inside a **fake-async zone**. Real sockets do not work
there:

1. `Future.delayed` never fires unless time is advanced;
2. more subtly — an `HttpClient`/Dio instance **created inside the fake zone
   never completes a real socket round-trip** (probes showed requests hanging
   or answering empty 400s, while the same POST ran fine from a real zone).
   A socket must be created, connected and awaited within one real zone.

The integration test therefore runs as a **plain `test()` in the real zone**
— its docstring records exactly this decision:

> "This test deliberately runs as a plain `test` (real async zone):
> `testWidgets` executes in a fake-async zone where real sockets created
> from that zone never deliver responses (an HttpClient must be created,
> connected and awaited within one real zone — the reason widget tests
> override repositories with fakes)."
> — `test/integration/golden_path_test.dart`

Consequences, applied consistently across the suite:

- **Real-HTTP tests** (data, state, integration) → plain `test()` + real
  awaits; background work is flushed with small real delays.
- **Widget tests** (which need the fake-async pump machinery) → repository
  fakes, never real sockets.
- The zone boundary is where earlier agents repeatedly hit a wall
  (empty 400s / hangs); root-causing it once and encoding it in the test
  docstring + this document is what keeps future tests green by design.

### The settle pattern (history)

Async-by-fire-and-forget code (cart persist, favorites cache writes, the
auth stream mirror) completes *after* the awaited call returns. Three
conventions evolved:

- State tests: `TestAppScope.settle()` — `Future.delayed(60ms)` with server
  latency zeroed;
- Integration test: explicit delays at the three fire-and-forget points
  (50 ms for the `userChanges` mirror, 200 ms for the cart persist, 800 ms
  for the 300 ms debounce + request);
- Widget tests: `await tester.pump()` + `pump(Duration(milliseconds: 120))`
  pairs after taps (Dio delivers through zone timers even against fakes in
  fake-async).

## The four bugs the suite caught

See [ARCHITECTURE.md](ARCHITECTURE.md#the-four-real-bugs-the-test-suite-caught)
for the full table. In short: raw Dio 401 during session restore (`29e1aa2`),
provider-cycle deadlock on 401 mid-restore (`be23db5`), favorites stale
notifier writes after rebuild (`9226ccb`), cart async restore clobbering a
mid-restore mutation (`2f24900`). Two of the four are concurrency bugs that
only reproduce when real network timing meets real provider lifecycles —
which is exactly why the repositories are tested over real HTTP instead of
fakes wherever possible.

## Running

```bash
flutter test             # all 215
flutter test test/state  # one group
flutter test --plain-name "the favorite button meets the 48dp touch target"
```

Gates (also enforced in CI, `.github/workflows/flutter_ci.yml`):
`dart format --output=none --set-exit-if-changed .` → `flutter analyze`
(0 issues) → `flutter test` (215/215).
