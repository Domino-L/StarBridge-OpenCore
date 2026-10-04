import 'menu_recovery.dart';
import 'menu_restore_preferences.dart';
import 'menu_window_preferences.dart';

/// Process lifetime, not account/composition lifetime. No account or tool data.
/// Chooses the first-opening policy and keeps unknown interruption conservative.
final class MenuRecoveryLifecycle {
  bool _opened = false;
  String? _handled;
  MenuRecoveryPort? _port;
  MenuRecoverySession? _session;

  Future<MenuRecoveryOpening> prepare({
    required bool live,
    required MenuWindowPreferences? preferences,
    required MenuWindowPreferencesPort? preferencesPort,
    required MenuRecoveryPort? recovery,
    required bool Function() isCurrent,
  }) async {
    final policy = MenuRestorePreferences.fromSettings(
      preferences?.settings ?? const {},
    )!;
    final restore = policy.restoreForOpening(firstInProcess: !_opened);
    final hasWindows =
        restore &&
        preferences != null &&
        (preferences.layout['open'] as List).isNotEmpty;
    var value = preferences;
    var pending = false, failed = false;
    if (live && recovery != null) {
      try {
        final session = await recovery.begin();
        if (!isCurrent()) {
          return const MenuRecoveryOpening(null, true, true, false);
        }
        _port = recovery;
        _session = session;
        if (hasWindows &&
            session.previousInterrupted &&
            _handled != session.token) {
          switch (policy.crashRecovery) {
            case 'restore':
              break;
            case 'startClean':
              if (preferencesPort == null) {
                throw const FormatException('No preference owner');
              }
              value = await preferencesPort.save(
                MenuWindowPreferences(preferences.revision, {
                  ...preferences.layout,
                  'open': <String>[],
                }, preferences.settings),
              );
              if (!isCurrent()) {
                return const MenuRecoveryOpening(null, true, true, false);
              }
              break;
            default:
              pending = true;
          }
        }
      } on Object {
        // Unknown marker or failed clean save: preserve layout and ask. Never
        // treat a failed read as consent for automatic restoration/deletion.
        pending = hasWindows;
        failed = true;
      }
    }
    return MenuRecoveryOpening(value, pending, failed, live && restore);
  }

  void resolved() {
    _opened = true;
    _handled = _session?.token;
  }

  /// Called after actual visible acknowledgment, never after a request alone.
  void visible({required bool live, required bool pending}) {
    if (live && !pending) resolved();
  }

  /// Normal app exit only. The caller flushes existing preferences first.
  Future<void> finish() async {
    if (_session case final session?) await _port?.finish(session.token);
  }
}

final class MenuRecoveryOpening {
  const MenuRecoveryOpening(
    this.preferences,
    this.pending,
    this.failed,
    this.restore,
  );
  final MenuWindowPreferences? preferences;
  final bool pending, failed, restore;
  MenuWindowPreferences get presentation {
    final value = preferences ?? MenuWindowPreferences.defaults;
    return pending || !restore
        ? MenuWindowPreferences(value.revision, {
            ...value.layout,
            'open': <String>[],
          }, value.settings)
        : value;
  }
}
