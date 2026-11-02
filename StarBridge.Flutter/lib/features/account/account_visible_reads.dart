import 'dart:async';

import 'account_module.dart';

/// Optional (2026-10-21): the account page is showing the staged details
/// (profile display, time zones, game identity, compatibility). While a hold
/// is active they are read now, one after another, instead of behind the
/// warm-up queue, and a click elsewhere does not cancel them.
abstract interface class AccountVisibleReads {
  void Function() holdVisibleReads();
}

extension AccountVisibleReadHold on AccountModule {
  void Function() holdVisibleReads() => switch (this) {
    final AccountVisibleReads reads => reads.holdVisibleReads(),
    _ => () {},
  };
}

/// Drives the staged reads while at least one hold is active. It starts no
/// read of its own: each step is the module's ordinary [prepareNext].
final class AccountVisibleReadDriver {
  AccountVisibleReadDriver({
    required this.prepareNext,
    required this.inFlight,
    this.pause = const Duration(milliseconds: 50),
  });

  final Future<bool> Function() prepareNext;
  final bool Function() inFlight;
  final Duration pause;
  int _holds = 0;
  bool _draining = false;

  bool get held => _holds > 0;

  void Function() hold() {
    _holds++;
    unawaited(drain());
    var released = false;
    return () {
      if (released) return;
      released = true;
      _holds--;
    };
  }

  Future<void> drain() async {
    if (_draining || !held) return;
    _draining = true;
    try {
      while (held) {
        if (inFlight()) {
          await Future<void>.delayed(pause);
          continue;
        }
        if (!await prepareNext()) break;
      }
    } finally {
      _draining = false;
    }
  }
}
