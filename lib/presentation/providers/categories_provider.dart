import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/category.dart';
import 'infrastructure_providers.dart';

/// The category list, refreshed each time the categories tab is entered.
///
/// Serves the categories screen and category-name lookups in feed filter
/// chips. `autoDispose` keeps the response out of memory when unused.
final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(productRepositoryProvider).getCategories();
});
