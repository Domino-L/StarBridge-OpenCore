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
    this.status = 'loading',
    this.targets = const [],
    this.available = false,
    this.busy = false,
    this.failure = false,
  });
  final int revision;
  final String mode, status;
  final String? code, actualId;
  final List<OverlaySceneTarget> targets;
  final bool available, busy, failure;
  String get preferredId => mode == 'community' ? 'org:$code' : mode;
  OverlaySceneState renamed(String targetCode, String name) =>
      OverlaySceneState(
        revision: revision,
        mode: mode,
        code: code,
        actualId: actualId,
        status: status,
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
    status: failed ? 'unavailable' : status,
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
  void close();
}

final class OverlaySceneController {
  OverlaySceneController(this._port, {bool autoStart = true}) {
    _events = _port.invalidations.listen((_) {
      _epoch++;
      _pendingNames.clear();
      _pageCode = null;
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
  final _view = ValueNotifier(const OverlaySceneState());
  ValueListenable<OverlaySceneState> get projection => _view;
  late final StreamSubscription<void> _events;
  Timer? _timer;
  bool _closed = false, _busy = false;
  int _epoch = 0;
  String? _pageCode;
  bool _focusDirty = false;
  void focusCommunity(String code) {
    if (_closed || code.isEmpty || _pageCode == code) return;
    _pageCode = code;
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
    final focused = _focusDirty ? _pageCode : null;
    _pendingNames.clear();
    try {
      final state = focused == null
          ? await _port.read()
          : await _port.focusCommunity(focused);
      if (!_closed && epoch == _epoch) {
        _view.value = _mergeNames(state);
        if (focused == _pageCode) _focusDirty = false;
      }
    } catch (_) {
      if (!_closed && epoch == _epoch && focused == null) {
        _view.value = _view.value.pending(failed: true);
      }
    } finally {
      if (epoch == _epoch) {
        _busy = false;
        if (!_closed && _focusDirty && focused != _pageCode) {
          unawaited(refresh());
        }
      }
    }
  }

  Future<bool> select(String id) async {
    if (_closed || _busy || !_view.value.available || id == 'fleet') {
      return false;
    }
    final mode = id.startsWith('org:') ? 'community' : id;
    final code = mode == 'community' ? id.substring(4) : null;
    if (!['auto', 'room', 'community'].contains(mode) ||
        mode == 'community' &&
            !_view.value.targets.any((x) => x.code == code)) {
      return false;
    }
    final before = _view.value;
    _pendingNames.clear();
    _busy = true;
    final epoch = _epoch;
    _view.value = before.pending();
    try {
      final result = await _port.select(before.revision, mode, code);
      if (_closed || epoch != _epoch) return false;
      _view.value = _mergeNames(result);
      return result.mode == mode && result.code == code;
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
