import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show key;
import 'interaction_batch3eq_test.dart' show validationApp;
import 'interaction_batch3et_test.dart'
    show activate, roomFormHome, password, primary;

void main() {
  testWidgets(
    'room password and toggles fit narrow scaled dark and light dialogs',
    (t) async {
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
            size(t, const Size(500, 1000));
            final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
            final frame = GlobalKey();
            await module.refresh();
            try {
              await t.pumpWidget(
                RepaintBoundary(
                  key: frame,
                  child: validationApp(
                    roomFormHome(module, 'create'),
                    suite,
                    light: light,
                    locale: locale,
                    scale: 1.5,
                  ),
                ),
              );
              await t.pumpAndSettle();
              await activate(t, key('room-form-open'), 'pointer');
              await t.pumpAndSettle();
              await activate(t, key('room-password-toggle'), 'pointer');
              await t.pumpAndSettle();
              await activate(t, primary(), 'pointer');
              await t.pumpAndSettle();
              await t.ensureVisible(password());
              await t.tap(password());
              await t.pumpAndSettle();
              expect(
                t.state<FormFieldState<String>>(password()).hasError,
                isTrue,
              );
              expect(t.takeException(), isNull);
              final field = t.getRect(password());
              expect(field.left, greaterThanOrEqualTo(0));
              expect(field.right, lessThanOrEqualTo(500));
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
                    '$output/${suite.name}-${light ? 'light' : 'dark'}-password.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            } finally {
              module.stopSession();
              await t.pumpWidget(const SizedBox());
              module.dispose();
            }
          }
        }
      }
    },
  );
}
