import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/game_log/game_log_panel.dart';

import '../../features/game_log/game_log_test.dart' show Harness;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final width in [360.0, 1100.0]) {
      testWidgets('$suite width=$width log panel review render', (t) async {
        await loadFonts();
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final h = Harness(), capture = GlobalKey();
        try {
          await t.pump();
          final findLog = h.controller.run(command: 'find');
          await t.pump();
          await findLog;
          await t.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: scopedApp(
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 720,
                    child: SingleChildScrollView(
                      child: GameLogPanel(controller: h.controller),
                    ),
                  ),
                ),
                suite,
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final image = (await t.runAsync(
            () =>
                (capture.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(),
          ))!;
          try {
            final data = (await t.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png),
            ))!;
            final file = File(
              'build/reviews/interaction-batch3bj/${suite.name}-${width.toInt()}.png',
            );
            file.parent.createSync(recursive: true);
            file.writeAsBytesSync(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            );
          } finally {
            image.dispose();
          }
        } finally {
          await t.pumpWidget(const SizedBox());
          await t.pump();
          await h.close(t);
        }
      });
    }
  }
}
