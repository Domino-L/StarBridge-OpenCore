import 'dart:async';

/// One deferred receipt retry per application; never runs after owner disposal.
final class StorageResultRetry {
  StorageResultRetry({required this.current});
  final bool Function(int revision) current;
  Timer? _timer;
  bool _disposed = false;

  void schedule(int revision, void Function() retry) {
    if (_disposed || !current(revision)) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {
      if (!_disposed && current(revision)) retry();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
