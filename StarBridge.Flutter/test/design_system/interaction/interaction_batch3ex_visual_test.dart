import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_panel.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/room_chat_test.dart' show message;
import 'interaction_batch3eq_test.dart' show validationApp;
import 'interaction_batch3et_test.dart' show activate;
import 'interaction_batch3ex_test.dart' show ReadTracePort, action;

void main() {
  testWidgets('chat read wait and uncertain action fit scaled narrow panel', (
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
          size(t, const Size(650, 900));
          final port = ReadTracePort()
            ..reading = (_, _) async => RoomChatPage([message(11)], 11, true);
          final module = RoomChatModule(
            port,
            interval: const Duration(hours: 1),
          )..setRoom('one');
          final frame = GlobalKey();
          await t.pump();
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: validationApp(
                RoomChatPanel(module: module),
                suite,
                light: light,
                locale: locale,
                scale: 1.5,
              ),
            ),
          );
          await t.pumpAndSettle();
          final held = Completer<RoomChatPage>();
          port.reading = (_, _) => held.future;
          await activate(t, action('refresh'), 'pointer');
          await t.pump(const Duration(milliseconds: 120));
          final wait = t.getRect(find.byType(SuiteProgressBar));
          expect(wait.left, greaterThanOrEqualTo(0));
          expect(wait.right, lessThanOrEqualTo(650));
          held.complete(const RoomChatPage([], 11, true));
          await t.pumpAndSettle();
          await t.enterText(find.byKey(const Key('room-chat-draft')), '保留草稿');
          port.sending = () async =>
              throw const RoomChatFailure('outcomeUnknown');
          // Localized send label varies, so use the sole primary action.
          final primary = find.byWidgetPredicate(
            (w) =>
                w is StarBridgeActionButton &&
                w.kind == StarBridgeActionKind.primary,
          );
          await activate(t, primary, 'keyboard');
          await t.pumpAndSettle();
          expect(module.uncertain, isTrue);
          final review = t.getRect(action('review-send'));
          expect(review.right, lessThanOrEqualTo(650));
          expect(review.bottom, lessThanOrEqualTo(900));
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
                '$output/${suite.name}-${light ? 'light' : 'dark'}-chat.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          module.setRoom(null);
          module.dispose();
        }
      }
    }
  });
}
