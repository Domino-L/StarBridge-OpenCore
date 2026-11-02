import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/composition/room_invitation_navigation.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_invitation_card.dart';
import 'package:starbridge_flutter/features/party_rooms/room_invitations.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/party_rooms_test.dart' show ready, wire;
import '../../features/party_rooms/room_management_test.dart'
    show InvitationPort;
import '../../features/party_rooms/room_member_removal_test.dart'
    show removalRoom;
import 'interaction_batch3b_test.dart' show semanticTap;
import 'interaction_batch3i_test.dart'
    show mount, keyPress, route, dialogAction, scopedApp;

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3L'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3l');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Map<String, Object?> invitation({bool expired = false}) => {
  'invitationId': 'synthetic-invite',
  'roomId': 'a',
  'roomTitle': '邀请测试房间',
  'inviterCallsign': '合成房主',
  'inviterGameId': '',
  'recipientCallsign': '合成成员',
  'recipientGameId': '',
  'expiresAt': DateTime.now()
      .add(Duration(days: expired ? -1 : 1))
      .toIso8601String(),
};

Map<String, Object?> directory({
  bool host = false,
  bool expired = false,
  bool joined = false,
}) =>
    wire(
        current: host || joined ? 'a' : null,
        rooms: [removalRoom(host: host)],
      )
      ..['receivedInvitations'] = [invitation(expired: expired)]
      ..['sentInvitations'] = host ? [invitation()] : [];

class MotionInvitationPort extends InvitationPort {
  final commands = <RoomCommand>[];
  final requests = <Completer<RoomCommandResult>>[];
  Completer<RoomCommandResult>? targets;
  @override
  Future<RoomCommandResult> execute(RoomCommand command) {
    calls++;
    commands.add(command);
    if (command.operation == RoomOperation.inviteTargets) {
      return targets?.future ??
          Future.value(
            const RoomCommandResult(
              'targets',
              targets: [
                RoomInviteTarget('friend-ref', '可邀请的好友'),
                RoomInviteTarget(
                  'already-ref',
                  '已经邀请的好友',
                  alreadyInvited: true,
                ),
              ],
            ),
          );
    }
    final request = Completer<RoomCommandResult>();
    requests.add(request);
    return request.future;
  }
}

Finder action(String label) =>
    find.widgetWithText(StarBridgeActionButton, label);
Finder cardAction(String label) => find.descendant(
  of: find.byType(RoomInvitationCard),
  matching: action(label),
);

Future<void> activate(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  if (source == 'keyboard') {
    await keyPress(t, target);
  } else if (source == 'reader') {
    final text = t
        .widget<Text>(
          find.descendant(of: target, matching: find.byType(Text)).first,
        )
        .data!;
    await semanticTap(
      t,
      find.bySemanticsLabel(RegExp('^${RegExp.escape(text)}\$')).last,
    );
    await t.pump();
    await t.pump();
  } else {
    await t.tap(target);
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
  }
}

Future<void> clean(WidgetTester t, PartyRoomsModule module) async {
  await t.pumpWidget(const SizedBox());
  module.stopSession();
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final current in [true, false]) {
      testWidgets(
        '$suite notification preserves original keyboard source across refresh current=$current',
        (t) async {
          size(t, const Size(1200, 900));
          final read = Completer<RoomReadResult>();
          final port = MotionInvitationPort()..pending = read;
          final composition = AppComposition.forTest(
            windowChrome: InMemoryWindowChrome(),
            partyRoomsPort: port,
          );
          final origin = ValueNotifier(InteractionSource.keyboard);
          addTearDown(origin.dispose);
          addTearDown(composition.dispose);
          var stillCurrent = true;
          Future<bool>? opening;
          await t.pumpWidget(
            scopedApp(
              StarBridgeActivationOrigin(
                source: origin,
                child: Builder(
                  builder: (context) => Center(
                    child: StarBridgeActionButton(
                      onActivate: (_) {
                        opening = openRoomInvitationDestination(
                          context,
                          composition,
                          '/rooms/invitations?invitation=synthetic-invite',
                          isCurrent: () => stillCurrent,
                        );
                      },
                      child: const Text('通知打开'),
                    ),
                  ),
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await keyPress(t, action('通知打开'));
          expect(find.byType(AlertDialog), findsNothing);
          expect(port.reads, 1);
          origin.value = InteractionSource.pointer;
          stillCurrent = current;
          read.complete(ready(directory()));
          await t.pump();
          await t.pump();
          if (current) {
            expect(route(t).animation!.value, 1);
            expect(find.byType(RoomInvitationCard), findsOneWidget);
            expect(composition.partyRooms.directory!.currentRoomId, isNull);
            await keyPress(t, action('完成'));
          } else {
            expect(find.byType(AlertDialog), findsNothing);
          }
          expect(await opening, true);
          expect(port.commands, isEmpty);
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
      );
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite invitations $source source survives nested cancel and does not accept',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = MotionInvitationPort()..result = ready(directory());
          final module = PartyRoomsModule(port);
          final frame = GlobalKey();
          final harness = await mount(t, module, suite, frame: frame);
          await activate(t, action('房间邀请 · 1'), source);
          final outer = route(t);
          if (source != 'pointer') expect(outer.animation!.value, 1);
          await t.pumpAndSettle();
          if (source == 'pointer') {
            await capture(t, frame, '${suite.name}-invitations');
          }
          expect(find.byType(RoomInvitationCard), findsOneWidget);
          expect(port.commands, isEmpty);
          await activate(t, cardAction('加入房间'), source);
          final inner = route(t);
          expect(inner, isNot(same(outer)));
          if (source != 'pointer') expect(inner.animation!.value, 1);
          expect(port.commands, isEmpty);
          harness.change(() => harness.reduce = true);
          await t.pump();
          await t.pump();
          expect(inner.animation!.value, 1);
          if (source == 'pointer') {
            await capture(t, frame, '${suite.name}-confirm');
          }
          await keyPress(t, dialogAction('取消'));
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(port.commands, isEmpty);
          await keyPress(t, action('完成'));
          expect(find.byType(AlertDialog), findsNothing);
          await clean(t, module);
          semantics.dispose();
        },
      );
    }

    testWidgets(
      '$suite invitation reject retry waits for owner and keyboard success closes instantly',
      (t) async {
        final port = MotionInvitationPort()..result = ready(directory());
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        await keyPress(t, action('房间邀请 · 1'));
        final outer = route(t);
        for (final accepted in [false, true]) {
          await keyPress(t, cardAction('加入房间'));
          await keyPress(t, dialogAction('加入房间'));
          expect(module.busy, true);
          expect(
            t.widget<StarBridgeActionButton>(action('完成')).onActivate,
            isNull,
          );
          expect(
            t.widget<StarBridgeActionButton>(cardAction('加入房间')).onActivate,
            isNull,
          );
          expect(module.directory!.currentRoomId, isNull);
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(port.requests.length, accepted ? 2 : 1);
          expect(port.commands.last.operation, RoomOperation.inviteJoin);
          expect(port.commands.last.data, {
            'roomId': 'a',
            'invitationId': 'synthetic-invite',
          });
          port.requests.last.complete(
            accepted
                ? RoomCommandResult(
                    'joined',
                    directory: ready(directory(joined: true)).directory,
                  )
                : const RoomCommandResult('rejected', error: 'unavailable'),
          );
          await t.pump();
          await t.pump();
          if (!accepted) {
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(module.directory!.currentRoomId, isNull);
            expect(
              t.widget<StarBridgeActionButton>(cardAction('加入房间')).onActivate,
              isNotNull,
            );
          } else {
            expect(outer.animation?.value ?? 0, 0);
            expect(find.byType(AlertDialog), findsNothing);
            expect(module.directory!.currentRoomId, 'a');
          }
        }
        await clean(t, module);
      },
    );

    testWidgets(
      '$suite invite list read failure retry and host writes preserve loading and permissions',
      (t) async {
        final targetRead = Completer<RoomCommandResult>();
        final port = MotionInvitationPort()
          ..result = ready(directory(host: true))
          ..targets = targetRead;
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        await keyPress(t, action('邀请好友'));
        expect(
          t.widget<StarBridgeActionButton>(action('完成')).onActivate,
          isNull,
        );
        expect(port.commands.single.operation, RoomOperation.inviteTargets);
        targetRead.complete(
          const RoomCommandResult('rejected', error: 'unavailable'),
        );
        await t.pumpAndSettle();
        expect(
          module.canCommand,
          true,
          reason: 'Enumeration failure is not a failed write',
        );
        port.targets = null;
        await keyPress(t, action('刷新名单'));
        expect(find.text('可邀请的好友'), findsOneWidget);
        expect(
          t.widget<StarBridgeActionButton>(action('已邀请')).onActivate,
          isNull,
        );
        await keyPress(t, action('邀请'));
        expect(port.commands.last.data, {
          'roomId': 'a',
          'targetRef': 'friend-ref',
        });
        expect(module.busy, true);
        expect(
          t.widget<StarBridgeActionButton>(action('邀请')).onActivate,
          isNull,
        );
        port.requests.last.complete(
          RoomCommandResult(
            'invited',
            directory: ready(directory(host: true)).directory,
          ),
        );
        await t.pumpAndSettle();
        expect(port.commands.last.operation, RoomOperation.inviteTargets);
        await keyPress(t, cardAction('撤回'));
        expect(port.commands.last.operation, RoomOperation.inviteRevoke);
        port.requests.last.complete(
          const RoomCommandResult('rejected', error: 'unavailable'),
        );
        await t.pumpAndSettle();
        expect(module.directory!.sentInvitations, hasLength(1));
        final count = port.calls;
        port.result = ready(directory(joined: true));
        await module.refresh();
        await t.pumpAndSettle();
        expect(find.text('可邀请的好友'), findsNothing);
        expect(
          t.widget<StarBridgeActionButton>(action('刷新名单')).onActivate,
          isNull,
        );
        expect(port.calls, count);
        await keyPress(t, action('完成'));
        await clean(t, module);
      },
    );

    for (final state in ['expired', 'joined']) {
      testWidgets(
        '$suite $state invitation cannot accept or expose activation',
        (t) async {
          final port = MotionInvitationPort()
            ..result = ready(
              directory(expired: state == 'expired', joined: state == 'joined'),
            );
          final module = PartyRoomsModule(port);
          await mount(t, module, suite);
          await keyPress(t, action('房间邀请 · 1'));
          expect(
            t.widget<StarBridgeActionButton>(cardAction('加入房间')).onActivate,
            isNull,
          );
          expect(port.commands, isEmpty);
          await keyPress(t, action('完成'));
          await clean(t, module);
        },
      );
    }

    testWidgets(
      '$suite stale confirmation and unmounted target read cannot act later',
      (t) async {
        final port = MotionInvitationPort()..result = ready(directory());
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        await keyPress(t, action('房间邀请 · 1'));
        await keyPress(t, cardAction('加入房间'));
        module.stopSession();
        await t.pump();
        await keyPress(t, dialogAction('加入房间'));
        expect(port.commands, isEmpty);
        await clean(t, module);

        final pending = Completer<RoomCommandResult>();
        final hostPort = MotionInvitationPort()
          ..result = ready(directory(host: true))
          ..targets = pending;
        final host = PartyRoomsModule(hostPort);
        await mount(t, host, suite);
        await keyPress(t, action('邀请好友'));
        await clean(t, host);
        pending.complete(
          const RoomCommandResult(
            'targets',
            targets: [RoomInviteTarget('late-ref', '迟到结果')],
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('迟到结果'), findsNothing);
        expect(hostPort.calls, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
}
