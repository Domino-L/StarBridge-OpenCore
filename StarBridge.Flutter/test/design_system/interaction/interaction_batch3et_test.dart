import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/example_room_copy.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_action_dialogs.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/room_management_test.dart'
    show ManagementPort;
import 'interaction_batch3eo_test.dart' show key;
import 'interaction_batch3eo_test.dart' as controls show activate;
import 'interaction_batch3i_test.dart' show scopedApp;

class RoomFormPort extends ManagementPort {
  final commands = <RoomCommand>[];
  final sources = <InteractionSource>[];
  Completer<RoomCommandResult> next = Completer();
  @override
  Future<RoomCommandResult> execute(RoomCommand command) {
    calls++;
    commands.add(command);
    sources.add(currentStarBridgeActivationSource);
    return next.future;
  }
}

Future<RoomReadResult> formData({
  bool host = false,
  bool password = false,
}) async {
  final example = ExamplePartyRoomsAdapter();
  if (host) example.selectPreviewScene('host');
  final read = await example.read();
  await example.close();
  final data = read.directory!;
  final room = copyExampleRoom(data.rooms.first, passwordRequired: password);
  return RoomReadResult(
    RoomReadState.ready,
    directory: RoomDirectory(
      rooms: [room],
      currentRoomId: host ? room.id : null,
      serverTime: data.serverTime,
      tagOptions: data.tagOptions,
    ),
  );
}

Finder primary() => find.descendant(
  of: find.byType(AlertDialog).last,
  matching: find.byWidgetPredicate(
    (w) =>
        w is StarBridgeActionButton && w.kind == StarBridgeActionKind.primary,
  ),
);
Finder cancel() => find.descendant(
  of: find.byType(AlertDialog).last,
  matching: find.byWidgetPredicate(
    (w) => w is StarBridgeActionButton && w.kind == StarBridgeActionKind.quiet,
  ),
);
Finder password({bool form = true}) {
  final editor = find.byWidgetPredicate((w) => w is TextField && w.obscureText);
  return form
      ? find.ancestor(of: editor, matching: find.byType(TextFormField))
      : editor;
}

Future<void> activate(WidgetTester t, Finder target, String input) async {
  // A wrapper's outer Listener is above its Material MergeSemantics. Read the
  // actual native button, not the route node inherited by that outer Listener.
  final native = find.descendant(
    of: target,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  await controls.activate(
    t,
    input == 'reader' && native.evaluate().length == 1 ? native : target,
    input,
  );
}

Widget roomFormHome(PartyRoomsModule module, String kind) => Builder(
  builder: (context) => StarBridgeActionButton(
    controlKey: const Key('room-form-open'),
    onActivate: (source) => switch (kind) {
      'edit' => editRoomDialog(context, module, source: source),
      'join' => joinRoomDialog(context, module, source: source),
      _ => createRoomDialog(context, module, source: source),
    },
    child: const Text('Open'),
  ),
);

Future<PartyRoomsModule> openRoomForm(
  WidgetTester t,
  RoomFormPort port,
  InteractionSuite suite,
  String kind,
) async {
  size(t, const Size(1280, 1100));
  final module = PartyRoomsModule(port);
  addTearDown(module.dispose);
  await module.refresh();
  await t.pumpWidget(scopedApp(roomFormHome(module, kind), suite));
  await t.pumpAndSettle();
  await activate(t, key('room-form-open'), 'pointer');
  await t.pumpAndSettle();
  return module;
}

Future<void> chooseTags(WidgetTester t) async {
  await activate(t, key('room-choose-tags'), 'pointer');
  await t.pumpAndSettle();
  await t.enterText(key('tag-catalog-search'), '不知道玩啥');
  await t.pumpAndSettle();
  await t.tap(key('search-tag-undecided'));
  await t.pumpAndSettle();
  await t.tap(key('room-tags-confirm'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite create fields and toggles retain validation and payload with $input',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = RoomFormPort()..result = await formData();
          final module = await openRoomForm(t, port, suite, 'create');
          try {
            expect(find.byType(StarBridgeFieldFrame), findsNWidgets(2));
            expect(find.byType(StarBridgeSwitch), findsNWidgets(2));
            await activate(t, primary(), input);
            await t.pumpAndSettle();
            expect(
              t
                  .state<FormFieldState<String>>(key('room-create-title'))
                  .hasError,
              isTrue,
            );
            expect(port.calls, 0);
            final titleFrame = find
                .ancestor(
                  of: key('room-create-title'),
                  matching: find.byType(StarBridgeFieldFrame),
                )
                .first;
            expect(
              t.widget<StarBridgeFieldFrame>(titleFrame).followNativeError,
              isTrue,
            );
            await t.ensureVisible(key('room-create-title'));
            await t.pumpAndSettle();
            final titleSuite = t.widget<SuiteFieldFrame>(
              find.descendant(
                of: titleFrame,
                matching: find.byType(SuiteFieldFrame),
              ),
            );
            expect(titleSuite.errorResolver!(), isTrue);
            await t.enterText(key('room-create-title'), '  Synthetic room  ');
            await t.enterText(key('room-create-goal'), '  Synthetic goal  ');
            await activate(t, key('room-public-toggle'), input);
            await t.pumpAndSettle();
            expect(
              t.widget<StarBridgeSwitch>(key('room-public-toggle')).value,
              isFalse,
            );
            await activate(t, key('room-password-toggle'), input);
            await t.pumpAndSettle();
            expect(find.byType(StarBridgeFieldFrame), findsNWidgets(3));
            await activate(t, primary(), input);
            await t.pumpAndSettle();
            expect(
              t.state<FormFieldState<String>>(password()).hasError,
              isTrue,
            );
            expect(port.calls, 0);
            expect(
              t
                  .state<FormFieldState<String>>(key('room-create-title'))
                  .hasError,
              isFalse,
            );
            expect(titleSuite.errorResolver!(), isFalse);
            await t.enterText(password(), 'synthetic-password');
            await chooseTags(t);
            await activate(t, primary(), input);
            await t.pump();
            expect(port.calls, 1);
            expect(port.commands.single.operation, RoomOperation.create);
            expect(port.commands.single.data, {
              'title': 'Synthetic room',
              'goal': 'Synthetic goal',
              'capacity': 6,
              'isPublic': false,
              'eligibility': 'everyone',
              'admissionMode': 'direct',
              'passwordEnabled': true,
              'password': 'synthetic-password',
              'voiceRequirement': 'recommended',
              'language': 'zh',
              'autoDisbandHours': 6,
              'recruitmentDurationMinutes': null,
              'gameplayTagNodeIds': ['undecided'],
              'contextTagIds': <String>[],
            });
            expect(
              port.sources.single,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(
              t
                  .widget<AbsorbPointer>(
                    find
                        .ancestor(
                          of: key('room-create-title'),
                          matching: find.byType(AbsorbPointer),
                        )
                        .first,
                  )
                  .absorbing,
              isTrue,
            );
            expect(
              t.widget<StarBridgeActionButton>(cancel()).onActivate,
              isNull,
            );
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(find.byType(AlertDialog), findsOneWidget);
            port.next.complete(
              const RoomCommandResult('rejected', error: 'rejected'),
            );
            await t.pumpAndSettle();
            expect(
              t
                  .widget<TextFormField>(key('room-create-title'))
                  .controller!
                  .text,
              '  Synthetic room  ',
            );
            expect(
              t.widget<TextFormField>(password()).controller!.text,
              'synthetic-password',
            );
            expect(
              t.widget<StarBridgeSwitch>(key('room-public-toggle')).value,
              isFalse,
            );
            port.next = Completer();
            await activate(t, primary(), input);
            expect(port.calls, 2);
            expect(port.commands.last.data, port.commands.first.data);
            port.next.complete(
              RoomCommandResult(
                'joined',
                directory: (await formData(host: true)).directory,
              ),
            );
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(module.directory!.currentRoomId, isNotNull);
            expect(t.takeException(), isNull);
          } finally {
            module.stopSession();
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '$suite join preserves code and password through failures with $input',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = RoomFormPort()..result = await formData();
          final module = await openRoomForm(t, port, suite, 'join');
          try {
            expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
            await t.enterText(find.byType(TextField), '  CODE123  ');
            await activate(t, primary(), input);
            expect(port.commands.single.data, {'roomCode': 'CODE123'});
            expect(
              t.widget<TextField>(find.byType(TextField)).enabled,
              isFalse,
            );
            port.next.complete(
              const RoomCommandResult('rejected', error: 'unavailable'),
            );
            await t.pumpAndSettle();
            expect(
              t.widget<TextField>(find.byType(TextField)).controller!.text,
              '  CODE123  ',
            );
            port.next = Completer();
            await activate(t, primary(), input);
            final preview = (await formData(password: true))
                .directory!
                .rooms
                .single;
            port.next.complete(RoomCommandResult('resolved', preview: preview));
            await t.pumpAndSettle();
            expect(module.directory!.currentRoomId, isNull);
            expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
            await t.enterText(password(form: false), '  join-password  ');
            port.next = Completer();
            await activate(t, primary(), input);
            expect(port.commands.last.operation, RoomOperation.join);
            expect(port.commands.last.data, {
              'roomId': preview.id,
              'password': 'join-password',
            });
            port.next.complete(
              const RoomCommandResult('rejected', error: 'rejected'),
            );
            await t.pumpAndSettle();
            expect(
              t.widget<TextField>(password(form: false)).controller!.text,
              '  join-password  ',
            );
            port.next = Completer();
            await activate(t, primary(), input);
            expect(port.commands.last.data, {
              'roomId': preview.id,
              'password': 'join-password',
            });
            port.next.complete(
              RoomCommandResult(
                'joined',
                directory: RoomDirectory(
                  rooms: [preview],
                  serverTime: DateTime.now().toUtc(),
                  currentRoomId: preview.id,
                ),
              ),
            );
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(module.directory!.currentRoomId, preview.id);
            expect(t.takeException(), isNull);
          } finally {
            module.stopSession();
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets('$suite edit preserves keep replace remove password modes', (
      t,
    ) async {
      final port = RoomFormPort()
        ..result = await formData(host: true, password: true);
      final module = await openRoomForm(t, port, suite, 'edit');
      expect(find.byType(StarBridgeFieldFrame), findsNWidgets(3));
      expect(t.widget<TextFormField>(password()).controller!.text, isEmpty);
      await activate(t, primary(), 'keyboard');
      expect(port.commands.single.operation, RoomOperation.update);
      expect(port.commands.single.data['passwordMode'], 'keep');
      port.next.complete(
        const RoomCommandResult('rejected', error: 'rejected'),
      );
      await t.pumpAndSettle();
      await t.enterText(password(), 'replacement');
      port.next = Completer();
      await activate(t, primary(), 'pointer');
      expect(port.commands.last.data['passwordMode'], 'replace');
      expect(port.commands.last.data['password'], 'replacement');
      port.next.complete(
        const RoomCommandResult('rejected', error: 'rejected'),
      );
      await t.pumpAndSettle();
      await activate(t, key('room-password-toggle'), 'keyboard');
      await t.pumpAndSettle();
      port.next = Completer();
      await activate(t, primary(), 'keyboard');
      expect(port.commands.last.data['passwordMode'], 'remove');
      expect(port.commands.last.data['password'], '');
      port.next.complete(
        RoomCommandResult('updated', directory: port.result.directory),
      );
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(port.calls, 3);
      module.stopSession();
    });

    testWidgets(
      '$suite create editor IME and validation survive live style changes',
      (t) async {
        size(t, const Size(1280, 1100));
        final port = RoomFormPort()..result = await formData();
        final module = PartyRoomsModule(port);
        addTearDown(module.dispose);
        await module.refresh();
        var selected = suite, reduce = false, light = false;
        late StateSetter update;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return scopedApp(
                roomFormHome(module, 'create'),
                selected,
                reduce: reduce,
                light: light,
              );
            },
          ),
        );
        await t.pumpAndSettle();
        await activate(t, key('room-form-open'), 'pointer');
        await t.pumpAndSettle();
        await activate(t, primary(), 'pointer');
        await t.pumpAndSettle();
        final formField = t.state<FormFieldState<String>>(
          key('room-create-title'),
        );
        final controller = t
            .widget<TextFormField>(key('room-create-title'))
            .controller!;
        controller.value = const TextEditingValue(
          text: 'native-draft',
          selection: TextSelection(baseOffset: 3, extentOffset: 6),
          composing: TextRange(start: 0, end: 6),
        );
        await t.pump();
        final value = controller.value;
        update(() {
          selected = InteractionSuite.glow;
          reduce = true;
          light = true;
        });
        await t.pump();
        await t.pump();
        expect(
          t.state<FormFieldState<String>>(key('room-create-title')),
          same(formField),
        );
        expect(formField.hasError, isTrue);
        expect(
          t.widget<TextFormField>(key('room-create-title')).controller,
          same(controller),
        );
        expect(controller.value, value);
        expect(port.calls, 0);
        await activate(t, cancel(), 'keyboard');
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      '$suite removing a form during a request cannot revive it on late response',
      (t) async {
        final port = RoomFormPort()..result = await formData();
        final module = await openRoomForm(t, port, suite, 'join');
        expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
        await t.enterText(find.byType(TextField), 'CODE123');
        await activate(t, primary(), 'pointer');
        await t.pumpWidget(const SizedBox());
        module.stopSession();
        port.next.complete(
          RoomCommandResult(
            'resolved',
            preview: port.result.directory!.rooms.first,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(port.calls, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
}
