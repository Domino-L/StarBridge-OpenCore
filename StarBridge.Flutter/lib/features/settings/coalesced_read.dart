import 'dart:async';

/// One in-flight read. A request that arrives while a round runs waits for
/// exactly one follow-up round, so a newer event is never answered with an
/// older snapshot, and later requests never hold back earlier waiters. The
/// owner keeps authority: [retire] releases every waiter when its epoch ends,
/// and a retired round never touches the next epoch's state.
final class CoalescedRead {
  Completer<void>? _round;
  Completer<void>? _next;

  bool get active => _round != null;

  /// [current] says whether the starting epoch is still live; [allowed]
  /// re-checks the owner's preconditions before a follow-up round.
  Future<void> run(
    Future<void> Function() read, {
    required bool Function() current,
    required bool Function() allowed,
  }) {
    if (_round != null) return (_next ??= Completer<void>()).future;
    final round = _round = Completer<void>();
    unawaited(_drive(round, read, current, allowed));
    return round.future;
  }

  Future<void> _drive(
    Completer<void> first,
    Future<void> Function() read,
    bool Function() current,
    bool Function() allowed,
  ) async {
    var round = first;
    while (true) {
      try {
        await read();
      } catch (_) {
        // The owner's read records its own failure state.
      }
      if (!identical(_round, round)) {
        if (!round.isCompleted) round.complete(); // Retired meanwhile.
        return;
      }
      final next = _next;
      _next = null;
      if (next == null || !current() || !allowed()) {
        _round = null;
        round.complete();
        next?.complete();
        return;
      }
      _round = next;
      round.complete();
      round = next;
    }
  }

  void retire() {
    final round = _round, next = _next;
    _round = null;
    _next = null;
    if (round != null && !round.isCompleted) round.complete();
    if (next != null && !next.isCompleted) next.complete();
  }
}
