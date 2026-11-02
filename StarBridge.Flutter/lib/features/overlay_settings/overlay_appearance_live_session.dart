import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

/// Presentation only. Intentionally omits hotkeys, source grants, account
/// context, collection receipts and pet actions. Host chooses the real display.
@immutable
final class OverlayAppearanceLiveFrame {
  OverlayAppearanceLiveFrame({
    required this.appearanceId,
    required this.settings,
    required List<OverlayWorkspaceLayoutItem> layout,
    required this.options,
    required this.language,
    required this.reduceMotion,
  }) : layout = List.unmodifiable(layout) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(appearanceId) ||
        !const {'zh', 'zh-CN', 'zh-Hant', 'en', 'en-US'}.contains(language) ||
        layout.length != 4 ||
        layout.map((item) => item.key).toSet().length != layout.length) {
      throw const FormatException('Invalid live appearance frame.');
    }
    for (final item in layout) {
      if (!const {'Notice', 'Squads', 'Members', 'Chat'}.contains(item.key)) {
        throw const FormatException('Invalid preview module.');
      }
      // Reuse normal layout validation, not a separate permissive preview codec.
      OverlayWorkspaceLayoutItem.fromMap(item.toMap());
    }
  }
  final String appearanceId;
  final OverlayWorkspaceSettings settings;
  final List<OverlayWorkspaceLayoutItem> layout;
  final OverlayAppearanceOptions options;
  final String language;
  final bool reduceMotion;

  Map<String, Object?> toMap() => {
    'appearanceId': appearanceId,
    'settings': settings.toMap(),
    'layout': layout.map((item) => item.toMap()).toList(growable: false),
    'appearanceOptions': options.toMap(),
    'language': language,
    'reduceMotion': reduceMotion,
  };
}

/// New capability, not assumed from the old open/close-only preview port.
abstract interface class OverlayAppearanceLivePort {
  Future<String> openLivePreview(OverlayAppearanceLiveFrame frame);
  Future<int> updateLivePreview(
    String sessionId,
    int revision,
    OverlayAppearanceLiveFrame frame,
  );
  Future<void> closeLivePreview(String sessionId);
  Future<int> renewLivePreview(String sessionId, int revision);
}

/// Availability must be positively declared by the new Host capability.
abstract interface class OverlayAppearanceLiveAvailability {
  bool get supportsLiveAppearancePreview;
}

/// Optional ownership invalidation from a transport; it is not an activity
/// source for the pet. Local test ports need not invent account events.
abstract interface class OverlayAppearanceLiveOwnerEvents {
  Stream<void> get previewOwnerChanges;
}

/// Feedback from the installed renderer for the most recently acknowledged frame.
abstract interface class OverlayAppearanceLivePlacementPort {
  Map<String, String> get placementStates;
}

@immutable
final class OverlayPreviewControlArea {
  const OverlayPreviewControlArea(this.x, this.y, this.width, this.height);
  final double x, y, width, height;
  bool get valid =>
      x.isFinite &&
      y.isFinite &&
      width.isFinite &&
      height.isFinite &&
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1.000000001 &&
      y + height <= 1.000000001;
  Map<String, Object?> toMap() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

abstract interface class OverlayAppearanceLiveControlsPort {
  Future<int> protectLivePreviewControls(
    String sessionId,
    int revision,
    List<OverlayPreviewControlArea> areas,
  );
}

enum OverlayAppearancePreviewPlayback {
  noticeShow,
  noticeHide,
  eventAdd,
  eventHide,
  eventSequence,
  barrage,
  stop,
  transition;

  String get wireName => '${name[0].toUpperCase()}${name.substring(1)}';
}

abstract interface class OverlayAppearanceLivePlaybackPort {
  Future<bool> playLivePreview(
    String sessionId,
    int revision,
    OverlayAppearancePreviewPlayback action,
  );
}

enum OverlayAppearanceLivePhase {
  idle,
  opening,
  live,
  updating,
  failed,
  closing,
  closed,
}

/// Owns one temporary native session. Latest passive draft wins, writes are
/// serial, and Save/normal HUD commands are deliberately outside this interface.
final class OverlayAppearanceLiveSession extends ChangeNotifier {
  OverlayAppearanceLiveSession(this._port) {
    if (_port is OverlayAppearanceLiveOwnerEvents) {
      _ownerSubscription = (_port as OverlayAppearanceLiveOwnerEvents)
          .previewOwnerChanges
          .listen((_) {
            if (!_stop) unawaited(close().catchError((Object _) {}));
          });
    }
  }
  final OverlayAppearanceLivePort _port;
  StreamSubscription<void>? _ownerSubscription;
  OverlayAppearanceLivePhase _phase = OverlayAppearanceLivePhase.idle;
  Object? _failure;
  OverlayAppearanceLivePhase get phase => _phase;
  Object? get failure => _failure;
  String? _id;
  OverlayAppearanceLiveFrame? _desired;
  int _wanted = 0;
  int _applied = 0;
  Future<void>? _opening;
  Future<void>? _pumping;
  Future<void>? _closing;
  Future<void>? _protecting;
  Future<bool>? _playing;
  Timer? _lease;
  Future<void>? _renewing;
  int _renewalRevision = 0;
  int _playbackRevision = 0;
  int _controlRevision = 0;
  bool _stop = false, _disposed = false;
  int get appliedRevision => _applied;
  int get desiredRevision => _wanted;
  bool get hasSession => _id != null;
  bool get supportsControlProtection =>
      _port is OverlayAppearanceLiveControlsPort;
  bool get supportsPlayback => _port is OverlayAppearanceLivePlaybackPort;
  bool get playbackBusy => _playing != null;
  Map<String, String> get placementStates =>
      _phase == OverlayAppearanceLivePhase.live &&
          _wanted == _applied &&
          _port is OverlayAppearanceLivePlacementPort
      ? (_port as OverlayAppearanceLivePlacementPort).placementStates
      : const {};

  /// One explicit intent, not an action queue. Await latest passive draft and
  /// control protection so the example never runs against an older skin/layout.
  Future<bool> play(OverlayAppearancePreviewPlayback action) {
    if (_stop ||
        _disposed ||
        !supportsPlayback ||
        _id == null ||
        _playing != null) {
      throw StateError('Preview playback unavailable.');
    }
    final completion = Completer<bool>();
    _playing = completion.future;
    notifyListeners();
    unawaited(() async {
      try {
        while (_pumping != null) {
          await _pumping;
        }
        await _protecting;
        if (_stop || _phase == OverlayAppearanceLivePhase.failed) {
          throw StateError('Preview stopped.');
        }
        final accepted = await (_port as OverlayAppearanceLivePlaybackPort)
            .playLivePreview(_id!, ++_playbackRevision, action);
        completion.complete(!_stop && accepted);
      } on Object catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _playing = null;
        if (!_disposed) notifyListeners();
      }
    }());
    return completion.future;
  }

  /// Manual control relocation/popup opening awaits this receipt before making
  /// its new geometry visible. These transitions are ordered, not coalesced.
  Future<void> protectControls(List<OverlayPreviewControlArea> areas) {
    if (_stop || _disposed || !supportsControlProtection) {
      throw StateError('Preview protection unavailable.');
    }
    if (areas.length > 16 || areas.any((a) => !a.valid)) {
      throw const FormatException('Invalid control areas.');
    }
    final snapshot = List<OverlayPreviewControlArea>.unmodifiable(areas);
    final previous = _protecting;
    final revision = ++_controlRevision;
    final next = () async {
      try {
        await previous;
      } on Object {
        /* A fresh explicit protection can retry. */
      }
      await _opening;
      if (_stop || _id == null) throw StateError('Preview stopped.');
      final applied = await (_port as OverlayAppearanceLiveControlsPort)
          .protectLivePreviewControls(_id!, revision, snapshot);
      if (applied != revision) {
        throw const FormatException('Invalid control protection receipt.');
      }
    }();
    _protecting = next;
    return next;
  }

  Future<void> open(OverlayAppearanceLiveFrame frame) {
    if (_disposed || phase != OverlayAppearanceLivePhase.idle) {
      throw StateError('Preview already started.');
    }
    _desired = frame;
    _set(OverlayAppearanceLivePhase.opening);
    return _opening = _open(frame);
  }

  Future<void> _open(OverlayAppearanceLiveFrame frame) async {
    try {
      final id = await _port.openLivePreview(frame);
      if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(id)) {
        throw const FormatException('Invalid preview session receipt.');
      }
      _id = id;
      if (_stop) return;
      _set(OverlayAppearanceLivePhase.live);
      if (!_stop) {
        _lease = Timer.periodic(
          const Duration(seconds: 30),
          (_) => _renewLease(),
        );
      }
      _startPump();
    } on Object catch (error) {
      if (!_stop) _set(OverlayAppearanceLivePhase.failed, error);
    }
  }

  // Independent of passive drafts and example playback. A delayed receipt is
  // never queued behind another heartbeat, and no failure auto-reopens a HUD.
  void _renewLease() {
    if (_stop || _disposed || _id == null || _renewing != null) return;
    final completion = Completer<void>();
    _renewing = completion.future;
    unawaited(() async {
      try {
        final revision = ++_renewalRevision;
        final receipt = await _port.renewLivePreview(_id!, revision);
        if (receipt != revision) {
          throw const FormatException('Invalid preview renewal receipt.');
        }
      } on Object {
        // A lost lease ends this temporary session. Native also has its own
        // bounded expiry if the page/transport disappears before Close arrives.
        if (!_stop) unawaited(close().catchError((Object _) {}));
      } finally {
        _renewing = null;
        completion.complete();
      }
    }());
  }

  /// No timer replay, open/reopen, persistence or pet command on configuration.
  void update(OverlayAppearanceLiveFrame frame) {
    if (_stop || _disposed || phase == OverlayAppearanceLivePhase.idle) {
      throw StateError('Preview is not editable.');
    }
    _desired = frame;
    _wanted++;
    _startPump();
  }

  void retryUpdate() {
    if (_stop ||
        _disposed ||
        _id == null ||
        phase != OverlayAppearanceLivePhase.failed) {
      return;
    }
    _startPump();
  }

  void _startPump() {
    if (_stop || _id == null || _pumping != null || _wanted <= _applied) return;
    final completion = Completer<void>();
    _pumping = completion.future;
    unawaited(_drain(completion));
  }

  Future<void> _drain(Completer<void> completion) async {
    var failed = false;
    try {
      while (!_stop && _wanted > _applied) {
        final revision = _wanted;
        final draft = _desired!;
        _set(OverlayAppearanceLivePhase.updating);
        final receipt = await _port.updateLivePreview(_id!, revision, draft);
        if (_stop) return;
        if (receipt != revision) {
          throw const FormatException('Invalid preview revision receipt.');
        }
        _applied = receipt;
      }
      if (!_stop) _set(OverlayAppearanceLivePhase.live);
    } on Object catch (error) {
      failed = true;
      if (!_stop) _set(OverlayAppearanceLivePhase.failed, error);
      // Retain the latest draft and session. Explicit retry or a new edit can
      // recover; no blind auto-reopen or old-draft replay.
    } finally {
      _pumping = null;
      completion.complete();
      // A UI listener can make another edit when the successful receipt changes
      // phase to live. It saw an in-flight pump; drain that new intent now.
      if (!failed && !_stop && _wanted > _applied) _startPump();
    }
  }

  Future<void> close() {
    if (_closing case final pending?) return pending;
    if (phase == OverlayAppearanceLivePhase.closed) return Future.value();
    _stop = true;
    _lease?.cancel();
    _lease = null;
    _set(OverlayAppearanceLivePhase.closing);
    final completion = Completer<void>();
    _closing = completion.future;
    unawaited(_close(completion));
    return completion.future;
  }

  Future<void> _close(Completer<void> completion) async {
    try {
      await _ownerSubscription?.cancel();
      _ownerSubscription = null;
      await _opening;
      await _pumping;
      await _renewing;
      try {
        await _playing;
      } on Object {
        /* Close still removes examples. */
      }
      try {
        await _protecting;
      } on Object {
        /* Closing still removes the window. */
      }
      if (_id case final id?) await _port.closeLivePreview(id);
      _id = null;
      _desired = null;
      _set(OverlayAppearanceLivePhase.closed);
      completion.complete();
    } on Object catch (error, stack) {
      _set(OverlayAppearanceLivePhase.failed, error);
      completion.completeError(error, stack);
    } finally {
      _closing = null;
    }
  }

  void _set(OverlayAppearanceLivePhase next, [Object? error]) {
    _phase = next;
    _failure = error;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Explicit mode exit awaits close and reports errors. This final safety net
    // cannot report to a dead widget; Native's bounded expiry is still required.
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
