import 'dart:async';

enum DirectMessageReceiveResult {
  skipped,
  unchanged,
  changed,
  failed,
  invalidated,
}

/// One fallback clock for all visible borrowers of a conversation owner.
/// Live activity and explicit refresh still use the original receive path.
final class DirectMessageReceivePolling {
  DirectMessageReceivePolling({
    required this.read,
    required this.isHealthy,
    bool Function()? foreground,
  }) : _foreground = foreground ?? _alwaysForeground;
  static bool _alwaysForeground() => true;
  final bool Function() _foreground;
  final Future<DirectMessageReceiveResult> Function() read;
  final bool Function() isHealthy;
  final _leases = <DirectMessageReceiveLease>{};
  Timer? _timer;
  bool _closed = false, _reading = false, _wasVisible = false;
  bool _wakePending = false;
  bool? _foregrounded;
  bool? _healthy;
  int _nextTick = 1, _unchanged = 0, _failures = 0, _revision = 0;

  DirectMessageReceiveLease observe(
    bool Function() isVisible, {
    void Function()? onDispose,
  }) {
    final lease = DirectMessageReceiveLease._(this, isVisible, onDispose);
    if (_closed) return lease;
    _leases.add(lease);
    if (_timer == null) {
      _nextTick = 1;
      _wasVisible = false;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
    return lease;
  }

  void _reset() {
    _revision++;
    _unchanged = _failures = 0;
    _nextTick = _timer?.tick ?? 0;
  }

  void invalidate() {
    if (!_closed) _reset();
  }

  void _wake(DirectMessageReceiveLease lease) {
    if (_closed || !_leases.contains(lease) || !lease.isVisible()) return;
    _reset();
    if (_reading) _wakePending = true;
    _tick();
  }

  void _tick() {
    if (_closed || _timer == null) return;
    if (!_leases.any((lease) => lease.isVisible())) {
      _wasVisible = false;
      return;
    }
    final healthy = isHealthy();
    final foreground = _foreground();
    if (!_wasVisible || healthy != _healthy || foreground != _foregrounded) {
      _reset();
    }
    _wasVisible = true;
    _healthy = healthy;
    _foregrounded = foreground;
    if (_reading || _timer!.tick < _nextTick) {
      return;
    }
    _reading = true;
    unawaited(_receive(_revision));
  }

  Future<void> _receive(int revision) async {
    try {
      DirectMessageReceiveResult result;
      try {
        result = await read();
      } catch (_) {
        // Unexpected transport throws use the same bounded retry policy.
        result = DirectMessageReceiveResult.failed;
      }
      if (_closed || revision != _revision) return;
      // Push delivers changes immediately; one minute checks for lost hints
      // without repeating REST reads every second. Failures retain backoff.
      if (_healthy == true &&
          (result == DirectMessageReceiveResult.changed ||
              result == DirectMessageReceiveResult.unchanged)) {
        _nextTick = (_timer?.tick ?? 0) + 60;
        return;
      }
      final int interval;
      switch (result) {
        case DirectMessageReceiveResult.skipped:
          interval = 1; // Busy/send/read owners retain admission authority.
        case DirectMessageReceiveResult.invalidated:
          _unchanged = _failures = 0;
          interval = 1;
        case DirectMessageReceiveResult.failed:
          _unchanged = 0;
          if (_failures < 5) _failures++;
          interval = _foregrounded == false
              ? 15 * (1 << (_failures > 3 ? 3 : _failures))
              : _failures == 5
              ? 30
              : 1 << _failures;
        case DirectMessageReceiveResult.changed:
          _unchanged = _failures = 0;
          interval = _foregrounded == false ? 15 : 1;
        case DirectMessageReceiveResult.unchanged:
          _failures = 0;
          if (_unchanged < 3) _unchanged++;
          interval = _foregrounded == false ? 15 : 1 << _unchanged;
      }
      _nextTick = (_timer?.tick ?? 0) + interval;
    } finally {
      _reading = false;
      if (_wakePending && !_closed) {
        _wakePending = false;
        _tick();
      }
    }
  }

  void _release(DirectMessageReceiveLease lease) {
    _leases.remove(lease);
    if (_leases.isNotEmpty) return;
    _timer?.cancel();
    _timer = null;
    _wasVisible = false;
    _reset();
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _leases.clear();
  }
}

final class DirectMessageReceiveLease {
  DirectMessageReceiveLease._(this._owner, this.isVisible, this._onDispose);
  final DirectMessageReceivePolling _owner;
  final bool Function() isVisible;
  final void Function()? _onDispose;
  bool _closed = false;
  void wake() {
    if (!_closed) _owner._wake(this);
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    try {
      _onDispose?.call();
    } finally {
      _owner._release(this);
    }
  }
}
