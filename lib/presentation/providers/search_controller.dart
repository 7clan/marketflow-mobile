import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/debouncer.dart';
import '../../domain/entities/product.dart';
import 'infrastructure_providers.dart';

/// Rendered state of the product search.
class SearchState {
  const SearchState({
    this.query = '',
    this.results = const <Product>[],
    this.isSearching = false,
    this.error,
  });

  /// The live text in the search field (updated instantly, before results).
  final String query;

  /// Products matching the committed query.
  final List<Product> results;

  /// `true` from the moment the user stops typing until results (or an
  /// error) arrive — drives the results skeleton.
  final bool isSearching;

  /// Error of the last committed search, when it failed.
  final AppException? error;

  /// `true` when there is a meaningful query to search for.
  bool get hasQuery => query.trim().isNotEmpty;

  /// `true` for the "no results" empty state (only when nothing failed).
  bool get isEmpty =>
      hasQuery && !isSearching && error == null && results.isEmpty;

  SearchState copyWith({
    String? query,
    List<Product>? results,
    bool? isSearching,
    Object? error = _unset,
  }) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      error: identical(error, _unset) ? this.error : error as AppException?,
    );
  }

  /// Sentinel for [copyWith]'s nullable clear.
  static const _unset = Object();
}

/// Debounced product search.
///
/// * keystrokes update the query instantly (the field feels live) but the
///   network only fires after 300ms of quiet;
/// * the previous request is cancelled via [CancelToken] and, belt and
///   braces, stale responses drop themselves via a request sequence number;
/// * empty queries reset to the idle state.
final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchController extends Notifier<SearchState> {
  static const searchDebounce = Duration(milliseconds: 300);

  late final Debouncer _debouncer = Debouncer(delay: searchDebounce);
  int _requestSeq = 0;
  CancelToken? _cancelToken;

  @override
  SearchState build() {
    ref.keepAlive();
    ref.onDispose(_debouncer.dispose);
    return const SearchState();
  }

  /// Called on every keystroke; commits the search after the debounce window.
  void onQueryChanged(String query) {
    if (query == state.query) return;
    state = state.copyWith(query: query, isSearching: query.trim().isNotEmpty);
    _debouncer(() => _runSearch(query));
  }

  /// Re-runs the search for the current query (error retry button).
  Future<void> refresh() => _runSearch(state.query);

  /// Clears the query, cancels anything in flight, resets the state.
  void clear() {
    _debouncer.cancel();
    _cancelInFlight();
    state = const SearchState();
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _cancelInFlight();
      state = state.copyWith(
        results: const [],
        isSearching: false,
        error: null,
      );
      return;
    }

    _cancelInFlight();
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final seq = ++_requestSeq;
    final repository = ref.read(productRepositoryProvider);
    final pageSize = ref.read(appConfigProvider).pageSize;

    try {
      final result = await repository.getProducts(
        page: 1,
        pageSize: pageSize,
        query: trimmed,
        cancelToken: cancelToken,
      );
      if (seq != _requestSeq) return; // superseded by a newer query
      state = state.copyWith(
        results: result.items,
        isSearching: false,
        error: null,
      );
    } on CancelledException {
      // Superseded by a newer query — leave the newer state alone.
    } on AppException catch (error) {
      if (seq != _requestSeq) return;
      state = state.copyWith(isSearching: false, error: error);
    }
  }

  void _cancelInFlight() {
    _requestSeq++;
    final token = _cancelToken;
    _cancelToken = null;
    if (token != null && !token.isCancelled) token.cancel();
  }
}
