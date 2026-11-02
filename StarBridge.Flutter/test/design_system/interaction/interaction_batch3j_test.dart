import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_member_menu.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_menu_anchor.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_member_menu.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/party_rooms_test.dart' show ready, wire;
import '../../features/party_rooms/room_member_removal_test.dart'
    show removalRoom, token;
import 'interaction_batch3b_test.dart' show semanticTap;
import 'interaction_batch3i_test.dart'
    show mount, MotionRoomPort, keyPress, dialogAction, route, scopedApp;

Future<void> openMemberMenu(WidgetTester t, String source) async {
  final menu = find.byType(RoomMemberMenu).first;
  if (source == 'pointer') {
    await t.tap(menu);
  } else if (source == 'keyboard') {
    t
        .widget<StarBridgeIconAction>(
          find.descendant(
            of: menu,
            matching: find.byType(StarBridgeIconAction),
          ),
        )
        .focusNode!
        .requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final label = t
        .widget<StarBridgeMenuAnchor>(
          find.descendant(
            of: menu,
            matching: find.byType(StarBridgeMenuAnchor),
          ),
        )
        .semanticLabel;
    await semanticTap(t, find.bySemanticsLabel(label).first);
  }
  await t.pumpAndSettle();
}

Future<void> chooseMemberAction(
  WidgetTester t,
  String id,
  String label,
  String source,
) async {
  if (source == 'pointer') {
    await t.tap(find.byKey(ValueKey<Object>(id)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 60));
  } else if (source == 'keyboard') {
    await keyPress(t, find.byKey(ValueKey<Object>(id)));
  } else {
    await semanticTap(t, find.bySemanticsLabel(label).first);
    await t.pump();
    await t.pump();
  }
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3J'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3j');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite member menu keeps native viewport hidden through exit and disposal',
      (t) async {
        size(t, const Size(1000, 800));
        await t.pumpWidget(
          scopedApp(Center(child: RoomMemberMenu(onRemove: (_) {})), suite),
        );
        await t.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        await openMemberMenu(t, 'pointer');
        expect(nativeViewportMenus.value, 1);
        await t.tap(find.byKey(const ValueKey<Object>('remove')));
        await t.pump();
        if (suite != InteractionSuite.standard) {
          expect(nativeViewportMenus.value, 1);
        }
        await t.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        await openMemberMenu(t, 'keyboard');
        expect(nativeViewportMenus.value, 1);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(nativeViewportMenus.value, 0);
        expect(t.takeException(), isNull);
      },
    );
    for (final id in ['remove', 'transfer']) {
      final label = id == 'remove' ? '移出房间' : '转移房主';
      testWidgets(
        '$suite $id keeps pointer, keyboard and reader source through menu',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            for (final source in ['pointer', 'keyboard', 'reader']) {
              final port = MotionRoomPort()
                ..result = ready(
                  wire(current: 'a', rooms: [removalRoom()])
                    ..['supportsHostTransfer'] = true,
                );
              final module = PartyRoomsModule(port);
              final frame = GlobalKey();
              final h = await mount(t, module, suite, frame: frame);
              await openMemberMenu(t, source);
              if (source == 'pointer' && id == 'remove') {
                await capture(t, frame, '${suite.name}-member-menu');
              }
              await chooseMemberAction(t, id, label, source);
              expect(find.byType(AlertDialog), findsOneWidget);
              if (source == 'pointer' && suite != InteractionSuite.standard) {
                expect(route(t).animation!.value, inExclusiveRange(0, 1));
              } else if (source != 'pointer') {
                expect(route(t).animation!.value, 1);
              }
              expect(port.calls, 0);
              if (source == 'pointer') {
                h.change(() => h.reduce = true);
                await t.pump();
                await t.pump();
                expect(route(t).animation!.value, 1);
                h.change(() => h.reduce = false);
                await t.pumpAndSettle();
                if (id == 'remove') {
                  await capture(t, frame, '${suite.name}-member-confirm');
                }
              }
              await keyPress(t, dialogAction('取消'));
              expect(find.byType(AlertDialog), findsNothing);
              expect(port.calls, 0);
              await openMemberMenu(t, 'keyboard');
              await chooseMemberAction(t, id, label, 'keyboard');
              await keyPress(t, dialogAction(label));
              expect(port.calls, 1);
              expect(
                port.commands.single.operation,
                id == 'remove'
                    ? RoomOperation.remove
                    : RoomOperation.transferHost,
              );
              expect(
                port.commands.single.data[id == 'remove'
                    ? 'removalToken'
                    : 'memberToken'],
                token,
              );
              port.next.complete(
                const RoomCommandResult('rejected', error: 'unavailable'),
              );
              await t.pumpAndSettle();
              expect(module.selectedRoom!.members, hasLength(2));
              expect(module.selectedRoom!.viewerIsHost, true);
              module.stopSession();
              await t.pumpWidget(const SizedBox());
              await t.pumpAndSettle();
              expect(t.takeException(), isNull);
            }
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite revoking host retires open menu and stale confirmation',
      (t) async {
        final port = MotionRoomPort()
          ..result = ready(
            wire(current: 'a', rooms: [removalRoom()])
              ..['supportsHostTransfer'] = true,
          );
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        await openMemberMenu(t, 'keyboard');
        port.result = ready(
          wire(current: 'a', rooms: [removalRoom(host: false)]),
        );
        await module.refresh();
        await t.pump();
        await t.pump();
        expect(find.byKey(const ValueKey<Object>('remove')), findsNothing);
        expect(find.byType(RoomMemberMenu), findsNothing);
        expect(port.calls, 0);
        port.result = ready(
          wire(current: 'a', rooms: [removalRoom()])
            ..['supportsHostTransfer'] = true,
        );
        await module.refresh();
        await t.pumpAndSettle();
        await openMemberMenu(t, 'keyboard');
        await chooseMemberAction(t, 'remove', '移出房间', 'keyboard');
        port.result = ready(
          wire(current: 'a', rooms: [removalRoom(host: false)]),
        );
        await module.refresh();
        await t.pumpAndSettle();
        await keyPress(t, dialogAction('移出房间'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(port.calls, 0);
        module.stopSession();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite nested tag picker keeps parent draft, validation and cancellation',
      (t) async {
        final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
        final h = await mount(t, module, suite);
        await keyPress(t, find.byKey(const Key('room-create-open')));
        await t.enterText(find.byKey(const Key('room-create-title')), '保留中的草稿');
        final choose = find.byKey(const Key('room-choose-tags'));
        await t.ensureVisible(choose);
        await keyPress(t, choose);
        expect(route(t).animation!.value, 1);
        await keyPress(t, find.byKey(const Key('room-tags-confirm')));
        expect(find.text('至少选择一条玩法路径。'), findsOneWidget);
        await keyPress(t, dialogAction('取消'));
        expect(find.byKey(const Key('room-create-title')), findsOneWidget);
        expect(find.text('保留中的草稿'), findsOneWidget);
        await t.ensureVisible(choose);
        await t.tap(choose);
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        if (suite != InteractionSuite.standard) {
          expect(route(t).animation!.value, inExclusiveRange(0, 1));
        }
        h.change(() => h.reduce = true);
        await t.pump();
        await t.pump();
        expect(route(t).animation!.value, 1);
        await t.enterText(find.byKey(const Key('tag-catalog-search')), '不知道玩啥');
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('search-tag-undecided')));
        await t.pumpAndSettle();
        h.change(() => h.reduce = false);
        await t.pumpAndSettle();
        await keyPress(t, find.byKey(const Key('room-tags-confirm')));
        expect(find.text('保留中的草稿'), findsOneWidget);
        final selectedTag = find.byKey(
          const ValueKey('selected-tag-undecided'),
        );
        expect(selectedTag, findsOneWidget);
        expect(
          find.descendant(of: selectedTag, matching: find.text('不知道玩啥')),
          findsOneWidget,
        );
        expect(module.directory!.currentRoomId, isNull);
        await keyPress(t, dialogAction('取消'));
        expect(find.byType(AlertDialog), findsNothing);
        module.stopSession();
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite directory join preserves keyboard and reader source without joining early',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final port = MotionRoomPort()
            ..result = ready(wire(rooms: [removalRoom()]));
          final module = PartyRoomsModule(port);
          await mount(t, module, suite);
          final join = find.byKey(const ValueKey('room-join-a'));
          for (final source in ['keyboard', 'reader']) {
            if (source == 'keyboard') {
              await keyPress(t, join);
            } else {
              await semanticTap(t, join);
              await t.pump();
              await t.pump();
            }
            expect(route(t).animation!.value, 1);
            expect(port.calls, 0);
            expect(module.directory!.currentRoomId, isNull);
            await keyPress(t, dialogAction('取消'));
            expect(find.byType(AlertDialog), findsNothing);
          }
          module.stopSession();
          expect(t.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '$suite game menu retains exact confirmed lease after reference renewal',
      (t) async {
        size(t, const Size(1000, 800));
        var actionKey = 'original', valid = true;
        late StateSetter rebuild;
        final calls = <String>[];
        await t.pumpWidget(
          scopedApp(
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return Center(
                  child: MenuRoomMemberMenu(
                    enabled: valid,
                    action: (
                      key: actionKey,
                      label: '移出房间',
                      confirm: '移出测试成员？',
                      input: null,
                      role: 'removeMember',
                      secret: false,
                      limit: 128,
                    ),
                    dispatch: (key, _) => calls.add(key),
                  ),
                );
              },
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await openMemberMenu(t, 'keyboard');
        await chooseMemberAction(t, 'remove', '移出房间', 'keyboard');
        expect(route(t).animation!.value, 1);
        rebuild(() => actionKey = 'renewed');
        await t.pump();
        await keyPress(t, dialogAction('移出房间'));
        expect(calls, ['original']);
        await openMemberMenu(t, 'keyboard');
        await chooseMemberAction(t, 'remove', '移出房间', 'keyboard');
        rebuild(() => valid = false);
        await t.pump();
        await keyPress(t, dialogAction('移出房间'));
        expect(calls, ['original']);
        expect(t.takeException(), isNull);
      },
    );
  }
}
