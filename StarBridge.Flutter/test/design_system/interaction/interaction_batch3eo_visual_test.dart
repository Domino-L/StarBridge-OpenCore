import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievement_catalog.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart'
    show CatalogProbe, IdeasProbe, activate, key;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  testWidgets(
    'capture achievement directory and idea controls in approved suites',
    (t) async {
      const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
      if (output.isEmpty) return;
      await loadFonts();
      Future<void> capture(GlobalKey frame, String name) async {
        await t.runAsync(() async {
          final boundary =
              frame.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
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
        size(t, const Size(1100, 950));
        final account = ValueNotifier(achievementTestAccount(9));
        final frame = GlobalKey();
        final first = achievementCatalog.first;
        final catalog = List.generate(
          30,
          (i) => AchievementDefinition(
            id: 'future-$i',
            nameKey: 'Future $i',
            conditionKey: 'Requirement $i',
            memoryKey: first.memoryKey,
            earnedAsset: first.earnedAsset,
            lockedAsset: first.lockedAsset,
            groupId: 'g${i % 4}',
            groupNameKey: 'Group ${i % 4}',
            target: 100,
          ),
        );
        await t.pumpWidget(
          RepaintBoundary(
            key: frame,
            child: scopedApp(
              AchievementsPage(
                account: account,
                port: CatalogProbe(),
                ideas: IdeasProbe(),
                catalog: catalog,
              ),
              suite,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await precacheImage(
            AssetImage(first.earnedAsset),
            t.element(find.byType(AchievementsPage)),
          );
        });
        await t.pumpAndSettle();
        await activate(t, key('achievement-group-earned'), 'pointer');
        await t.pumpAndSettle();
        await capture(frame, '${suite.name}-directory');
        size(t, const Size(380, 950));
        await t.pumpAndSettle();
        await activate(t, key('achievement-contribute'), 'pointer');
        await t.pumpAndSettle();
        await capture(frame, '${suite.name}-idea-narrow');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        account.dispose();
      }
    },
  );
}
