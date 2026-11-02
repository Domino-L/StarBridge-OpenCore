import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_history_port.dart';

/// Why the last explicit attempt did not finish. Cleared by the next attempt.
enum LocalHistoryFailure { none, scan, confirm, unconfirmed }

/// Result for the setup summary. Only a Host-reported import counts as saved;
/// skipping is the user's explicit choice in this route and writes nothing.
enum LocalHistoryOutcome { saved, skipped, incomplete, failed }

/// Result of the last explicit reset attempt, shown until the next attempt.
enum LocalResetResult { none, done, empty, failed }

@immutable
final class LocalHistoryView {
  const LocalHistoryView({
    this.snapshot = const LocalHistorySnapshot(),
    this.busy = false,
    this.skipped = false,
    this.failure = LocalHistoryFailure.none,
    this.lastResult,
    this.reset = LocalResetResult.none,
  });
  final LocalHistorySnapshot snapshot;
  final bool busy, skipped;
  final LocalHistoryFailure failure;

  /// Terminal scan/confirm result shown until the next attempt (empty, path...).
  final LocalHistoryState? lastResult;
  final LocalResetResult reset;

  bool get imported => snapshot.state == LocalHistoryState.imported;
  bool get canScan =>
      !busy && !imported && snapshot.state == LocalHistoryState.available;
  bool get canConfirm => !busy && snapshot.state == LocalHistoryState.preview;
  bool get canSkip => !busy && !imported && !skipped;

  LocalHistoryOutcome get outcome => imported
      ? LocalHistoryOutcome.saved
      : failure != LocalHistoryFailure.none ||
            const {
              LocalHistoryState.path,
              LocalHistoryState.limit,
            }.contains(lastResult)
      ? LocalHistoryOutcome.failed
      : skipped
      ? LocalHistoryOutcome.skipped
      : LocalHistoryOutcome.incomplete;
}

/// Explicit scan → preview → confirm. Nothing is imported automatically, an
/// uncertain confirmation is never resent implicitly, and the Host keeps the
/// original saved time on any failure.
final class LocalHistoryController extends ValueNotifier<LocalHistoryView> {
  LocalHistoryController(
    this.port, {
    this.pollInterval = const Duration(milliseconds: 250),
  }) : super(const LocalHistoryView()) {
    _events = port.invalidations.listen((_) {
      if (_disposed || value.snapshot.state == LocalHistoryState.scanning) {
        return;
      }
      if (_inFlight) {
        _pending = true;
      } else {
        unawaited(refresh());
      }
    });
  }
  final LocalHistoryPort port;
  final Duration pollInterval;
  late final StreamSubscription<void> _events;
  bool _disposed = false, _inFlight = false, _pending = false;
  bool _cancelRequested = false;

  void _publish({
    LocalHistorySnapshot? snapshot,
    bool? busy,
    bool? skipped,
    LocalHistoryFailure? failure,
    LocalHistoryState? lastResult,
    bool clearResult = false,
    LocalResetResult? reset,
  }) {
    if (_disposed) return;
    value = LocalHistoryView(
      snapshot: snapshot ?? value.snapshot,
      busy: busy ?? value.busy,
      skipped: skipped ?? value.skipped,
      failure: failure ?? value.failure,
      lastResult: clearResult ? null : lastResult ?? value.lastResult,
      reset: reset ?? (clearResult ? LocalResetResult.none : value.reset),
    );
  }

  bool get resetSupported => port.resetSupported;

  /// Explicit reset. [confirm] shows what will be cleared and must return true;
  /// nothing is written before that, and a confirmation is never resent.
  Future<void> reset(Future<bool> Function(LocalResetSnapshot) confirm) async {
    if (_disposed || _inFlight || !port.resetSupported) return;
    _inFlight = true;
    _publish(busy: true, clearResult: true);
    try {
      final preview = await port.previewReset();
      if (preview.state == 'empty') {
        _publish(reset: LocalResetResult.empty);
        return;
      }
      if (preview.state != 'ready' || preview.resetId == null) {
        _publish(reset: LocalResetResult.failed);
        return;
      }
      _publish(busy: false);
      if (!await confirm(preview) || _disposed) return;
      _publish(busy: true);
      final result = await port.confirmReset(preview.resetId!);
      _publish(
        reset: result.state == 'reset'
            ? LocalResetResult.done
            : LocalResetResult.failed,
        skipped: false,
        failure: LocalHistoryFailure.none,
      );
    } on Object {
      _publish(reset: LocalResetResult.failed);
    } finally {
      await _reread();
      _finish();
    }
  }

  Future<void> refresh() async {
    if (_disposed || _inFlight) return;
    _inFlight = true;
    _publish(busy: true);
    try {
      final snapshot = await port.read();
      _publish(snapshot: snapshot);
      if (snapshot.state == LocalHistoryState.scanning &&
          snapshot.scanId != null) {
        // A scan started earlier is still running: keep following it.
        await _follow(snapshot);
      }
    } on Object {
      _publish(snapshot: const LocalHistorySnapshot());
    } finally {
      _finish();
    }
  }

  Future<void> scan() async {
    if (_disposed || _inFlight || !value.canScan) return;
    _inFlight = true;
    _cancelRequested = false;
    _publish(
      busy: true,
      skipped: false,
      failure: LocalHistoryFailure.none,
      clearResult: true,
    );
    try {
      await _follow(await port.startScan());
    } on Object {
      _publish(failure: LocalHistoryFailure.scan);
      await _reread();
    } finally {
      _finish();
    }
  }

  Future<void> _follow(LocalHistorySnapshot snapshot) async {
    var current = snapshot;
    while (!_disposed &&
        current.state == LocalHistoryState.scanning &&
        current.scanId != null) {
      _publish(snapshot: current);
      await Future<void>.delayed(pollInterval);
      if (_disposed) return;
      current = _cancelRequested
          ? await port.cancelScan(current.scanId!)
          : await port.readScan(current.scanId!);
    }
    if (_disposed) return;
    if (current.state == LocalHistoryState.preview ||
        current.state == LocalHistoryState.imported) {
      _publish(snapshot: current);
      return;
    }
    // Terminal results are one-shot. Show them, then re-read the durable state
    // so an empty, cancelled or failed scan stays retryable.
    _publish(
      lastResult: current.state,
      failure:
          const {
            LocalHistoryState.unavailable,
            LocalHistoryState.contextChanged,
          }.contains(current.state)
          ? LocalHistoryFailure.scan
          : null,
    );
    await _reread();
  }

  Future<void> cancel() async {
    if (_disposed || value.snapshot.state != LocalHistoryState.scanning) {
      return;
    }
    _cancelRequested = true;
  }

  Future<void> confirm() async {
    if (_disposed || _inFlight || !value.canConfirm) return;
    final previewId = value.snapshot.previewId!;
    _inFlight = true;
    _publish(busy: true, failure: LocalHistoryFailure.none, clearResult: true);
    try {
      final result = await port.confirm(previewId);
      if (result.state == LocalHistoryState.imported) {
        _publish(snapshot: result, skipped: false);
        return;
      }
      _publish(
        lastResult: result.state,
        failure: result.state == LocalHistoryState.unavailable
            ? LocalHistoryFailure.confirm
            : null,
      );
      await _reread();
    } on Object {
      // The reply was lost. Do not resend; read what the Host actually saved.
      _publish(failure: LocalHistoryFailure.unconfirmed);
      await _reread();
      if (value.imported) _publish(failure: LocalHistoryFailure.none);
    } finally {
      _finish();
    }
  }

  /// Explicitly leave history out of this setup. Writes nothing; the import
  /// stays available from this setup entry later.
  void skip() {
    if (_disposed || !value.canSkip) return;
    _publish(skipped: true);
  }

  void undoSkip() {
    if (_disposed || !value.skipped) return;
    _publish(skipped: false);
  }

  Future<void> _reread() async {
    try {
      final snapshot = await port.read();
      _publish(snapshot: snapshot);
    } on Object {
      _publish(snapshot: const LocalHistorySnapshot());
    }
  }

  void _finish() {
    _inFlight = false;
    _publish(busy: false);
    if (!_disposed && _pending) {
      _pending = false;
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.cancel());
    super.dispose();
  }
}
