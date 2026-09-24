# MarketFlow

A Flutter marketplace app — product feed, categories, search, favorites, cart,
checkout and order history — engineered like a production client: layered
architecture, Riverpod 3 state, a real Dio HTTP pipeline against a
deterministic in-process backend, typed error mapping, accessibility contracts
enforced by tests, and a 215-test suite that caught four real bugs before
release.

**Verified status:** 215/215 tests passing · `flutter analyze` 0 issues ·
`dart format` clean · Flutter 3.47.5 / Dart 3.13.4 · CI on GitHub Actions.

[![Flutter CI](https://github.com/7clan/marketflow-mobile/actions/workflows/flutter_ci.yml/badge.svg)](https://github.com/7clan/marketflow-mobile/actions/workflows/flutter_ci.yml)

## Features

- **Authentication** — login, register, splash session-restore (verified
  server-side via `GET /auth/me`), automatic sign-out on token expiry, secure
  token storage (`flutter_secure_storage`).
- **Product feed** — paginated grid (20 items/page), infinite scroll with
  600 px pre-load, pull-to-refresh, skeleton loading, in-list retry footer for
  failed page loads.
- **Categories** — 6 seeded categories with live product counts.
- **Search** — 300 ms debounced, cancels the superseded request via
  `CancelToken`, stale-response protection, recent searches (persisted).
- **Filters & sorting** — category, price range, in-stock-only, plus 5 sort
  orders (relevance, newest, price ↑/↓, rating); every change re-runs page 1.
- **Product detail** — image gallery, ratings, stock state, quantity stepper
  bounded by stock.
- **Favorites** — optimistic add/remove with automatic rollback and a
  user-visible reason on failure; instant cold-start from a local id cache.
- **Cart** — deduped lines, per-line stock clamps ("Only 3 left in stock"),
  derived totals (free shipping ≥ \$99, 8.5 % tax), persisted to
  `SharedPreferences`, safe async restore.
- **Checkout** — 3-step state machine (address → review → placed) with local +
  server field validation mapped onto the same form fields, 409 out-of-stock
  conflicts, retry.
- **Orders** — history with statuses and detail views; successful checkout
  decrements server stock.
- **UX quality** — Material 3 light/dark themes, polished empty and error
  states, 48 dp touch targets, live regions, 2.0× text-scale-safe layouts.

## Stack

| Concern | Choice | Why |
| --- | --- | --- |
| State / DI | `flutter_riverpod` 3.4.3 | compile-safe providers, `AsyncNotifier`, rebuild scoping via `select`, trivial test overrides |
| Navigation | `go_router` 16 | declarative routes, `StatefulShellRoute` 5-tab shell, auth redirect |
| Networking | `dio` 5.11.1 | interceptors (auth, 401 session expiry), timeouts, `CancelToken`, typed errors |
| Backend | in-process `HttpServer` (`MockMarketplaceServer`) | real HTTP over loopback — timeouts/interceptors/cancellation are exercised for real; swap to production = one config override |
| Persistence | `flutter_secure_storage` (session), `SharedPreferences` (cart, favorites cache, recents, theme) | right tool per data sensitivity |
| Images | `cached_network_image` 4.0.2 | disk + memory cache, decode-width control |
| UI | Material 3, `intl` | light/dark, currency/date formatting |

## Architecture (short version)

```
presentation ──► application/state ──► domain ◄── data
(screens/widgets)  (Riverpod providers)  (entities +      (datasources/models/
                                        repository        repositories)
                                        interfaces)
                                              ▲
                    core/network: Dio + ApiClient + AuthInterceptor
                    core/errors:  ErrorMapper → AppException hierarchy
```

Full details, the in-process backend design and the four bugs the test suite
caught: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick start

```bash
flutter pub get
flutter run        # Android emulator / device / Chrome
flutter test       # 215 tests, ~30s
```

No backend to start — the app boots its own deterministic marketplace server
(`lib/data/datasources/mock_marketplace_server.dart`) on an ephemeral
loopback port at startup (`lib/main.dart`).

### Demo account

| Field | Value |
| --- | --- |
| Email | `demo@marketflow.dev` |
| Password | `Password123` |

The seeded demo user (**Dana Mercado**) comes with 3 favorites and 2 historical
orders. The login screen has a **"Use demo account"** button. The catalog is
deterministic: 66 products, 6 categories, fixed prices (e.g. the *Aurora
Wireless Noise-Cancelling Earbuds* always cost **\$124.15**).

### 2-minute demo script

1. Log in with the demo account → the feed loads page 1 (66 items total).
2. Scroll to the bottom → page 2 appends (pagination footer states).
3. Tap the heart on a card → optimistic favorite (instant), then visit the
   Favorites tab.
4. Search "wireless" → debounced results, earbuds at \$124.15.
5. Add 2 × earbuds to the cart → subtotal \$248.30, free shipping, 8.5 % tax,
   total **\$269.41**.
6. Checkout → submit an empty address (inline field errors) → fill it in →
   review → place the order → order history shows the new pending order.

To experience failure states, flip `BackendConditions` on the running server
(forced 500s, malformed JSON, checkout conflicts, latency) — see
[docs/API.md](docs/API.md).

## Documentation

| Document | Contents |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | layers, backend design, error flow, routing, the 4 bugs fixed by tests |
| [docs/STATE_MANAGEMENT.md](docs/STATE_MANAGEMENT.md) | every provider: type, watches, lifecycle, test overrides |
| [docs/API.md](docs/API.md) | full mock protocol: routes, envelopes, status codes, seed facts |
| [docs/TESTING.md](docs/TESTING.md) | the 215-test suite map, the fake-async zone lesson |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | each optimization and why it matters |
| [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md) | semantics, touch targets, text scaling — with the tests that verify them |
| [docs/RELEASE.md](docs/RELEASE.md) | Android universal APK / AAB process, signing, iOS status |
| [docs/AI_WORKFLOW.md](docs/AI_WORKFLOW.md) | AI-assisted development disclosure |
| [docs/INTERVIEW_GUIDE.md](docs/INTERVIEW_GUIDE.md) | 57 questions mapped to real code |
| [docs/CV_EVIDENCE.md](docs/CV_EVIDENCE.md) | verified claims + CV bullets |

## Project layout

```
lib/
  core/           config, errors (AppException + ErrorMapper), network
                  (ApiClient, AuthInterceptor), theme, utils
  domain/         entities + repository interfaces (pure Dart)
  data/           datasources (mock server, secure session, prefs caches),
                  models (tolerant fromJson), repository impls
  presentation/   providers (14 files), router, screens (15), widgets (11)
test/             core/ data/ state/ widget/ integration/ (215 tests)
.github/          CI workflow (format + analyze + test)
```

89 source files, 24 test files (~11.5k lines of app code, ~4.3k lines of
tests).
