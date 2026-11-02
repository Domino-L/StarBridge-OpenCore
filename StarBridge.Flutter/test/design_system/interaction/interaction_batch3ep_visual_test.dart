import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show IdeasProbe, activate, key;
import 'interaction_batch3i_test.dart' show scopedApp;

class _ArtPort implements AchievementCollectionPort {
  @override
  Future<AchievementCollection> read({required int generation}) async =>
      AchievementCollection(
        generation: generation,
        status: AchievementCollectionStatus.ready,
        earnedAt: {'first-entry': DateTime.utc(2026, 10, 1)},
      );
}

void main() {
  testWidgets('capture achievement card and native-shaped suite dialogs', (
    t,
  ) async {
    const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
    if (output.isEmpty) return;
    await loadFonts();
    Future<void> capture(GlobalKey frame, String name) async {
      await t.runAsync(() async {
        final boundary =
            frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output).create(recursive: true);
        await File('$output/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final suite in [
      InteractionSuite.rail,
      InteractionSuite.scan,
      InteractionSuite.glow,
    ]) {
      size(t, const Size(1100, 900));
      final account = ValueNotifier(achievementTestAccount(9));
      final frame = GlobalKey();
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await t.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: scopedApp(
              AchievementsPage(
                account: account,
                port: _ArtPort(),
                ideas: IdeasProbe(),
              ),
              suite,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await precacheImage(
            AssetImage(achievementCatalog.first.earnedAsset),
            t.element(find.byType(AchievementsPage)),
          );
        });
        await t.pumpAndSettle();
        final card = key('achievement-entry-first-entry');
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(card));
        await t.pump();
        await t.pump(const Duration(milliseconds: 180));
        await capture(frame, '${suite.name}-card-hover');
        await activate(t, card, 'pointer');
        await t.pump(const Duration(milliseconds: 90));
        await capture(frame, '${suite.name}-detail-entrance');
        await t.pumpAndSettle();
        await activate(t, key('achievement-detail-close'), 'pointer');
        await t.pumpAndSettle();
        await activate(t, key('achievement-contribute'), 'pointer');
        await t.pumpAndSettle();
        await t.enterText(
          key('achievement-idea-name'),
          'A voyage worth remembering',
        );
        await activate(t, key('achievement-idea-close'), 'pointer');
        await t.pumpAndSettle();
        await capture(frame, '${suite.name}-discard');
        expect(t.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await t.pumpWidget(const SizedBox());
        account.dispose();
      }
    }
  });
}
