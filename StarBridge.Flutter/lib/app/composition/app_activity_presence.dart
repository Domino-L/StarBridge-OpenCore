import 'dart:async';

import 'package:flutter/foundation.dart';

/// Local app inactivity only. No input content, persistence or remote publication.
/// Start/stop follows the mounted app, so headless composition creates no timer.
final class AppActivityPresence extends ValueNotifier<bool> {
  AppActivityPresence({
    this.awayAfter = const Duration(minutes: 15),
    this._elapsed,
  }) : super(false) {
    if (awayAfter <= Duration.zero) {
      throw ArgumentError.value(awayAfter, 'awayAfter');
    }
  }

  final Duration awayAfter;
  final Duration Function()? _elapsed;
  final Stopwatch _clock = Stopwatch();
  Duration _lastInteraction = Duration.zero;
  Timer? _timer;
  bool _active = false;
  bool _disposed = false;
  Duration get _now => _elapsed?.call() ?? _clock.elapsed;

  void start() {
    if (_disposed || _active) return;
    _active = true;
    _clock.start();
    _lastInteraction = _now;
    value = false;
    _timer = Timer(awayAfter, _check);
  }

  void recordInteraction() {
    if (_disposed || !_active) return;
    _lastInteraction = _now;
    if (value) value = false;
    // Moving the mouse does not allocate a new timer for every event.
    _timer ??= Timer(awayAfter, _check);
  }

  void _check() {
    _timer = null;
    if (_disposed || !_active) return;
    var idle = _now - _lastInteraction;
    if (idle < Duration.zero) {
      _lastInteraction = _now;
      idle = Duration.zero;
    }
    if (idle >= awayAfter) {
      value = true;
    } else {
      _timer = Timer(awayAfter - idle, _check);
    }
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
