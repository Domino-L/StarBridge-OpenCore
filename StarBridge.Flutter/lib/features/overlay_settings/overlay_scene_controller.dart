import 'dart:async';

import 'package:flutter/foundation.dart';

@immutable
final class OverlaySceneTarget {
  const OverlaySceneTarget(this.code, this.name);
  final String code, name;
}

@immutable
final class OverlaySceneState {
  const OverlaySceneState({
    this.revision = 0,
    this.mode = 'auto',
    this.code,
    this.actualId,
    this.sourceOwnerKey,
    this.automaticPresetSourceId,
    this.contextGeneration,
    this.presetBindingId,
    this.temporarySourceId,
    this.resolvedSourceIds,
    this.status = 'loading',
    this.fleetStatus,
    this.fleetName,
    this.targets = const [],
    this.available = false,
    this.busy = false,
    this.failure = false,
  });
  final int revision;
  final String mode, status;
  // Main fleet source state from the Host: ready, notMember, unavailable or
  // loading. Null when the Host cannot show the main fleet at all.
  final String? fleetStatus;
  // The main fleet's own name; it is listed like one more organization.
  final String? fleetName;

  /// Whether the main fleet is offered as a choice. The name only exists after
  /// a confirmed membership read, so not a member (or not known yet) means the
  /// entry is simply absent, and a failed read never invents one.
  bool get offersFleet => fleetName != null && fleetStatus != 'notMember';

  /// "Domino Pizza · 主舰队": the fleet's name, marked so it is not mistaken
  /// for a community organization of the same name.
  String fleetLabel(String Function(String key) copy) => offersFleet
      ? '$fleetName · ${copy('overlay.source.fleet')}'
      : copy('overlay.source.missing');
  final String? code, actualId;
  final String? sourceOwnerKey;
  final String? automaticPresetSourceId;
  final int? contextGeneration;
  final String? presetBindingId, temporarySourceId;
  // Host-resolved preview metadata, not a grant to display remote content.
  final Map<String, String?>? resolvedSourceIds;
  final List<OverlaySceneTarget> targets;
  final bool available, busy, failure;
  String get accountPreferredId => mode == 'community' ? 'org:$code' : mode;
  String get preferredId =>
      temporarySourceId ?? presetBindingId ?? accountPreferredId;
  OverlaySceneState renamed(String targetCode, String name) =>
      OverlaySceneState(
        revision: revision,
        mode: mode,
        code: code,
        actualId: actualId,
        sourceOwnerKey: sourceOwnerKey,
        automaticPresetSourceId: automaticPresetSourceId,
        contextGeneration: contextGeneration,
        presetBindingId: presetBindingId,
        temporarySourceId: temporarySourceId,
        resolvedSourceIds: resolvedSourceIds,
        status: status,
        fleetStatus: fleetStatus,
        fleetName: fleetName,
        targets: List.unmodifiable(
          targets.map(
            (row) => row.code == targetCode
                ? OverlaySceneTarget(row.code, name)
                : row,
          ),
        ),
        available: available,
        busy: busy,
        failure: failure,
      );
  OverlaySceneState pending({bool failed = false}) => OverlaySceneState(
    revision: revision,
    mode: mode,
    code: code,
    actualId: failed ? null : actualId,
    sourceOwnerKey: sourceOwnerKey,
    automaticPresetSourceId: failed ? null : automaticPresetSourceId,
    contextGeneration: contextGeneration,
    presetBindingId: presetBindingId,
    temporarySourceId: temporarySourceId,
    resolvedSourceIds: failed ? null : resolvedSourceIds,
    status: failed ? 'unavailable' : status,
    fleetStatus: fleetStatus,
    fleetName: fleetName,
    targets: targets,
    available: available,
    busy: !failed,
    failure: failed,
  );
}

abstract interface class OverlayScenePort {
  Stream<void> get invalidations;
  Future<OverlaySceneState> read();
  Future<OverlaySceneState> select(int revision, String mode, String? code);
  Future<OverlaySceneState> focusCommunity(String code);
  Future<OverlaySceneState> focusFleet();
  void close();
}

final class OverlaySceneController {
  OverlaySceneController(this._port, {bool autoStart = true}) {
    _events = _port.invalidations.listen((_) {
      _epoch++;
      _pendingNames.clear();
      _pageId = null;
      _focusDirty = false;
      _busy = false;
      _view.value = const OverlaySceneState();
      unawaited(refresh());
    });
    if (autoStart) {
      _timer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(refresh()),
      );
      unawaited(refresh());
    }
  }
  final OverlayScenePort _port;
  // Wired by the settings coordinator. A selection is always the remembered
  // account choice and never creates a session-only source (the Host drops a
  // leftover one once no plan fixes a source). A plan's fixed source is
  // released explicitly.
  Future<bool> Function()? followShared;
  final _view = ValueNotifier(const OverlaySceneState());
  ValueListenable<OverlaySceneState> get projection => _view;
  late final StreamSubscription<void> _events;
  Timer? _timer;
  bool _closed = false, _busy = false;
  int _epoch = 0, _failedReads = 0;
  // The page the user is on, as a source id: 'org:<code>' or 'fleet'.
  String? _pageId;
  bool _focusDirty = false;
  void focusCommunity(String code) {
    if (code.isNotEmpty) _focusPage('org:$code');
  }

  void focusFleet() => _focusPage('fleet');

  void _focusPage(String id) {
    if (_closed || _pageId == id) return;
    _pageId = id;
    _focusDirty = true;
    unawaited(refresh());
  }

  final _pendingNames = <String, String>{};
  void renameCommunity(String code, String name) {
    if (_closed) return;
    if (_busy) _pendingNames[code] = name;
    _view.value = _view.value.renamed(code, name);
  }

  OverlaySceneState _mergeNames(OverlaySceneState value) {
    for (final entry in _pendingNames.entries) {
      value = value.renamed(entry.key, entry.value);
    }
    return value;
  }

  Future<void> refresh() async {
    if (_closed || _busy) return;
    _busy = true;
    final epoch = _epoch;
    final focused = _focusDirty ? _pageId : null;
    _pendingNames.clear();
    try {
      final state = focused == null
          ? await _port.read()
          : focused == 'fleet'
          ? await _port.focusFleet()
          : await _port.focusCommunity(focused.substring(4));
      if (!_closed && epoch == _epoch) {
        _failedReads = 0;
        _view.value = _mergeNames(state);
        if (focused == _pageId) _focusDirty = false;
      }
    } catch (_) {
      // A missed background read keeps the last answer; the timer reads again
      // in 10 s. Only repeated misses (about half a minute) are shown.
      if (!_closed &&
          epoch == _epoch &&
          focused == null &&
          ++_failedReads >= 3) {
        _view.value = _view.value.pending(failed: true);
      }
    } finally {
      if (epoch == _epoch) {
        _busy = false;
        if (!_closed && _focusDirty && focused != _pageId) {
          unawaited(refresh());
        }
      }
    }
  }

  Future<bool> select(String id) async {
    if (_closed || _view.value.busy || !_view.value.available) {
      return false;
    }
    final before = _view.value;
    if (id == 'followShared') {
      if (before.presetBindingId == null || followShared == null) return false;
      return _run(before, () async {
        if (!await followShared!()) throw StateError('Plan source kept');
        return null;
      }, (result) => result.presetBindingId == null);
    }
    final mode = id.startsWith('org:') ? 'community' : id;
    final code = mode == 'community' ? id.substring(4) : null;
    // A plan's fixed source wins over the account choice, so the pickers offer
    // "follow" first instead of a write that would visibly change nothing.
    if (before.presetBindingId != null ||
        !['auto', 'room', 'community', 'fleet'].contains(mode) ||
        mode == 'fleet' && !before.offersFleet ||
        mode == 'community' && !before.targets.any((x) => x.code == code)) {
      return false;
    }
    return _run(
      before,
      () => _port.select(before.revision, mode, code),
      (result) => result.mode == mode && result.code == code,
    );
  }

  /// [work] returns the Host result, or null to confirm by reading.
  Future<bool> _run(
    OverlaySceneState before,
    Future<OverlaySceneState?> Function() work,
    bool Function(OverlaySceneState result) applied,
  ) async {
    _pendingNames.clear();
    _busy = true;
    // A visible picker must not silently discard clicks during a background
    // read. A manual selection supersedes that read; late results stay stale.
    final epoch = ++_epoch;
    _view.value = before.pending();
    try {
      final written = await work();
      if (_closed || epoch != _epoch) return false;
      final result = written ?? await _port.read();
      if (_closed || epoch != _epoch) return false;
      _view.value = _mergeNames(result);
      return applied(result);
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        _view.value = _mergeNames(before.pending(failed: true));
      }
      return false;
    } finally {
      if (epoch == _epoch) {
        _busy = false;
        // Confirm uncertain local writes by reading. Never replay the write.
        if (!_closed && (_view.value.failure || _focusDirty)) {
          unawaited(refresh());
        }
      }
    }
  }

  void dispose() {
    _closed = true;
    _epoch++;
    _timer?.cancel();
    unawaited(_events.cancel());
    _port.close();
    _view.dispose();
  }
}
