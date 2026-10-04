/// Display-only browser state. Native code owns IDs, WebViews and history.
final class MenuBrowserTab {
  const MenuBrowserTab(
    this.id,
    this.title,
    this.url,
    this.back,
    this.forward,
    this.loading,
    this.failed, {
    this.unavailable = false,
  });
  final String id, title, url;
  final bool back, forward, loading, failed;
  final bool unavailable;
}

final class MenuBrowserState {
  const MenuBrowserState(this.tabs, this.activeId, this.limit);
  final List<MenuBrowserTab> tabs;
  final String activeId;
  final int limit;
  MenuBrowserTab get active => tabs.firstWhere((tab) => tab.id == activeId);

  static MenuBrowserState parse(Object? value) {
    if (value is! Map ||
        value['tabs'] is! List ||
        value['activeTabId'] is! String ||
        value['tabLimit'] is! int) {
      throw const FormatException('Invalid browser state');
    }
    final limit = value['tabLimit'] as int;
    final rows = value['tabs'] as List;
    if (limit < 1 || limit > 12 || rows.isEmpty || rows.length > limit) {
      throw const FormatException('Invalid browser tabs');
    }
    final ids = <String>{};
    final tabs = <MenuBrowserTab>[];
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          row['title'] is! String ||
          row['url'] is! String ||
          !RegExp(r'^t[1-9][0-9]{0,19}$').hasMatch(row['id'] as String) ||
          !ids.add(row['id'] as String) ||
          (row['title'] as String).length > 16384 ||
          (row['url'] as String).length > 16384 ||
          (row.containsKey('unavailable') && row['unavailable'] is! bool) ||
          [
            'back',
            'forward',
            'loading',
            'failed',
          ].any((k) => row[k] is! bool)) {
        throw const FormatException('Invalid browser tab');
      }
      tabs.add(
        MenuBrowserTab(
          row['id'] as String,
          row['title'] as String,
          row['url'] as String,
          row['back'] as bool,
          row['forward'] as bool,
          row['loading'] as bool,
          row['failed'] as bool,
          unavailable: row['unavailable'] == true,
        ),
      );
    }
    final active = value['activeTabId'] as String;
    if (!ids.contains(active)) {
      throw const FormatException('Missing active tab');
    }
    return MenuBrowserState(List.unmodifiable(tabs), active, limit);
  }
}
