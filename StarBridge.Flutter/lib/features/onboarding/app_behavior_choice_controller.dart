import 'package:flutter/foundation.dart';

import '../../app/preferences/app_preferences.dart';
import '../../app/preferences/app_preferences_port.dart';

/// Startup and close behaviour as the original preferences owner reports it.
/// `null` means no explicit choice has been saved yet.
@immutable
final class AppBehaviorChoiceView {
  const AppBehaviorChoiceView({
    this.available = false,
    this.launchAtStartup,
    this.keepInTray,
    this.savedLaunchAtStartup,
    this.savedKeepInTray,
    this.busy = false,
    this.failed = false,
  });
  final bool available;

  /// Draft selection. Nothing is preselected for a first choice.
  final bool? launchAtStartup, keepInTray;

  /// Confirmed by the preferences owner; drives readiness and the summary.
  final bool? savedLaunchAtStartup, savedKeepInTray;
  final bool busy, failed;

  bool get saved => savedLaunchAtStartup != null && savedKeepInTray != null;
  bool get dirty =>
      launchAtStartup != savedLaunchAtStartup || keepInTray != savedKeepInTray;
  bool get canSave =>
      available &&
      !busy &&
      launchAtStartup != null &&
      keepInTray != null &&
      dirty;
}

/// Asks startup and close behaviour once, inside first-use setup, through the
/// existing preferences owner. Saving here also satisfies the standalone
/// startup and first-close prompts, which check the same choice flags.
final class AppBehaviorChoiceController
    extends ValueNotifier<AppBehaviorChoiceView> {
  AppBehaviorChoiceController(this._preferences)
    : super(const AppBehaviorChoiceView()) {
    _preferences.projection.addListener(_sync);
    _sync();
  }
  final AppPreferencesPort _preferences;
  bool _disposed = false;

  ApplicationBehaviorPreferences? get _confirmed =>
      _preferences.projection.value.confirmed?.applicationBehavior;

  void _sync() {
    if (_disposed) return;
    final behavior = _confirmed;
    final savedStartup = behavior != null && behavior.startupChoiceMade
        ? behavior.launchAtStartup
        : null;
    final savedTray = behavior != null && behavior.closeBehaviorChoiceMade
        ? behavior.keepRunningInBackground
        : null;
    final old = value;
    // Keep an unsaved draft unless the owner's saved values changed meanwhile.
    final keepDraft =
        old.dirty &&
        old.savedLaunchAtStartup == savedStartup &&
        old.savedKeepInTray == savedTray;
    value = AppBehaviorChoiceView(
      available: behavior != null,
      launchAtStartup: keepDraft ? old.launchAtStartup : savedStartup,
      keepInTray: keepDraft ? old.keepInTray : savedTray,
      savedLaunchAtStartup: savedStartup,
      savedKeepInTray: savedTray,
      busy: old.busy,
      failed: old.failed,
    );
  }

  void _draft({bool? launchAtStartup, bool? keepInTray}) {
    if (_disposed || value.busy) return;
    value = AppBehaviorChoiceView(
      available: value.available,
      launchAtStartup: launchAtStartup ?? value.launchAtStartup,
      keepInTray: keepInTray ?? value.keepInTray,
      savedLaunchAtStartup: value.savedLaunchAtStartup,
      savedKeepInTray: value.savedKeepInTray,
    );
  }

  void chooseStartup(bool launchAtStartup) =>
      _draft(launchAtStartup: launchAtStartup);
  void chooseClose(bool keepInTray) => _draft(keepInTray: keepInTray);

  /// Returns true only when the owner confirms both values as saved.
  Future<bool> save() async {
    final behavior = _confirmed;
    if (_disposed || !value.canSave || behavior == null) return false;
    final launch = value.launchAtStartup!, tray = value.keepInTray!;
    value = AppBehaviorChoiceView(
      available: value.available,
      launchAtStartup: launch,
      keepInTray: tray,
      savedLaunchAtStartup: value.savedLaunchAtStartup,
      savedKeepInTray: value.savedKeepInTray,
      busy: true,
    );
    var ok = false;
    try {
      ok = await _preferences.setApplicationBehavior(
        behavior
            .copyWith(
              launchAtStartup: launch,
              // An earlier, unchanged startup choice keeps its own setting.
              startMinimized:
                  behavior.startupChoiceMade &&
                      behavior.launchAtStartup == launch
                  ? behavior.startMinimized
                  : launch,
              startupChoiceMade: true,
              keepRunningInBackground: tray,
              closeBehaviorChoiceMade: true,
            )
            .normalize(),
      );
    } on Object {
      ok = false;
    }
    if (_disposed) return false;
    final after = _confirmed;
    final confirmed =
        ok &&
        after != null &&
        after.startupChoiceMade &&
        after.closeBehaviorChoiceMade &&
        after.launchAtStartup == launch &&
        after.keepRunningInBackground == tray;
    value = AppBehaviorChoiceView(
      available: value.available,
      launchAtStartup: launch,
      keepInTray: tray,
      savedLaunchAtStartup: value.savedLaunchAtStartup,
      savedKeepInTray: value.savedKeepInTray,
      failed: !confirmed,
    );
    _sync();
    return confirmed;
  }

  @override
  void dispose() {
    _disposed = true;
    _preferences.projection.removeListener(_sync);
    super.dispose();
  }
}
