import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_settings_card.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import '../../app/menu_overlay/menu_preview_window_test.dart'
    show MemoryMenuPreferences;
import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Store extends MemoryMenuPreferences {
  bool fail = false;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences value) async {
    if (fail) throw StateError('synthetic storage failure');
    return super.save(value);
  }
}

void main() {
  setUpAll(loadFonts);
  test('strict browser options; legacy document remains unchanged', () {
    final legacy = {...MenuWindowPreferences.defaults.settings};
    expect(
      MenuBrowserPreferences.fromSettings(legacy)!.toMap(),
      const MenuBrowserPreferences().toMap(),
    );
    expect(legacy.containsKey('browser'), false);
    for (final options in [
      null,
      {},
      {...const MenuBrowserPreferences().toMap(), 'provider': 'custom'},
      {...const MenuBrowserPreferences().toMap(), 'tabLimit': 1.5},
      {...const MenuBrowserPreferences().toMap(), 'tabLimit': 0},
      {...const MenuBrowserPreferences().toMap(), 'tabLimit': 13},
      {...const MenuBrowserPreferences().toMap(), 'openLinksInNewTab': 'true'},
      {...const MenuBrowserPreferences().toMap(), 'pauseWhenHidden': 1},
      {
        ...const MenuBrowserPreferences().toMap(),
        'url': 'https://example.test',
      },
    ]) {
      expect(
        MenuWindowPreferences.parse({
          ...MenuWindowPreferences.defaults.toMap(),
          'settings': {...legacy, 'browser': options},
        }),
        isNull,
      );
    }
    for (final provider in MenuBrowserPreferences.providers) {
      for (final limit in [1, 12]) {
        final value = MenuWindowPreferences.defaults.withSettingsPatch(
          MenuBrowserPreferences(
            provider: provider,
            tabLimit: limit,
            openLinksInNewTab: false,
            pauseWhenHidden: false,
          ).toSettingsPatch(),
        );
        expect(MenuWindowPreferences.parse(value.toMap()), isNotNull);
        expect(value.layout, MenuWindowPreferences.defaults.layout);
      }
    }
  });
  testWidgets(
    'save failure keeps draft; re-read and save preserve other settings and geometry',
    (tester) async {
      final store = _Store()..fail = true;
      await tester.pumpWidget(
        app(SingleChildScrollView(child: MenuBrowserSettingsCard(port: store))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-browser-links')));
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('menu-browser-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-browser-error')), findsOneWidget);
      expect(
        tester
            .widget<MenuBrowserEditor>(find.byType(MenuBrowserEditor))
            .value
            .openLinksInNewTab,
        false,
      );
      final saved = MenuWindowPreferences(
        9,
        const {
          'version': 1,
          'panels': [
            {
              'id': 'browser',
              'bounds': [-10, 20, 800, 500],
            },
          ],
          'open': ['browser'],
        },
        {
          ...MenuWindowPreferences.defaults.settings,
          'restoreDesktop': true,
          'showClock': false,
        },
      );
      store.value = saved;
      store.fail = false;
      final reload = find.byKey(const Key('menu-browser-reload'));
      await tester.ensureVisible(reload);
      await tester.tap(reload);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuBrowserEditor>(find.byType(MenuBrowserEditor))
            .value
            .openLinksInNewTab,
        false,
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.value.layout, saved.layout);
      expect(store.value.settings['showClock'], false);
      expect(store.value.settings['restoreDesktop'], true);
      expect(
        MenuBrowserPreferences.fromSettings(store.value.settings)!
            .openLinksInNewTab,
        false,
      );
      expect(find.byKey(const Key('menu-browser-error')), findsNothing);
    },
  );
  testWidgets(
    'menu editor reuses browser model and emits the saved preference shape',
    (tester) async {
      size(tester, const Size(1280, 900));
      final tools = MenuLocalToolsController((_, _) async => null);
      final changes = <Map<String, Object?>>[];
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            localToolsController: tools,
            localCall: (_, _) async => null,
            onSettingsChanged: changes.add,
            initialSettings: {
              ...MenuWindowPreferences.defaults.settings,
              'restoreDesktop': true,
            },
            initialLayout: const {
              'version': 1,
              'panels': [],
              'open': ['settings'],
            },
          ),
        ),
      );
      // Restore through the actual workspace and edit the shared settings.
      await tester.pumpAndSettle();
      final pause = find.byKey(const Key('menu-browser-pause'));
      await tester.ensureVisible(pause);
      await tester.tap(pause);
      await tester.pumpAndSettle();
      expect(tools.browser.pauseWhenHidden, false);
      expect(
        MenuWindowPreferences.parse({
          'revision': 1,
          'layout': MenuWindowPreferences.defaults.layout,
          'settings': changes.last,
        }),
        isNotNull,
      );
      expect((changes.last['browser'] as Map)['pauseWhenHidden'], false);
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [320.0, 1040.0]) {
      testWidgets('browser settings $locale width=$width large text', (
        tester,
      ) async {
        size(tester, Size(width, 900));
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: locale,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.8)),
                  child: RepaintBoundary(
                    key: key,
                    child: SingleChildScrollView(
                      child: MenuBrowserSettingsCard(port: _Store()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'menu-browser-settings-${locale.toLanguageTag()}-${width.toInt()}',
        );
        if (width == 320) {
          final reload = find.byKey(const Key('menu-browser-reload'));
          await tester.ensureVisible(reload);
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(reload)
                .overlaps(const Rect.fromLTWH(0, 0, 320, 900)),
            true,
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'menu-browser-settings-${locale.toLanguageTag()}-320-bottom',
          );
        }
      });
    }
  }
}
