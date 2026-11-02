import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/room_filter_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_catalog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eq_test.dart' show validationApp;
import 'interaction_batch3et_test.dart' show activate;
import 'interaction_batch3ev_test.dart' show header, choice;

void main() {
  testWidgets('persistent room filters fit 290px with scaled labels', (
    t,
  ) async {
    const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
    await loadFonts();
    for (final suite in [
      InteractionSuite.rail,
      InteractionSuite.scan,
      InteractionSuite.glow,
    ]) {
      for (final light in [false, true]) {
        for (final locale in [
          const Locale('zh', 'CN'),
          const Locale('zh', 'TW'),
          const Locale('en'),
        ]) {
          size(t, const Size(400, 1000));
          final frame = GlobalKey();
          Set<String> selected = {'pve_bounty', 'need_pilot'};
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: validationApp(
                StatefulBuilder(
                  builder: (context, update) => Center(
                    child: SizedBox(
                      width: 290,
                      height: 900,
                      child: RoomFilterPanel(
                        options: RoomTagCatalog.exampleOptions,
                        selected: selected,
                        onChanged: (value) => update(() => selected = value),
                      ),
                    ),
                  ),
                ),
                suite,
                light: light,
                locale: locale,
                scale: 1.5,
              ),
            ),
          );
          await t.pumpAndSettle();
          await activate(t, header('combat'), 'keyboard');
          await t.pumpAndSettle();
          await activate(t, header('pve'), 'keyboard');
          await t.pumpAndSettle();
          final tile = t.getRect(choice('pve_bounty'));
          final panel = t.getRect(find.byType(RoomFilterPanel));
          expect(tile.left, greaterThanOrEqualTo(panel.left));
          expect(tile.right, lessThanOrEqualTo(panel.right));
          if (output.isNotEmpty && locale.countryCode == 'CN') {
            await t.runAsync(() async {
              final image =
                  await (frame.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              await File(
                '$output/${suite.name}-${light ? 'light' : 'dark'}-filters.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        }
      }
    }
  });
}
