/// Cache of favorite product ids.
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
