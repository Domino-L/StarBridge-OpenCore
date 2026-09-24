import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

Widget app(
  Widget child, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, mode)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: const [
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('en'),
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  for (final mode in AppearanceMode.values) {
    testWidgets('render tray component $mode', (tester) async {
      tester.view.physicalSize = const Size(400, 660);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: TrayQuickPanel(
              state: const TrayQuickPanelState(
                runtime: TrayRuntimeState.background,
                overlay: TrayOverlayState.enabled,
                scene: '默认场景',
                version: '1.0.0',
              ),
              onDismiss: () {},
              onOpen: () async {},
              onOverlaySettings: () async {},
              onToggleOverlay: () async {},
              onExit: () async {},
            ),
          ),
          mode: mode,
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final asset in [
          'assets/brand/starbridge_taskbar_compact.png',
          'assets/brand/starbridge_taskbar_trails.png',
        ]) {
          await precacheImage(AssetImage(asset), boundary.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      if (Platform.environment['STARBRIDGE_RENDER_TRAY'] == '1') {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/tray-component-review');
          await directory.create(recursive: true);
          await File('${directory.path}/${mode.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unavailable facts do not invent scene or enable actions', (
    tester,
  ) async {
    var toggles = 0;
    await tester.pumpWidget(
      app(
        TrayQuickPanel(
          state: const TrayQuickPanelState(),
          onDismiss: () {},
          onToggleOverlay: () async {
            toggles++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('tray-enable')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('tray-exit')))
          .onPressed,
      isNull,
    );
    expect(find.text('自动 · 舰队'), findsNothing);
    expect(toggles, 0);
  });
  testWidgets('real projected facts and explicit operations', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      app(
        TrayQuickPanel(
          state: const TrayQuickPanelState(
            runtime: TrayRuntimeState.background,
            overlay: TrayOverlayState.enabled,
            scene: '测试组织场景',
            version: '1.2.3',
          ),
          onDismiss: () => calls.add('dismiss'),
          onOpen: () async {
            calls.add('open');
          },
          onToggleOverlay: () async {
            calls.add('toggle');
          },
          onOverlaySettings: () async {
            calls.add('settings');
          },
          onExit: () async {
            calls.add('exit');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('测试组织场景'), findsOneWidget);
    for (final key in ['open', 'disable', 'settings', 'exit']) {
      await tester.tap(find.byKey(Key('tray-$key')));
      await tester.pumpAndSettle();
    }
    expect(calls, ['open', 'toggle', 'settings', 'exit']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(calls.last, 'dismiss');
  });
  testWidgets(
    'pending action blocks all repeated operations without optimistic state',
    (tester) async {
      final done = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        app(
          TrayQuickPanel(
            state: const TrayQuickPanelState(
              overlay: TrayOverlayState.disabled,
            ),
            onDismiss: () {},
            onToggleOverlay: () {
              calls++;
              return done.future;
            },
            onExit: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = tester
          .widget<OutlinedButton>(find.byKey(const Key('tray-enable')))
          .onPressed!;
      action();
      action();
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('tray-exit')))
            .onPressed,
        isNull,
      );
      expect(find.text('未开启'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      done.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failure is visible and retryable', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      app(
        TrayQuickPanel(
          state: const TrayQuickPanelState(),
          onDismiss: () {},
          onOpen: () async {
            if (++attempts == 1) throw StateError('private');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tray-open')));
    await tester.pumpAndSettle();
    expect(find.text('未能完成操作，请重试。'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    await tester.tap(find.byKey(const Key('tray-open')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('未能完成操作，请重试。'), findsNothing);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    for (final mode in AppearanceMode.values) {
      testWidgets('narrow tray $locale $mode', (tester) async {
        tester.view.physicalSize = const Size(360, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            TrayQuickPanel(
              state: const TrayQuickPanelState(
                overlay: TrayOverlayState.enabled,
                scene: 'Long scene name · A very long community name · 场景名称',
              ),
              onDismiss: () {},
            ),
            locale: locale,
            mode: mode,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('tray-exit')));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
