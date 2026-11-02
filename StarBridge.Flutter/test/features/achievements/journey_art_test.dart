import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_art.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';

// 斯坦顿旅程五项的正式图（用户 10-29 定稿的交付包）：
// 192 列表图 / 512 详情图，已获得 / 未解锁各一套，按物理边长选图。
void main() {
  final journey = achievementCatalog
      .where((d) => d.id.startsWith('journey-'))
      .toList();

  test('五项都齐：两种状态 × 两档尺寸，文件名按成就 id', () {
    expect(journey.map((d) => d.id), [
      'journey-lorville',
      'journey-area18',
      'journey-orison',
      'journey-new-babbage',
      'journey-stanton',
    ]);
    for (final d in journey) {
      expect(d.earnedAsset, 'assets/achievements/${d.id}-earned-192.webp');
      expect(d.lockedAsset, 'assets/achievements/${d.id}-locked-192.webp');
      expect(
        d.earnedDetailAsset,
        'assets/achievements/${d.id}-earned-512.webp',
      );
      expect(
        d.lockedDetailAsset,
        'assets/achievements/${d.id}-locked-512.webp',
      );
    }
  });

  test('按物理边长选图：≤192 用列表图，否则用详情图', () {
    final d = journey.first;
    String pick(bool earned, double size, double dpr) =>
        d.artAsset(earned: earned, logicalSize: size, devicePixelRatio: dpr);
    expect(pick(true, 42, 1), d.earnedAsset);
    expect(pick(true, 64, 3), d.earnedAsset, reason: '64@3x = 192 仍是列表图');
    expect(pick(true, 96, 3), d.earnedDetailAsset, reason: '96@3x = 288');
    expect(pick(false, 240, 1), d.lockedDetailAsset);
    expect(pick(true, 240, 1), d.earnedDetailAsset);
    // 没有大图的成就永远用列表图。
    final legacy = achievementCatalog.firstWhere((d) => d.id == 'first-entry');
    expect(
      legacy.artAsset(earned: true, logicalSize: 240, devicePixelRatio: 2),
      legacy.earnedAsset,
    );
  });

  testWidgets('20 张图都能解码，尺寸正确；未解锁版每个像素 R=G=B', (tester) async {
    await tester.runAsync(() async {
      for (final d in journey) {
        for (final (asset, size) in [
          (d.earnedAsset, 192),
          (d.lockedAsset, 192),
          (d.earnedDetailAsset!, 512),
          (d.lockedDetailAsset!, 512),
        ]) {
          final bytes = await rootBundle.load(asset);
          final image = await decodeImageFromList(bytes.buffer.asUint8List());
          expect(image.width, size, reason: asset);
          expect(image.height, size, reason: asset);
          if (asset.contains('-locked-')) {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            var maxChroma = 0;
            for (var i = 0; i < data.lengthInBytes; i += 4) {
              final r = data.getUint8(i);
              final g = data.getUint8(i + 1);
              final b = data.getUint8(i + 2);
              final chroma =
                  [r, g, b].reduce((a, b) => a > b ? a : b) -
                  [r, g, b].reduce((a, b) => a < b ? a : b);
              if (chroma > maxChroma) maxChroma = chroma;
              expect(data.getUint8(i + 3), 255, reason: '$asset 不透明');
            }
            expect(maxChroma, 0, reason: '$asset 必须是严格中性灰');
          }
          image.dispose();
        }
      }
    });
  }, skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'));

  testWidgets('列表格 42 逻辑像素用 192 图，详情 240 用 512 图', (tester) async {
    final d = journey.first;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    String? shown() {
      final image = tester.widget<Image>(find.byType(Image));
      return (image.image as AssetImage).assetName;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AchievementArt(definition: d, earned: false, size: 42),
        ),
      ),
    );
    expect(shown(), d.lockedAsset);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AchievementArt(definition: d, earned: true, size: 240),
        ),
      ),
    );
    expect(shown(), d.earnedDetailAsset);
  });
}
