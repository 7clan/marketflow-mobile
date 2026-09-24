import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';

/// Cache of favorite product ids (SharedPreferences-backed).
///
/// Written through by the favorites repository after every server sync so
/// the favorites surface can render instantly on a cold start; the ids are
/// always re-validated against the server once it answers.
abstract interface class FavoritesCache {
  /// Reads the cached ids (empty when never synced).
  Future<Set<String>> readIds();

  /// Writes the ids through to the cache.
  Future<void> writeIds(Set<String> ids);

  /// Removes the cache.
  Future<void> clear();
}

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

/// Fully in-memory variant for tests and previews.
class InMemoryFavoritesCache implements FavoritesCache {
  Set<String> _ids = const <String>{};

  @override
  Future<Set<String>> readIds() async => Set<String>.unmodifiable(_ids);

  @override
  Future<void> writeIds(Set<String> ids) async =>
      _ids = Set<String>.unmodifiable(ids);

  @override
  Future<void> clear() async => _ids = const <String>{};
}
