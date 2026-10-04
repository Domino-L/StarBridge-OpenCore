final class MenuShortcutSettings {
  const MenuShortcutSettings(
    this.revision,
    this.binding,
    this.enabled,
    this.closeWithHotkey,
    this.state,
  );
  final int revision;
  final String binding, state;
  final bool enabled, closeWithHotkey;
  Map<String, Object?> toMap() => {
    'schemaVersion': 1,
    'revision': revision,
    'binding': binding,
    'enabled': enabled,
    'closeWithHotkey': closeWithHotkey,
    'state': state,
  };
  static const states = {
    'registered',
    'disabled',
    'failed',
    'unavailable',
    'conflictWithInformation',
    'modifierRequired',
    'reserved',
    'invalid',
  };
  factory MenuShortcutSettings.parse(Map<String, Object?> p) {
    if (p.length != 6 ||
        p['schemaVersion'] != 1 ||
        p['revision'] is! int ||
        (p['revision'] as int) < 0 ||
        p['binding'] is! String ||
        (p['binding'] as String).isEmpty ||
        (p['binding'] as String).length > 64 ||
        p['enabled'] is! bool ||
        p['closeWithHotkey'] is! bool ||
        !states.contains(p['state'])) {
      throw const FormatException('Invalid menu shortcut settings');
    }
    return MenuShortcutSettings(
      p['revision'] as int,
      p['binding'] as String,
      p['enabled'] as bool,
      p['closeWithHotkey'] as bool,
      p['state'] as String,
    );
  }
}

abstract interface class MenuShortcutSettingsPort {
  Future<MenuShortcutSettings> readShortcut();
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings value);
}

abstract interface class MenuShortcutSettingsProvider {
  MenuShortcutSettingsPort? get shortcutSettings;
}
