import 'dart:async';

/// Runs a callback at most once after the caller stops calling for [delay].
///
/// Used to keep search requests from firing on every keystroke: each call
/// cancels the pending timer and schedules [action] anew.
class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  /// Quiet period required before the scheduled action runs.
  final Duration delay;

  Timer? _timer;
  bool _disposed = false;

  /// Whether an action is currently waiting for the quiet period to elapse.
  bool get isPending => _timer?.isActive ?? false;

  /// Schedules [action], replacing any previously scheduled one.
  void call(void Function() action) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Drops the pending action, if any.
  void cancel() => _timer?.cancel();

  /// Cancels any pending action and permanently disables this debouncer.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
