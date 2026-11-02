import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/onboarding/bridge_first_use_startup.dart';
import '../../features/onboarding/connection_mode_controller.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../../features/onboarding/onboarding_models.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'startup_prompt_queue.dart';

enum FirstUseRecoveryChoice { keepCurrent, openSetup }

/// This notice owns presentation lifetime, not data, identity or permissions.
final class FirstUseRecoveryNotice extends ChangeNotifier {
  FirstUseRecoveryNotice(this.reason, this._current, this._reread);
  String reason;
  final bool Function() _current;
  final Future<String?> Function() _reread;
  bool _retired = false, busy = false;
  bool get active => !_retired && _current();
  Future<bool> recheck() async {
    if (!active || busy) return false;
    busy = true;
    notifyListeners();
    try {
      final next = await _reread();
      if (!active || next == null) return false;
      if (next != 'ready') reason = next;
      return next == 'ready';
    } finally {
      busy = false;
      if (!_retired) notifyListeners();
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    notifyListeners();
  }
}

/// Unknown is not first-use, existing-user choice is not completion. Every
/// action here is a read or navigation over the original Host and navigator.
final class FirstUseRecoveryFlow {
  FirstUseRecoveryFlow({
    required this.session,
    required this.queue,
    required this.ready,
    required this.current,
    required this.show,
    required this.openSetup,
    this.onHealthy,
    this.mode,
  }) : _startup = BridgeFirstUseStartup(session) {
    _events = session.events
        .where(
          (e) => const {
            'account.changed',
            'bootstrap.invalidated',
            'onboarding.changed',
          }.contains(e.name),
        )
        .listen(
          (_) => _invalidate(),
          onDone: _invalidate,
          onError: (Object _) => _invalidate(),
        );
  }
  final BridgeClientSession session;
  final ConnectionModeController? mode;
  final StartupPromptQueue queue;
  final bool Function() ready, current;
  final Future<FirstUseRecoveryChoice?> Function(FirstUseRecoveryNotice) show;
  final Future<void> Function() openSetup;
  final VoidCallback? onHealthy;
  final BridgeFirstUseStartup _startup;
  late final StreamSubscription<Object?> _events;
  final _key = Object();
  FirstUseRecoveryNotice? _notice;
  int _epoch = 0;
  bool _disposed = false,
      _shown = false,
      _pending = false,
      _showing = false,
      _hold = false;
  bool get blocksOptionalPrompts => _pending || _showing;
  bool get _current => !_disposed && current();
  void _invalidate() {
    _epoch++;
    _pending = false;
    queue.cancel(_key);
    _notice?.retire();
  }

  void consumeManualEntry() {
    _shown = true;
    _hold = true;
    _invalidate();
  }

  Future<String?> _read(int epoch) async {
    final generation = session.activeGeneration;
    FirstUseStartupObservation? startup;
    try {
      startup = await _startup.read();
    } on Object {
      if (!_current ||
          epoch != _epoch ||
          generation != session.activeGeneration ||
          !_startup.supported) {
        return null;
      }
      return 'unavailable';
    }
    if (!_current ||
        epoch != _epoch ||
        generation != session.activeGeneration ||
        startup == null) {
      return null;
    }
    await mode?.refresh();
    if (!_current ||
        epoch != _epoch ||
        generation != session.activeGeneration) {
      return null;
    }
    if (mode?.busy == true) return 'switching';
    if (mode?.failed == true) return 'unavailable';
    final state = mode?.snapshot;
    if (state != null &&
        state.state != ConnectionModeState.unsupported &&
        state.scope != startup.scope) {
      return null;
    }
    if (state?.state == ConnectionModeState.recoveryRequired) return 'pending';
    if (state?.state == ConnectionModeState.unavailable) return 'unavailable';
    return startup.eligibility == OnboardingEligibility.unknown
        ? startup.reason
        : 'ready';
  }

  Future<bool> check() async {
    if (!_current || _shown || _showing) return _hold;
    final epoch = ++_epoch;
    _pending = false;
    queue.cancel(_key);
    if (!_startup.supported) return false;
    final reason = await _read(epoch);
    if (!_current || epoch != _epoch) return true;
    _hold = reason != 'ready';
    if (reason == null || reason == 'ready' || reason == 'switching') {
      return _hold;
    }
    _pending = true;
    queue.enqueue(
      _key,
      priority: 40,
      eligible: () => _current && epoch == _epoch && ready(),
      show: () async {
        _pending = false;
        final observed = await _read(epoch);
        if (!_current ||
            epoch != _epoch ||
            !ready() ||
            queue.hasBlockingRoute) {
          return;
        }
        if (observed == 'ready') {
          _hold = false;
          onHealthy?.call();
          return;
        }
        if (observed == null || observed == 'switching') return;
        _shown = true;
        _showing = true;
        final generation = session.activeGeneration;
        final notice = FirstUseRecoveryNotice(
          observed,
          () =>
              _current &&
              epoch == _epoch &&
              _startup.supported &&
              generation == session.activeGeneration,
          () => _read(epoch),
        );
        _notice = notice;
        try {
          final choice = await show(notice);
          if (choice == FirstUseRecoveryChoice.openSetup && notice.active) {
            await openSetup();
          }
        } finally {
          notice.retire();
          notice.dispose();
          if (identical(_notice, notice)) _notice = null;
          _showing = false;
        }
      },
    );
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _invalidate();
    unawaited(_events.cancel());
  }
}
