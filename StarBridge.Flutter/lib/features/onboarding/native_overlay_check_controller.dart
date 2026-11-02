import 'dart:async';

import 'package:flutter/foundation.dart';

import 'native_overlay_observation.dart';

enum NativeHotkeyCheck { notStarted, waiting, observed, timedOut, interrupted }

enum NativePreviewVisit { notStarted, opening, returned, blocked, failed }

@immutable
final class NativeOverlayCheckView {
  const NativeOverlayCheckView({
    this.observation,
    this.hotkey = NativeHotkeyCheck.notStarted,
    this.preview = NativePreviewVisit.notStarted,
    this.busy = false,
    this.readError = false,
  });
  final NativeOverlayObservation? observation;
  final NativeHotkeyCheck hotkey;
  final NativePreviewVisit preview;
  final bool busy, readError;

  bool get canCheckHotkey =>
      !busy &&
      observation?.preview.sessionId == null &&
      observation?.hotkey.binding?.isNotEmpty == true &&
      const {
        'registered',
        'gameCompatibleOnly',
        'desktopOnly',
      }.contains(observation?.hotkey.state);
}

/// Ephemeral observations, not S4 readiness or persisted user acceptance.
/// The original preview route owns its Native session and awaited close. This
/// module only borrows read access; it never toggles a window, simulates a key,
/// saves settings, or closes a preview owned by another caller.
final class NativeOverlayCheckController
    extends ValueNotifier<NativeOverlayCheckView> {
  NativeOverlayCheckController(this.port)
    : super(const NativeOverlayCheckView()) {
    _events = port.invalidations.listen((_) => suspend());
  }

  final NativeOverlayObservationPort port;
  late final StreamSubscription<void> _events;
  NativeOverlayObservation? _observation, _baseline;
  NativeHotkeyCheck _hotkey = NativeHotkeyCheck.notStarted;
  NativePreviewVisit _preview = NativePreviewVisit.notStarted;
  Timer? _poll, _deadline;
  int _epoch = 0;
  bool _reading = false,
      _visiting = false,
      _disposed = false,
      _readError = false;

  void _publish() {
    if (!_disposed) {
      value = NativeOverlayCheckView(
        observation: _observation,
        hotkey: _hotkey,
        preview: _preview,
        busy: _reading || _visiting || _hotkey == NativeHotkeyCheck.waiting,
        readError: _readError,
      );
    }
  }

  void _stopTimers() {
    _poll?.cancel();
    _deadline?.cancel();
    _poll = _deadline = null;
  }

  void stopHotkeyCheck() {
    if (_disposed || _hotkey != NativeHotkeyCheck.waiting) return;
    _stopTimers();
    _baseline = null;
    _hotkey = NativeHotkeyCheck.notStarted;
    _publish();
  }

  /// Scope change, disabled panel or navigation drops evidence immediately,
  /// but does not pretend that an outstanding read/preview route has finished.
  void suspend() {
    if (_disposed) return;
    _epoch++;
    _stopTimers();
    _baseline = _observation = null;
    if (_hotkey != NativeHotkeyCheck.notStarted) {
      _hotkey = NativeHotkeyCheck.interrupted;
    }
    if (!_visiting) _preview = NativePreviewVisit.notStarted;
    _readError = false;
    _publish();
  }

  static bool _sameHotkeyScope(
    NativeOverlayObservation a,
    NativeOverlayObservation b,
  ) =>
      a.generation == b.generation &&
      a.runtimeId == b.runtimeId &&
      a.hotkey.configurationRevision == b.hotkey.configurationRevision &&
      a.hotkey.binding == b.hotkey.binding &&
      a.hotkey.state == b.hotkey.state &&
      a.hotkey.acceptedInputCount >= b.hotkey.acceptedInputCount;

  Future<void> refresh() async {
    if (_disposed || _reading) return;
    _reading = true;
    final epoch = ++_epoch;
    _publish();
    try {
      final result = await port.read();
      if (_disposed || epoch != _epoch) return;
      _observation = result;
      _readError = false;
      final baseline = _baseline;
      if (baseline != null) {
        if (result == null ||
            result.preview.sessionId != null ||
            !_sameHotkeyScope(result, baseline)) {
          _stopTimers();
          _baseline = null;
          _hotkey = NativeHotkeyCheck.interrupted;
        } else if (result.acceptedHotkeyInputSince(baseline)) {
          _stopTimers();
          _baseline = result;
          _hotkey = NativeHotkeyCheck.observed;
        }
      }
    } on Object {
      if (!_disposed && epoch == _epoch) {
        _observation = _baseline = null;
        _stopTimers();
        if (_hotkey != NativeHotkeyCheck.notStarted) {
          _hotkey = NativeHotkeyCheck.interrupted;
        }
        _readError = true;
      }
    } finally {
      _reading = false;
      _publish();
    }
  }

  /// Read a fresh baseline only after an explicit click. Registration, old
  /// input and a preview frame are not a key test. No key input is generated.
  Future<void> startHotkeyCheck() async {
    if (_disposed || value.busy) return;
    await refresh();
    if (_disposed || !value.canCheckHotkey) return;
    _baseline = _observation;
    _hotkey = NativeHotkeyCheck.waiting;
    _poll = Timer.periodic(const Duration(milliseconds: 750), (_) {
      unawaited(refresh());
    });
    _deadline = Timer(const Duration(seconds: 30), () {
      if (_disposed || _hotkey != NativeHotkeyCheck.waiting) return;
      _stopTimers();
      _baseline = null;
      _hotkey = NativeHotkeyCheck.timedOut;
      _publish();
    });
    _publish();
  }

  /// Opening the original editor is not a passed preview test. A current
  /// preview belonging to another caller blocks this visit; no close is sent.
  Future<void> visitPreview(Future<void> Function() open) async {
    if (_disposed || value.busy) return;
    _visiting = true;
    _preview = NativePreviewVisit.opening;
    _publish();
    try {
      await refresh();
      final before = _observation;
      if (_disposed) return;
      if (before == null || before.preview.sessionId != null) {
        _preview = NativePreviewVisit.blocked;
        return;
      }
      final epoch = _epoch;
      await open();
      if (_disposed) return;
      if (epoch != _epoch) {
        _preview = NativePreviewVisit.failed;
        return;
      }
      await refresh();
      final after = _observation;
      _preview =
          after == null ||
              after.generation != before.generation ||
              after.runtimeId != before.runtimeId
          ? NativePreviewVisit.failed
          : after.preview.sessionId != null
          ? NativePreviewVisit.blocked
          : NativePreviewVisit.returned;
    } on Object {
      if (!_disposed) _preview = NativePreviewVisit.failed;
    } finally {
      _visiting = false;
      _publish();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _stopTimers();
    unawaited(_events.cancel());
    super.dispose();
  }
}
