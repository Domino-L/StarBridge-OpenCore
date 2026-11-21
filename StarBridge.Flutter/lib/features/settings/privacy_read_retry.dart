import 'dart:async';

/// Owns the pending timer and backoff for one privacy setting.
final class PrivacyReadRetry {
  static const _delays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  Timer? _timer;
  int _nextDelay = 0;

  void afterRead({
    required bool shouldRetry,
    required Future<void> Function() refresh,
  }) {
    if (!shouldRetry) {
      reset();
      return;
    }
    _timer = Timer(_delays[_nextDelay], () {
      _timer = null;
      // Manual and page-entry reads leave the next automatic delay unspent.
      if (_nextDelay < _delays.length - 1) _nextDelay++;
      unawaited(refresh());
    });
  }

  void cancelPending() {
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    cancelPending();
    _nextDelay = 0;
  }
}
