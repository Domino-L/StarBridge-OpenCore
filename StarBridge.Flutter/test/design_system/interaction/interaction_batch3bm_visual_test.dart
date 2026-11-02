import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/settings/community_member_visibility_dialog.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';

import '../../features/settings/community_sharing_test.dart' show target;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bm_test.dart' show legacyPort, action, close;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final width in [430.0, 1100.0]) {
      testWidgets('$suite width=$width member editor and conversion review', (
        t,
      ) async {
        await loadFonts();
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final p = legacyPort(),
            c = LocalPrivacyController(p),
            capture = GlobalKey();
        try {
          await c.refresh();
          await t.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: scopedApp(
                CommunityMemberVisibilityDialog(
                  controller: c,
                  target: target('A'),
                  scope: c.draft!.communities!.single,
                ),
                suite,
              ),
            ),
          );
          await t.pumpAndSettle();
          for (final phase in ['editor', 'conversion']) {
            if (phase == 'conversion') {
              await action(t, 'pointer', 'privacy-member-convert');
              await t.pumpAndSettle();
            }
            // A completed async roster read can precede its painted frame.
            // Verify the actual ready state, then flush a fresh capture frame.
            expect(
              find.byKey(const Key('privacy-member-member-0-reset')),
              findsOneWidget,
            );
            final convert = t.widget<StarBridgeActionButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is StarBridgeActionButton &&
                    w.controlKey == const Key('privacy-member-convert'),
              ),
            );
            expect(convert.onActivate, isNotNull);
            t.binding.scheduleFrame();
            await t.pump(const Duration(milliseconds: 16));
            expect(t.takeException(), isNull);
            final image = (await t.runAsync(
              () =>
                  (capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(),
            ))!;
            try {
              final bytes = (await t.runAsync(
                () => image.toByteData(format: ui.ImageByteFormat.png),
              ))!;
              final file = File(
                'build/reviews/interaction-batch3bm/${suite.name}-${width.toInt()}-$phase.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
            }
          }
        } finally {
          await close(t, c, p);
        }
      });
    }
  }
}
