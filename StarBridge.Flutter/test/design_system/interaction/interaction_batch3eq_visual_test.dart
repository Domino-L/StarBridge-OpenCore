import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show IdeasProbe, activate, key;
import 'interaction_batch3eq_test.dart' show validationApp;

void main() {
  testWidgets(
    'capture actual achievement validation at 1.5x text in dark and light',
    (t) async {
      const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
      if (output.isEmpty) return;
      await loadFonts();
      for (final suite in [
        InteractionSuite.rail,
        InteractionSuite.scan,
        InteractionSuite.glow,
      ]) {
        for (final light in [false, true]) {
          size(t, const Size(500, 1000));
          final account = ValueNotifier(achievementTestAccount(9));
          final ideas = IdeasProbe(), frame = GlobalKey();
          try {
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: validationApp(
                  AchievementsPage(account: account, ideas: ideas),
                  suite,
                  light: light,
                  scale: 1.5,
                ),
              ),
            );
            await t.pumpAndSettle();
            await activate(t, key('achievement-contribute'), 'pointer');
            await t.pumpAndSettle();
            await activate(t, key('achievement-idea-submit'), 'pointer');
            await t.pumpAndSettle();
            await t.ensureVisible(key('achievement-idea-name'));
            await t.tap(key('achievement-idea-name'));
            await t.pumpAndSettle();
            expect(
              t
                  .state<FormFieldState<String>>(key('achievement-idea-name'))
                  .hasError,
              isTrue,
            );
            expect(
              t
                  .state<FormFieldState<String>>(
                    key('achievement-idea-condition'),
                  )
                  .hasError,
              isTrue,
            );
            expect(ideas.receipts, isEmpty);
            await t.runAsync(() async {
              final image =
                  await (frame.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              await File(
                '$output/${suite.name}-${light ? 'light' : 'dark'}-validation.png',
              ).writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            account.dispose();
          }
        }
      }
    },
  );
}
