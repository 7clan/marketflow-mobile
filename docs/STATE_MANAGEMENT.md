# State Management

All application state is Riverpod 3 (`flutter_riverpod` 3.4.3), in 14 files
under `lib/presentation/providers/`. Widgets hold zero app state — screens are
`ConsumerWidget`/`ConsumerStatefulWidget` that map provider state to UI and
forward user intent to controller methods.

Provider types used and why:

| Type | Used for | Why |
| --- | --- | --- |
| `AsyncNotifierProvider` | auth, feed, orders | async `build()` with loading/error/data states for free |
| `NotifierProvider` | search, filters, favorites, cart, checkout, favorite products, recents, theme | synchronous state, explicit methods |
| `FutureProvider.autoDispose` | categories, product detail, order detail | fire-and-forget reads with no commands |
| `Provider` | config, Dio client, repositories, storage | DI / composition |

## Provider inventory

### Composition root — `lib/presentation/providers/infrastructure_providers.dart`

| Provider | Type | Watches | Notes |
| --- | --- | --- | --- |
| `sharedPreferencesProvider` | `Provider<SharedPreferences>` | — | **must** be overridden in `main()` after `getInstance()`; throws `UnimplementedError` otherwise |
| `mockApiHostProvider` | `Provider<MarketApiHost>` | — | overridden in `main()` with the started host (stopped on scope dispose) |
| `appConfigProvider` | `Provider<AppConfig>` | `mockApiHostProvider` | `AppConfig.localServer(port)`; production override replaces this one provider |
| `sessionLocalDataSourceProvider` | `Provider<SessionLocalDataSource>` | — | `SecureSessionLocalDataSource` in prod; in-memory in tests |
| `apiClientProvider` | `Provider<ApiClient>` | `appConfigProvider`, `sessionLocalDataSourceProvider` | builds Dio with timeouts + `AuthInterceptor` (token from session storage); `ref.onDispose(client.close)` |
| `cartLocalDataSourceProvider` | `Provider<CartLocalDataSource>` | `sharedPreferencesProvider` | SharedPreferences impl in prod |
| `favoritesCacheProvider` | `Provider<FavoritesCache>` | `sharedPreferencesProvider` | id cache |
| `authRepositoryProvider` | `Provider<AuthRepository>` | `apiClientProvider`, `sessionLocalDataSourceProvider` | builds `AuthRepositoryImpl` **and** attaches the session-expiry `InterceptorsWrapper` to the shared Dio (401 + token → `discardLocalSession()`); this wiring lives here — not in `apiClientProvider` — to avoid a provider-initializer cycle that deadlocked session restore (see [ARCHITECTURE.md](ARCHITECTURE.md) bug #2) |
| `productRepositoryProvider` / `favoritesRepositoryProvider` / `cartRepositoryProvider` / `orderRepositoryProvider` | `Provider<…>` | `apiClientProvider` (+ cache / local sources) | thin, all overridable |

### `authControllerProvider` — `AsyncNotifierProvider<AuthController, AuthState>`

`lib/presentation/providers/auth_controller.dart`

- `state` is `AsyncValue<AuthState>` where `AuthState` is a sealed class:
  `AuthAuthenticated(user)` / `AuthUnauthenticated()`.
- `build()`: `ref.keepAlive()` (auth is app-global and must survive losing
  all listeners during navigation); **watches** `authRepositoryProvider`;
  subscribes to the repository's `userChanges` stream and mirrors every
  session transition into state (`ref.onDispose(subscription.cancel)`);
  then `await repository.restoreSession()` and returns the initial state.
- `login`/`register` set `AsyncLoading`, await the repository, and **rethrow**
  `AppException`s to the caller — the login form shows inline field errors /
  a banner; the shared state only tracks the session itself (transitions
  arrive via the stream).
- `logout` clears state to unauthenticated **even when the network call
  fails** (local session is already cleared by the repository).
- `handleSessionExpired()` — called from the auth interceptor path — discards
  the local session; the stream mirrors the sign-out.
- `AuthUserX` extension: `user` / `isAuthenticated` read directly off the
  `AsyncValue`.

### `productFeedProvider` — `AsyncNotifierProvider<ProductFeedController, ProductFeedState>`

`lib/presentation/providers/product_feed_controller.dart`

- **Watches** `filterControllerProvider` — any filter/sort change re-runs
  `build()` (page 1).
- `ProductFeedState`: `items`, `page`, `hasMore`, `totalItems`,
  `isLoadingMore`, `error` (the *load-more* error only — refresh errors
  surface as the provider's `AsyncError` so the screen can show a full-screen
  error while keeping the list on partial failures).
- **Stale-response protection via request sequence number**: `_requestSeq`
  increments on every `build()`; `loadNextPage()` captures `seq` before
  awaiting and drops its own result (`if (seq != _requestSeq) return;`) if a
  filter change landed mid-flight — both on success *and* on error paths.
- `refresh()` = `ref.invalidateSelf(); await future;`.
- `loadNextPage()` guards: no value yet, `!hasMore`, `isLoadingMore` — all
  return early.

### `searchControllerProvider` — `NotifierProvider<SearchController, SearchState>`

`lib/presentation/providers/search_controller.dart`

- `ref.keepAlive()` + `ref.onDispose(_debouncer.dispose)`.
- `onQueryChanged(query)` updates the query **instantly** (field feels live)
  and schedules `_runSearch` through a `Debouncer(delay: 300ms)`.
- `_runSearch`: trims; empty → idle; otherwise cancels the in-flight request
  (`_cancelInFlight()` bumps `_requestSeq` and calls `CancelToken.cancel()`),
  creates a fresh `CancelToken`, captures `seq = ++_requestSeq`, awaits the
  repository, and drops superseded results (`seq != _requestSeq`).
  `CancelledException` is swallowed (a newer query owns the state now);
  other `AppException`s set `error` unless superseded.
- `clear()` cancels debounce + in-flight and resets to idle.
- `SearchState`: `query`, `results`, `isSearching`, `error` + derived
  `hasQuery` / `isEmpty`.

### `filterControllerProvider` — `NotifierProvider<FilterController, FilterState>`

`lib/presentation/providers/filter_controller.dart`

- `ref.keepAlive()` (filters persist while browsing other tabs).
- `FilterState` is a value type (`==`/`hashCode` over category / min / max /
  inStockOnly / sort) with the **sentinel `copyWith`** pattern
  (`static const _unset = Object()`) to distinguish "not provided" from
  "explicitly clear this nullable field".
- Methods: `setCategory`, `setMinPrice`, `setMaxPrice`, `setInStockOnly`,
  `setSort`, `clear`.
- **Rebuild chain:** `FilterState` change → feed `build()` re-runs (watch) →
  new page 1 → old in-flight page request drops itself via `_requestSeq`.

### `favoritesControllerProvider` — `NotifierProvider<FavoritesController, FavoritesState>`

`lib/presentation/providers/favorites_controller.dart`

- `ref.keepAlive()` (heart buttons live on many screens).
- `build()`: hydrates from the local id cache instantly
  (`_hydrateFromCache()`), `ref.listen(authControllerProvider, …)` —
  authenticated → `syncFromServer()`, unauthenticated → clear ids; and
  because a listener never fires for an auth state that *already* existed
  when this controller is first watched (e.g. a session restored during
  splash), it also checks the current value and defers
  `Future.microtask(syncFromServer)` (state may not be set synchronously
  during build).
- `addFavorite` / `removeFavorite`: **optimistic** — apply the id change
  immediately, await the repository, persist the new id set to the cache on
  success; on `AppException` **roll back to the captured `previous` state**
  and surface `error` (the hosting screen announces it via SnackBar).
- Every post-await write is guarded by `ref.mounted` — bug #3
  (stale notifier writes, see [ARCHITECTURE.md](ARCHITECTURE.md)).
- `syncFromServer()` is also the pull-to-refresh action; it re-writes the
  cache from the authoritative list.

### `favoriteProductsProvider` — `NotifierProvider<FavoriteProductsController, List<Product>>`

`lib/presentation/providers/favorite_products_provider.dart`

- **Watches** `favoritesControllerProvider.select((state) => state.ids)` —
  only id-set changes rebuild this provider, nothing else in favorites state.
- Keeps a private snapshot map `Map<String, Product>`; on each build it drops
  snapshots for ids no longer favorited, **fetches only the missing ids in
  parallel** (`Future.wait`), then `_materialize`s the list. Removing and
  re-adding a favorite never refetches the whole list.
- `_fetchMissing` writes state only `if (ref.mounted)`.

### `cartControllerProvider` — `NotifierProvider<CartController, CartState>`

`lib/presentation/providers/cart_controller.dart`

- `ref.keepAlive()` (the shell's cart badge must be alive everywhere).
- `build()`: kicks off `unawaited(_restore())` and returns the empty state —
  the UI renders immediately; restore fills items when storage answers.
- **Restore race fix:** `_restore()` captures `_mutationSeq` before awaiting;
  if any mutation landed mid-restore (`seqAtStart != _mutationSeq`) it drops
  the stale snapshot (the mutation's own persist already re-wrote storage).
  Bug #4 (see [ARCHITECTURE.md](ARCHITECTURE.md)).
- Mutations are **synchronous and optimistic** (local data, no network):
  `addToCart`, `updateQuantity` (≤ 0 removes), `removeItem`, `clear`.
- Quantity bounds: deduped by product, `1..min(stock, 99)`
  (`CartItem.maxQuantity = 99`); clamps set per-line validation messages
  ("Only 3 left in stock." / "Maximum 99 per order.") in
  `CartState.validationMessages`.
- **Derived totals:** `CartState.totals` is a getter computing
  `computeCartTotals(items)` — subtotal, shipping (free ≥ \$99),
  8.5 % tax, total. Totals are *never stored*, so every surface (cart,
  checkout review, order) shows identical numbers from the same items.
- Persistence is fire-and-forget: `_mutate` bumps `_mutationSeq`, sets state,
  and `unawaited(_persist(...))`; a `CacheException` surfaces as
  `CartState.error` without reverting the in-memory cart.

### `checkoutControllerProvider` — `NotifierProvider<CheckoutController, CheckoutState>`

`lib/presentation/providers/checkout_controller.dart`

- **Deliberately no `keepAlive`** — a checkout flow should restart fresh when
  the user re-enters it.
- State machine: `editingAddress → reviewing → submitting → success |
  failure(error, failureStep)` (`CheckoutStep` enum with labels).
- `submitAddress(address)` validates locally with the shared `Validators`;
  invalid fields stay on `editingAddress` with `fieldErrors` keyed to the
  same names the server's 422 uses, so server-side errors land on the same
  form fields.
- `confirmAndPlaceOrder()`: guards (no address → back to form; empty cart →
  failure with a `ValidationException`); on success clears the cart and
  records `orderId`; on `ValidationException` returns to the form with field
  errors; any other `AppException` → `failure` with `failureStep:
  reviewing` (retry re-runs the same submission).
- `retry()` = `confirmAndPlaceOrder()`; `reset()` returns to the clean state.

### `ordersControllerProvider` — `AsyncNotifierProvider<OrdersController, List<Order>>`

`lib/presentation/providers/orders_controller.dart`

- No `keepAlive` — order history is re-fetched whenever the orders screen is
  (re-)entered, so statuses are always fresh; `refresh()` =
  `ref.invalidateSelf(); await future;`.
- `orderDetailProvider` = `FutureProvider.family<Order, String>` — per-id,
  auto-disposed with its listener.

### `categoriesProvider` — `FutureProvider.autoDispose<List<Category>>`

`lib/presentation/providers/categories_provider.dart` — refreshed on each
categories-tab entry; `autoDispose` keeps the payload out of memory when
unused; also feeds category-name lookups in the feed's filter chips.

### `productDetailProvider` — `FutureProvider.autoDispose.family<Product, String>`

`lib/presentation/providers/product_detail_provider.dart` — the feed keeps no
product cache, so leaving the detail screen frees it; unknown ids surface a
mapped `NotFoundException`.

### `recentSearchesProvider` — `NotifierProvider<RecentSearchesController, List<String>>`

`lib/presentation/providers/recent_searches_provider.dart` — `keepAlive`;
watches `sharedPreferencesProvider`; reads `marketflow.recent_searches`;
`add` (front-insert, dedupe, cap 8) / `remove` / `clear`, each persisting
best-effort.

### `themeModeControllerProvider` — `NotifierProvider<ThemeModeController, ThemeMode>`

`lib/presentation/providers/theme_mode_controller.dart` — `keepAlive`;
`marketflow.theme_mode` int index; corrupt/missing values fall back to
`ThemeMode.system`.

## Lifecycle policy summary

| Provider | keepAlive? | Rationale |
| --- | --- | --- |
| auth, cart, favorites, filters, search, recents, theme | **yes** | app-global state that must survive tab switches / losing listeners |
| feed, orders, categories, product detail, order detail, favorite products | **no** (autoDispose/default) | screen-scoped data should be re-fetchable and free memory |
| checkout | **no (on purpose)** | a checkout flow must restart clean |

## Test override patterns

All seams are providers, so tests override providers — never mocks of
singletons. Patterns used in `test/`:

```dart
// Real HTTP, real repositories (state/integration tests, golden path):
container = ProviderContainer(overrides: [
  mockApiHostProvider.overrideWith((ref) => host),        // started host
  sessionLocalDataSourceProvider.overrideWith((ref) => InMemorySessionLocalDataSource()),
  cartLocalDataSourceProvider.overrideWith((ref) => InMemoryCartLocalDataSource()),
  favoritesCacheProvider.overrideWith((ref) => InMemoryFavoritesCache()),
]);

// Fakes (widget tests — no sockets in the fake-async zone):
container = await createFakeRepositoryContainer(          // test/helpers/
  productRepository: FakeProductRepository(products: [...]),
  favoritesRepository: FakeFavoritesRepository(),
);
await tester.pumpWidget(UncontrolledProviderScope(
  container: container,
  child: const MaterialApp(home: ProductFeedScreen()),
));
```

- `FutureProvider.autoDispose` needs a live listener in a bare
  `ProviderContainer` — the integration test holds it with
  `container.listen(categoriesProvider, (_, _) {}, fireImmediately: true)`
  and closes the subscription after reading.
- Fakes are hand-written (`test/helpers/fake_repositories.dart`) with call
  counters (`addCalls`, `removeCalls`) and gates
  (`Completer<void> getProductsGate`) for precise interaction assertions.
- `FakeFavoritesRepository` failures let widget tests prove **optimistic
  rollback**: tap heart → heart fills → repository rejects → heart reverts.

See [TESTING.md](TESTING.md) for the full suite map and the fake-async zone
constraint that dictates these two patterns.
