import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_screenshot_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_screenshot_settings_card.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import '../../app/menu_overlay/menu_preview_window_test.dart'
    show MemoryMenuPreferences;
import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Store extends MemoryMenuPreferences {
  bool fail = false;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences value) async {
    if (fail) throw StateError('synthetic failure');
    return super.save(value);
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'failed save and stale revision preserve draft; reload saves only screenshot patch',
    (tester) async {
      final store = _Store()..fail = true;
      size(tester, const Size(1040, 900));
      await tester.pumpWidget(
        app(
          SingleChildScrollView(child: MenuScreenshotSettingsCard(port: store)),
        ),
      );
      await tester.pumpAndSettle();
      final editor = find.byType(MenuScreenshotEditor);
      tester
          .widget<MenuScreenshotEditor>(editor)
          .onChanged(
            const MenuScreenshotPreferences(
              format: 'jpeg',
              jpegQuality: 75,
              copyAfterSave: true,
              showConfirmation: false,
            ),
          );
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('menu-screenshot-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-screenshot-error')), findsOneWidget);
      expect(tester.widget<MenuScreenshotEditor>(editor).value.jpegQuality, 75);
      store.fail = false;
      final original = MenuWindowPreferences(
        9,
        const {
          'version': 1,
          'panels': [],
          'open': ['image'],
        },
        {
          ...MenuWindowPreferences.defaults.settings,
          'restoreDesktop': true,
          'showClock': false,
        },
      );
      store.value = original;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-screenshot-error')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('menu-screenshot-reload')),
      );
      await tester.tap(find.byKey(const Key('menu-screenshot-reload')));
      await tester.pumpAndSettle();
      expect(tester.widget<MenuScreenshotEditor>(editor).value.jpegQuality, 75);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.value.layout, original.layout);
      expect(store.value.settings['showClock'], false);
      expect(
        MenuScreenshotPreferences.fromSettings(store.value.settings)!.toMap(),
        tester.widget<MenuScreenshotEditor>(editor).value.toMap(),
      );
      expect(find.byKey(const Key('menu-screenshot-error')), findsNothing);
    },
  );
  testWidgets(
    'menu uses the same editor and host settings patch without copying or saving a screenshot',
    (tester) async {
      size(tester, const Size(1280, 900));
      final calls = <String>[], changes = <Map<String, Object?>>[];
      final tools = MenuLocalToolsController((name, _) async {
        calls.add(name);
        return null;
      });
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
              ...const MenuScreenshotPreferences(
                format: 'jpeg',
                jpegQuality: 75,
              ).toSettingsPatch(),
            },
            initialLayout: const {
              'version': 1,
              'panels': [],
              'open': ['settings'],
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tools.screenshotPreferences.jpegQuality, 75);
      final hideMenu = find.byKey(const Key('menu-screenshot-hide-menu'));
      await tester.ensureVisible(hideMenu);
      await tester.tap(hideMenu);
      await tester.pumpAndSettle();
      expect(tools.screenshotPreferences.hideMenu, false);
      expect((changes.last['screenshot'] as Map)['hideMenu'], false);
      final slider = find.byKey(const Key('menu-screenshot-quality'));
      await tester.ensureVisible(slider);
      tester.widget<Slider>(slider).onChanged!(65);
      await tester.pumpAndSettle();
      expect(tools.screenshotPreferences.jpegQuality, 65);
      expect((changes.last['screenshot'] as Map)['jpegQuality'], 65);
      expect(
        MenuWindowPreferences.parse({
          'revision': 1,
          'layout': MenuWindowPreferences.defaults.layout,
          'settings': changes.last,
        }),
        isNotNull,
      );
      expect(calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [1040.0, 320.0]) {
      testWidgets('JPEG settings $locale width=$width large text stay reachable', (
        tester,
      ) async {
        size(tester, Size(width, 900));
        final key = GlobalKey(), store = _Store();
        store.value = store.value.withSettingsPatch(
          const MenuScreenshotPreferences(
            format: 'jpeg',
            jpegQuality: 75,
          ).toSettingsPatch(),
        );
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
                      child: MenuScreenshotSettingsCard(port: store),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('JPEG'), findsOneWidget);
        await capture(
          tester,
          key,
          'menu-screenshot-settings-${locale.toLanguageTag()}-${width.toInt()}',
        );
        final hide = find.byKey(const Key('menu-screenshot-hide-menu'));
        await tester.ensureVisible(hide);
        tester.widget<SwitchListTile>(hide).onChanged!(false);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('menu-screenshot-quality')),
        );
        tester
            .widget<Slider>(find.byKey(const Key('menu-screenshot-quality')))
            .onChanged!(65);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MenuScreenshotEditor>(find.byType(MenuScreenshotEditor))
              .value
              .jpegQuality,
          65,
        );
        await tester.ensureVisible(
          find.byKey(const Key('menu-screenshot-copy')),
        );
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('menu-screenshot-copy')),
            )
            .onChanged!(true);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('menu-screenshot-save')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'menu-screenshot-settings-${locale.toLanguageTag()}-${width.toInt()}-bottom',
        );
        await tester.tap(find.byKey(const Key('menu-screenshot-save')));
        await tester.pumpAndSettle();
        expect(
          MenuScreenshotPreferences.fromSettings(store.value.settings)!
              .hideMenu,
          false,
        );
        expect(
          MenuScreenshotPreferences.fromSettings(store.value.settings)!
              .copyAfterSave,
          true,
        );
      });
    }
  }
}
