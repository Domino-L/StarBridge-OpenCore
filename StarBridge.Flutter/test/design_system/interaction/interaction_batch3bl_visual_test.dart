import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/data_location_dialog.dart';
import 'package:starbridge_flutter/features/settings/data_location_port.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bl_test.dart' show LocationPort, action;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final width in [360.0, 1100.0]) {
      testWidgets('$suite width=$width data location ready and confirm render', (
        t,
      ) async {
        await loadFonts();
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final p = LocationPort(), capture = GlobalKey();
        p.location = DataLocation(
          path:
              'C:/synthetic/${List.filled(7, 'long-folder').join('-')}/StarBridge/data',
          exists: true,
        );
        p.choice = DataLocationMigrationChoice(
          ticket: 'synthetic-ticket',
          source: p.location.path,
          destination: 'D:/synthetic/StarBridge/data',
        );
        try {
          await t.pumpWidget(
            RepaintBoundary(
              key: capture,
              child: scopedApp(
                DataLocationDialog(port: p, exitAvailable: true),
                suite,
              ),
            ),
          );
          await t.pumpAndSettle();
          for (final phase in ['ready', 'confirm']) {
            if (phase == 'confirm') {
              await action(t, 'pointer', 'data-location-move');
              await t.pumpAndSettle();
            }
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
                'build/reviews/interaction-batch3bl/${suite.name}-${width.toInt()}-$phase.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
            } finally {
              image.dispose();
            }
          }
        } finally {
          await t.pumpWidget(const SizedBox());
          await t.pump();
        }
      });
    }
  }
}
