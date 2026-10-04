/// UI-only restoration policy. Old documents used one switch for both cases;
/// reading them preserves that choice without writing a migration.
class MenuRestorePreferences {
  const MenuRestorePreferences({
    this.inSession = false,
    this.afterRestart = false,
    this.lastFocus = true,
    this.safeModeNextLaunch = false,
    this.crashRecovery = 'ask',
  });
  final bool inSession, afterRestart, lastFocus, safeModeNextLaunch;
  final String crashRecovery;
  static const recoveryModes = ['ask', 'restore', 'startClean'];
  bool get remembersWindows => inSession || afterRestart;
  bool restoreForOpening({required bool firstInProcess}) =>
      firstInProcess ? afterRestart : inSession;
  static MenuRestorePreferences? fromSettings(Map settings) {
    for (final key in [
      'restoreDesktop',
      'restoreAfterRestart',
      'restoreLastFocus',
      'safeModeNextLaunch',
    ]) {
      if (settings.containsKey(key) && settings[key] is! bool) return null;
    }
    if (settings.containsKey('crashRecovery') &&
        !recoveryModes.contains(settings['crashRecovery'])) {
      return null;
    }
    final session = settings['restoreDesktop'] == true;
    return MenuRestorePreferences(
      inSession: session,
      afterRestart: settings['restoreAfterRestart'] as bool? ?? session,
      lastFocus: settings['restoreLastFocus'] as bool? ?? true,
      safeModeNextLaunch: settings['safeModeNextLaunch'] as bool? ?? false,
      crashRecovery: settings['crashRecovery'] as String? ?? 'ask',
    );
  }

  MenuRestorePreferences change({
    bool? inSession,
    bool? afterRestart,
    bool? lastFocus,
    bool? safeModeNextLaunch,
    String? crashRecovery,
  }) => MenuRestorePreferences(
    inSession: inSession ?? this.inSession,
    afterRestart: afterRestart ?? this.afterRestart,
    lastFocus: lastFocus ?? this.lastFocus,
    safeModeNextLaunch: safeModeNextLaunch ?? this.safeModeNextLaunch,
    crashRecovery: crashRecovery ?? this.crashRecovery,
  );

  Map<String, Object?> toSettingsPatch() => {
    'restoreDesktop': inSession,
    'restoreAfterRestart': afterRestart,
    'restoreLastFocus': lastFocus,
    'safeModeNextLaunch': safeModeNextLaunch,
    'crashRecovery': crashRecovery,
  };
}
