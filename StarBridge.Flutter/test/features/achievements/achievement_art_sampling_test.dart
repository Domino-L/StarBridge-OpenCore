import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_art.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';

void main() {
  testWidgets(
    'native-size comparison uses original client artwork at device density',
    (tester) async {
      const output = String.fromEnvironment('ACHIEVEMENT_SAMPLING_DIR');
      for (final definition in achievementCatalog) {
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: AchievementArt(
                    definition: definition,
                    earned: true,
                    size: 68,
                  ),
                ),
              ),
            ),
          ),
        );
        final context = tester.element(find.byType(AchievementArt));
        await tester.runAsync(
          () => precacheImage(AssetImage(definition.earnedAsset), context),
        );
        await tester.pumpAndSettle();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        for (final scale in [1.0, 1.25, 1.5, 2.0, 3.0]) {
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: scale);
            expect(image.width, (68 * scale).ceil());
            expect(image.height, (68 * scale).ceil());
            if (output.isNotEmpty) {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await Directory(output).create(recursive: true);
              await File(
                '$output/flutter-${definition.id}-${(scale * 96).round()}.png',
              ).writeAsBytes(bytes.buffer.asUint8List());
            }
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
      }
    },
    skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'),
  );
}
