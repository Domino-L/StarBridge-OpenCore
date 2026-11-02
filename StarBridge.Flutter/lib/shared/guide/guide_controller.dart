import 'dart:async';

import 'package:flutter/foundation.dart';

import 'guide_state.dart';

enum _OpStatus { pending, ok, failed }

final class _Entry {
  _Entry(this.serial, this.op);
  final int serial;
  final GuideOp op;
  _OpStatus status = _OpStatus.pending;
}

/// Owner of the guide memory for the current profile.
///
/// - Each profile context has its own epoch. A context switch ([reload])
///   hides the old state at once; no write is accepted until the new
///   context's first read succeeds, and replies from an older epoch are
///   dropped, so nothing from one profile reaches another.
/// - The shown value is derived, never patched: the last Host state
///   (`_base`, which already contains every write up to `_mark`) plus the
///   newer local edits in order, plus failed edits on top. Host handles one
///   profile's requests in order, so a reply for write n contains writes
///   before n, and a read started after write n contains it.
/// - Failure policy: a failed write stays as a session-local overlay (a tip
///   the user closed stays closed until restart) and is never resent.
///   The result is the same whatever order replies arrive in.
final class GuideController extends ValueNotifier<GuideState> {
  GuideController(this._port, {this.reload}) : super(GuideState.unavailable) {
    reload?.addListener(_contextChanged);
    unawaited(refresh());
  }

  final GuideStatePort _port;

  /// Fires on account/profile switches.
  final Listenable? reload;
  int _epoch = 0;
  int _read = 0;
  int _write = 0;
  bool _disposed = false;
  GuideState _base = GuideState.unavailable;
  int _mark = 0;
  final _log = <_Entry>[];

  /// The current profile context; bumps on every switch.
  int get epoch => _epoch;

  void _contextChanged() {
    _epoch++;
    _base = GuideState.unavailable;
    _log.clear();
    _mark = _write;
    if (value.available) value = GuideState.unavailable;
    unawaited(refresh());
  }

  /// Re-reads the current context. [then] is applied only if this very read
  /// succeeds in the same context (e.g. "eligible" at the end of setup,
  /// once Host has installed the profile).
  Future<void> refresh({List<GuideOp> then = const []}) async {
    if (!_port.supported) return;
    final epoch = _epoch, serial = ++_read, since = _write;
    try {
      final next = await _port.read();
      if (_disposed || epoch != _epoch || serial != _read) return;
      // The read contains every write sent before it started.
      _rebase(next, since);
      if (next.available) then.forEach(_apply);
    } catch (_) {
      // Guides stay silent when Host cannot answer; a failed first read of a
      // new context leaves the old one hidden.
    }
  }

  bool seen(String id) => value.seen.contains(id);

  void markSeen(String id) => _apply(GuideOp.markSeen(id));
  void markDone(String id) => _apply(GuideOp.markDone(id));
  void markEligible() => _apply(const GuideOp.markEligible());
  void setChecklist({bool? collapsed, bool? dismissed, bool? celebrated}) =>
      _apply(
        GuideOp.setChecklist(
          collapsed: collapsed,
          dismissed: dismissed,
          celebrated: celebrated,
        ),
      );
  void resetSeen() => _apply(const GuideOp.resetSeen());
  void resetChecklist() => _apply(const GuideOp.resetChecklist());

  void _apply(GuideOp op) {
    if (_disposed || !value.available) return;
    // Idempotent no-ops never reach Host (no disk write for nothing).
    if (value.apply(op) == value) return;
    final epoch = _epoch;
    final entry = _Entry(++_write, op);
    _log.add(entry);
    _derive();
    unawaited(
      _port
          .update([op])
          .then(
            (reply) {
              if (_disposed || epoch != _epoch) return;
              entry.status = _OpStatus.ok;
              if (reply.available) {
                _rebase(reply, entry.serial);
              } else {
                _derive();
              }
            },
            onError: (Object _) {
              if (_disposed || epoch != _epoch) return;
              entry.status = _OpStatus.failed;
              _derive();
            },
          ),
    );
  }

  /// Adopts a Host state that contains every write up to [mark], unless a
  /// newer one is already in hand, then drops log entries it now contains.
  void _rebase(GuideState state, int mark) {
    if (mark >= _mark || !_base.available) {
      _base = state;
      _mark = mark;
    }
    // Watermark compaction: confirmed entries at or below the mark are in
    // the base; pending ones wait for their reply; failed ones stay.
    _log.removeWhere((e) => e.status == _OpStatus.ok && e.serial <= _mark);
    _derive();
  }

  void _derive() {
    if (!_base.available) {
      value = _base;
      return;
    }
    var next = _base;
    for (final e in _log) {
      if (e.status != _OpStatus.failed && e.serial > _mark) {
        next = next.apply(e.op);
      }
    }
    for (final e in _log) {
      if (e.status == _OpStatus.failed) next = next.apply(e.op);
    }
    value = next;
  }

  @override
  void dispose() {
    _disposed = true;
    reload?.removeListener(_contextChanged);
    super.dispose();
  }
}
