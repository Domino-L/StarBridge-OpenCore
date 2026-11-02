import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_widget.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_window.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_menu_widget_button.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/platform/window/menu_desktop_widgets.dart';
import 'package:starbridge_flutter/platform/window/menu_display_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_exec_hangar_summary.dart';
import 'package:starbridge_flutter/platform/window/menu_toolbar_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import '../../features/tools/exec_hangar_test.dart'
    show app, sample, ExperiencePort, origin, captureHangar;
import '../../features/friends/social_layout_test.dart' show size, loadFonts;

class SummaryPort implements MenuExecHangarSummaryPort {
  int reads = 0;
  MenuExecHangarSummary value = MenuExecHangarSummary.fromSnapshot(sample());
  Completer<MenuExecHangarSummary>? pending;
  @override
  Future<MenuExecHangarSummary> read() async {
    reads++;
    return pending?.future ?? value;
  }
}

class PreferencesPort implements MenuWindowPreferencesPort {
  MenuWindowPreferences value = MenuWindowPreferences.defaults;
  bool conflict = false;
  @override
  Future<MenuWindowPreferences> read() async => value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences proposed) async {
    if (conflict || proposed.revision != value.revision) {
      throw StateError('revision conflict');
    }
    return value = MenuWindowPreferences(
      value.revision + 1,
      proposed.layout,
      proposed.settings,
    );
  }
}

void main() {
  testWidgets(
    'default widget follows menu openings and respects an explicit hidden choice',
    (tester) async {
      size(tester, const Size(1000, 700));
      final port = SummaryPort();
      Widget menu(Map<String, Object?>? settings) => app(
        MenuBridgePreview(
          visible: true,
          onDismiss: () {},
          hangar: port,
          initialSettings: settings,
          localCall: (_, _) async => null,
        ),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      );
      await tester.pumpWidget(menu(null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-widget')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(menu(null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-widget')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        menu(
          MenuWindowPreferences.defaults.withSettingsPatch({
            'widgets': const MenuDesktopWidgets(hangar: false).toMap(),
          }).settings,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-widget')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'fixed transparent widget extends the clock rail and ignores legacy positions',
    (tester) async {
      size(tester, const Size(1000, 700));
      Rect? fixed;
      for (final point in const [
        Offset.zero,
        Offset(1, 0),
        Offset(0, 1),
        Offset(1, 1),
      ]) {
        await tester.pumpWidget(
          app(
            MenuBridgePreview(
              visible: true,
              onDismiss: () {},
              hangar: SummaryPort(),
              localCall: (_, _) async => null,
              initialSettings: MenuWindowPreferences.defaults.withSettingsPatch(
                {
                  'widgets': MenuDesktopWidgets(
                    x: point.dx,
                    y: point.dy,
                  ).toMap(),
                },
              ).settings,
            ),
            const Locale('zh', 'CN'),
            AppearanceMode.dark,
          ),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(
          find.byKey(const Key('menu-hangar-widget')),
        );
        expect(rect.width, 268);
        expect(rect.height, lessThan(85));
        final rail = tester.getRect(
          find.byKey(const Key('menu-information-rail')),
        );
        final presence = tester.getRect(
          find.byKey(const ValueKey('menu-local-presence')),
        );
        expect(rect.top, greaterThan(presence.bottom));
        expect(rail.contains(rect.topLeft), true);
        expect(rail.contains(rect.bottomRight), true);
        final decoration =
            tester
                    .widget<Container>(
                      find.byKey(const Key('menu-information-rail')),
                    )
                    .decoration!
                as BoxDecoration;
        expect(decoration.color, isNull);
        expect(decoration.border!.isUniform, false);
        fixed ??= rect;
        expect(rect, fixed);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'fixed widget ignores movement and supports keyboard activation',
    (tester) async {
      size(tester, const Size(1000, 700));
      var value = const MenuDesktopWidgets(x: .3, y: .3);
      var saves = 0;
      var opened = 0;
      final port = SummaryPort();
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) => MenuExecHangarWidget(
              port: port,
              preferences: value,
              editing: false,
              onOpen: () => opened++,
              onEdit: () {},
              onChanged: (next, persist) {
                setState(() => value = next);
                if (persist) saves++;
              },
            ),
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const Key('menu-hangar-widget')));
      await tester.drag(
        find.byKey(const Key('menu-hangar-widget')),
        const Offset(120, 80),
      );
      await tester.pumpAndSettle();
      expect(value.x, .3);
      expect(value.y, .3);
      expect(saves, 0);
      expect(tester.getRect(find.byKey(const Key('menu-hangar-widget'))), rect);
      await tester.tap(find.byKey(const Key('menu-hangar-widget')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, 2);
      expect(saves, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('hangar keeps its rail when clock date and presence are hidden', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = SummaryPort();
    await tester.pumpWidget(
      app(
        MenuBridgePreview(
          visible: true,
          onDismiss: () {},
          hangar: port,
          localCall: (_, _) async => null,
          initialSettings: MenuWindowPreferences.defaults
              .withSettingsPatch(
                const MenuDisplayPreferences(
                  showClock: false,
                  showDate: false,
                  showPresence: false,
                ).toSettingsPatch(),
              )
              .settings,
        ),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-information-rail')), findsOneWidget);
    expect(find.byKey(const Key('menu-hangar-widget')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-local-clock')), findsNothing);
    expect(find.byKey(const ValueKey('menu-local-date')), findsNothing);
    expect(find.byKey(const ValueKey('menu-local-presence')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'unpinned menu has discoverable pin and add entries without app handoff',
    (tester) async {
      size(tester, const Size(1280, 900));
      final port = SummaryPort();
      var opened = 0;
      Map<String, Object?>? saved, layout;
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            onDismiss: () {},
            localCall: (_, _) async => null,
            hangar: port,
            initialSettings: MenuWindowPreferences.defaults.withSettingsPatch({
              'widgets': const MenuDesktopWidgets(hangar: false).toMap(),
            }).settings,
            onOpenHangar: () => opened++,
            onSettingsChanged: (value) => saved = value,
            onLayoutChanged: (value) => layout = value,
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-widget')), findsNothing);
      await tester.tap(find.byKey(const Key('menu-tool-ship')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-window')), findsOneWidget);
      expect(find.byKey(const Key('exec-countdown')), findsOneWidget);
      expect(find.text('接下来的开启与关闭'), findsOneWidget);
      expect(opened, 0);
      expect(
        (layout!['panels'] as List).where((p) => p['id'] == 'execHangar'),
        hasLength(1),
      );
      expect(
        MenuWindowPreferences.parse(
          MenuWindowPreferences(
            0,
            layout!,
            MenuWindowPreferences.defaults.settings,
          ).toMap(),
        ),
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('menu-hangar-pin')));
      await tester.pumpAndSettle();
      expect(MenuDesktopWidgets.parse(saved!['widgets'])!.hangar, true);
      expect(find.byKey(const Key('menu-hangar-widget')), findsOneWidget);
      expect(
        find.byKey(const Key('menu-hangar-window')),
        findsNothing,
        reason: 'Pinning reveals the desktop widget immediately',
      );
      await tester.tap(find.byKey(const Key('menu-tool-ship')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-hangar-pin')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-widget')), findsNothing);
      await tester.tap(find.byKey(const Key('menu-edit-widgets')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-add-hangar-widget')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-widget')), findsOneWidget);
      expect(MenuDesktopWidgets.parse(saved!['widgets'])!.hangar, true);
      expect(opened, 0);
      await tester.tap(find.byKey(const Key('menu-tool-ship')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-hangar-settings')));
      await tester.pumpAndSettle();
      expect(
        opened,
        1,
        reason: 'Only the explicit app reminder-settings action navigates',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'menu timing window pauses reads while hidden and rejects old replies',
    (tester) async {
      size(tester, const Size(800, 700));
      final port = SummaryPort();
      var active = true;
      var accepted = 0;
      Widget build() => app(
        MenuExecHangarWindow(
          port: port,
          active: active,
          pinned: false,
          onSnapshot: (_) => accepted++,
        ),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(accepted, 1);
      port.pending = Completer<MenuExecHangarSummary>();
      await tester.pump(const Duration(seconds: 60));
      await tester.pump();
      active = false;
      await tester.pumpWidget(build());
      port.pending!.complete(port.value);
      await tester.pumpAndSettle();
      expect(accepted, 1);
      final reads = port.reads;
      await tester.pump(const Duration(minutes: 2));
      expect(port.reads, reads);
      port.pending = null;
      active = true;
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(accepted, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('menu time window respects narrow layout and locale $locale', (
      tester,
    ) async {
      size(tester, const Size(320, 700));
      final port = SummaryPort();
      await tester.pumpWidget(
        app(
          MenuExecHangarWindow(
            port: port,
            active: true,
            pinned: false,
            onPinned: (_) {},
            onSettings: () {},
          ),
          locale,
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exec-countdown')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'menu time window visual capture uses shared clock and timeline',
    (tester) async {
      size(tester, const Size(1280, 900));
      if (Platform.environment['STARBRIDGE_CAPTURE_EXEC'] == '1') {
        await tester.runAsync(loadFonts);
      }
      final visual = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: visual,
            child: MenuBridgePreview(
              visible: true,
              onDismiss: () {},
              localCall: (_, _) async => null,
              hangar: SummaryPort(),
              onOpenHangar: () {},
            ),
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-tool-ship')));
      await tester.pumpAndSettle();
      await captureHangar(tester, visual, 'exec-hangar-menu-window');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('legacy toolbar appends hangar without resetting custom order or visibility', () {
    final old = MenuToolbarPreferences.ids
        .where((id) => id != 'execHangar')
        .toList()
        .reversed
        .toList();
    final saved = MenuToolbarPreferences.parse({
      'order': old,
      'hidden': ['friends', 'image'],
      'density': 'compact',
      'labels': 'iconsOnly',
    });
    expect(saved!.order, [...old, 'execHangar']);
    expect(saved.hidden, ['friends', 'image']);
    expect(saved.density, 'compact');
    expect(MenuToolbarPreferences.parse(saved.toMap())!.toMap(), saved.toMap());
    expect(
      MenuToolbarPreferences.parse({
        ...saved.toMap(),
        'order': [...old.skip(1), 'execHangar'],
      }),
      isNull,
    );
  });
  test(
    'menu widgets accept bounded positions and reject unrelated authority',
    () {
      for (final raw in [
        {
          'hangar': true,
          'position': [1.01, 0],
        },
        {
          'hangar': true,
          'position': [-.1, 0],
        },
        {
          'hangar': true,
          'position': [0, double.nan],
        },
        {
          'hangar': true,
          'position': [0, 0],
          'account': 'forbidden',
        },
        {
          'hangar': 1,
          'position': [0, 0],
        },
      ]) {
        expect(MenuDesktopWidgets.parse(raw), isNull);
      }
      final raw = const MenuDesktopWidgets(hangar: true, x: .7, y: .8).toMap();
      final saved = MenuWindowPreferences.defaults.withSettingsPatch({
        'widgets': raw,
      });
      expect(
        MenuWindowPreferences.parse(jsonDecode(saved.encode()))!
            .settings['widgets'],
        raw,
      );
      expect(
        MenuWindowPreferences.parse(
          saved.withSettingsPatch({'widgets': null}).toMap(),
        ),
        isNull,
      );
    },
  );
  test(
    'summary request fences late replies and rejects every non-read intent',
    () async {
      final port = ExperiencePort();
      var current = true, opened = 0;
      Future<Object?> call(String method, Object? args) =>
          MenuExecHangarRequest.handle(
            method: method,
            arguments: args,
            opening: 3,
            isCurrent: () => current,
            port: port,
            openTool: () => opened++,
          );
      final reply = await call('execHangarSummary', {'opening': 3}) as String;
      final summary = MenuExecHangarSummary.parse(jsonDecode(reply));
      expect(summary.phases.first.green, 5);
      expect(
        jsonDecode(reply).keys,
        unorderedEquals(['now', 'reliable', 'fetchedAt', 'phases', 'windows']),
      );
      await call('openExecHangar', {'opening': 3});
      expect(opened, 1);
      for (final args in [
        {'opening': 2},
        {'opening': 3, 'action': 'stop'},
        {'opening': 3, 'payload': '{}'},
      ]) {
        await expectLater(
          call('execHangarSummary', args),
          throwsA(isA<PlatformException>()),
        );
      }
      await expectLater(
        call('execHangar.stop', {'opening': 3}),
        throwsA(isA<PlatformException>()),
      );
      current = false;
      await expectLater(
        call('openExecHangar', {'opening': 3}),
        throwsA(isA<PlatformException>()),
      );
      expect(opened, 1);
      expect(port.saves, 0);
      expect(port.starts, 0);
      expect(port.tests, 0);
      final pending = Completer<MenuExecHangarSummary>();
      const channel = MethodChannel('fixture/menu-hangar');
      current = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => jsonEncode((await pending.future).toMap()),
          );
      final future = SurfaceMenuExecHangarSummary(
        channel,
        3,
        () => current,
      ).read();
      final rejected = expectLater(future, throwsA(isA<PlatformException>()));
      current = false;
      pending.complete(summary);
      await rejected;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets(
    'adding to menu preserves latest geometry and failures keep old choice',
    (tester) async {
      size(tester, const Size(800, 500));
      final port = PreferencesPort()
        ..value = MenuWindowPreferences.defaults.withSettingsPatch({
          'widgets': const MenuDesktopWidgets(hangar: false).toMap(),
        });
      await tester.pumpWidget(
        app(
          ExecHangarMenuWidgetButton(port: port),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      final layout = {
        'version': 1,
        'panels': [
          {
            'id': 'browser',
            'bounds': [10, 20, 500, 300],
          },
        ],
        'open': <String>[],
      };
      port.value = MenuWindowPreferences(5, layout, {
        ...port.value.settings,
        'widgets': const MenuDesktopWidgets(x: .8, y: .4).toMap(),
      });
      await tester.tap(find.byKey(const Key('exec-pin-menu')));
      await tester.pumpAndSettle();
      expect(
        MenuDesktopWidgets.parse(port.value.settings['widgets'])!.hangar,
        true,
      );
      expect(MenuDesktopWidgets.parse(port.value.settings['widgets'])!.x, .8);
      expect(port.value.layout, layout);
      expect(port.value.revision, 6);
      port.conflict = true;
      await tester.tap(find.byKey(const Key('exec-pin-menu')));
      await tester.pumpAndSettle();
      expect(find.text('菜单设置未保存，请重试。'), findsOneWidget);
      expect(
        MenuDesktopWidgets.parse(port.value.settings['widgets'])!.hangar,
        true,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'menu widget opens an in-menu window and editing never navigates to app',
    (tester) async {
      size(tester, const Size(1280, 900));
      if (Platform.environment['STARBRIDGE_CAPTURE_EXEC'] == '1') {
        await tester.runAsync(loadFonts);
      }
      final visual = GlobalKey();
      final port = SummaryPort();
      Map<String, Object?>? saved;
      var opened = 0;
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: visual,
            child: MenuBridgePreview(
              visible: true,
              onDismiss: () {},
              localCall: (_, _) async => null,
              hangar: port,
              onOpenHangar: () => opened++,
              initialSettings: {
                ...MenuWindowPreferences.defaults.settings,
                'widgets': const MenuDesktopWidgets(hangar: true).toMap(),
              },
              onSettingsChanged: (value) => saved = value,
            ),
          ),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('01:05:00'), findsOneWidget);
      await captureHangar(tester, visual, 'exec-hangar-menu-widget');
      await tester.tap(find.byKey(const Key('menu-hangar-widget')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-window')), findsOneWidget);
      expect(opened, 0);
      await tester.tap(find.byKey(const Key('menu-tool-ship')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-window')), findsOneWidget);
      expect(opened, 0);
      await tester.tap(find.byKey(const ValueKey('menu-toggle-all-windows')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-edit-widgets')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('menu-hangar-widget')),
        const Offset(200, 120),
      );
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(opened, 0, reason: 'Drag never navigates to the app');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(saved, isNull, reason: 'Fixed rail never saves a position');
      await tester.tap(find.byKey(const Key('menu-hangar-remove')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-hangar-widget')), findsNothing);
      expect(MenuDesktopWidgets.parse(saved!['widgets'])!.hangar, false);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final width in [320.0, 520.0]) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en', 'US'),
    ]) {
      testWidgets(
        'summary layout $width ${locale.toLanguageTag()} and closing phase',
        (tester) async {
          size(tester, Size(width, 400));
          final port = SummaryPort()
            ..value = MenuExecHangarSummary.fromSnapshot(
              sample(
                at: origin.add(const Duration(minutes: 63)),
                phases: [
                  ExecHangarPhase(
                    origin,
                    origin.add(const Duration(minutes: 65)),
                    true,
                    0,
                    0,
                  ),
                ],
              ),
            );
          await tester.pumpWidget(
            app(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: MenuExecHangarWidget(
                    port: port,
                    preferences: const MenuDesktopWidgets(hangar: true),
                    editing: false,
                    onOpen: () {},
                    onEdit: () {},
                    onChanged: (_, _) {},
                  ),
                ),
              ),
              locale,
              AppearanceMode.dark,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('00:02:00'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  TestWidgetsFlutterBinding.ensureInitialized();
}
