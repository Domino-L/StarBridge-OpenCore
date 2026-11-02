import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/room_directory_card.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/party_rooms_test.dart'
    show room, ready, wire;
import 'interaction_batch3eq_test.dart' show validationApp;

void main() {
  testWidgets(
    'directory cards preserve geometry and scaled content during suite press',
    (t) async {
      const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
      final shadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await loadFonts();
        await (FontLoader('Source Code Pro')..addFont(
              rootBundle.load('assets/fonts/SourceCodeVF-Upright.ttf'),
            ))
            .load();
        final data = ready(wire(rooms: [room('a'), room('b')])).directory!;
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
              for (final width in [850.0, 540.0]) {
                size(t, const Size(950, 1000));
                final frame = GlobalKey();
                await t.pumpWidget(
                  RepaintBoundary(
                    key: frame,
                    child: validationApp(
                      SizedBox(
                        width: width,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < 2; i++) ...[
                              RoomDirectoryCard(
                                room: data.rooms[i],
                                serverTime: data.serverTime,
                                selected: i == 0,
                                onSelect: i == 0 ? () {} : null,
                                onJoin: (_) {},
                                supportsCommands: true,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
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
                final target = find.byKey(const ValueKey('room-a'));
                final before = t.getRect(target);
                final gesture = await t.startGesture(
                  t.getCenter(find.text('测试房间 a')),
                );
                await t.pump(const Duration(milliseconds: 110));
                expect(t.getRect(target), before);
                expect(t.getSize(target).width, width);
                if (output.isNotEmpty &&
                    locale.countryCode == 'CN' &&
                    width == 850) {
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
                      '$output/${suite.name}-${light ? 'light' : 'dark'}-card.png',
                    ).writeAsBytes(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
                await gesture.up();
                await t.pumpAndSettle();
                expect(t.takeException(), isNull);
                await t.pumpWidget(const SizedBox());
              }
            }
          }
        }
      } finally {
        debugDisableShadows = shadows;
      }
    },
  );
}
