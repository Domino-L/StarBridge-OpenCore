import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_address.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_preferences.dart';

import 'menu_browser_tabs_test.dart'
    show BrowserFake, mount, workspace, flush, page;

void main() {
  for (final provider in MenuBrowserPreferences.providers) {
    testWidgets('$provider opens its homepage for first and new tabs', (
      tester,
    ) async {
      final native = BrowserFake()..tabs.clear();
      native.tabs.add(page('t1', url: 'about:blank'));
      final work = workspace();
      final preferences = MenuBrowserPreferences(provider: provider);
      await mount(tester, native, work, preferences: preferences);
      final home = menuBrowserHome(provider: provider).toString();
      expect(
        native.calls.singleWhere((c) => c.$1 == 'browserOpen').$2['url'],
        home,
      );
      expect(native.tabs.single['url'], home);
      expect(Uri.parse(home).scheme, 'https');
      expect(Uri.parse(home).query, isEmpty);
      await tester.tap(find.byKey(const ValueKey('browser-new-tab')));
      await flush(tester);
      expect(native.tabs.length, 2);
      expect(native.tabs.last['url'], home);
      expect(native.calls.where((c) => c.$1 == 'browserNavigate').length, 1);
      expect(
        native.calls.singleWhere((c) => c.$1 == 'browserNewTab').$2['url'],
        home,
      );
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    });
  }

  testWidgets('changing search engine affects only newly created tabs', (
    tester,
  ) async {
    final native = BrowserFake(), work = workspace();
    await mount(tester, native, work);
    await mount(
      tester,
      native,
      work,
      preferences: const MenuBrowserPreferences(provider: 'duckduckgo'),
    );
    expect(native.calls.where((c) => c.$1 == 'browserNavigate'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('browser-new-tab')));
    await flush(tester);
    expect(native.tabs.last['url'], 'https://duckduckgo.com/');
    expect(native.tabs.first['url'], 'https://example.test/t1');
    await tester.pumpWidget(const SizedBox());
    work.dispose();
  });
}
