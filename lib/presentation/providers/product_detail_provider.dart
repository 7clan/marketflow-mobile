import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/product.dart';
import 'infrastructure_providers.dart';

/// Full detail of a single product, keyed by id and auto-disposed with its
/// listener (the feed keeps no product cache, so leaving the detail screen
/// frees it).
///
/// Throws [NotFoundException] (mapped, user-safe message) for unknown ids.
final productDetailProvider = FutureProvider.autoDispose
    .family<Product, String>((ref, id) {
      return ref.watch(productRepositoryProvider).getProduct(id);
    });
