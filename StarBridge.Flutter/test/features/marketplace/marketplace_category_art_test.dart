import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_category_roots.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_silhouette.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';

import 'marketplace_slice4_test.dart' show preview;

Future<Uint8List> raster(
  WidgetTester tester,
  int category,
  int edge, {
  Color color = Colors.white,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox.square(
          dimension: edge.toDouble(),
          child: MarketSilhouette(category, color: color),
        ),
      ),
    ),
  );
  final painter = tester.widget<CustomPaint>(find.byType(CustomPaint)).painter!;
  return (await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Size.square(edge.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(edge, edge);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final result = Uint8List.fromList(data!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
    return result;
  }))!;
}

void main() {
  testWidgets('all nine categories remain visible and transparent at small sizes',
      (tester) async {
    for (var category = 1; category <= 9; category++) {
      for (final edge in [16, 24, 32, 64]) {
        final pixels = await raster(tester, category, edge);
        var filled = 0;
        for (var i = 3; i < pixels.length; i += 4) {
          if (pixels[i] > 128) filled++;
        }
        expect(filled, greaterThan(edge * edge * .06),
            reason: 'category $category at $edge px');
        expect(filled, lessThan(edge * edge * .7));
        expect(pixels[3], 0, reason: 'no background rectangle');
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('approved component A keeps end-frame and core gaps', (tester) async {
    final pixels = await raster(tester, 4, 64);
    int alpha(int x, int y) => pixels[(y * 64 + x) * 4 + 3];
    expect(alpha(10, 32), 255); // Left end frame.
    expect(alpha(17, 32), 0); // Frame / core gap.
    expect(alpha(22, 32), 255); // Inner module.
    expect(alpha(28, 32), 0); // Exposed central core gap.
    expect(alpha(31, 32), 255); // Central core.
    expect(alpha(42, 18), 255); // Upper cross-member.
  });

  testWidgets('artwork uses only supplied solid ink without gradient', (tester) async {
    const ink = Color(0xFF5082BE);
    for (var category = 1; category <= 9; category++) {
      final pixels = await raster(tester, category, 64, color: ink);
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i + 3] == 255) {
          expect(pixels[i], 80);
          expect(pixels[i + 1], 130);
          expect(pixels[i + 2], 190);
        }
      }
    }
  });

  testWidgets('existing child-category mapping reuses its root artwork', (tester) async {
    expect(await raster(tester, 41, 64), await raster(tester, 4, 64));
    expect(await raster(tester, 71, 32), await raster(tester, 7, 32));
    for (final unknown in [0, -1, 99]) {
      final pixels = await raster(tester, unknown, 24);
      expect(pixels.any((value) => value != 0), isTrue);
    }
  });

  for (final appearance in [AppearanceMode.dark, AppearanceMode.light]) {
    testWidgets('category artwork bypasses remote image and tinted surface $appearance',
        (tester) async {
      await tester.pumpWidget(
        preview(
          const SizedBox(
            width: 130,
            height: 108,
            child: Column(
              children: [
                Expanded(
                  child: MarketArt(
                    'https://example.invalid/category.png',
                    category: 4,
                    categoryIcon: true,
                    tint: Colors.purple,
                  ),
                ),
                Text('Component'),
              ],
            ),
          ),
          appearance,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarketSilhouette), findsOneWidget);
      expect(find.byType(RemoteImage), findsNothing);
      final paintedSize = tester.getSize(
        find.descendant(
          of: find.byType(MarketSilhouette),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(paintedSize.width, greaterThan(0));
      expect(paintedSize.height, greaterThan(0));
      final art = find.byType(MarketArt);
      expect(find.descendant(of: art, matching: find.byType(DecoratedBox)), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ordinary item art retains its remote-image path by default',
      (tester) async {
    await tester.pumpWidget(
      preview(
        const SizedBox.square(
          dimension: 64,
          child: MarketArt('https://example.invalid/item.png', category: 4),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    // The whole photo, plus the same photo blurred behind it for the bands.
    final images = tester.widgetList<RemoteImage>(find.byType(RemoteImage));
    expect(images.map((i) => i.fit), [BoxFit.cover, BoxFit.contain]);
    expect(images.map((i) => i.source).toSet(), {
      'https://example.invalid/item.png',
    });
    expect(
      find.ancestor(
        of: find.byWidget(images.first),
        matching: find.byKey(const ValueKey('market-art-backdrop')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an item without a photo shows its root category icon', (
    tester,
  ) async {
    // Before the tree is read, SCM's numbering leads to the root.
    expect(marketRootCategory(311), 3);
    expect(marketRootCategory(0), 0);
    marketRememberCategories([
      {'id': 6, 'parentId': 0},
      {'id': 64, 'parentId': 6},
      {'id': 1201, 'parentId': 64},
    ]);
    expect(marketRootCategory(1201), 6);
    expect(marketRootCategory(64), 6);
    expect(marketRootCategory(6), 6);

    // An order names the category on its first item.
    final order = {
      'thumbnailUrl': null,
      'items': [
        {'itemId': 9, 'categoryId': 1201, 'thumbnailUrl': ''},
      ],
    };
    expect(marketCategoryOf(order), 1201);
    await tester.pumpWidget(
      preview(
        SizedBox.square(dimension: 64, child: MarketArt.of(order)),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RemoteImage), findsNothing);
    expect(
      tester.widget<MarketSilhouette>(find.byType(MarketSilhouette)).category,
      1201,
    );
    expect(tester.takeException(), isNull);
  });
}

