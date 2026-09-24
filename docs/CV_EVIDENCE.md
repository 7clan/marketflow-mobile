# CV Evidence

Only claims backed by files and tests in **this repository**. Anything not
yet verified is marked as such — no fabrication.

## Verified technologies (with evidence)

| Technology | Evidence |
| --- | --- |
| Flutter 3.47.5 / Dart 3.13.4, Material 3 | `pubspec.yaml`, `lib/core/theme/app_theme.dart` (light+dark), 15 screens |
| Riverpod 3 (`flutter_riverpod` 3.4.3) | 14 provider files: `AsyncNotifierProvider` (auth, feed, orders), `NotifierProvider` (8 controllers), `FutureProvider.autoDispose(.family)`, `select` scoping, keepAlive policy, test overrides |
| Dio 5.11.1 | `lib/core/network/api_client.dart`, `auth_interceptor.dart` (bearer injection, 401 expiry reporting), `CancelToken` cancellation, 8 s/12 s/10 s timeouts |
| GoRouter 16 | `lib/presentation/router/app_router.dart`: `StatefulShellRoute.indexedStack` 5-branch shell, auth redirect, root-navigator detail routes |
| `flutter_secure_storage` | `lib/data/datasources/secure_session_local_data_source.dart` (token + user, in-memory mirror, corrupt-data safety) |
| `SharedPreferences` | cart (`marketflow.cart`), favorites id cache, recent searches, theme mode — all in `lib/data/datasources/` |
| `cached_network_image` | `product_card.dart` (`memCacheWidth: 500`), detail gallery (800), line thumbnails (220) |
| `intl` | `lib/core/utils/formatters.dart` (currency, compact, dates) — 9 tests |
| GitHub Actions CI | `.github/workflows/flutter_ci.yml`: format gate + analyze + tests, Flutter pinned 3.47.5 |

## Verified features

- Auth: login/register/restore/logout, server-verified session restore
  (`GET /auth/me`), auto sign-out on token expiry.
- Feed: pagination (20/page), infinite scroll with 600 px pre-load,
  pull-to-refresh, skeletons, in-list retry footer.
- Search: 300 ms debounce, request cancellation, stale-response guard,
  persisted recent searches (cap 8).
- Filters/sorting: category, price range, in-stock-only, 5 sort orders.
- Favorites: optimistic toggle with rollback + user-visible reason,
  cold-start cache hydration, snapshot-based tab list.
- Cart: dedupe, stock/max clamps with inline messages, derived totals
  (free shipping ≥ \$99, 8.5 % tax), persistence, safe async restore.
- Checkout: 3-step state machine, local + server field validation on the
  same keys, 409 out-of-stock handling, retry.
- Orders: history + detail; checkout decrements server stock.
- Error handling: sealed `AppException` taxonomy, single `ErrorMapper`
  pipeline, user-safe copy end to end.
- Accessibility: 48 dp targets (semantics-geometry test), live regions,
  `errorText` validation, autofill hints, 2.0× text-scale no-overflow
  tests.

## Architecture (verified)

- Layered: `presentation (89-file tree under lib/) → providers → domain
  (pure entities + 5 interfaces) ← data (models/datasources/repositories)`,
  with `core/` networking consumed by data only.
- In-process deterministic HTTP backend (real `dart:io` `HttpServer`,
  ephemeral loopback port, seeded catalog 66 products / 6 categories,
  failure injection via `BackendConditions`) — production swap is one
  `AppConfig` override.
- 4 real bugs found by the test suite and fixed with dedicated commits:
  raw Dio 401 during session restore (`29e1aa2`), provider-cycle deadlock
  on 401 (`be23db5`), favorites stale notifier writes (`9226ccb`), cart
  async restore clobbering (`2f24900`).

## Tests (verified)

**215 passing** (`flutter test`): core 4 files / 74 tests, data 5 / 63,
state 6 / 55, widget 5 / 22, integration 1 golden-path test
(login → feed → pagination → filter → search → cart → checkout → order
history over the real HTTP stack, asserting deterministic totals
\$248.30 / \$269.41). `flutter analyze`: 0 issues. `dart format`: clean.

## Accessibility & performance (verified)

Semantics-geometry 48 dp assertion, live-region assertions, combined card
labels, 360 dp + `TextScaler.linear(2.0)` overflow tests — all in
`test/widget/`. Lazy builder lists, decode-width-controlled image caching,
`select` rebuild scoping, request-sequence stale protection, derived
totals — detailed with file references in `docs/PERFORMANCE.md`.

## Release / build status

- **Verified:** release process documented (`docs/RELEASE.md`): universal
  3-ABI APK command, AAB, ABI verification, NDK requirement, signing
  reality (debug-signed artifacts here; real keystore recipe documented),
  versioning.
- **Pending verification (marked as such, not claimed):** the actual
  `flutter build apk/appbundle` run for this repo —
  `docs/RELEASE.md` § "Build verification log" is intentionally empty
  until the orchestrator appends real command output. iOS: scaffolded,
  **not verified** (Linux; requires macOS/Xcode/signing).

## Known limitations (say these in interviews — credibility)

- No real backend integration (mock server is deterministic and
  in-process; the swap seam is designed and documented but not exercised
  against production infra).
- No golden-image tests; no real TalkBack/VoiceOver session recordings.
- English-only strings (no localization).
- iOS not built or run; Android release artifacts debug-signed; build log
  pending.
- No code generation for models — deliberate, tested tolerant `fromJson`
  instead.

## CV bullets (pick 3–6)

- Built **MarketFlow**, a production-style Flutter marketplace app (feed
  with pagination/filters/sorting, debounced search, favorites, cart,
  checkout, orders) over a layered domain/data/presentation architecture
  with a deterministic in-process HTTP backend — 89 source files,
  **215 automated tests** (unit/repository/state/widget/integration),
  analyzer-clean, CI-gated.
- Implemented **Riverpod 3 state management with concurrency safety**:
  request-sequence stale-response protection, debounced + cancellable
  search (CancelToken), optimistic favorites with rollback, and an
  async-restore race fix — each guarded by regression tests.
- Designed a **typed error pipeline** (Dio interceptor → single
  `ErrorMapper` → sealed `AppException` hierarchy → user-safe messages,
  inline 422 field errors, 409 conflict ids) verified by 26 mapping tests
  against a real HTTP server with injected timeouts, 5xx and malformed
  bodies.
- Found and fixed **four real concurrency bugs via the test suite**
  (session-restore 401 escape, provider-cycle deadlock, stale notifier
  writes, cart restore clobbering) — evidence of tests written to catch
  defects, not decorate coverage.
- Enforced **accessibility as a test contract**: semantics-geometry 48 dp
  assertions, live regions for errors/loading, autofill-ready forms, and
  2.0× text-scale no-overflow checks across the widget suite.
- Optimized **list and image performance** for a 66-product remote-image
  catalog: lazy builder grids, server-side pagination, decode-width
  controlled `cached_network_image` caching, `select`-scoped rebuilds —
  each technique documented with its rationale.
