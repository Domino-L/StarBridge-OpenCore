import 'dart:async';

import 'overlay_workspace_models.dart';
import 'overlay_workspace_port.dart';
import 'overlay_workspace_projection.dart';

/// The draft a live runtime sync applies, or null before a workspace is read.
extension OverlayWorkspaceRuntimeDraftOf on OverlayWorkspaceProjection {
  OverlayWorkspaceRuntimeDraft? get runtimeDraft {
    final revision = snapshot?.revision;
    if (!available || revision == null) return null;
    return OverlayWorkspaceRuntimeDraft(
      expectedRevision: revision,
      settings: settings!,
      layout: layout,
      hotkey: hotkey!,
      sources: sources,
      appearanceOptions: snapshot!.appearanceOptionsEnabled
          ? appearanceOptions
          : null,
    );
  }
}

/// Host runtime pushes (`overlay.runtime.changed`) for one workspace module.
///
/// Every runtime change is pushed, so the last applied push is the newest
/// state: a runtime response whose request overlapped an applied push must not
/// replace it. Callers take [mark] before a request and keep the response only
/// while [unchangedSince] holds.
final class OverlayRuntimePushes {
  OverlayRuntimePushes(
    this._port, {
    required bool Function(OverlayRuntimeSnapshot runtime) apply,
  }) {
    if (_port case final OverlayRuntimeChangePort changes) {
      _subscription = changes.runtimeChanges.listen((runtime) {
        if (apply(runtime)) _applied++;
      });
    }
  }

  final OverlayWorkspacePort _port;

  /// False on an older Host; callers then keep polling as the fallback. Read
  /// live: Host capabilities may arrive after the module is built.
  bool get supported =>
      _port is OverlayRuntimeChangePort &&
      (_port as OverlayRuntimeChangePort).supportsRuntimeChanges;
  StreamSubscription<OverlayRuntimeSnapshot>? _subscription;
  int _applied = 0;

  int get mark => _applied;
  bool unchangedSince(int mark) => mark == _applied;

  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// True when [b] differs from [a] at most in runtime facts, as after a push.
  static bool sameExceptRuntime(
    OverlayWorkspaceProjection a,
    OverlayWorkspaceProjection b,
  ) =>
      identical(a, b) ||
      a.operation == b.operation &&
          a.runtimeOperation == b.runtimeOperation &&
          identical(a.snapshot, b.snapshot) &&
          identical(a.settings, b.settings) &&
          identical(a.layout, b.layout) &&
          a.renderMode == b.renderMode &&
          identical(a.hotkey, b.hotkey) &&
          identical(a.sources, b.sources) &&
          identical(a.appearanceOptions, b.appearanceOptions) &&
          a.failure == b.failure &&
          a.dirty == b.dirty;
}

/// Live draft-to-HUD sync: at most one runtime request in flight; edits during
/// a round coalesce into exactly one more round with the newest draft.
final class OverlayLiveRuntimeSync {
  OverlayLiveRuntimeSync({required this.canSync, required this.round});

  final bool Function() canSync;
  final Future<void> Function() round;
  bool _inFlight = false;
  bool _requested = false;
  bool _closed = false;

  void request() {
    if (_closed || !canSync()) return;
    _requested = true;
    if (!_inFlight) unawaited(_drain());
  }

  void cancelPending() => _requested = false;

  void close() {
    _closed = true;
    _requested = false;
  }

  Future<void> _drain() async {
    if (_inFlight || _closed) return;
    _inFlight = true;
    try {
      while (_requested && !_closed) {
        _requested = false;
        if (!canSync()) break;
        await round();
      }
    } finally {
      _inFlight = false;
      if (_requested && !_closed) request();
    }
  }
}
