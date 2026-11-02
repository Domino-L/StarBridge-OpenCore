import 'dart:async';

/// Direct save for the overlay workspace, without timers. Edits made in the
/// same turn are written together on the next microtask; while a write runs,
/// further edits wait and are written once, together, when it finishes. A
/// pointer gesture on the editor (a slider or module drag) and an explicit
/// edit session (in-game placement, where Done saves and Cancel restores)
/// hold scheduled writes until they end.
final class OverlayWorkspaceAutoSave {
  OverlayWorkspaceAutoSave({required this.commit});

  /// Writes the current draft; true when nothing is left unsaved.
  final Future<bool> Function() commit;
  bool _scheduled = false;
  Future<bool>? _running;
  int _holds = 0;
  bool _closed = false;

  /// A write is scheduled or running.
  bool get pending => _scheduled || _running != null;
  bool get held => _holds > 0;

  void schedule() {
    if (_closed || _holds > 0 || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(() {
      if (!_scheduled) return;
      _scheduled = false;
      if (!_closed && _holds == 0) unawaited(flush());
    });
  }

  void hold() {
    _holds++;
    cancel();
  }

  /// Ends one hold; whatever is still unsaved is scheduled again.
  void release() {
    if (_holds == 0) return;
    if (--_holds == 0) schedule();
  }

  void cancel() => _scheduled = false;

  /// Writes now, after any running write. Explicit, so it ignores holds.
  Future<bool> flush() async {
    cancel();
    for (var running = _running; running != null; running = _running) {
      await running;
    }
    if (_closed) return false;
    final run = commit();
    _running = run;
    try {
      return await run;
    } finally {
      if (identical(_running, run)) _running = null;
    }
  }

  void close() {
    _closed = true;
    cancel();
  }
}
