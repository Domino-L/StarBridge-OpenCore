/// Menu presentation only; does not alter friend relations or message delivery.
class MenuSocialPreferences {
  const MenuSocialPreferences({
    this.friendSort = 'onlineFirst',
    this.notifications = true,
    this.sound = false,
    this.showAvatars = true,
    this.preview = 'sourceOnly',
  });
  final String friendSort, preview;
  final bool notifications, sound, showAvatars;
  static const sorts = ['onlineFirst', 'alphabetical'];
  static const previews = ['fullContent', 'sourceOnly', 'hiddenDetails'];
  MenuSocialPreferences copyWith({
    String? friendSort,
    bool? notifications,
    bool? sound,
    bool? showAvatars,
    String? preview,
  }) => MenuSocialPreferences(
    friendSort: friendSort ?? this.friendSort,
    notifications: notifications ?? this.notifications,
    sound: sound ?? this.sound,
    showAvatars: showAvatars ?? this.showAvatars,
    preview: preview ?? this.preview,
  );
  static MenuSocialPreferences? fromSettings(Map settings) {
    if (!settings.containsKey('social')) return const MenuSocialPreferences();
    final raw = settings['social'];
    if (raw is! Map ||
        raw.keys.any(
          (k) => !const [
            'friendSort',
            'notifications',
            'preview',
            'sound',
            'showAvatars',
          ].contains(k),
        ) ||
        !sorts.contains(raw['friendSort']) ||
        (raw.containsKey('notifications') && raw['notifications'] is! bool) ||
        (raw.containsKey('sound') && raw['sound'] is! bool) ||
        (raw.containsKey('showAvatars') && raw['showAvatars'] is! bool) ||
        (raw.containsKey('preview') && !previews.contains(raw['preview']))) {
      return null;
    }
    return MenuSocialPreferences(
      friendSort: raw['friendSort'] as String,
      notifications: raw['notifications'] as bool? ?? true,
      sound: raw['sound'] as bool? ?? false,
      showAvatars: raw['showAvatars'] as bool? ?? true,
      preview: raw['preview'] as String? ?? 'sourceOnly',
    );
  }

  Map<String, Object?> toSettingsPatch() => {
    'social': {
      'friendSort': friendSort,
      'notifications': notifications,
      'sound': sound,
      'showAvatars': showAvatars,
      'preview': preview,
    },
  };
}
