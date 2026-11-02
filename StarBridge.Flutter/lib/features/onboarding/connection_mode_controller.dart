import 'dart:async';

import 'package:flutter/foundation.dart';

import 'connection_mode_port.dart';
import '../../shared/release/official_client_profile.dart';

final class ConnectionModeController extends ChangeNotifier
    implements ConnectionModeControl, ConnectionModeDisplayContinuitySource {
  ConnectionModeController(this.port) {
    if (!OfficialClientProfile.connectionModes) return;
    _hasModeOwner = port.supported;
    _events = port.invalidations.listen((_) {
      _recheck?.cancel();
      _epoch++;
      _hasModeOwner = _hasModeOwner || port.supported;
      _snapshot = ConnectionModeSnapshot(
        state: _hasModeOwner
            ? ConnectionModeState.unavailable
            : ConnectionModeState.unsupported,
      );
      _refreshQueued = true;
      notifyListeners();
      if (!_busy) unawaited(refresh());
    });
  }
  final ConnectionModePort port;
  StreamSubscription<void>? _events;
  ConnectionModeSnapshot _snapshot = const ConnectionModeSnapshot();
  Future<void>? _reading;
  Timer? _recheck;
  bool _busy = false,
      _failed = false,
      _disposed = false,
      _refreshQueued = false;
  bool _hasModeOwner = false;
  @override
  OnlineModeDisplayContinuity? get displayContinuity =>
      !_disposed &&
          !_failed &&
          !_busy &&
          snapshot.state == ConnectionModeState.unavailable &&
          port is ConnectionModeDisplayContinuitySource
      ? (port as ConnectionModeDisplayContinuitySource).displayContinuity
      : null;
  int _epoch = 0;
  @override
  ConnectionModeSnapshot get snapshot => _snapshot;
  @override
  bool get busy => _busy || snapshot.state == ConnectionModeState.switching;
  @override
  bool get failed => _failed;
  @override
  bool get allowsOnlineTraffic =>
      !_disposed &&
      !_busy &&
      (!OfficialClientProfile.connectionModes ||
          !_hasModeOwner && !port.supported ||
          port.supported && snapshot.state == ConnectionModeState.online);
  @override
  bool get canEnterOffline =>
      OfficialClientProfile.connectionModes &&
      !_disposed &&
      !_busy &&
      _reading == null &&
      port.supported &&
      snapshot.state == ConnectionModeState.online &&
      snapshot.canEnterOffline;
  Future<void> refresh() {
    if (_disposed || !OfficialClientProfile.connectionModes) {
      return Future.value();
    }
    _recheck?.cancel();
    if (_busy) {
      _refreshQueued = true;
      return Future.value();
    }
    return _reading ??= _read();
  }

  Future<void> _read() async {
    final epoch = _epoch;
    _refreshQueued = false;
    // Publish the task before any completion so concurrent readers share it.
    await Future<void>.delayed(Duration.zero);
    try {
      _hasModeOwner = _hasModeOwner || port.supported;
      final result = await port.read();
      if (!_disposed && epoch == _epoch) {
        _snapshot =
            _hasModeOwner && result.state == ConnectionModeState.unsupported
            ? const ConnectionModeSnapshot(
                state: ConnectionModeState.unavailable,
              )
            : result;
        _failed = false;
      }
    } on Object {
      if (!_disposed && epoch == _epoch) {
        _snapshot = ConnectionModeSnapshot(
          state: _hasModeOwner
              ? ConnectionModeState.unavailable
              : ConnectionModeState.unsupported,
        );
        _failed = true;
      }
    } finally {
      _reading = null;
      if (!_disposed) {
        notifyListeners();
        if (_refreshQueued) {
          unawaited(refresh());
        } else {
          _observePending();
        }
      }
    }
  }

  @override
  Future<bool> enterOffline() async {
    if (!canEnterOffline || snapshot.revision == null) return false;
    final epoch = ++_epoch, revision = snapshot.revision!;
    _busy = true;
    _failed = false;
    notifyListeners();
    try {
      final result = await port.enterOffline(revision);
      if (_disposed || epoch != _epoch) return false;
      _snapshot = result;
      _failed = !result.isOffline;
      return result.isOffline;
    } on Object {
      if (!_disposed && epoch == _epoch) {
        _snapshot = const ConnectionModeSnapshot(
          state: ConnectionModeState.unavailable,
        );
        _failed = true;
        _refreshQueued = true; // Reconcile with a read, never replay a write.
      }
      return false;
    } finally {
      _busy = false;
      if (!_disposed) {
        notifyListeners();
        if (_refreshQueued) {
          unawaited(refresh());
        } else {
          _observePending();
        }
      }
    }
  }

  // Only a real pending Native transaction needs observation. This timer does
  // not replay writes, query an account, or continue after a read failure.
  void _observePending() {
    if (_disposed ||
        _busy ||
        _reading != null ||
        snapshot.state != ConnectionModeState.switching) {
      return;
    }
    _recheck?.cancel();
    _recheck = Timer(const Duration(seconds: 2), () {
      _recheck = null;
      if (!_disposed) unawaited(refresh());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _recheck?.cancel();
    _epoch++;
    unawaited(_events?.cancel());
    super.dispose();
  }
}
