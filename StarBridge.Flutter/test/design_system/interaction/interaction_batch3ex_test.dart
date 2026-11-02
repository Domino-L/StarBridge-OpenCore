import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_panel.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/room_chat_test.dart' show ChatPort, message;
import 'interaction_batch3et_test.dart' show activate;
import 'interaction_batch3i_test.dart' show scopedApp;

class ReadTracePort extends ChatPort {
  final requests = <(String, int, int, InteractionSource)>[];
  final sent = <(String, String)>[];
  @override
  Future<RoomChatPage> read(String roomId, {int after = 0, int before = 0}) {
    requests.add((roomId, after, before, currentStarBridgeActivationSource));
    return super.read(roomId, after: after, before: before);
  }

  @override
  Future<RoomChatMessage> send(String roomId, String text) {
    sent.add((roomId, text));
    return super.send(roomId, text);
  }
}

class ChatProbe {
  ChatProbe(this.module, this.suite);
  final RoomChatModule module;
  InteractionSuite suite;
  bool reduce = false, light = false;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        RoomChatPanel(module: module),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<(ReadTracePort, ChatProbe)> chat(
  WidgetTester t,
  InteractionSuite suite, {
  Duration interval = const Duration(hours: 1),
}) async {
  size(t, const Size(1100, 900));
  final port = ReadTracePort()
    ..reading = (_, _) async =>
        RoomChatPage([message(11), message(12)], 12, true);
  final module = RoomChatModule(port, interval: interval)..setRoom('one');
  addTearDown(module.dispose);
  await t.pump();
  final p = ChatProbe(module, suite);
  await t.pumpWidget(p.app());
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const Key('room-chat-draft')), '  保留草稿  ');
  await t.pump();
  return (port, p);
}

Finder action(String name) => find.byKey(Key('room-chat-$name'));
Finder send() => find.widgetWithText(StarBridgeActionButton, '发送');
StarBridgeActionButton button(WidgetTester t, Finder target) =>
    t.widget<StarBridgeActionButton>(
      find.ancestor(of: target, matching: find.byType(StarBridgeActionButton)),
    );
Future<void> clean(WidgetTester t, ChatProbe p) async {
  await t.pumpWidget(const SizedBox());
  p.module.setRoom(null);
  await t.pump();
}

Future<void> activateBackward(WidgetTester t, Finder target) async {
  final control = t.widget(target);
  final node = control is SuitePressable
      ? control.focusNode!
      : (control as ButtonStyleButton).focusNode!;
  expect(node.canRequestFocus, isTrue);
  for (var i = 0; !node.hasPrimaryFocus && i < 32; i++) {
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
  }
  expect(node.hasPrimaryFocus, isTrue);
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard']) {
      testWidgets(
        '$suite initially pending chat inherits $input opening wait policy',
        (t) async {
          size(t, const Size(1000, 900));
          final held = Completer<RoomChatPage>();
          final port = ReadTracePort()..reading = (_, _) => held.future;
          final module = RoomChatModule(
            port,
            interval: const Duration(hours: 1),
          )..setRoom('one');
          addTearDown(module.dispose);
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) => StarBridgeActionButton(
                  controlKey: const Key('open-pending-chat'),
                  onActivate: (source) => showStarBridgeDialog<void>(
                    context,
                    source: source,
                    builder: (_) => Dialog(
                      child: SizedBox(
                        width: 650,
                        height: 650,
                        child: RoomChatPanel(module: module),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
              suite,
            ),
          );
          await t.pump();
          await activate(t, find.byKey(const Key('open-pending-chat')), input);
          await t.pump(const Duration(milliseconds: 500));
          expect(module.loading, isTrue);
          expect(
            find.byType(SuiteProgressBar),
            input == 'pointer' ? findsOneWidget : findsNothing,
          );
          held.complete(const RoomChatPage([], 0, false));
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          await t.pumpWidget(const SizedBox());
          module.setRoom(null);
        },
      );
    }
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite chat $input refresh failure older and latest keep distinct cursors and draft',
        (t) async {
          final semantics = t.ensureSemantics();
          final (port, p) = await chat(t, suite);
          try {
            final before = p.module.messages;
            var held = Completer<RoomChatPage>();
            port.reading = (_, _) => held.future;
            await activate(t, action('refresh'), input);
            expect(p.module.loading, isTrue);
            expect(p.module.messages, same(before));
            expect(button(t, action('refresh')).onActivate, isNull);
            expect(button(t, action('older')).onActivate, isNull);
            expect(
              find.byType(SuiteProgressBar),
              input == 'pointer' ? findsOneWidget : findsNothing,
            );
            expect(port.requests.last.$2, 12);
            expect(port.requests.last.$3, 0);
            held.completeError(const RoomChatFailure('unavailable'));
            await t.pumpAndSettle();
            expect(p.module.error, 'unavailable');
            expect(p.module.draft, '  保留草稿  ');
            held = Completer();
            port.reading = (_, _) => held.future;
            await activate(t, action('older'), input);
            expect(p.module.followLatest, isFalse);
            expect(port.requests.last.$2, 0);
            expect(port.requests.last.$3, 11);
            held.complete(RoomChatPage([message(9), message(10)], 12, false));
            await t.pumpAndSettle();
            expect(p.module.messages.map((m) => m.sequence), [9, 10, 11, 12]);
            expect(p.module.draft, '  保留草稿  ');
            expect(action('older'), findsNothing);
            held = Completer();
            port.reading = (_, _) => held.future;
            await activate(t, action('latest'), input);
            expect(port.requests.last.$2, 0);
            expect(port.requests.last.$3, 0);
            held.complete(RoomChatPage([message(20), message(21)], 21, true));
            await t.pumpAndSettle();
            expect(p.module.messages.map((m) => m.sequence), [20, 21]);
            expect(p.module.followLatest, isTrue);
            expect(p.module.unread, 0);
            expect(p.module.draft, '  保留草稿  ');
            expect(port.requests, hasLength(4));
            expect(port.sends, 0);
            expect(t.takeException(), isNull);
          } finally {
            await clean(t, p);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite chat $input uncertain send requires explicit acknowledgement not replay',
        (t) async {
          final semantics = t.ensureSemantics();
          final (port, p) = await chat(t, suite);
          try {
            port.sending = () async =>
                throw const RoomChatFailure('outcomeUnknown');
            await activate(t, send(), input);
            await t.pumpAndSettle();
            expect(p.module.uncertain, isTrue);
            expect(p.module.draft, '  保留草稿  ');
            expect(port.sent, [('one', '保留草稿')]);
            final reads = port.requests.length;
            await activate(t, action('review-send'), input);
            await t.pumpAndSettle();
            expect(p.module.uncertain, isFalse);
            expect(p.module.error, isNull);
            expect(p.module.draft, '  保留草稿  ');
            expect(port.sends, 1);
            expect(port.requests, hasLength(reads));
            port.sending = () async => message(13);
            await activate(t, send(), input);
            await t.pumpAndSettle();
            expect(port.sends, 2);
            expect(p.module.draft, '');
            expect(p.module.messages.last.sequence, 13);
            expect(t.takeException(), isNull);
          } finally {
            await clean(t, p);
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite chat wait source resets for background reads and live reduce',
      (t) async {
        final (port, p) = await chat(
          t,
          suite,
          interval: const Duration(seconds: 5),
        );
        var held = Completer<RoomChatPage>();
        port.reading = (_, _) => held.future;
        await activate(t, action('refresh'), 'keyboard');
        expect(find.byType(SuiteProgressBar), findsNothing);
        expect(find.text('正在处理…'), findsOneWidget);
        held.complete(const RoomChatPage([], 12, true));
        await t.pumpAndSettle();
        held = Completer();
        port.reading = (_, _) => held.future;
        await t.pump(const Duration(seconds: 5));
        await t.pump();
        expect(port.requests, hasLength(3));
        expect(p.module.loading, isTrue);
        expect(find.byType(SuiteProgressBar), findsOneWidget);
        p.update(() {
          p.reduce = true;
          p.light = true;
        });
        await t.pump();
        await t.pump();
        expect(find.byType(SuiteProgressBar), findsNothing);
        expect(find.text('正在处理…'), findsOneWidget);
        held.complete(const RoomChatPage([], 12, true));
        await t.pumpAndSettle();
        expect(p.module.draft, '  保留草稿  ');
        await clean(t, p);
      },
    );
    testWidgets(
      '$suite chat pending send preserves older-only-loading gate and no duplicate request',
      (t) async {
        final (port, p) = await chat(t, suite);
        final held = Completer<RoomChatMessage>();
        port.sending = () => held.future;
        await activate(t, send(), 'keyboard');
        expect(p.module.sending, isTrue);
        expect(button(t, action('refresh')).onActivate, isNull);
        // Existing older action is gated by loading only, not sending.
        expect(button(t, action('older')).onActivate, isNotNull);
        final reads = port.requests.length;
        await t.pumpAndSettle();
        await activateBackward(t, action('older'));
        expect(p.module.followLatest, isFalse);
        expect(port.requests, hasLength(reads));
        expect(port.sends, 1);
        held.complete(message(13));
        await t.pumpAndSettle();
        expect(p.module.draft, '');
        await clean(t, p);
      },
    );
    testWidgets(
      '$suite chat room exit retires held read and old visible draft',
      (t) async {
        final (port, p) = await chat(t, suite);
        final held = Completer<RoomChatPage>();
        port.reading = (_, _) => held.future;
        await activate(t, action('refresh'), 'keyboard');
        p.module.setRoom(null);
        await t.pumpAndSettle();
        held.complete(RoomChatPage([message(90)], 90, false));
        await t.pumpAndSettle();
        expect(p.module.messages, isEmpty);
        expect(p.module.draft, '');
        expect(p.module.roomId, isNull);
        expect(port.sends, 0);
        expect(find.byType(SuiteProgressBar), findsNothing);
        await clean(t, p);
        expect(t.takeException(), isNull);
      },
    );
  }
}
