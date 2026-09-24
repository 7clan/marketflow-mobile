import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/cart_item.dart';
import '../models/cart_item_model.dart';
import 'cart_local_data_source.dart';

/// SharedPreferences-backed cart persistence (JSON under one string key).
class SharedPreferencesCartLocalDataSource implements CartLocalDataSource {
  SharedPreferencesCartLocalDataSource({required this.preferences});

  static const _storageKey = 'marketflow.cart';

  final SharedPreferences preferences;

  @override
  Future<List<CartItem>> load() async {
    try {
      final raw = preferences.getString(_storageKey);
      if (raw == null || raw.isEmpty) return const <CartItem>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const CacheException(
          cause: 'Persisted cart is not a JSON array.',
        );
      }
      final items = <CartItem>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        // A single corrupt entry never wipes the whole cart.
        try {
          items.add(CartItemModel.fromJson(entry).toDomain());
        } on CacheException {
          rethrow;
        } catch (_) {
          // Skip unparsable entry.
        }
      }
      return items;
    } on CacheException {
      rethrow;
    } catch (error, stackTrace) {
      throw CacheException(cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> save(List<CartItem> items) async {
    try {
      final encoded = jsonEncode([
        for (final item in items) CartItemModel.fromDomain(item).toJson(),
      ]);
      final success = await preferences.setString(_storageKey, encoded);
      if (!success) {
        throw const CacheException(
          cause: 'SharedPreferences rejected the write.',
        );
      }
    } on CacheException {
      rethrow;
    } catch (error, stackTrace) {
      throw CacheException(cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await preferences.remove(_storageKey);
    } catch (error, stackTrace) {
      throw CacheException(cause: error, stackTrace: stackTrace);
    }
  }
}
