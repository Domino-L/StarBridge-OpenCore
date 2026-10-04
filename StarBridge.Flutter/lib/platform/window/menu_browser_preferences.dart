/// Local browser behavior only; URLs and browsing history are not preferences.
class MenuBrowserPreferences {
  const MenuBrowserPreferences({
    this.provider = 'bing-global',
    this.tabLimit = 8,
    this.openLinksInNewTab = true,
    this.pauseWhenHidden = true,
  });
  static const providers = [
    'bing-cn',
    'baidu',
    'google',
    'duckduckgo',
    'bing-global',
  ];
  final String provider;
  final int tabLimit;
  final bool openLinksInNewTab, pauseWhenHidden;
  MenuBrowserPreferences effective({required bool safeMode}) =>
      safeMode && !pauseWhenHidden ? change('pauseWhenHidden', true) : this;
  @override
  bool operator ==(Object other) =>
      other is MenuBrowserPreferences &&
      provider == other.provider &&
      tabLimit == other.tabLimit &&
      openLinksInNewTab == other.openLinksInNewTab &&
      pauseWhenHidden == other.pauseWhenHidden;
  @override
  int get hashCode =>
      Object.hash(provider, tabLimit, openLinksInNewTab, pauseWhenHidden);
  static MenuBrowserPreferences? fromSettings(Map settings) {
    if (!settings.containsKey('browser')) return const MenuBrowserPreferences();
    final raw = settings['browser'];
    if (raw is! Map ||
        raw.length != 4 ||
        !providers.contains(raw['provider']) ||
        raw['tabLimit'] is! int ||
        (raw['tabLimit'] as int) < 1 ||
        (raw['tabLimit'] as int) > 12 ||
        raw['openLinksInNewTab'] is! bool ||
        raw['pauseWhenHidden'] is! bool) {
      return null;
    }
    return MenuBrowserPreferences(
      provider: raw['provider'],
      tabLimit: raw['tabLimit'],
      openLinksInNewTab: raw['openLinksInNewTab'],
      pauseWhenHidden: raw['pauseWhenHidden'],
    );
  }

  Map<String, Object?> toMap() => {
    'provider': provider,
    'tabLimit': tabLimit,
    'openLinksInNewTab': openLinksInNewTab,
    'pauseWhenHidden': pauseWhenHidden,
  };
  Map<String, Object?> toSettingsPatch() => {'browser': toMap()};
  MenuBrowserPreferences change(String key, Object value) => fromSettings({
    'browser': {...toMap(), key: value},
  })!;
}
