import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/platform/window/menu_display_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_toolbar_preferences.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_display_settings_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_display_editor.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_clock.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Store implements MenuWindowPreferencesPort {
  MenuWindowPreferences value = const MenuWindowPreferences(
    3,
    {'version': 1, 'panels': [], 'open': []},
    {'showClock': true, 'showContext': true, 'dimming': .5},
  );
  bool fail = false;
  int writes = 0;
  Completer<MenuWindowPreferences>? pending;
  @override
  Future<MenuWindowPreferences> read() async => pending?.future ?? value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    writes++;
    if (fail) throw StateError('fixture write failure');
    expect(next.revision, value.revision);
    return value = MenuWindowPreferences(
      next.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  test('legacy display defaults are read only and nested fields are exact', () {
    final base = MenuWindowPreferences.defaults;
    final legacy = MenuDisplayPreferences.fromSettings(base.settings)!;
    expect(legacy.showDate, true);
    expect(legacy.clockFormat, 'system');
    expect(legacy.textScalePercent, 100);
    expect(legacy.interfaceScalePercent, 0);
    expect(legacy.reduceMotion, false);
    expect(legacy.highContrast, false);
    expect(legacy.change('highContrast', true).highContrast, true);
    expect(legacy.change('reduceMotion', true).reduceMotion, true);
    for (final percent in MenuDisplayPreferences.interfaceScales) {
      expect(
        legacy.change('interfaceScalePercent', percent).interfaceScalePercent,
        percent,
      );
    }
    for (final percent in MenuDisplayPreferences.textScales) {
      expect(
        legacy.change('textScalePercent', percent).textScalePercent,
        percent,
      );
    }
    expect(base.settings.containsKey('display'), false);
    final patch = legacy.toSettingsPatch();
    final nested = patch['display'] as Map;
    final old = {...nested}
      ..remove('streamerPrivacy')
      ..remove('textScalePercent')
      ..remove('interfaceScalePercent')
      ..remove('reduceMotion')
      ..remove('highContrast')
      ..remove('showRoomCode');
    final compatible = MenuDisplayPreferences.fromSettings({'display': old})!;
    expect(compatible.streamerPrivacy, false);
    expect(compatible.textScalePercent, 100);
    expect(compatible.roomCodeVisible, true);
    expect(old.containsKey('showRoomCode'), false);
    final hidden = compatible.change('streamerPrivacy', true);
    expect(hidden.effectiveShowLocation, false);
    expect(hidden.roomCodeVisible, false);
    expect(hidden.showLocation, true);
    expect(hidden.change('streamerPrivacy', false).effectiveShowLocation, true);
    expect(
      hidden
          .change('showRoomCode', false)
          .change('streamerPrivacy', false)
          .roomCodeVisible,
      false,
    );
    for (final bad in [
      null,
      {...nested, 'clockFormat': 'bad'},
      {...nested, 'showServer': 1},
      {...nested, 'streamerPrivacy': null},
      {...nested, 'showRoomCode': 'true'},
      {...nested, 'reduceMotion': 1},
      {...nested, 'reduceMotion': null},
      {...nested, 'highContrast': null},
      {...nested, 'highContrast': 'true'},
      for (final invalid in [null, '125', 125.0, 0, 99, 126, true])
        {...nested, 'textScalePercent': invalid},
      for (final invalid in [null, '125', 125.0, 99, 126, true])
        {...nested, 'interfaceScalePercent': invalid},
      {...nested, 'account': 'forbidden'},
      {...nested}..remove('showDate'),
    ]) {
      expect(
        MenuWindowPreferences.parse({
          ...base.toMap(),
          'settings': {...base.settings, 'display': bad},
        }),
        isNull,
      );
    }
  });
  testWidgets(
    'display save failure keeps draft and reload preserves concurrent layout and toolbar',
    (tester) async {
      final store = _Store()..fail = true;
      await tester.pumpWidget(
        app(SingleChildScrollView(child: MenuDisplaySettingsCard(port: store))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-display-showClock')));
      await tester.pump();
      expect(store.writes, 0);
      final save = find.byKey(const Key('menu-display-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-display-error')), findsOneWidget);
      store.value = MenuWindowPreferences(
        9,
        const {
          'version': 1,
          'panels': [
            {
              'id': 'browser',
              'bounds': [10, 20, 500, 400],
            },
          ],
          'open': [],
        },
        {
          ...store.value.settings,
          'snapWindows': true,
          'toolbar': const MenuToolbarPreferences(hidden: ['friends']).toMap(),
        },
      );
      await tester.tap(find.byKey(const Key('menu-display-reload')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MenuDisplayEditor>(find.byType(MenuDisplayEditor))
            .value
            .showClock,
        false,
      );
      store.fail = false;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.value.settings['showClock'], false);
      expect(store.value.settings['snapWindows'], true);
      expect(
        MenuToolbarPreferences.parse(store.value.settings['toolbar'])!.hidden,
        ['friends'],
      );
      expect(store.value.layout['panels'], isNotEmpty);
      expect(store.value.revision, 10);
    },
  );
  testWidgets('late port read cannot replace the current settings editor', (
    tester,
  ) async {
    final old = _Store()..pending = Completer<MenuWindowPreferences>();
    final current = _Store()
      ..value = const MenuWindowPreferences(
        8,
        {'version': 1, 'panels': [], 'open': []},
        {'showClock': false, 'showContext': true, 'dimming': .5},
      );
    await tester.pumpWidget(
      app(SingleChildScrollView(child: MenuDisplaySettingsCard(port: old))),
    );
    await tester.pump();
    await tester.pumpWidget(
      app(SingleChildScrollView(child: MenuDisplaySettingsCard(port: current))),
    );
    await tester.pumpAndSettle();
    old.pending!.complete(old.value);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MenuDisplayEditor>(find.byType(MenuDisplayEditor))
          .value
          .showClock,
      false,
    );
    expect(current.writes, 0);
  });
  testWidgets(
    'clock format covers midnight noon system preference and localized date',
    (tester) async {
      final moment = DateTime(2026, 1, 2);
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Column(
              children: [
                Text(menuClockText(context, moment, 'twelveHour')),
                Text(
                  menuClockText(
                    context,
                    moment.add(const Duration(hours: 12)),
                    'twelveHour',
                  ),
                ),
                Text(
                  menuClockText(context, moment, 'system', system24Hour: true),
                ),
                Text(
                  menuClockText(context, moment, 'system', system24Hour: false),
                ),
                const MenuClock(
                  preferences: MenuDisplayPreferences(
                    showClock: false,
                    showPresence: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('上午 12:00'), findsNWidgets(2));
      expect(find.text('下午 12:00'), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-local-date')), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-local-clock')), findsNothing);
      expect(find.byKey(const ValueKey('menu-local-presence')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'menu display switches affect the live desktop and settings patch immediately',
    (tester) async {
      size(tester, const Size(1280, 900));
      final tools = MenuLocalToolsController((_, _) async => null);
      addTearDown(tools.dispose);
      Map<String, Object?>? saved;
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            localToolsController: tools,
            contextValues: const [
              'Scene',
              'Members',
              'Ship',
              'Location',
              'Server',
              'presence.away',
            ],
            onSettingsChanged: (value) => saved = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Location'), findsOneWidget);
      tools.settings(display: tools.display.change('textScalePercent', 125));
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(tester.element(find.text('Location')))
            .scale(16),
        20,
      );
      expect((saved!['display'] as Map)['textScalePercent'], 125);
      tools.settings(display: tools.display.change('reduceMotion', true));
      await tester.pumpAndSettle();
      expect(MediaQuery.disableAnimationsOf(tester.element(find.text('Location'))), true);
      expect((saved!['display'] as Map)['reduceMotion'], true);
      expect(tester.takeException(), isNull);
      tools.settings(display: tools.display.change('streamerPrivacy', true));
      await tester.pumpAndSettle();
      expect(find.text('Location'), findsNothing);
      expect(tools.display.showLocation, true);
      tools.settings(display: tools.display.change('streamerPrivacy', false));
      await tester.pumpAndSettle();
      expect(find.text('Location'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-local-presence')), findsOneWidget);
      tools.settings(
        display: tools.display
            .change('showLocation', false)
            .change('showClock', false)
            .change('showDate', false)
            .change('showPresence', false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Location'), findsNothing);
      expect(find.text('Server'), findsOneWidget);
      expect(find.byKey(const ValueKey('menu-local-presence')), findsNothing);
      expect(find.byType(MenuClock), findsNothing);
      expect((saved!['display'] as Map)['showLocation'], false);
      tools.settings(context: false);
      await tester.pumpAndSettle();
      expect(find.text('Server'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 760.0, 1040.0]) {
    testWidgets('display editor fits width $width', (tester) async {
      size(tester, Size(width, 900));
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: SingleChildScrollView(
              child: MenuDisplaySettingsCard(port: _Store()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'menu-display-${width.toInt()}');
      await tester.ensureVisible(
        find.byKey(const ValueKey('menu-display-showRoomCode')),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'menu-display-privacy-${width.toInt()}');
    });
  }
  for (final locale in [const Locale('en'), const Locale('zh', 'TW')]) {
    testWidgets(
      'display controls localize at narrow width and enlarged text $locale',
      (tester) async {
        size(tester, const Size(320, 900));
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: locale,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.8)),
                  child: SingleChildScrollView(
                    child: MenuDisplaySettingsCard(port: _Store()),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(AppStrings.resolve(locale).text('menu.display.title')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
