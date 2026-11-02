import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'boundary_test.dart' show palette;

void main() {
  for (final suite in [InteractionSuite.rail, InteractionSuite.scan]) {
    for (final inset in [false, true]) {
      testWidgets('toast $suite follows the physical surface inset=$inset', (
        t,
      ) async {
        final rect = inset
            ? const Rect.fromLTWH(20, 10, 60, 40)
            : const Rect.fromLTWH(0, 0, 100, 80);
        await t.pumpWidget(
          InteractionScope(
            data: InteractionData(suite: suite, palette: palette),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SuiteSurfaceTransition(
                  animation: const AlwaysStoppedAnimation(1),
                  kind: SurfaceKind.toast,
                  surfaceBounds: inset ? rect : null,
                  tone: Colors.red,
                  child: const SizedBox(width: 100, height: 80),
                ),
              ),
            ),
          ),
        );
        final painter = t
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.foregroundPainter != null,
              ),
            )
            .foregroundPainter!;
        await t.runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), const Size(100, 80));
          final picture = recorder.endRecording();
          final image = await picture.toImage(100, 80);
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final index = suite == InteractionSuite.rail
              ? (rect.center.dy.toInt() * 100 + rect.left.toInt() + 1) * 4
              : ((rect.top.toInt() + 2) * 100 + rect.left.toInt() + 2) * 4;
          expect(bytes!.getUint8(index), 244);
          expect(bytes.getUint8(index + 1), 67);
          expect(bytes.getUint8(index + 2), 54);
          expect(bytes.getUint8(index + 3), 255);
          if (inset) expect(bytes.getUint8((30 * 100) * 4 + 3), 0);
          image.dispose();
          picture.dispose();
        });
      });
    }
  }
}
