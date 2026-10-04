import 'package:flutter/material.dart';

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

Future<void> verifyPaint(
  WidgetTester tester,
  GlobalKey boundary,
  String phase,
) async {
  await tester.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final codec = await ui.instantiateImageCodec(png.buffer.asUint8List());
    final decoded = (await codec.getNextFrame()).image;
    final roundtrip = (await decoded.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    for (final entry in {'raw': raw, 'png': roundtrip}.entries) {
      var bright = 0;
      for (var y = 35; y < 95; y++) {
        for (var x = 45; x < 330; x++) {
          final i = (y * image.width + x) * 4;
          if (entry.value.getUint8(i) > 180 &&
              entry.value.getUint8(i + 1) > 180 &&
              entry.value.getUint8(i + 2) > 180 &&
              entry.value.getUint8(i + 3) > 180) {
            bright++;
          }
        }
      }
      expect(
        bright,
        greaterThan(100),
        reason: '$phase ${entry.key}: clock must remain painted',
      );
    }
    decoded.dispose();
    codec.dispose();
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  testWidgets('fresh strong contrast workspace visual', (tester) async {
    size(tester, const Size(1280, 900));
    final tools = MenuLocalToolsController((_, _) async => null);
    tools.settings(display: tools.display.change('highContrast', true));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      app(
        RepaintBoundary(
          key: boundary,
          child: MenuBridgePreview(
            visible: true,
            localToolsController: tools,
            onDismiss: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final workspace = tester
        .widget<MenuBridgeWorkspace>(find.byType(MenuBridgeWorkspace))
        .controller;
    expect(workspace.open('friends'), true);
    await tester.pumpAndSettle();
    await capture(tester, boundary, 'menu-contrast-fresh-strong-1280');
    await verifyPaint(tester, boundary, 'fresh strong contrast');
    await tester.pumpWidget(const SizedBox());
    tools.dispose();
  });
  testWidgets(
    'contrast switches on the actual workspace without losing tools',
    (tester) async {
      size(tester, const Size(1280, 900));
      final tools = MenuLocalToolsController((_, _) async => null);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: boundary,
            child: MenuBridgePreview(
              visible: true,
              localToolsController: tools,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final workspace = tester
          .widget<MenuBridgeWorkspace>(find.byType(MenuBridgeWorkspace))
          .controller;
      expect(workspace.open('friends'), true);
      await tester.pumpAndSettle();
      final layout = workspace.exportLayout();
      for (var iteration = 0; iteration < 12; iteration++) {
        final enabled = iteration.isOdd;
        tools.settings(display: tools.display.change('highContrast', enabled));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(workspace.exportLayout(), layout);
        expect(
          tester
              .widget<MenuPresentation>(find.byType(MenuPresentation))
              .highContrast,
          enabled,
        );
        await verifyPaint(
          tester,
          boundary,
          'iteration $iteration contrast $enabled',
        );
        await capture(
          tester,
          boundary,
          'menu-contrast-${enabled ? "strong" : "normal"}-1280',
        );
      }
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    },
  );
  testWidgets(
    'strong outlines honor system preference and preserve image palette',
    (tester) async {
      for (final system in [false, true]) {
        for (final user in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(highContrast: system),
                child: MenuPresentation(
                  safeMode: false,
                  highContrast: user,
                  child: Builder(
                    builder: (context) {
                      final ink = MenuBridgeColors.of(context);
                      expect(
                        ink.line,
                        system || user ? BridgeInk.text : BridgeInk.line,
                      );
                      expect(
                        ink.blue,
                        system || user ? BridgeInk.text : BridgeInk.blue,
                      );
                      expect(ink.panel, BridgeInk.panel);
                      return const BridgePlate(child: Text('Panel'));
                    },
                  ),
                ),
              ),
            ),
          );
          final plate = tester.widget<DecoratedBox>(
            find.descendant(
              of: find.byType(BridgePlate),
              matching: find.byType(DecoratedBox),
            ),
          );
          final border = (plate.decoration as BoxDecoration).border! as Border;
          expect(
            border.bottom.color,
            system || user ? BridgeInk.text : BridgeInk.line,
          );
        }
      }
    },
  );
}
