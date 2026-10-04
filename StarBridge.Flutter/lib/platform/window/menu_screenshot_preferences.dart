/// Device-local capture/export behavior. No image, path or account is persisted.
class MenuScreenshotPreferences {
  const MenuScreenshotPreferences({
    this.format = 'png',
    this.jpegQuality = 90,
    this.copyAfterSave = false,
    this.showConfirmation = true,
    this.hideMenu = true,
  });
  final String format;
  final int jpegQuality;
  final bool copyAfterSave, showConfirmation, hideMenu;
  static MenuScreenshotPreferences? fromSettings(Map settings) {
    if (!settings.containsKey('screenshot')) {
      return const MenuScreenshotPreferences();
    }
    final raw = settings['screenshot'];
    if (raw is! Map ||
        (raw.length != 4 && raw.length != 5) ||
        raw.keys.any(
          (key) => !const {
            'format',
            'jpegQuality',
            'copyAfterSave',
            'showConfirmation',
            'hideMenu',
          }.contains(key),
        ) ||
        !const ['png', 'jpeg'].contains(raw['format']) ||
        raw['jpegQuality'] is! int ||
        (raw['jpegQuality'] as int) < 50 ||
        (raw['jpegQuality'] as int) > 100 ||
        raw['copyAfterSave'] is! bool ||
        raw['showConfirmation'] is! bool ||
        (raw.containsKey('hideMenu') && raw['hideMenu'] is! bool)) {
      return null;
    }
    return MenuScreenshotPreferences(
      format: raw['format'],
      jpegQuality: raw['jpegQuality'],
      copyAfterSave: raw['copyAfterSave'],
      showConfirmation: raw['showConfirmation'],
      hideMenu: raw['hideMenu'] ?? true,
    );
  }

  Map<String, Object?> toMap() => {
    'format': format,
    'jpegQuality': jpegQuality,
    'copyAfterSave': copyAfterSave,
    'showConfirmation': showConfirmation,
    'hideMenu': hideMenu,
  };
  Map<String, Object?> toSettingsPatch() => {'screenshot': toMap()};
  Map<String, Object?> toExportOptions() => {
    'format': format,
    'jpegQuality': jpegQuality,
  };
  MenuScreenshotPreferences change(String key, Object value) => fromSettings({
    'screenshot': {...toMap(), key: value},
  })!;
}
