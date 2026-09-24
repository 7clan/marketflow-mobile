import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/data/datasources/cart_local_data_source.dart';
import 'package:marketflow/data/datasources/favorites_cache.dart';
import 'package:marketflow/data/datasources/market_api_host.dart';
import 'package:marketflow/data/datasources/session_local_data_source.dart';
import 'package:marketflow/domain/entities/address.dart';
import 'package:marketflow/domain/entities/order.dart';
import 'package:marketflow/presentation/providers/auth_controller.dart';
import 'package:marketflow/presentation/providers/cart_controller.dart';
import 'package:marketflow/presentation/providers/categories_provider.dart';
import 'package:marketflow/presentation/providers/checkout_controller.dart';
import 'package:marketflow/presentation/providers/filter_controller.dart';
import 'package:marketflow/presentation/providers/infrastructure_providers.dart';
import 'package:marketflow/presentation/providers/orders_controller.dart';
import 'package:marketflow/presentation/providers/product_feed_controller.dart';
import 'package:marketflow/presentation/providers/search_controller.dart';

/// Golden-path integration test: the COMPLETE application pipeline —
/// session restore → login → product feed → pagination → category filter →
/// debounced search → add to cart → address validation → checkout →
/// placed order → order history — against the REAL in-process HTTP backend
/// through the REAL Dio pipeline and repositories.
///
/// This test deliberately runs as a plain `test` (real async zone):
/// `testWidgets` executes in a fake-async zone where real sockets created
/// from that zone never deliver responses (an HttpClient must be created,
/// connected and awaited within one real zone — the reason widget tests
/// override repositories with fakes). Every controller method invoked here
/// is exactly the one the corresponding screen's button tap calls, so the
/// widget tests + this test together cover the full stack.
void main() {
  late MarketApiHost host;
  late ProviderContainer container;
  late InMemorySessionLocalDataSource sessionLocal;
  late InMemoryCartLocalDataSource cartLocal;
  late InMemoryFavoritesCache favoritesCache;

  setUp(() async {
    host = MarketApiHost();
    host.server.conditions.latencyMinMs = 0;
    host.server.conditions.latencyMaxMs = 0;
    await host.start();
    sessionLocal = InMemorySessionLocalDataSource();
    cartLocal = InMemoryCartLocalDataSource();
    favoritesCache = InMemoryFavoritesCache();
    container = ProviderContainer(
      overrides: [
        mockApiHostProvider.overrideWith((ref) => host),
        sessionLocalDataSourceProvider.overrideWith((ref) => sessionLocal),
        cartLocalDataSourceProvider.overrideWith((ref) => cartLocal),
        favoritesCacheProvider.overrideWith((ref) => favoritesCache),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await host.stop();
  });

  test(
    'demo user logs in, shops, searches, checks out and sees the order',
    () async {
      // ------------------------------------------------------------------
      // 1. Session restore on a cold start finds nothing (unauthenticated).
      // ------------------------------------------------------------------
      final coldState = await container.read(authControllerProvider.future);
      expect(coldState, isA<AuthUnauthenticated>());

      // ------------------------------------------------------------------
      // 2. Sign in with the demo account (the login screen's Sign in
      //    button calls exactly this controller method).
      // ------------------------------------------------------------------
      await container
          .read(authControllerProvider.notifier)
          .login(email: 'demo@marketflow.dev', password: 'Password123');

      // The repository emits the session through its userChanges stream;
      // let the controller's subscription deliver that event.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final authState = container.read(authControllerProvider);
      final authValue = authState.value;
      expect(authValue, isA<AuthAuthenticated>());
      expect(
        (authValue as AuthAuthenticated).user.email,
        'demo@marketflow.dev',
      );
      expect(
        (await sessionLocal.read())?.token,
        'tok-demo-1',
        reason: 'login persisted the session',
      );

      // ------------------------------------------------------------------
      // 3. The feed loads the first page (what the /shop tab renders).
      // ------------------------------------------------------------------
      var feed = await container.read(productFeedProvider.future);
      expect(feed.items, isNotEmpty);
      expect(feed.page, 1);
      expect(
        feed.totalItems,
        66,
        reason: 'the full seeded catalog is reachable',
      );

      // ------------------------------------------------------------------
      // 4. Pagination appends the second page (infinite scroll).
      // ------------------------------------------------------------------
      await container.read(productFeedProvider.notifier).loadNextPage();
      feed = container.read(productFeedProvider).value!;
      expect(feed.page, 2);
      expect(
        feed.items.length,
        40,
        reason: 'two pages of 20 items are accumulated',
      );

      // ------------------------------------------------------------------
      // 5. Filter by category — the categories tab → Electronics flow.
      // ------------------------------------------------------------------
      // Keep the autoDispose provider alive while we read it.
      final categorySub = container.listen(
        categoriesProvider,
        (_, _) {},
        fireImmediately: true,
      );
      final categories = await container.read(categoriesProvider.future);
      categorySub.close();
      final electronics = categories.firstWhere(
        (category) => category.name == 'Electronics',
      );
      container
          .read(filterControllerProvider.notifier)
          .setCategory(electronics.id);
      await container.read(productFeedProvider.future);
      feed = container.read(productFeedProvider).value!;
      expect(
        feed.items.every((product) => product.categoryId == electronics.id),
        isTrue,
        reason: 'every feed item is in the selected category',
      );

      // Back to all categories for the search step.
      container.read(filterControllerProvider.notifier).setCategory(null);
      await container.read(productFeedProvider.future);

      // ------------------------------------------------------------------
      // 6. Search 'wireless' (the search screen's debounced field drives
      //    this exact controller).
      // ------------------------------------------------------------------
      container
          .read(searchControllerProvider.notifier)
          .onQueryChanged('wireless');
      // Let the 300ms debounce elapse and the request complete.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final searchState = container.read(searchControllerProvider);
      expect(searchState.results, isNotEmpty);
      expect(
        searchState.results.every(
          (product) => product.title.toLowerCase().contains('wireless'),
        ),
        isTrue,
      );
      final earbuds = searchState.results.firstWhere(
        (product) =>
            product.title == 'Aurora Wireless Noise-Cancelling Earbuds',
      );
      expect(earbuds.price, 124.15);

      // ------------------------------------------------------------------
      // 7. Add to the cart — quantity 2 via the stepper + add-to-cart.
      // ------------------------------------------------------------------
      final cart = container.read(cartControllerProvider.notifier);
      cart.addToCart(earbuds, quantity: 2);
      var cartState = container.read(cartControllerProvider);
      expect(cartState.itemCount, 2, reason: 'one line of two units');
      expect(cartState.items.first.product.id, earbuds.id);
      expect(cartState.totals.subtotal, 248.30);
      expect(cartState.totals.shipping, 0, reason: 'free shipping over \$99');
      expect(
        cartState.totals.total,
        269.41,
        reason: 'subtotal + 8.5% tax = 269.41',
      );

      // The cart persists through the repository (SharedPreferences in
      // production) — give the fire-and-forget save a moment to land.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final persisted = await container.read(cartRepositoryProvider).loadCart();
      expect(persisted.length, 1);
      expect(persisted.first.quantity, 2);

      // ------------------------------------------------------------------
      // 8. Address validation rejects an empty address (the checkout
      //    screen's Continue-to-review path).
      // ------------------------------------------------------------------
      final checkout = container.read(checkoutControllerProvider.notifier);
      final invalidAddress = Address(
        fullName: '',
        street: '',
        city: '',
        state: '',
        zip: '',
        country: '',
        phone: '',
      );
      checkout.submitAddress(invalidAddress);
      var checkoutState = container.read(checkoutControllerProvider);
      expect(
        checkoutState.step,
        CheckoutStep.editingAddress,
        reason: 'an empty address must not advance',
      );
      expect(checkoutState.fieldErrors, isNotEmpty);

      // ------------------------------------------------------------------
      // 9. A valid address advances to review; placing the order succeeds
      //    (review → Place order).
      // ------------------------------------------------------------------
      final address = Address(
        fullName: 'Dana Mercado',
        street: '123 Market Street',
        city: 'San Francisco',
        state: 'California',
        zip: '94103',
        country: 'United States',
        phone: '+1 415 555 0100',
      );
      checkout.submitAddress(address);
      checkoutState = container.read(checkoutControllerProvider);
      expect(checkoutState.step, CheckoutStep.reviewing);

      await checkout.confirmAndPlaceOrder();

      checkoutState = container.read(checkoutControllerProvider);
      expect(checkoutState.step, CheckoutStep.success);
      final orderId = checkoutState.orderId;
      expect(orderId, isNotNull, reason: 'checkout produced an order id');

      cartState = container.read(cartControllerProvider);
      expect(
        cartState.isEmpty,
        isTrue,
        reason: 'a placed order clears the cart',
      );

      // ------------------------------------------------------------------
      // 10. The order shows up in the history (the orders screen).
      // ------------------------------------------------------------------
      await container.read(ordersControllerProvider.notifier).refresh();
      final orders = container.read(ordersControllerProvider).value!;
      expect(orders, isNotEmpty);
      final newOrder = orders.firstWhere((order) => order.id == orderId);
      expect(newOrder.status, OrderStatus.pending);
      expect(newOrder.total, 269.41);
      expect(newOrder.items.first.quantity, 2);

      // The seeded history is still there below the new order.
      expect(orders.any((order) => order.id == 'o1002'), isTrue);
      expect(orders.any((order) => order.id == 'o1001'), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
