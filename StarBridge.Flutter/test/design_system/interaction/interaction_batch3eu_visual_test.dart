import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_catalog.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_picker.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show key;
import 'interaction_batch3eq_test.dart' show validationApp;
import 'interaction_batch3et_test.dart' show activate;

void main() {
  testWidgets(
    'long room paths retain colour and fit narrow scaled tag picker',
    (t) async {
      const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
      await loadFonts();
      final longest = RoomTagCatalog.exampleOptions
          .where((tag) => tag.isGameplay)
          .reduce(
            (a, b) =>
                RoomTagCatalog.fullText(a).length >=
                    RoomTagCatalog.fullText(b).length
                ? a
                : b,
          );
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
            size(t, const Size(500, 1000));
            final frame = GlobalKey();
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: validationApp(
                  Builder(
                    builder: (context) => StarBridgeActionButton(
                      controlKey: const Key('open-long-tags'),
                      onActivate: (source) => showRoomTagPicker(
                        context,
                        options: RoomTagCatalog.exampleOptions,
                        selected: {longest.id, 'industry', 'need_pilot'},
                        source: source,
                      ),
                      child: const Text('Open'),
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
            await activate(t, key('open-long-tags'), 'pointer');
            await t.pumpAndSettle();
            final chip = find.byKey(ValueKey('selected-tag-${longest.id}'));
            final bounds = t.getRect(chip);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(500));
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
                  '$output/${suite.name}-${light ? 'light' : 'dark'}-tags.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          }
        }
      }
    },
  );
}
