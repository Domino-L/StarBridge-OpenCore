import 'dart:async';

import 'package:flutter/services.dart';

/// Native creates the menu engine inside the first opening (~1.6s measured).
/// Ask it to prepare that engine hidden while idle; native declines while the
/// desktop client is in use or a menu session is wanted, so this retries a
/// bounded number of times and stops after the first prepared engine.
final class MenuEnginePrewarm {
  MenuEnginePrewarm(
    this._channel, {
    this.delay = const Duration(seconds: 8),
    this.maxAttempts = 30,
  });
  final MethodChannel _channel;
  final Duration delay;
  final int maxAttempts;
  Timer? _timer;
  var _attempts = 0;
  var _busy = false;

  /// [canRun] skips a tick, for example while an opening is in progress.
  void start(bool Function() canRun) =>
      _timer ??= Timer.periodic(delay, (_) => _tick(canRun));

  Future<void> _tick(bool Function() canRun) async {
    if (_busy) return;
    if (++_attempts > maxAttempts) return dispose();
    if (!canRun()) return;
    _busy = true;
    try {
      if (await _channel.invokeMethod<bool>('prewarm') == true) dispose();
    } on Object {
      dispose();
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _attempts = maxAttempts;
  }
}
