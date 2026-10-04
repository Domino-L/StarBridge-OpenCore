import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_chrome_scale.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'moving tools reuses chrome paint while new display settings still render',
    (tester) async {
      size(tester, const Size(1280, 900));
      final tools = MenuLocalToolsController((_, _) async => null);
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            localToolsController: tools,
            onDismiss: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final workspace = tester
          .widget<MenuBridgeWorkspace>(find.byType(MenuBridgeWorkspace))
          .controller;
      expect(workspace.open('friends'), true);
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('menu-chrome-paint-boundary')),
      );
      boundary.debugResetMetrics();
      final lease = workspace.openPanels.single;
      for (var i = 0; i < 10; i++) {
        workspace.moveTo(
          lease,
          Offset(20 + i * 3, 30 + i * 2),
          const Size(1280, 900),
        );
        await tester.pump();
      }
      expect(boundary.debugSymmetricPaintCount, 0);
      expect(boundary.debugAsymmetricPaintCount, greaterThan(0));
      tools.settings(display: tools.display.change('showClock', false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-local-clock')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    },
  );
  for (final width in [1280.0, 1440.0]) {
    testWidgets('maximum chrome and accessible text fit $width', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      final tools = MenuLocalToolsController((_, _) async => null);
      tools.settings(
        display: tools.display
            .change('interfaceScalePercent', 125)
            .change('textScalePercent', 125),
      );
      final boundary = GlobalKey();
      var dismissed = false;
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: TextScaler.linear(1.8),
            ),
            child: RepaintBoundary(
              key: boundary,
              child: MenuBridgePreview(
                visible: true,
                localToolsController: tools,
                contextValues: const [
                  'Synthetic organization',
                  '6',
                  'Test ship',
                  'Test location',
                  'Test server',
                  'presence.away',
                ],
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'menu-chrome-large-${width.toInt()}');
      await tester.tap(find.byKey(const ValueKey('menu-return')));
      expect(dismissed, true);
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    });
  }
  for (final width in [1280.0, 1440.0]) {
    testWidgets('live chrome scale preserves tools and layout at $width', (
      tester,
    ) async {
      size(tester, Size(width, 900));
      final tools = MenuLocalToolsController((_, _) async => null);
      var dismissed = 0;
      await tester.pumpWidget(
        app(
          MenuBridgePreview(
            visible: true,
            localToolsController: tools,
            onDismiss: () => dismissed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final workspace = tester
          .widget<MenuBridgeWorkspace>(find.byType(MenuBridgeWorkspace))
          .controller;
      final before = workspace.exportLayout();
      for (final percent in [85, 100, 115, 125, 0]) {
        tools.settings(
          display: tools.display.change('interfaceScalePercent', percent),
        );
        await tester.pumpAndSettle();
        expect(workspace.exportLayout(), before);
        expect(
          tester.getSize(find.byType(MenuBridgeWorkspace)),
          Size(width, 900),
        );
        await tester.tap(find.byKey(const ValueKey('menu-return')));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(dismissed, 5);
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    });
  }
  testWidgets(
    'chrome fills surface at every scale and pointer targets stay aligned',
    (tester) async {
      for (final percent in [0, 85, 100, 115, 125]) {
        var tapped = false;
        Size? layout;
        await tester.pumpWidget(
          MaterialApp(
            home: MenuChromeScale(
              percent: percent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  layout = constraints.biggest;
                  return Align(
                    alignment: Alignment.bottomRight,
                    child: SizedBox(
                      width: 100,
                      height: 40,
                      child: TextButton(
                        key: const Key('target'),
                        onPressed: () => tapped = true,
                        child: const Text('Open'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final factor = percent == 0 ? 1.0 : percent / 100;
        expect(layout!.width, closeTo(800 / factor, .001));
        expect(layout!.height, closeTo(600 / factor, .001));
        await tester.tapAt(Offset(800 - 50 * factor, 600 - 20 * factor));
        await tester.pump();
        expect(tapped, true);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
