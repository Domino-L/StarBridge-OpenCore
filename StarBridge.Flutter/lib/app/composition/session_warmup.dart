import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../shared/diagnostics/loading_read_scope.dart';

/// Bounded, read-only preparation after the shell and account are ready.
/// One job at a time; foreground actions never await this queue.
final class SessionWarmup {
  SessionWarmup({
    required this.account,
    required this.jobs,
    this.continueWork,
    this.workChanges,
    this.cancelWork,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    account.addListener(_changed);
    workChanges?.addListener(wake);
  }
  final ValueListenable<AccountProjection> account;
  final List<Future<void> Function()> jobs;

  /// Performs at most one additional batch. False drains the queue; a feature
  /// change can wake it again without replaying the startup jobs.
  final Future<bool> Function()? continueWork;
  final Listenable? workChanges;
  final VoidCallback? cancelWork;
  final DateTime Function() _now;
  bool _drained = false;
  int _workRevision = 0;
  Timer? _timer;
  int _epoch = 0, _next = 0;
  (int, AccountSessionState)? _identity;
  bool _active = false, _foreground = true, _closed = false, _busy = false;
  DateTime? _deferredUntil;

  bool get _ready =>
      account.value.sessionState == AccountSessionState.signedIn ||
      account.value.sessionState == AccountSessionState.legacySignedIn;

  void start() {
    if (_closed || _active) return;
    _active = true;
    _changed();
  }

  void _changed() {
    if (_closed) return;
    final identity = _ready
        ? (account.value.generation, account.value.sessionState)
        : null;
    if (_identity != identity) {
      cancelWork?.call();
      _identity = identity;
      _epoch++;
      _next = 0;
      _drained = false;
      _timer?.cancel();
    }
    _schedule();
  }

  void wake() {
    if (_closed) return;
    _workRevision++;
    _drained = false;
    _schedule();
  }

  void setForeground(bool value) {
    if (_closed) return;
    _foreground = value;
    if (!value) {
      _timer?.cancel();
      cancelWork?.call();
    }
    if (value) wake();
  }

  void deferForInteraction() {
    if (_closed) return;
    cancelWork?.call();
    _deferredUntil = _now().add(const Duration(milliseconds: 800));
    _timer?.cancel();
    wake();
  }

  void _schedule() {
    if (_closed ||
        !_active ||
        !_foreground ||
        !_ready ||
        account.value.isBusy ||
        _busy ||
        (_next >= jobs.length && (continueWork == null || _drained)) ||
        (_timer?.isActive ?? false)) {
      return;
    }
    final remaining = _deferredUntil?.difference(_now());
    final delay =
        remaining != null && remaining > const Duration(milliseconds: 300)
        ? remaining
        : const Duration(milliseconds: 300);
    _timer = Timer(delay, () => backgroundLoadingRead(_run));
  }

  Future<void> _run() async {
    if (_closed ||
        !_active ||
        !_foreground ||
        !_ready ||
        account.value.isBusy) {
      return;
    }
    final epoch = _epoch;
    final revision = _workRevision;
    final continuing = _next >= jobs.length;
    _busy = true;
    try {
      if (_next < jobs.length) {
        await jobs[_next++]();
      } else {
        final more = await continueWork!();
        if (epoch == _epoch && revision == _workRevision) _drained = !more;
      }
    } catch (_) {
      if (continuing && epoch == _epoch && revision == _workRevision) {
        _drained = true;
      }
      // Optional warming cannot block startup or become an automatic retry loop.
      // Actual destinations retain their normal retry and error handling.
    } finally {
      _busy = false;
      if (!_closed) {
        if (epoch != _epoch) _next = 0;
        _schedule();
      }
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    cancelWork?.call();
    _epoch++;
    _timer?.cancel();
    account.removeListener(_changed);
    workChanges?.removeListener(wake);
  }
}
