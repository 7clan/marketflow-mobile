import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'infrastructure_providers.dart';

/// The user's recent search queries, newest first, persisted locally.
///
/// Capped at [_maxEntries] entries; purely a presentation convenience (the
/// search itself is fully stateless via the search controller).
final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

class RecentSearchesController extends Notifier<List<String>> {
  static const String _storageKey = 'marketflow.recent_searches';
  static const int _maxEntries = 8;

  @override
  List<String> build() {
    // Recents must survive leaving and re-entering the search screen.
    ref.keepAlive();
    final preferences = ref.watch(sharedPreferencesProvider);
    return preferences.getStringList(_storageKey) ?? const <String>[];
  }

  /// Records [query] (trimmed), moves it to the front, dedupes and persists.
  void add(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = <String>[
      trimmed,
      ...state.where((entry) => entry != trimmed),
    ].take(_maxEntries).toList();
    if (_sameList(updated, state)) return;
    state = updated;
    _persist(updated);
  }

  /// Forgets one entry.
  void remove(String query) {
    final updated = [
      for (final entry in state)
        if (entry != query) entry,
    ];
    if (updated.length == state.length) return;
    state = updated;
    _persist(updated);
  }

  /// Forgets everything.
  void clear() {
    if (state.isEmpty) return;
    state = const <String>[];
    _persist(const <String>[]);
  }

  void _persist(List<String> entries) {
    unawaited(
      ref.read(sharedPreferencesProvider).setStringList(_storageKey, entries),
    );
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
