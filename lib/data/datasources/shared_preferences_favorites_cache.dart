import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';
import 'favorites_cache.dart';

/// SharedPreferences-backed favorites id cache.
class SharedPreferencesFavoritesCache implements FavoritesCache {
  SharedPreferencesFavoritesCache({required this.preferences});

  static const _storageKey = 'marketflow.favorites.ids';

  final SharedPreferences preferences;

  @override
  Future<Set<String>> readIds() async {
    try {
      final raw = preferences.getStringList(_storageKey);
      if (raw == null) return const <String>{};
      return Set<String>.unmodifiable(raw);
    } catch (error, stackTrace) {
      throw CacheException(cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> writeIds(Set<String> ids) async {
    try {
      final success = await preferences.setStringList(
        _storageKey,
        ids.toList(growable: false),
      );
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
