import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eq_test.dart' show validationApp;
import 'interaction_batch3ew_test.dart' show openScene, refresh, sceneTrigger;

void main() {
  testWidgets('room header and original example selector fit scaled full page', (
    t,
  ) async {
    const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
    // Flutter's test-only shadow mode draws an elevation*2 solid outline.
    // Keep actual Material shadows in these review images, not that debug cue.
    final shadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await loadFonts();
      await (FontLoader('Source Code Pro')
            ..addFont(rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf')))
          .load();
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
            size(t, const Size(1280, 1000));
            final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
            final frame = GlobalKey();
            await module.refresh();
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: validationApp(
                  PartyRoomsPage(module: module),
                  suite,
                  light: light,
                  locale: locale,
                  scale: 1.5,
                ),
              ),
            );
            await t.pumpAndSettle();
            final button = t.getRect(refresh());
            final selector = t.getRect(sceneTrigger());
            expect(button.right, lessThanOrEqualTo(1280));
            expect(selector.width, lessThanOrEqualTo(230));
            expect(button.height, lessThan(90));
            await openScene(t, 'pointer');
            await t.pumpAndSettle();
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
                  '$output/${suite.name}-${light ? 'light' : 'dark'}-header.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            expect(t.takeException(), isNull);
            module.stopSession();
            await t.pumpWidget(const SizedBox());
            module.dispose();
          }
        }
      }
    } finally {
      debugDisableShadows = shadows;
    }
  });
}
