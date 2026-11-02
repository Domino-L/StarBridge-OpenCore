import 'package:flutter/foundation.dart';

/// Decides when scrolling up leaves the lower screen for the upper one. Reaching
/// the top of a list must not switch screens by itself (user 2026-10-30): the
/// wheel has to rest first, then travel a deliberate distance upward.
final class OfficialFleetWheelGate {
  OfficialFleetWheelGate({Duration Function()? now}) : _now = now ?? _clock;

  static final _stopwatch = Stopwatch()..start();
  static Duration _clock() => debugNow?.call() ?? _stopwatch.elapsed;

  /// Lets widget tests advance time; their frames do not move a real stopwatch.
  @visibleForTesting
  static Duration Function()? debugNow;

  /// How long after the list last moved the wheel is still that same scroll.
  static const rest = Duration(milliseconds: 350);

  /// A longer pause starts counting the upward distance again.
  static const pause = Duration(milliseconds: 600);

  /// About two wheel notches.
  static const distance = 150.0;

  final Duration Function() _now;
  Duration? _bodyMovedAt, _lastUp;
  double _travel = 0;

  /// The list under the wheel actually scrolled.
  void bodyMoved() {
    _bodyMovedAt = _now();
    _travel = 0;
  }

  void reset() {
    _bodyMovedAt = _lastUp = null;
    _travel = 0;
  }

  /// One upward wheel step of [amount] pixels. True when the screens switch.
  bool up(double amount, {required bool bodyAtTop}) {
    final now = _now(), moved = _bodyMovedAt, last = _lastUp;
    _lastUp = now;
    if (!bodyAtTop || moved != null && now - moved < rest) {
      _travel = 0;
      return false;
    }
    if (last == null || now - last > pause) _travel = 0;
    _travel += amount;
    if (_travel < distance) return false;
    reset();
    return true;
  }
}
