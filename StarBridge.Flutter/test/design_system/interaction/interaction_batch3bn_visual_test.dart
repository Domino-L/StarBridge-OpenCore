import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';

import '../../features/settings/community_sharing_test.dart'
    show SharingFixture;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bn_test.dart' show section, activate, cleanup, action;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final width in [430.0, 1100.0]) {
      testWidgets('$suite width=$width legacy organization confirmation review', (
        t,
      ) async {
        await loadFonts();
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final p = SharingFixture(),
            c = LocalPrivacyController(p),
            capture = GlobalKey();
        try {
          await c.refresh();
          await t.pumpWidget(
            RepaintBoundary(key: capture, child: section(c, suite)),
          );
          await t.pumpAndSettle();
          expect(
            action(t, 'privacy-organizations-migrate').onActivate,
            isNotNull,
          );
          for (final phase in ['entry', 'confirm']) {
            if (phase == 'confirm') {
              await activate(t, 'pointer', 'privacy-organizations-migrate');
            }
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
                'build/reviews/interaction-batch3bn/${suite.name}-${width.toInt()}-$phase.png',
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
          await cleanup(t, c, p);
        }
      });
    }
  }
}
