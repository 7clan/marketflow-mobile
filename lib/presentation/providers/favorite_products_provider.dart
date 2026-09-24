import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/product.dart';
import 'favorites_controller.dart';
import 'infrastructure_providers.dart';

/// Product snapshots for the favorites tab, derived from the favorite ids.
///
/// Presentation-local view state on top of [favoritesControllerProvider]:
///
/// * renders cached snapshots instantly, so optimistic id toggles update
///   the list without any network round-trip;
/// * fetches (in parallel) only ids that were never seen before — removing
///   and re-adding favorites never refetches the whole list;
/// * [reload] drops the snapshot cache for pull-to-refresh.
final favoriteProductsProvider =
    NotifierProvider<FavoriteProductsController, List<Product>>(
      FavoriteProductsController.new,
    );

class FavoriteProductsController extends Notifier<List<Product>> {
  final Map<String, Product> _snapshots = {};

  @override
  List<Product> build() {
    final ids = ref.watch(
      favoritesControllerProvider.select((state) => state.ids),
    );

    // Snapshots of ids that are no longer favorited are stale.
    _snapshots.removeWhere((id, _) => !ids.contains(id));

    final missing = [
      for (final id in ids)
        if (!_snapshots.containsKey(id)) id,
    ];
    if (missing.isNotEmpty) {
      unawaited(_fetchMissing(missing));
    }

    return _materialize(ids);
  }

  /// Pull-to-refresh: forget every snapshot and refetch in parallel.
  Future<void> reload() {
    _snapshots.clear();
    return _fetchMissing(
      ref.read(favoritesControllerProvider).ids.toList(growable: false),
    );
  }

  Future<void> _fetchMissing(List<String> ids) async {
    if (ids.isEmpty) return;
    final repository = ref.read(productRepositoryProvider);
    await Future.wait(
      ids.map((id) async {
        try {
          _snapshots[id] = await repository.getProduct(id);
        } on AppException {
          // A snapshot that cannot be fetched stays absent until the next
          // sync; the ids remain the source of truth.
        }
      }),
    );
    // The favorites list may have changed while the fetches were in flight
    // (or the provider lost its listeners) — writing state through a
    // disposed ref would throw, so guard with [Ref.mounted].
    if (!ref.mounted) return;
    state = _materialize(ref.read(favoritesControllerProvider).ids);
  }

  List<Product> _materialize(Set<String> ids) => [
    for (final id in ids)
      if (_snapshots.containsKey(id)) _snapshots[id]!,
  ];
}
