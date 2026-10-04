/// Device-local defaults for newly selected reference images only.
/// Image bytes, paths and individual adjustments are never persisted here.
class MenuImagePreferences {
  const MenuImagePreferences({
    this.openMode = 'edit',
    this.scaleMode = 'fit',
    this.opacityPercent = 100,
    this.rememberAdjustments = true,
    this.defaultPinned = false,
  });
  final String openMode, scaleMode;
  final int opacityPercent;
  final bool rememberAdjustments, defaultPinned;
  static MenuImagePreferences? fromSettings(Map settings) {
    if (!settings.containsKey('image')) return const MenuImagePreferences();
    final raw = settings['image'];
    if (raw is! Map ||
        raw.keys.any(
          (key) => !const {
            'openMode',
            'scaleMode',
            'opacityPercent',
            'rememberAdjustments',
            'defaultPinned',
          }.contains(key),
        ) ||
        !const ['edit', 'imageOnly'].contains(raw['openMode']) ||
        !const ['fit', 'actualSize'].contains(raw['scaleMode']) ||
        raw['opacityPercent'] is! int ||
        (raw['opacityPercent'] as int) < 20 ||
        (raw['opacityPercent'] as int) > 100 ||
        (raw.containsKey('rememberAdjustments') &&
            raw['rememberAdjustments'] is! bool) ||
        (raw.containsKey('defaultPinned') && raw['defaultPinned'] is! bool)) {
      return null;
    }
    return MenuImagePreferences(
      openMode: raw['openMode'],
      scaleMode: raw['scaleMode'],
      opacityPercent: raw['opacityPercent'],
      rememberAdjustments: raw['rememberAdjustments'] ?? true,
      defaultPinned: raw['defaultPinned'] ?? false,
    );
  }

  Map<String, Object?> toMap() => {
    'openMode': openMode,
    'scaleMode': scaleMode,
    'opacityPercent': opacityPercent,
    'rememberAdjustments': rememberAdjustments,
    'defaultPinned': defaultPinned,
  };
  Map<String, Object?> toSettingsPatch() => {'image': toMap()};
  MenuImagePreferences change(String key, Object value) => fromSettings({
    'image': {...toMap(), key: value},
  })!;
}
