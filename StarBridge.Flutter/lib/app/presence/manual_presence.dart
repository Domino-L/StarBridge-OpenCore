import 'package:flutter/foundation.dart';

import '../../features/onboarding/connection_mode_port.dart';
import '../../shared/release/official_client_profile.dart';

/// Historical WPF/Host wire modes. The UI offers online/invisible only;
/// inGame remains readable for compatibility, while normal game state is detected.
enum PresenceVisibility { online, inGame, invisible }

@immutable
class ManualPresenceSnapshot {
  const ManualPresenceSnapshot({
    required this.scope,
    this.confirmedMode,
    this.automaticKey = 'presence.unknown',
    this.canChange = false,
    this.hasRealtimeAuthority = false,
    this.realtimeStatus,
  });

  /// An opaque account/session generation, never a display name or credential.
  final Object scope;
  final PresenceVisibility? confirmedMode;
  final String automaticKey;
  final bool canChange;
  final bool hasRealtimeAuthority;
  final int? realtimeStatus;

  String get selfKey => hasRealtimeAuthority
      ? switch (realtimeStatus) {
          0 => 'presence.offline',
          1 =>
            automaticKey == 'presence.away' || automaticKey == 'presence.inGame'
                ? automaticKey
                : 'presence.online',
          2 => 'presence.inGame',
          3 => 'presence.invisible',
          _ => 'presence.unknown',
        }
      : switch (confirmedMode) {
          PresenceVisibility.invisible => 'presence.invisible',
          PresenceVisibility.inGame => 'presence.inGame',
          PresenceVisibility.online => switch (automaticKey) {
            'presence.online' ||
            'presence.inGame' ||
            'presence.away' ||
            'presence.offline' => automaticKey,
            _ => 'presence.unknown',
          },
          null => 'presence.unknown',
        };
}

/// Shared by avatar menu, top-bar badge and tray. The source owns confirmed
/// state; this controller neither persists a second value nor publishes status.
/// The writer must guard the supplied scope before side effects and complete
/// after publishing its authoritative result into [source].
class ManualPresenceController extends ChangeNotifier {
  ManualPresenceController({
    required this.source,
    this.write,
    this.connectionMode,
  }) {
    _scope = source.value.scope;
    source.addListener(_onSource);
    connectionMode?.addListener(_onMode);
  }

  final ValueListenable<ManualPresenceSnapshot> source;
  final Future<void> Function(PresenceVisibility mode, Object scope)? write;
  final ConnectionModeControl? connectionMode;
  late Object _scope;
  bool _busy = false, _failed = false, _disposed = false;
  bool _restoring = false;
  Future<bool> Function()? _restoreOnline;
  int _request = 0;
  bool get busy => _busy || _restoring || (connectionMode?.busy ?? false);
  bool get failed => _failed || (connectionMode?.failed ?? false);
  bool get canChange =>
      write != null &&
      source.value.canChange &&
      !busy &&
      (connectionMode?.allowsOnlineTraffic ?? true);
  bool get canEnterOffline =>
      OfficialClientProfile.newOfflineSelection &&
      !busy &&
      (connectionMode?.canEnterOffline ?? false);
  bool get isOffline =>
      OfficialClientProfile.connectionModes &&
      (connectionMode?.snapshot.isOffline ?? false);
  bool get canRestoreOnline =>
      OfficialClientProfile.connectionModes &&
      !_disposed &&
      !busy &&
      connectionMode?.failed != true &&
      (isOffline || connectionMode?.snapshot.needsOnlineRecovery == true) &&
      _restoreOnline != null;
  VoidCallback bindOnlineRestore(Future<bool> Function() restore) {
    _restoreOnline = restore;
    notifyListeners();
    return () {
      if (!_disposed && identical(_restoreOnline, restore)) {
        _restoreOnline = null;
        notifyListeners();
      }
    };
  }

  Future<bool> restoreOnline() async {
    if (!canRestoreOnline) return false;
    final scope = snapshot.scope;
    final restore = _restoreOnline!;
    _restoring = true;
    _failed = false;
    notifyListeners();
    try {
      return await restore();
    } on Object {
      if (!_disposed && snapshot.scope == scope) _failed = true;
      return false;
    } finally {
      _restoring = false;
      if (!_disposed) notifyListeners();
    }
  }

  String get selfKey => isOffline
      ? 'presence.manualOffline'
      : connectionMode != null && !connectionMode!.allowsOnlineTraffic
      ? 'presence.unknown'
      : snapshot.selfKey;
  void _onMode() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> selectOffline() async {
    if (!canEnterOffline) return false;
    return connectionMode!.enterOffline();
  }

  ManualPresenceSnapshot get snapshot => source.value;

  void _onSource() {
    if (_scope != source.value.scope) {
      _scope = source.value.scope;
      _request++;
      _busy = false;
      _failed = false;
    }
    notifyListeners();
  }

  Future<void> select(PresenceVisibility mode) async {
    if (!canChange || snapshot.confirmedMode == mode) return;
    final generation = ++_request;
    final scope = snapshot.scope;
    _busy = true;
    _failed = false;
    notifyListeners();
    try {
      await write!(mode, scope);
      if (!_disposed && generation == _request) {
        // Successful transport alone is not proof that visibility changed.
        _failed = snapshot.confirmedMode != mode;
      }
    } on Object {
      if (!_disposed && generation == _request) _failed = true;
    } finally {
      if (!_disposed && generation == _request) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    source.removeListener(_onSource);
    connectionMode?.removeListener(_onMode);
    super.dispose();
  }
}
