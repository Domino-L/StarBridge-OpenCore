import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_preferences.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

Future<Uint8List> _png(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 640, 360),
      Paint()..color = const Color(0xff173348),
    );
    canvas.drawRect(
      const Rect.fromLTWH(40, 45, 180, 110),
      Paint()..color = const Color(0xff4cb2f5),
    );
    final picture = recorder.endRecording(),
        image = await picture.toImage(640, 360);
    bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  return bytes;
}

void main() {
  setUpAll(loadFonts);
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [320.0, 1040.0]) {
      testWidgets(
        'screenshot $locale width=$width previews without writing and explicit capture saves',
        (tester) async {
          size(tester, Size(width, 900));
          final png = await _png(tester),
              calls = <(String, Map<String, Object?>)>[];
          final tools = MenuLocalToolsController((action, arguments) async {
            calls.add((action, arguments));
            if (action == 'capture') return png;
            return true;
          });
          tools.screenshotDirectoryAvailable = true;
          tools.settings(
            screenshot: const MenuScreenshotPreferences(
              format: 'jpeg',
              jpegQuality: 75,
              copyAfterSave: true,
            ),
          );
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
                      child: MenuImageTool(tools: tools, capture: true),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(calls, isEmpty);
          final text = AppStrings.resolve(locale);
          await tester.tap(find.text(text.text('menu.screenshot.capture')));
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => precacheImage(
              MemoryImage(png),
              tester.element(find.byType(MenuImageTool)),
            ),
          );
          await tester.pumpAndSettle();
          expect(calls.map((call) => call.$1), ['capture']);
          for (final control in ['fit', 'zoomOut', 'zoomIn', 'rotate']) {
            expect(
              find.text(text.text('menu.screenshot.$control')),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'menu-screenshot-export-${locale.toLanguageTag()}-${width.toInt()}-preview',
          );
          final zoom = find.text(text.text('menu.screenshot.zoomIn'));
          await tester.ensureVisible(zoom);
          await tester.tap(zoom);
          await tester.pumpAndSettle();
          final view = tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer),
          );
          expect(
            view.transformationController!.value.getMaxScaleOnAxis(),
            1.25,
          );
          final fit = find.text(text.text('menu.screenshot.fit'));
          await tester.ensureVisible(fit);
          await tester.tap(fit);
          await tester.pumpAndSettle();
          expect(view.transformationController!.value.getMaxScaleOnAxis(), 1);
          expect(calls.map((call) => call.$1), ['capture']);
          await capture(
            tester,
            key,
            'menu-screenshot-export-${locale.toLanguageTag()}-${width.toInt()}-controls',
          );
          final save = find.text(text.text('menu.screenshot.captureSave'));
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(calls.map((call) => call.$1), [
            'capture',
            'capture',
            'screenshotDestination',
            'saveToDirectory',
            'screenshotCopy',
          ]);
          expect(calls[2].$2, isEmpty);
          expect(calls[3].$2['export'], {'format': 'jpeg', 'jpegQuality': 75});
          expect(calls.last.$2.containsKey('export'), false);
          expect(
            find.text(text.text('menu.screenshot.savedCopied')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'menu-screenshot-export-${locale.toLanguageTag()}-${width.toInt()}-saved',
          );
          await tester.pumpWidget(const SizedBox());
          tools.dispose();
        },
      );
    }
  }
}
