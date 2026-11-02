import 'package:flutter/widgets.dart';

/// Detects high-frequency passive data updates explicitly opted into by
/// the caller. Active clicks/selections never use this tracker to suppress
/// their one-shot feedback.
///
/// Enters after [enterCount] events where each follows the previous within
/// [gap]; leaves after [gap] of silence. Entering needs a run of events and
/// leaving needs silence, so a rate near the threshold does not flicker.
///
/// The silence clock is a single reused [AnimationController]: no timer is
/// created per event, it honours `timeDilation` and stops with [TickerMode].
/// Only count real passive data revisions, never taps, rebuilds, scrolling
/// or resizes. Do not infer this policy merely from update frequency.
class BurstTracker {
  BurstTracker({
    required TickerProvider vsync,
    required this.onChanged,
    this.enterCount = 3,
    Duration gap = const Duration(milliseconds: 800),
  }) : _quiet = AnimationController(vsync: vsync, duration: gap) {
    _quiet.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      _count = 0;
      if (_active) {
        _active = false;
        onChanged(false);
      }
    });
  }

  final int enterCount;
  final ValueChanged<bool> onChanged;
  final AnimationController _quiet;
  int _count = 0;
  bool _active = false;

  /// Whether the control is in its continuous state.
  bool get active => _active;

  /// Records one event and returns whether the continuous state is active.
  bool hit() {
    _count = _quiet.isAnimating ? _count + 1 : 1;
    _quiet.forward(from: 0);
    if (!_active && _count >= enterCount) {
      _active = true;
      onChanged(true);
    }
    return _active;
  }

  /// Leaves the continuous state at once (keyboard use, reduced motion).
  void reset() {
    _quiet.stop();
    _count = 0;
    if (_active) {
      _active = false;
      onChanged(false);
    }
  }

  void dispose() => _quiet.dispose();
}

/// Continuous-state timing shared by the suites (first-pass values from the
/// recheck brief; tune in the lab).
abstract final class BurstMotion {
  /// Fade-in of the continuous layer when the state starts.
  static const enter = Duration(milliseconds: 120);

  /// Settle back to the static final state after the burst ends.
  static const settle = Duration(milliseconds: 160);

  /// Follow duration bounds when chasing a new target mid-burst.
  static const followMin = Duration(milliseconds: 80);
  static const followMax = Duration(milliseconds: 180);

  /// Follow time for a move of [distance] logical pixels: shorter hops are
  /// quicker, long jumps cap at [followMax] so the indicator never lags.
  static Duration follow(double distance) {
    final ms = (80 + distance * 0.9).clamp(
      followMin.inMilliseconds.toDouble(),
      followMax.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: ms.round());
  }
}
