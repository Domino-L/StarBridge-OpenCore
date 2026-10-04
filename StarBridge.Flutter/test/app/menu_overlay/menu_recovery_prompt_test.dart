import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_prompt.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadFonts();
    // Widget tests do not discover Windows system fonts. Register this local
    // face for review only; never copy it into the repository or change the
    // production font contract to make a synthetic screenshot pass.
    final traditional = File('C:/Windows/Fonts/msjh.ttc');
    if (Platform.isWindows && await traditional.exists()) {
      await (FontLoader(
        'Microsoft JhengHei UI',
      )..addFont(traditional.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final width in [320.0, 1280.0]) {
      testWidgets('recovery prompt $locale at $width and large text', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.reset);
        final actions = <String>[];
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            theme: buildMenuOverlayTheme(locale),
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
              Locale('en', 'US'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundaryKey,
              child: MenuRecoveryPrompt(onChoose: actions.add, failed: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (boundaryKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('build/reviews').create(recursive: true);
            await File(
              'build/reviews/menu-recovery-${locale.toLanguageTag()}-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).autofocus,
          true,
        );
        await tester.ensureVisible(find.byType(FilledButton));
        await tester.tap(find.byType(FilledButton));
        expect(actions, ['startClean']);
      });
    }
  }
}
