import 'package:flutter/foundation.dart';

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
  });

  /// An opaque account/session generation, never a display name or credential.
  final Object scope;
  final PresenceVisibility? confirmedMode;
  final String automaticKey;
  final bool canChange;

  String get selfKey => switch (confirmedMode) {
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
  ManualPresenceController({required this.source, this.write}) {
    _scope = source.value.scope;
    source.addListener(_onSource);
  }

  final ValueListenable<ManualPresenceSnapshot> source;
  final Future<void> Function(PresenceVisibility mode, Object scope)? write;
  late Object _scope;
  bool _busy = false, _failed = false, _disposed = false;
  int _request = 0;
  bool get busy => _busy;
  bool get failed => _failed;
  bool get canChange => write != null && source.value.canChange && !_busy;
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
    super.dispose();
  }
}
