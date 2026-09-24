# Performance

Every technique below is in the shipped code with the file to prove it, and
each has a concrete reason it matters on a mid-range Android device. The
guiding constraints: 66 products with 600×600 remote images, 20 items per
feed page, and a mock network that injects 150–300 ms latency by default —
which makes every one of these optimizations *observable* while developing.

## Techniques

### 1. Lazy builder lists — only visible cells build

`lib/presentation/screens/feed/product_feed_screen.dart` renders the feed as
`SliverGrid.builder` (2 columns); search, favorites, cart, categories and
orders all use `ListView.builder` / `ListView.separated`
(`search_screen.dart:130`, `favorites_screen.dart:94`, `cart_screen.dart:63`,
`categories_screen.dart:55`, `orders_screen.dart:62`).

**Why it matters:** a builder constructs a widget only when it scrolls into
the viewport. The 66-product catalog never builds 33 cards up front —
`product_feed_screen_test.dart` proves the laziness ("the grid is lazy: only
the visible cells build"). Without builders, jank scales with catalog size;
with them it stays constant.

### 2. Pagination — bounded DOM/state per query

The feed requests 20 items per page (`AppConfig.pageSize = 20`) and appends
via `ProductFeedController.loadNextPage()`, triggered 600 px before the list
end (`_preloadExtent = 600.0` in a `NotificationListener<ScrollNotification>`).

**Why it matters:** first paint waits for 20 items, not 66; the memory
footprint of the items list grows only as the user actually scrolls; and
`totalItems` comes from the server so the footer can show an end-of-catalog
marker. `loadNextPage` also guards (`!hasMore`, `isLoadingMore`) so scroll
storms never duplicate requests.

### 3. 300 ms search debounce + request cancellation — fewer, fresher queries

`lib/presentation/providers/search_controller.dart`:
`Debouncer(delay: 300ms)` commits the search only after typing quiets down;
each new commit **cancels the superseded request** via `CancelToken.cancel()`
and bumping `_requestSeq`; superseded responses drop themselves even if the
cancel arrives too late.

**Why it matters (two effects):** (a) typing "wireless" fires **one** network
request instead of seven — `search_controller_test.dart` asserts this with
the server's `handledRequestCount`; (b) cancellation plus the sequence guard
means a slow response for "wir" can never overwrite the results for
"wireless" (stale-response protection). The query text itself updates
instantly on every keystroke, so the field still feels live.

### 4. `cached_network_image` with decode-width control — bounded image memory

`ProductCard` (`lib/presentation/widgets/product_card.dart:46`) loads images
with `memCacheWidth: 500`; line thumbnails use 220
(`cart_screen.dart:115`, `favorites_screen.dart:201`,
`search_screen.dart:167`); the detail gallery uses 800
(`product_detail_screen.dart:318`).

**Why it matters:** a 600×600 JPEG decodes to a 600×600×4-byte bitmap
(~1.4 MB) per image. A 2-column grid showing ~6 cards would pin ~8+ MB of
decoded images in memory — and cached_network_image's disk cache means none
of them refetch on scroll-back. `memCacheWidth: 500` makes the decoder
downscale at decode time, cutting the bitmap to the size actually rendered
(~500 device pixels per cell). Memory stays flat no matter how far the user
scrolls. Placeholder and error widgets (a flat `ColoredBox` / an icon) keep
scrolling smooth while images arrive over the 150–300 ms mock latency.

### 5. `const` widgets — canonicalized instances

`const` is used pervasively — every static decoration, paddings, skeleton
layouts (`skeleton.dart` is fully `const`), footer variants, navigation
destinations (`home_shell.dart`).

**Why it matters:** identical `const` widgets share one canonical instance —
no rebuild allocations, and the framework can skip identical-subtree
rebuilds. On a scrolling grid this is the difference between GC churn per
frame and none.

### 6. Riverpod rebuild scoping (`select`) — one heart per toggle

`FavoriteButton` (`lib/presentation/widgets/favorite_button.dart`) watches
only the membership bit:

```dart
ref.watch(favoritesControllerProvider.select((state) => state.isFavorite(product.id)));
```

`HomeShell` watches only the badge count
(`cartControllerProvider.select((state) => state.itemCount)`); the feed's
favorite-rollback listener selects only `state.error`;
`favoriteProductsProvider` watches only the favorites *ids*.

**Why it matters:** without `select`, every favorite toggle would rebuild
**every** heart on screen (all watch the same provider). With it, exactly
the one toggled card rebuilds. Ditto: adding one cart item rebuilds the
badge, not the whole shell.

### 7. Persisted favorites cache — instant cold start

`FavoritesController._hydrateFromCache()` reads the locally cached favorite
id set (`SharedPreferencesFavoritesCache`) and renders hearts immediately;
the authoritative server sync happens in the background after sign-in.

**Why it matters:** the feed shows correct heart states on the first frame
after login, instead of a spinner-then-flash. The cache is an optimization —
a `CacheException` is swallowed, never fatal (documented in the controller).

### 8. Request-sequence stale protection — correct data under latency

`ProductFeedController._requestSeq` / `SearchController._requestSeq`
increment on every restart; in-flight results compare their captured seq and
drop themselves when superseded.

**Why it matters:** with 150–300 ms per request, a filter change mid-flight
is *normal*, not exceptional. Without the guard, page 2 of "all products"
would append itself into the filtered result list and corrupt ordering —
`product_feed_controller_test.dart` has the exact regression test ("a stale
load-more response (filter changed mid-flight) is discarded").

### 9. Skeletons, not spinners — perceived performance

Feed/categories/search/products load with layout-matching skeletons
(`SkeletonProductCard` mirrors `ProductCard`: image block + 2 title lines +
rating/price rows) driven by one pulse animation per visible tree.

**Why it matters:** skeletons communicate *where* content will appear,
reducing perceived latency versus a blocking centered spinner
(`product_feed_screen_test.dart` asserts the spinner is absent). One
`AnimationController` per skeleton tree (900 ms opacity pulse) keeps the
animation cheap.

### 10. Derived totals, frozen line prices — zero recomputation divergence

Cart totals are always computed by the pure function
`computeCartTotals(items)` (`lib/domain/entities/cart_totals.dart`), and cart
line prices are frozen at add-time (`per-line prices are frozen at add time`
— `cart_controller_test.dart`). The mock server recomputes order totals with
the same function.

**Why it matters:** no stored totals can drift out of sync with the items;
cart, checkout review and the recorded order show identical numbers by
construction (integration test asserts 248.30 / 0 / 21.11-equivalent tax /
269.41 end-to-end).

### 11. Fire-and-forget persistence off the interaction path

Cart mutations update state synchronously and persist via
`unawaited(_persist(...))`; recent searches and theme likewise. The UI never
awaits storage.

**Why it matters:** add-to-cart and stepper taps render on the same frame —
SharedPreferences IO never blocks the interaction. Failure is surfaced as
`CartState.error` rather than reverting correct in-memory state.

### 12. Auto-disposed screen-scoped providers — memory returns when unused

`categoriesProvider`, `productDetailProvider`, `orderDetailProvider` are
`FutureProvider.autoDispose(.family)` — the feed keeps no product cache, so
leaving a detail screen frees its payload.

**Why it matters:** browsing 20 product details doesn't accumulate 20
deserialized products; category data doesn't sit in memory while the user
shops.

## Deliberately not done (honesty section)

- **No HTTP response caching layer** — the mock backend is local and
  deterministic; adding one would be complexity without observable benefit.
  The repository seam is where it would go.
- **No `RepaintBoundary` tuning / no golden-frame profiling** — the catalog
  size (66 items, grid of ~0.72 aspect cards) doesn't show measurable
  overdraw in practice; flagging it here rather than pretending.
- **No image preloading beyond the 600 px scroll pre-load** — feed page
  requests are prefetched ahead of the viewport, but image bytes are not;
  `cached_network_image` placeholders cover that gap.
