import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_directory_card.dart';
import 'package:starbridge_flutter/features/party_rooms/room_display.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/party_rooms_test.dart'
    show ready, room, wire;
import 'interaction_batch3et_test.dart' show RoomFormPort, primary, cancel;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder card() => find.byKey(const ValueKey('room-a'));
Finder join() => find.byKey(const ValueKey('room-join-a'));

class CardProbe {
  CardProbe(this.suite);
  InteractionSuite suite;
  bool reduce = false, light = false, selected = false;
  bool selectEnabled = true, joinEnabled = true, supportsCommands = true;
  String mode = 'approval';
  int capacity = 4;
  bool closed = false;
  bool showAvatar = false, acceptSelection = true;
  int selections = 0;
  final joins = <InteractionSource>[];
  final selectionSources = <InteractionSource>[];
  late StateSetter update;
  PartyRoom get data {
    final value = room('a');
    if (showAvatar) {
      value['canPreviewMemberProfiles'] = true;
      ((value['members'] as List).first as Map)['userRef'] =
          '0123456789abcdef0123456789abcdef';
    }
    if (capacity == 2) {
      value['members'] = [
        ...(value['members'] as List),
        {
          ...(value['members'] as List).single as Map<String, Object?>,
          'gameId': 'Other_Citizen',
          'callsign': 'Other member',
          'isHost': false,
        },
      ];
    }
    return ready(
      wire(
        rooms: [
          value
            ..['admissionMode'] = mode
            ..['capacity'] = capacity
            ..['recruitmentClosesAt'] = closed ? '2026-09-05T11:00:00Z' : null,
        ],
      ),
    ).directory!.rooms.single;
  }

  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 900,
            child: RoomDirectoryCard(
              room: data,
              serverTime: DateTime.utc(2026, 9, 5, 12),
              selected: selected,
              supportsCommands: supportsCommands,
              onSelect: selectEnabled
                  ? () {
                      selections++;
                      selectionSources.add(currentStarBridgeActivationSource);
                      if (acceptSelection) update(() => selected = true);
                    }
                  : null,
              onJoin: joinEnabled ? joins.add : null,
            ),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<void> activateCard(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  if (source == 'reader') {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  } else if (source == 'keyboard') {
    // A card contains its own join action: ancestor containment alone would
    // incorrectly count focus on Join as focus on the outer card.
    final detectors = find.descendant(
      of: target,
      matching: find.byType(FocusableActionDetector),
    );
    final native = find.descendant(
      of: target,
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    final widget = t.widget(target);
    final node = widget is SuitePressable
        ? t.widget<FocusableActionDetector>(detectors.first).focusNode!
        : (widget is ButtonStyleButton
                  ? widget
                  : t.widget(native) as ButtonStyleButton)
              .focusNode!;
    expect(node.canRequestFocus, isTrue);
    for (var i = 0; !node.hasPrimaryFocus && i < 64; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(node.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else if (target.evaluate().single == card().evaluate().single) {
    await t.tap(find.text('测试房间 a'));
  } else {
    await t.tap(target);
  }
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite directory $source selects and joins independently', (
        t,
      ) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final p = CardProbe(suite);
        try {
          await t.pumpWidget(p.app());
          await t.pumpAndSettle();
          final control = t.widget<SuitePressable>(card());
          expect(control.kind, PressableKind.row);
          expect(control.coalesceDataUpdates, isFalse);
          await activateCard(t, card(), source);
          expect(p.selections, 1);
          expect(p.joins, isEmpty);
          expect(
            t.binding.transientCallbackCount,
            source == 'pointer' ? greaterThan(0) : 0,
          );
          expect(
            t
                .getSemantics(card())
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            Tristate.isTrue,
          );
          expect(
            p.selectionSources.single,
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          );
          await t.pumpAndSettle();
          await activateCard(t, join(), source);
          expect(
            p.selections,
            1,
            reason: 'Join must not also tap the outer row',
          );
          expect(p.joins, [
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          ]);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      });
    }
    testWidgets(
      '$suite disabled selection retains independent enabled join and gates',
      (t) async {
        size(t, const Size(1100, 900));
        final semantics = t.ensureSemantics();
        final p = CardProbe(suite)..selectEnabled = false;
        try {
          await t.pumpWidget(p.app());
          await t.pumpAndSettle();
          expect(t.widget<SuitePressable>(card()).onActivate, isNull);
          expect(
            t
                .getSemantics(card())
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          for (final input in ['pointer', 'keyboard', 'reader']) {
            await activateCard(t, join(), input);
            await t.pumpAndSettle();
          }
          expect(p.selections, 0);
          expect(p.joins, [
            InteractionSource.pointer,
            InteractionSource.keyboard,
            InteractionSource.keyboard,
          ]);
          p.update(() {
            p.selectEnabled = true;
            p.joinEnabled = false;
          });
          await t.pumpAndSettle();
          final button = t.widget<StarBridgeActionButton>(
            find.ancestor(
              of: join(),
              matching: find.byType(StarBridgeActionButton),
            ),
          );
          expect(button.onActivate, isNull);
          await activateCard(t, card(), 'pointer');
          expect(p.selections, 1);
          for (final gate in ['full', 'closed', 'unsupported']) {
            p.update(() {
              p.joinEnabled = true;
              p.capacity = gate == 'full' ? 2 : 4;
              p.closed = gate == 'closed';
              p.supportsCommands = gate != 'unsupported';
            });
            await t.pumpAndSettle();
            expect(join(), findsNothing);
            await activateCard(t, card(), 'pointer');
          }
          expect(p.selections, 4);
          expect(p.joins, hasLength(3));
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
    testWidgets(
      '$suite rapid card input preserves feedback and live reduction',
      (t) async {
        size(t, const Size(1100, 900));
        final p = CardProbe(suite);
        await t.pumpWidget(p.app());
        await t.pumpAndSettle();
        final before = t.getRect(card());
        for (var i = 0; i < 6; i++) {
          await t.tap(find.text('测试房间 a'));
          await t.pump(const Duration(milliseconds: 20));
        }
        expect(p.selections, 6);
        expect(p.joins, isEmpty);
        expect(t.binding.transientCallbackCount, greaterThan(0));
        p.update(() {
          p.reduce = true;
        });
        await t.pump();
        await t.pump();
        expect(t.binding.transientCallbackCount, 0);
        expect(t.getRect(card()), before);
        await activateCard(t, card(), 'keyboard');
        expect(p.selections, 7);
        expect(t.binding.transientCallbackCount, 0);
        p.update(() {
          p.suite = InteractionSuite.scan;
          p.reduce = false;
          p.selected = false;
        });
        await t.pumpAndSettle();
        expect(t.widget<SuitePressable>(card()).semanticSelected, isFalse);
        expect(p.selections, 7, reason: 'Settings do not select a room');
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite refused selection stays controlled and avatar stays independent',
      (t) async {
        size(t, const Size(1100, 900));
        final p = CardProbe(suite)..acceptSelection = false;
        await t.pumpWidget(p.app());
        await t.pumpAndSettle();
        await activateCard(t, card(), 'pointer');
        expect(p.selections, 1);
        expect(p.selected, isFalse);
        expect(t.widget<SuitePressable>(card()).semanticSelected, isFalse);
        p.update(() {
          p.selectEnabled = false;
          p.showAvatar = true;
        });
        await t.pumpAndSettle();
        await t.tap(find.byType(RoomIdentityAvatar));
        await t.pumpAndSettle();
        expect(find.text('查看资料'), findsOneWidget);
        expect(p.selections, 1);
        expect(p.joins, isEmpty);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(find.text('查看资料'), findsNothing);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite real directory successful join uses confirmed membership',
      (t) async {
        size(t, const Size(1280, 1000));
        final port = RoomFormPort()..result = ready(wire(rooms: [room('a')]));
        final module = PartyRoomsModule(port);
        addTearDown(module.dispose);
        await module.refresh();
        await t.pumpWidget(scopedApp(PartyRoomsPage(module: module), suite));
        await t.pumpAndSettle();
        await activateCard(t, join(), 'pointer');
        await t.pumpAndSettle();
        await t.tap(primary());
        await t.pump();
        expect(module.writing, isTrue);
        expect(module.directory!.currentRoomId, isNull);
        final result = ready(wire(current: 'a', rooms: [room('a')]));
        port.next.complete(
          RoomCommandResult('joined', directory: result.directory),
        );
        await t.pumpAndSettle();
        expect(port.calls, 1);
        expect(module.writing, isFalse);
        expect(module.directory, same(result.directory));
        expect(module.directory!.currentRoomId, 'a');
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(RoomDirectoryCard), findsNothing);
        module.stopSession();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite real directory join cancels then rejects and retries without extra select',
      (t) async {
        size(t, const Size(1280, 1000));
        final port = RoomFormPort()..result = ready(wire(rooms: [room('a')]));
        final module = PartyRoomsModule(port);
        addTearDown(module.dispose);
        await module.refresh();
        await t.pumpWidget(scopedApp(PartyRoomsPage(module: module), suite));
        await t.pumpAndSettle();
        var notices = 0;
        void changed() => notices++;
        module.addListener(changed);
        await t.tap(find.text('测试房间 a'));
        await t.pumpAndSettle();
        expect(module.selectedRoomId, 'a');
        expect(port.calls, 0);
        expect(notices, 1);
        await activateCard(t, join(), 'pointer');
        await t.pumpAndSettle();
        expect(
          notices,
          2,
          reason: 'Join owner selects once, not parent plus owner',
        );
        expect(port.calls, 0);
        await t.tap(cancel());
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(port.calls, 0);
        await activateCard(t, join(), 'keyboard');
        await t.pumpAndSettle();
        await t.tap(primary());
        await t.pump();
        expect(port.commands.single.operation, RoomOperation.join);
        expect(port.commands.single.data, {'roomId': 'a', 'password': ''});
        port.next.complete(
          const RoomCommandResult('rejected', error: 'rejected'),
        );
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(module.directory!.currentRoomId, isNull);
        port.next = Completer();
        await t.tap(primary());
        await t.pump();
        expect(port.calls, 2);
        expect(port.commands.last.data, port.commands.first.data);
        // Leaving while the command is pending must not recreate the card/dialog.
        module.removeListener(changed);
        module.stopSession();
        await t.pumpWidget(const SizedBox());
        port.next.complete(
          RoomCommandResult(
            'joined',
            directory: ready(wire(current: 'a', rooms: [room('a')])).directory,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(RoomDirectoryCard), findsNothing);
        expect(port.calls, 2);
        expect(t.takeException(), isNull);
      },
    );
  }
}
