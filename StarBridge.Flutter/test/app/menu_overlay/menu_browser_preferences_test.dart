import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_address.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_browser_state.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_preferences.dart';

import 'menu_browser_tabs_test.dart'
    show BrowserFake, mount, workspace, flush, page;

void main() {
  test('browser defaults enable new-window tabs and hidden-page pause without overriding saved choices', () {
    final defaults = MenuBrowserPreferences.fromSettings({})!;
    expect(defaults.openLinksInNewTab, true);
    expect(defaults.pauseWhenHidden, true);
    final saved = MenuBrowserPreferences.fromSettings(
      const MenuBrowserPreferences(
        openLinksInNewTab: false,
        pauseWhenHidden: false,
      ).toSettingsPatch(),
    )!;
    expect(saved.openLinksInNewTab, false);
    expect(saved.pauseWhenHidden, false);
  });
  for (final provider in MenuBrowserPreferences.providers) {
    test(
      'provider $provider encodes search but does not rewrite or permit unsafe addresses',
      () {
        final uri = menuBrowserAddress('星际公民 a&b', provider: provider)!;
        expect(uri.scheme, 'https');
        expect(
          uri.host,
          {
            'bing-cn': 'cn.bing.com',
            'baidu': 'www.baidu.com',
            'google': 'www.google.com',
            'duckduckgo': 'duckduckgo.com',
            'bing-global': 'www.bing.com',
          }[provider],
        );
        expect(
          uri.queryParameters[provider == 'baidu' ? 'wd' : 'q'],
          '星际公民 a&b',
        );
        expect(
          menuBrowserAddress(
            'http://example.test/a',
            provider: provider,
          ).toString(),
          'http://example.test/a',
        );
        for (final address in [
          'javascript:alert(1)',
          'file:///C:/',
          'https://user:pass@example.invalid',
        ]) {
          expect(menuBrowserAddress(address, provider: provider), isNull);
        }
      },
    );
  }
  test('state keeps open pages after lowering configured limit but rejects absolute overflow', () {
    final rows = [for (var i = 1; i <= 12; i++) page('t$i')];
    expect(
      MenuBrowserState.parse({'tabs': rows, 'activeTabId': 't1', 'tabLimit': 1})
          .tabs
          .length,
      12,
    );
    expect(
      () => MenuBrowserState.parse({
        'tabs': [...rows, page('t13')],
        'activeTabId': 't1',
        'tabLimit': 1,
      }),
      throwsFormatException,
    );
  });
  testWidgets(
    'native configure precedes open and navigation; saved provider is actually used',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(
        tester,
        native,
        work,
        preferences: const MenuBrowserPreferences(
          provider: 'duckduckgo',
          tabLimit: 12,
        ),
      );
      expect(native.calls.first.$1, 'browserConfigure');
      expect(native.calls[1].$1, 'browserOpen');
      expect(native.configured!['tabLimit'], 12);
      await tester.enterText(
        find.byKey(const ValueKey('browser-address')),
        'star citizen',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await flush(tester);
      final navigation = native.calls.lastWhere(
        (c) => c.$1 == 'browserNavigate',
      );
      expect(Uri.parse(navigation.$2['url'] as String).host, 'duckduckgo.com');
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );
  testWidgets(
    'live options apply without reopening; lower cap disables new tab but retains pages',
    (tester) async {
      final native = BrowserFake(), work = workspace();
      await mount(tester, native, work);
      await mount(
        tester,
        native,
        work,
        preferences: const MenuBrowserPreferences(
          tabLimit: 1,
          pauseWhenHidden: false,
          openLinksInNewTab: false,
        ),
      );
      expect(native.tabs.length, 2);
      expect(native.calls.where((c) => c.$1 == 'browserOpen').length, 1);
      expect(native.configured!['pauseWhenHidden'], false);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('browser-new-tab')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );
  testWidgets(
    'failed options do not open browser; retry applies options before opening',
    (tester) async {
      final native = BrowserFake()..failConfiguration = true;
      final work = workspace();
      await mount(tester, native, work);
      expect(native.calls.where((c) => c.$1 == 'browserOpen'), isEmpty);
      native.failConfiguration = false;
      await tester.tap(find.text('重试'));
      await flush(tester);
      expect(native.calls.where((c) => c.$1 == 'browserOpen').length, 1);
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );
  testWidgets(
    'newer edit during native reply is serialized before any action',
    (tester) async {
      final pending = Completer<Object?>();
      final native = BrowserFake()..pendingConfiguration = pending;
      final work = workspace();
      await mount(
        tester,
        native,
        work,
        preferences: const MenuBrowserPreferences(tabLimit: 12),
      );
      await mount(
        tester,
        native,
        work,
        preferences: const MenuBrowserPreferences(tabLimit: 2),
      );
      expect(native.calls.where((c) => c.$1 == 'browserOpen'), isEmpty);
      pending.complete();
      await flush(tester);
      expect(native.configured!['tabLimit'], 2);
      expect(native.calls.where((c) => c.$1 == 'browserConfigure').length, 2);
      expect(native.calls.where((c) => c.$1 == 'browserOpen').length, 1);
      await tester.pumpWidget(const SizedBox());
      work.dispose();
    },
  );
}
