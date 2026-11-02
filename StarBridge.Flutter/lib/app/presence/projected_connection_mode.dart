import 'package:flutter/foundation.dart';

import '../../features/onboarding/connection_mode_port.dart';
import '../../shared/release/official_client_profile.dart';

/// The auxiliary tray borrows display facts and routes commands back to the
/// primary owner. It cannot invoke Native mode routes or create another owner.
final class ProjectedConnectionMode extends ChangeNotifier
    implements ConnectionModeControl {
  ProjectedConnectionMode({required this.source, required this.write}) {
    source.addListener(_changed);
  }
  final ValueListenable<ConnectionModeSnapshot> source;
  final Future<void> Function(Object scope) write;
  bool _busy = false, _failed = false, _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  ConnectionModeSnapshot get snapshot => OfficialClientProfile.connectionModes
      ? source.value
      : const ConnectionModeSnapshot();
  @override
  bool get busy => _busy || snapshot.state == ConnectionModeState.switching;
  @override
  bool get failed => _failed;
  @override
  bool get allowsOnlineTraffic =>
      !_disposed &&
      !_busy &&
      const {
        ConnectionModeState.unsupported,
        ConnectionModeState.online,
      }.contains(snapshot.state);
  @override
  bool get canEnterOffline =>
      OfficialClientProfile.connectionModes &&
      !_disposed &&
      !busy &&
      snapshot.canEnterOffline &&
      snapshot.state == ConnectionModeState.online;
  @override
  Future<bool> enterOffline() async {
    if (!canEnterOffline) return false;
    final scope = snapshot.scope;
    _busy = true;
    _failed = false;
    notifyListeners();
    try {
      await write(scope);
      if (_disposed || source.value.scope != scope) return false;
      _failed = !snapshot.isOffline;
      return snapshot.isOffline;
    } on Object {
      if (!_disposed) _failed = true;
      return false;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    source.removeListener(_changed);
    super.dispose();
  }
}
