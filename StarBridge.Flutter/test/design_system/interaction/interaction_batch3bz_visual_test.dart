import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bz_test.dart'
    show FullFixture, FullHarness, FullHarnessState;
import 'interaction_batch3bt_test.dart' show hit;
import 'interaction_batch3bw_test.dart' show frames;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1400.0, 1.0), (430.0, 2.0)]) {
      testWidgets(
        '$suite width=${config.$1} text=${config.$2} fullscreen review',
        (t) async {
          await loadFonts();
          final oldShadows = debugDisableShadows;
          debugDisableShadows = false;
          t.view.physicalSize = Size(config.$1, 1100);
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.textScaleFactorTestValue = config.$2;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final h = FullFixture(), capture = GlobalKey();
          try {
            await h.module.initialize();
            await t.pumpWidget(
              RepaintBoundary(key: capture, child: FullHarness(h, suite)),
            );
            final state = t.state<FullHarnessState>(find.byType(FullHarness));
            state.change(() => state.light = config.$1 > 1000);
            await frames(t);
            await hit(t, 'pointer', 'overlay-enter-fullscreen');
            await frames(t);
            for (final phase in ['ready', 'saving', 'rejected']) {
              if (phase == 'saving') {
                // The edit starts saving on its own.
                h.port.pending = Completer<void>();
                h.port.reject = true;
                h.module.updateSetting('showMembers', true);
                await frames(t);
              }
              if (phase == 'rejected') {
                h.port.pending!.complete();
                await frames(t);
              }
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
                  'build/reviews/interaction-batch3bz/${suite.name}-${config.$1.toInt()}-${config.$2}-$phase.png',
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
            debugDisableShadows = oldShadows;
            await h.clean(t);
          }
        },
      );
    }
  }
}
