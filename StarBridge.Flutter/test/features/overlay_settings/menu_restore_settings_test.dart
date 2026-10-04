import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_restore_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_restore_settings_card.dart';
import 'package:starbridge_flutter/platform/window/menu_restore_preferences.dart';
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
  test('legacy choice is not rewritten; exact boolean options and layout-only disable', () {
    for (final legacy in [false, true]) {
      final settings = {
        ...MenuWindowPreferences.defaults.settings,
        'restoreDesktop': legacy,
      };
      final value = MenuRestorePreferences.fromSettings(settings)!;
      expect(value.inSession, legacy);
      expect(value.afterRestart, legacy);
      expect(value.lastFocus, true);
      expect(value.crashRecovery, 'ask');
      expect(settings.containsKey('restoreAfterRestart'), false);
      for (final invalid in [null, 1, 'true', <String>[]]) {
        expect(
          MenuWindowPreferences.parse({
            ...MenuWindowPreferences.defaults.toMap(),
            'settings': {...settings, 'restoreAfterRestart': invalid},
          }),
          isNull,
        );
      }
    }
    for (final patch in [
      {'restoreLastFocus': null},
      {'restoreLastFocus': 'true'},
      {'safeModeNextLaunch': null},
      {'safeModeNextLaunch': 1},
      {'crashRecovery': null},
      {'crashRecovery': true},
      {'crashRecovery': 'unknown'},
    ]) {
      expect(
        MenuWindowPreferences.parse({
          ...MenuWindowPreferences.defaults.toMap(),
          'settings': {...MenuWindowPreferences.defaults.settings, ...patch},
        }),
        isNull,
      );
    }
    final changed = const MenuRestorePreferences(
      inSession: true,
      crashRecovery: 'restore',
      lastFocus: false,
      safeModeNextLaunch: true,
    ).change(afterRestart: true);
    expect(changed.inSession && changed.afterRestart, true);
    expect(changed.lastFocus, false);
    expect(changed.crashRecovery, 'restore');
    expect(changed.safeModeNextLaunch, true);
    final original = MenuWindowPreferences(
      7,
      const {
        'version': 1,
        'panels': [
          {
            'id': 'friends',
            'bounds': [20, 40, 350, 420],
          },
        ],
        'open': ['friends'],
      },
      {...MenuWindowPreferences.defaults.settings, 'restoreDesktop': true},
    );
    final disabled = original.withSettingsPatch(
      const MenuRestorePreferences().toSettingsPatch(),
    );
    expect(MenuWindowPreferences.parse(disabled.toMap()), isNotNull);
    expect(disabled.layout['open'], isEmpty);
    expect(disabled.layout['panels'], original.layout['panels']);
    expect(disabled.revision, 7);
    expect(original.layout['open'], ['friends']);
  });
  testWidgets(
    'failed save keeps restoration draft; reload preserves geometry and other settings',
    (tester) async {
      final store = _Store()..fail = true;
      await tester.pumpWidget(
        app(SingleChildScrollView(child: MenuRestoreSettingsCard(port: store))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-restore-restart')));
      await tester.pump();
      final save = find.byKey(const Key('menu-restore-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-restore-error')), findsOneWidget);
      expect(
        tester
            .widget<MenuRestoreEditor>(find.byType(MenuRestoreEditor))
            .value
            .afterRestart,
        true,
      );
      store.value = MenuWindowPreferences(
        9,
        const {
          'version': 1,
          'panels': [
            {
              'id': 'friends',
              'bounds': [20, 40, 350, 420],
            },
          ],
          'open': [],
        },
        {...store.value.settings, 'snapWindows': true},
      );
      await tester.tap(find.byKey(const Key('menu-restore-reload')));
      await tester.pumpAndSettle();
      store.fail = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.value.revision, 10);
      expect(store.value.settings['restoreAfterRestart'], true);
      expect(store.value.settings['restoreDesktop'], false);
      expect(store.value.settings['snapWindows'], true);
      expect(store.value.layout['panels'], isNotEmpty);
    },
  );
  testWidgets(
    'shared editor saves focus and interruption choice without resetting other recovery flags',
    (tester) async {
      final store = _Store();
      await tester.pumpWidget(
        app(SingleChildScrollView(child: MenuRestoreSettingsCard(port: store))),
      );
      await tester.pumpAndSettle();
      final focus = find.byKey(const Key('menu-restore-last-focus'));
      await tester.ensureVisible(focus);
      await tester.tap(focus);
      await tester.pumpAndSettle();
      final safe = find.byKey(const Key('menu-safe-next-launch'));
      await tester.ensureVisible(safe);
      await tester.tap(safe);
      await tester.pumpAndSettle();
      final dropdown = find.byKey(const ValueKey('menu-restore-crash-ask'));
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('直接恢复窗口').last);
      await tester.pumpAndSettle();
      final editor = tester.widget<MenuRestoreEditor>(
        find.byType(MenuRestoreEditor),
      );
      expect(editor.value.lastFocus, false);
      expect(editor.value.crashRecovery, 'restore');
      expect(editor.value.inSession || editor.value.afterRestart, false);
      final save = find.byKey(const Key('menu-restore-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.value.settings['restoreLastFocus'], false);
      expect(store.value.settings['crashRecovery'], 'restore');
      expect(store.value.settings['safeModeNextLaunch'], true);
      expect(store.value.layout['open'], isEmpty);
    },
  );
  testWidgets(
    'restart-only windows mount on explicit startup; hiding obeys session option',
    (tester) async {
      size(tester, const Size(1280, 900));
      final tools = MenuLocalToolsController((_, _) async => null);
      final visibility = <bool>[];
      Widget menu(bool visible) => app(
        MenuBridgePreview(
          visible: visible,
          onDismiss: () {},
          localToolsController: tools,
          onFriendsVisible: visibility.add,
          initialSettings: {
            ...MenuWindowPreferences.defaults.settings,
            'restoreDesktop': false,
            'restoreAfterRestart': true,
          },
          initialLayout: const {
            'version': 1,
            'panels': [],
            'open': ['friends'],
          },
        ),
      );
      await tester.pumpWidget(menu(true));
      await tester.pumpAndSettle();
      expect(visibility, [true]);
      await tester.pumpWidget(menu(false));
      await tester.pumpAndSettle();
      expect(visibility, [true, false]);
      await tester.pumpWidget(menu(true));
      await tester.pumpAndSettle();
      expect(visibility, [true, false]);
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [320.0, 1040.0]) {
      testWidgets('restoration editor $locale width=$width large text', (
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
                      child: MenuRestoreSettingsCard(port: _Store()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(AppStrings.resolve(locale).text('menu.restore.title')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'menu-restore-${locale.toLanguageTag()}-${width.toInt()}',
        );
        if (width == 320) {
          final reload = find.byKey(const Key('menu-restore-reload'));
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
            'menu-restore-${locale.toLanguageTag()}-320-bottom',
          );
        }
      });
    }
  }
}
