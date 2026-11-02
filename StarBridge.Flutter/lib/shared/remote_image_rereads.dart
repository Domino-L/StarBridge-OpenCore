import 'dart:async';

import 'package:flutter/foundation.dart';

/// A widget reads an image only when told to, so a read that failed needs a
/// later nudge. Each failed image is read again at most three times, and only
/// the images that failed are told: a refused image or a working one is not
/// read again because something else failed.
final class RemoteImageRereads<K> extends ChangeNotifier {
  RemoteImageRereads(this._now);
  final DateTime Function() _now;

  // The first waits out the failed entry's 10 seconds.
  static const _delays = [
    Duration(seconds: 11),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];
  final _tries = <K, int>{};
  final _waiting = <K, DateTime>{};
  final _due = <K>{};
  Timer? _timer;

  void failed(K key) {
    if (!hasListeners) return;
    if (!_tries.containsKey(key) && _tries.length >= 256) return;
    final tries = _tries[key] ?? 0;
    _tries[key] = tries + 1;
    if (tries >= _delays.length) {
      _waiting.remove(key);
      return;
    }
    _waiting[key] = _now().add(_delays[tries]);
    _arm();
  }

  void succeeded(K key) {
    _tries.remove(key);
    _waiting.remove(key);
  }

  /// Whether the image should read again during the current notification.
  bool isDue(K key) => _due.contains(key);

  void reset() {
    _timer?.cancel();
    _timer = null;
    _tries.clear();
    _waiting.clear();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_waiting.isEmpty) return;
    final next = _waiting.values.reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = next.difference(_now());
    _timer = Timer(wait.isNegative ? Duration.zero : wait, _fire);
  }

  void _fire() {
    _timer = null;
    final now = _now();
    for (final row in _waiting.entries.toList()) {
      if (!row.value.isAfter(now)) {
        _waiting.remove(row.key);
        _due.add(row.key);
      }
    }
    if (_due.isNotEmpty) notifyListeners();
    _due.clear();
    _arm();
  }
}
