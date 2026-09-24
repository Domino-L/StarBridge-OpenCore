import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/bootstrap/shell_review_configuration.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/app/shell/widgets/navigation_item.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/design_system/styles/probe_style.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final windowCases = <({Size size, double dpiScale})>[
    (size: const Size(900, 620), dpiScale: 1),
    (size: const Size(1280, 720), dpiScale: 1.25),
    (size: const Size(1440, 900), dpiScale: 1.5),
    (size: const Size(1920, 1080), dpiScale: 1.75),
  ];

  for (final windowCase in windowCases) {
    testWidgets(
      'shell remains bounded at ${windowCase.size.width}x${windowCase.size.height} '
      'and ${windowCase.dpiScale}x DPI',
      (tester) async {
        await _pumpShell(
          tester,
          logicalSize: windowCase.size,
          dpiScale: windowCase.dpiScale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(StarBridgeShell), findsOneWidget);
        expect(
          find.byKey(const Key('application-window-frame')),
          findsOneWidget,
        );
        final frame = tester.widget<DecoratedBox>(
          find.byKey(const Key('application-window-frame')),
        );
        final decoration = frame.decoration as BoxDecoration;
        final border = decoration.border! as Border;
        final shellContext = tester.element(find.byType(StarBridgeShell));
        final expectedColor = shellContext.tokens.surfaces.windowFrame;
        expect(frame.position, DecorationPosition.foreground);
        for (final side in [
          border.top,
          border.right,
          border.bottom,
          border.left,
        ]) {
          expect(side.width, shellContext.tokens.stroke.hairline);
          expect(side.color, expectedColor);
        }
        expect(find.text('首页'), findsOneWidget);
        expect(
          find.byKey(
            Key(
              'navigation-pane-${ShellLayoutResolver.resolve(windowCase.size.width).name}',
            ),
          ),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('traditional Chinese and English are complete shell locales', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences();
    await _pumpShell(tester, preferences: preferences);

    await preferences.setLocale(const Locale('zh', 'TW'));
    await tester.pumpAndSettle();
    expect(find.text('首頁'), findsOneWidget);
    expect(find.text('社區組織'), findsOneWidget);

    await preferences.setLocale(const Locale('en', 'US'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Communities'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disconnected shell restores the global status notice', (
    tester,
  ) async {
    await _pumpShell(tester);

    final noticeFinder = find.byKey(const Key('connection-status-notice'));
    expect(noticeFinder, findsOneWidget);
    expect(find.text('客户端连接中断'), findsOneWidget);
    expect(find.text('Native Host 暂时不可用，应用正在自动重连。'), findsOneWidget);

    final notice = tester.widget<Container>(noticeFinder);
    final decoration = notice.decoration! as BoxDecoration;
    final shellContext = tester.element(find.byType(StarBridgeShell));
    final colors = shellContext.tokens.colors;
    expect(decoration.color, colors.dangerSoft);
    expect(
      (decoration.border! as Border).bottom.color,
      colors.danger.withValues(alpha: 0.72),
    );
  });

  testWidgets('long pseudo locale and RTL probe preserve the shell structure', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences(
      initial: AppPreferences.defaults.copyWith(
        locale: const Locale('en', 'XA'),
      ),
    );
    await _pumpShell(
      tester,
      logicalSize: const Size(900, 620),
      preferences: preferences,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Home · Home'), findsOneWidget);

    await preferences.setLocale(const Locale('ar', 'XB'));
    await tester.pumpAndSettle();
    final shellContext = tester.element(find.byType(StarBridgeShell));
    expect(Directionality.of(shellContext), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('appearance and reduced motion resolve through preferences', (
    tester,
  ) async {
    final preferences = InMemoryAppPreferences(
      initial: AppPreferences.defaults.copyWith(
        appearanceMode: AppearanceMode.light,
        motionPreference: MotionPreference.reduce,
      ),
    );
    await _pumpShell(tester, preferences: preferences);

    final context = tester.element(find.byType(StarBridgeShell));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(context.tokens.motion.pointerPageSwap, Duration.zero);
    expect(context.tokens.motion.splashEnabled, isFalse);
  });

  for (final appearance in AppearanceMode.values) {
    testWidgets('extreme probe renders the real Shell in ${appearance.name}', (
      tester,
    ) async {
      final preferences = InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(
          appearanceMode: appearance,
          designStyleId: ProbeStyle.id,
        ),
      );
      await _pumpShell(
        tester,
        logicalSize: const Size(900, 620),
        preferences: preferences,
      );

      final context = tester.element(find.byType(StarBridgeShell));
      expect(context.tokens.styleId, ProbeStyle.id);
      expect(context.tokens.appearanceMode, appearance);
      expect(tester.takeException(), isNull);
    });
  }

  test('Shell review configuration is explicit and fails safe', () {
    expect(
      ShellReviewConfiguration.fromEnvironment(const {})
          .preferences
          .appearanceMode,
      AppearanceMode.dark,
    );
    expect(
      ShellReviewConfiguration.fromEnvironment(const {
        ShellReviewConfiguration.appearanceEnvironmentKey: 'light',
      }).preferences.appearanceMode,
      AppearanceMode.light,
    );
    expect(
      ShellReviewConfiguration.fromEnvironment(const {
        ShellReviewConfiguration.appearanceEnvironmentKey: 'unknown',
      }).preferences.appearanceMode,
      AppearanceMode.dark,
    );
    expect(
      ShellReviewConfiguration.fromEnvironment(const {})
          .projection
          .connectionIssue,
      isNotNull,
    );
    expect(
      ShellReviewConfiguration.fromEnvironment(const {
        ShellReviewConfiguration.stateEnvironmentKey: 'healthy',
      }).projection.connectionIssue,
      isNull,
    );
    final example = ShellReviewConfiguration.forExampleScene(const {});
    expect(example.projection.connectionIssue, isNull);
    expect(example.accountState, AccountReviewState.signedIn);
  });

  testWidgets('keyboard traversal can activate a navigation destination', (
    tester,
  ) async {
    await _pumpShell(tester);

    var reached = false;
    final traversed = <String>[];
    for (var step = 0; step < 30; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final item = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ShellNavigationItem>();
      traversed.add(
        '${FocusManager.instance.primaryFocus?.debugLabel}: ${item?.descriptor.id} ${FocusManager.instance.primaryFocus?.nearestScope?.traversalEdgeBehavior}',
      );
      if (item?.descriptor.id == 'official-fleet') {
        reached = true;
        break;
      }
    }
    expect(
      reached,
      isTrue,
      reason: 'The fleet destination must be reachable by Tab: $traversed',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(OfficialFleetPage), findsOneWidget);
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size logicalSize = const Size(1280, 720),
  double dpiScale = 1,
  InMemoryAppPreferences? preferences,
}) async {
  tester.view.devicePixelRatio = dpiScale;
  tester.view.physicalSize = Size(
    logicalSize.width * dpiScale,
    logicalSize.height * dpiScale,
  );
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final composition = AppComposition.forTest(
    windowChrome: InMemoryWindowChrome(),
    preferences: preferences,
  );
  await tester.pumpWidget(StarBridgeApp(composition: composition));
  await tester.pumpAndSettle();
}
