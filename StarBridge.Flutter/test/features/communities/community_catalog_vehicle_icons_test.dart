import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/shared/ships/catalog_vehicle_icon.dart';

import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets(
      'all final spacecraft icons render statically in ${mode.name}',
      (tester) async {
        tester.view.physicalSize = const Size(980, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const categories = [
          'combat',
          'exploration',
          'logistics',
          'industrial',
          'support',
          'competition',
          'unclassified',
        ];
        const sizes = ['small', 'medium', 'large', 'capital'];
        final tokens = FutureRestraintStyle.resolve(mode);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(tokens, const Locale('en')),
            home: RepaintBoundary(
              key: const ValueKey('icons-capture'),
              child: Scaffold(
                backgroundColor: tokens.surfaces.ground.fill,
                body: Column(
                  children: [
                    for (final size in sizes)
                      Expanded(
                        child: Row(
                          children: [
                            for (final category in categories)
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CatalogVehicleIcon(
                                      category: category,
                                      sizeClass: size,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(category),
                                    Text(size),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(CatalogVehicleIcon),
            matching: find.byType(CustomPaint),
          ),
          findsNWidgets(27),
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('icons-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File('build/catalog-vehicle-icons-${mode.name}.png')
              .writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
