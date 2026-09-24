import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_controller.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/categories/categories_screen.dart';
import '../screens/checkout/checkout_screen.dart';
import '../screens/favorites/favorites_screen.dart';
import '../screens/feed/product_feed_screen.dart';
import '../screens/orders/order_detail_screen.dart';
import '../screens/orders/orders_screen.dart';
import '../screens/product/product_detail_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/shell/home_shell.dart';
import '../screens/splash/splash_screen.dart';
import '../../domain/entities/product.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Declarative navigation for MarketFlow.
///
/// Route table:
///
/// * `/` — splash (session restore, error + retry);
/// * `/login`, `/register` — authentication;
/// * shell (bottom navigation, preserved branch state): `/shop`,
///   `/categories`, `/favorites`, `/cart`, `/profile`;
/// * full-screen pushes above the shell: `/product/:id`, `/search`,
///   `/checkout`, `/orders`, `/orders/:id`.
///
/// The [GoRouter.redirect] gates every location on the auth state:
/// unresolved (restoring / failed) → splash, unauthenticated → `/login`,
/// authenticated → `/shop` when arriving on auth or splash routes.
///
/// Re-evaluation is driven by [_AuthRefresh], which notifies only when the
/// *resolved* auth value changes — the transient `AsyncLoading` states during
/// login/logout must not rebuild the navigator mid-interaction.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authRefresh = _AuthRefresh(ref);
  ref.onDispose(authRefresh.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' || location == '/register';

      // Session restore in flight or failed: hold on the splash route (the
      // splash renders progress and, on failure, an error + retry).
      if (auth.isLoading || auth.hasError) {
        return location == '/' ? null : '/';
      }

      final signedIn = auth.isAuthenticated;
      if (!signedIn) {
        return isAuthRoute ? null : '/login';
      }
      if (isAuthRoute || location == '/') {
        return '/shop';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SplashScreen()),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: RegisterScreen()),
      ),
      GoRoute(
        path: '/product/:id',
        name: 'productDetail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ProductDetailScreen(
          productId: state.pathParameters['id']!,
          initialProduct: state.extra is Product
              ? state.extra! as Product
              : null,
        ),
      ),
      GoRoute(
        path: '/search',
        name: 'search',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SearchScreen()),
      ),
      GoRoute(
        path: '/checkout',
        name: 'checkout',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: '/orders',
        name: 'orders',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const OrdersScreen(),
      ),
      GoRoute(
        path: '/orders/:id',
        name: 'orderDetail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) =>
            OrderDetailScreen(orderId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/shop',
                name: 'shop',
                builder: (context, state) => const ProductFeedScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/categories',
                name: 'categories',
                builder: (context, state) => const CategoriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/favorites',
                name: 'favorites',
                builder: (context, state) => const FavoritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/cart',
                name: 'cart',
                builder: (context, state) => const CartScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Notifies [GoRouter] to re-run its redirect.
///
/// Fires when the resolved auth value settles:
///
/// * any `isLoading`/`error` → resolved transition (startup, retry);
/// * signed-in ↔ signed-out flips (login, logout, session expiry).
///
/// Deliberately quiet for the intermediate `AsyncLoading` frames emitted
/// while a login/logout request is in flight.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    _subscription = ref.listen<AsyncValue<AuthState>>(authControllerProvider, (
      previous,
      next,
    ) {
      final wasAuthenticated = previous?.value is AuthAuthenticated;
      final isAuthenticated = next.value is AuthAuthenticated;
      final wasUnresolved =
          previous == null || previous.isLoading || previous.hasError;
      if (wasAuthenticated != isAuthenticated || wasUnresolved) {
        notifyListeners();
      }
    });
  }

  ProviderSubscription<AsyncValue<AuthState>>? _subscription;

  @override
  void dispose() {
    _subscription?.close();
    _subscription = null;
    super.dispose();
  }
}
