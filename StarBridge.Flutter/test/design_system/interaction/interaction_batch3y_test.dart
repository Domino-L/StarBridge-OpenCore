import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_composer.dart';
import 'package:starbridge_flutter/features/communities/community_chat_composer.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_message_composer.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/features/friends/example_friends_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_controls.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_toolbar.dart';

import '../../features/direct_messages/direct_message_send_test.dart'
    as direct
    show Sender, opened;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3m_test.dart' show activate;

class ComposerHarness extends StatefulWidget {
  const ComposerHarness(
    this.kind,
    this.initial, {
    super.key,
    this.module,
    this.frameKey,
  });
  final String kind;
  final InteractionSuite initial;
  final DirectMessagesModule? module;
  final GlobalKey? frameKey;
  @override
  State<ComposerHarness> createState() => ComposerState();
}

class ComposerState extends State<ComposerHarness> {
  final controller = TextEditingController(text: '初始草稿');
  late var suite = widget.initial;
  bool reduce = false,
      light = false,
      enabled = true,
      readOnly = false,
      blocked = false;
  double scale = 1;
  int changes = 0;
  final sources = <InteractionSource>[];
  void change(VoidCallback action) => setState(action);
  void send() => sources.add(currentStarBridgeActivationSource);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget compose() => switch (widget.kind) {
      'room' => RoomChatComposer(
        controller: controller,
        enabled: enabled,
        readOnly: readOnly,
        inputKey: const Key('input'),
        sendKey: const Key('send'),
        onChanged: (_) => changes++,
        onSend: blocked ? null : send,
        attachment: const Text('保留附件草稿'),
        leadingAction: const Text('原分享入口'),
      ),
      'community' => CommunityChatComposer(
        controller: controller,
        enabled: enabled,
        readOnly: readOnly,
        inputKey: const Key('input'),
        sendKey: const Key('send'),
        canSend: !blocked,
        onChanged: (_) => changes++,
        onSend: send,
      ),
      _ => DirectMessageComposer(widget.module!, onSend: send),
    };
    final child = widget.module == null
        ? compose()
        : ListenableBuilder(
            listenable: widget.module!,
            builder: (_, _) => compose(),
          );
    return scopedApp(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: RepaintBoundary(key: widget.frameKey, child: child),
            ),
          ),
        ),
      ),
      suite,
      reduce: reduce,
      light: light,
    );
  }
}

Future<GlobalKey<ComposerState>> composer(
  WidgetTester t,
  String kind,
  InteractionSuite suite, {
  GlobalKey? frame,
}) async {
  size(t, const Size(800, 1000));
  DirectMessagesModule? module;
  if (kind == 'direct') {
    module = await direct.opened(direct.Sender());
    module.editDraft('初始草稿');
    addTearDown(module.dispose);
  }
  final key = GlobalKey<ComposerState>();
  await t.pumpWidget(
    ComposerHarness(kind, suite, key: key, module: module, frameKey: frame),
  );
  await t.pumpAndSettle();
  return key;
}

Finder nativeEditor() => find.byType(EditableText);

class CacheHarness extends StatefulWidget {
  const CacheHarness(this.suite, this.nested, {super.key});
  final InteractionSuite suite;
  final bool nested;
  @override
  State<CacheHarness> createState() => CacheState();
}

class CacheState extends State<CacheHarness> {
  final revision = ValueNotifier(0);
  final focus = FocusNode(), controller = TextEditingController(text: '保留原值');
  void rekey() {
    revision.value++;
    if (!widget.nested) setState(() {});
  }

  Widget native(FocusNode focus) => TextFormField(
    key: ValueKey(revision.value),
    focusNode: focus,
    controller: controller,
    showCursor: false,
    maxLength: 24,
    decoration: InputDecoration(labelText: '保留标签', helperText: '说明与计数不算边框'),
  );
  @override
  void dispose() {
    revision.dispose();
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => scopedApp(
    SizedBox(
      width: 300,
      child: StarBridgeFieldFrame(
        focusNode: focus,
        builder: (_, f) => widget.nested
            ? ValueListenableBuilder(
                valueListenable: revision,
                builder: (_, _, _) => native(f),
              )
            : native(f),
      ),
    ),
    widget.suite,
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['room', 'community', 'direct']) {
      testWidgets(
        '$suite $kind native editing/composing survives style, theme and reduce',
        (t) async {
          final key = await composer(t, kind, suite), state = key.currentState!;
          await t.tap(nativeEditor());
          await t.pump();
          const value = TextEditingValue(
            text: '输入中的星海',
            selection: TextSelection(baseOffset: 1, extentOffset: 4),
            composing: TextRange(start: 1, end: 4),
          );
          t.testTextInput.updateEditingValue(value);
          await t.pump();
          final editor = t.state<EditableTextState>(nativeEditor());
          for (final next in InteractionSuite.values) {
            state.change(() {
              state.suite = next;
              state.reduce = !state.reduce;
              state.light = !state.light;
            });
            await t.pump();
            await t.pump();
            expect(t.state<EditableTextState>(nativeEditor()), same(editor));
            expect(
              t.widget<EditableText>(nativeEditor()).controller.value,
              value,
            );
            expect(
              t.widget<EditableText>(nativeEditor()).focusNode.hasFocus,
              isTrue,
            );
          }
          if (kind != 'direct') {
            expect(state.changes, 1);
          } else {
            expect(state.widget.module!.draft, value.text);
          }
          expect(state.sources, isEmpty);
          expect(t.takeException(), isNull);
        },
      );
      testWidgets(
        '$suite $kind IME/Shift+Enter/held keys preserve shortcut contract and source',
        (t) async {
          final key = await composer(t, kind, suite), state = key.currentState!;
          await t.tap(nativeEditor());
          await t.pump();
          t.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '中文',
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: 0, end: 2),
            ),
          );
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          expect(state.sources, isEmpty);
          t.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '中文',
              selection: TextSelection.collapsed(offset: 2),
            ),
          );
          await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          expect(await t.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
          await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          expect(state.sources, isEmpty);
          await t.sendKeyDownEvent(LogicalKeyboardKey.numpadEnter);
          await t.sendKeyRepeatEvent(LogicalKeyboardKey.numpadEnter);
          await t.sendKeyUpEvent(LogicalKeyboardKey.numpadEnter);
          await t.pump();
          expect(state.sources, [InteractionSource.keyboard]);
          if (kind == 'room') {
            expect(find.text('保留附件草稿'), findsOneWidget);
            expect(find.text('原分享入口'), findsOneWidget);
          }
          expect(t.takeException(), isNull);
        },
      );
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets('$suite $kind $source send calls original callback once', (
          t,
        ) async {
          final sem = t.ensureSemantics();
          try {
            final key = await composer(t, kind, suite);
            await activate(t, find.byType(StarBridgeActionButton), source);
            await t.pumpAndSettle();
            expect(key.currentState!.sources, [
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            sem.dispose();
          }
        });
      }
    }
    for (final nested in [false, true]) {
      testWidgets('$suite bounds cache follows native rekey nested=$nested', (
        t,
      ) async {
        final key = GlobalKey<CacheState>();
        await t.pumpWidget(CacheHarness(suite, nested, key: key));
        key.currentState!.focus.requestFocus();
        await t.pumpAndSettle();
        final old = t.state<EditableTextState>(nativeEditor());
        for (var i = 0; i < 4; i++) {
          key.currentState!.rekey();
          await t.pump();
          await t.pump();
          expect(t.state<EditableTextState>(nativeEditor()), isNot(same(old)));
          final frame = t.widget<SuiteFieldFrame>(find.byType(SuiteFieldFrame));
          final full = t.getSize(find.byType(SuiteFieldFrame));
          expect(frame.boundsResolver!(full).height, lessThan(full.height));
          expect(frame.paintExclusionResolver!(), isNotNull);
          expect(key.currentState!.controller.text, '保留原值');
          expect(t.takeException(), isNull);
        }
      });
    }
    for (final result in ['sent', 'unknown', 'rejected']) {
      testWidgets(
        '$suite real direct send $result keeps original ack and no duplicate',
        (t) async {
          size(t, const Size(800, 1000));
          final port = direct.Sender();
          final owner = await direct.opened(port);
          addTearDown(owner.dispose);
          await t.pumpWidget(
            scopedApp(
              ListenableBuilder(
                listenable: owner,
                builder: (_, _) => DirectMessageComposer(owner),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextFormField), '保留的消息');
          await t.pump();
          await activate(t, find.byType(StarBridgeActionButton), 'pointer');
          await t.pump();
          expect(port.writes, hasLength(1));
          // A2 (2026-10-21): the text moves into the outgoing bubble and the
          // composer is free; a second press with nothing typed sends nothing.
          expect(owner.draft, isEmpty);
          expect(owner.outgoing.single.text, '保留的消息');
          expect(
            t.widget<TextFormField>(find.byType(TextFormField)).enabled,
            isNot(false),
          );
          await t.tap(find.byType(StarBridgeActionButton), warnIfMissed: false);
          await t.pump();
          expect(port.writes, hasLength(1));
          if (result == 'sent') {
            port.confirmed = port.ack();
            port.reply.complete(
              DirectSendResult('sent', message: port.confirmed),
            );
          } else if (result == 'unknown') {
            port.reply.complete(const DirectSendResult('unknown'));
          } else {
            port.reply.complete(
              const DirectSendResult('rejected', error: 'request_pending'),
            );
          }
          await t.pumpAndSettle();
          expect(owner.draft, isEmpty);
          if (result == 'sent') {
            expect(owner.outgoing, isEmpty, reason: 'history replaced it');
          } else {
            expect(owner.outgoing.single.text, '保留的消息');
          }
          expect(
            owner.outgoing.firstOrNull?.state,
            result == 'rejected'
                ? DirectOutgoingState.failed
                : anyOf(isNull, DirectOutgoingState.sending),
          );
          expect(
            owner.sendStatus,
            result == 'rejected' ? 'request_pending' : isNull,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          // Let a queued same-id retry run; the owner is disposed after.
          await t.pump(const Duration(seconds: 4));
        },
      );
    }
    testWidgets(
      '$suite real friends query remains explicit and survives focus-style change',
      (t) async {
        size(t, const Size(1400, 1000));
        final owner = FriendsModule(ExampleFriendsAdapter());
        addTearDown(owner.dispose);
        await owner.refresh();
        Widget page(InteractionSuite style) => scopedApp(
          FriendsPage(module: owner, createPort: ExampleFriendsAdapter.new),
          style,
        );
        await t.pumpWidget(page(suite));
        await t.pumpAndSettle();
        final input = find.byType(TextField).first;
        await t.enterText(input, 'Example');
        await t.pump();
        expect(owner.query, 'Example');
        final controller = t.widget<TextField>(input).controller;
        await t.pumpWidget(page(InteractionSuite.glow));
        await t.pumpAndSettle();
        expect(t.widget<TextField>(input).controller, same(controller));
        expect(controller!.text, 'Example');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pumpAndSettle();
        expect(owner.query, 'Example');
        expect(t.takeException(), isNull);
      },
    );
    for (final ships in [false, true]) {
      testWidgets(
        '$suite real fleet ${ships ? 'ships' : 'members'} search keeps original module',
        (t) async {
          size(t, const Size(1200, 1000));
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          if (ships) {
            final owner = createOfficialFleetShipsModule(
              InMemoryOfficialFleetShipsAdapter.forReview(),
            );
            addTearDown(owner.dispose);
            await owner.open('officialFleet:7');
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder(
                  valueListenable: owner.projection,
                  builder: (_, p, _) => OfficialFleetShipsToolbar(
                    projection: p,
                    module: owner,
                    searchController: controller,
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const Key('official-fleet-ships-search')),
              '秃鹫',
            );
            await t.testTextInput.receiveAction(TextInputAction.search);
            await t.pumpAndSettle();
            expect(owner.projection.value.query!.search, '秃鹫');
            expect(owner.projection.value.ships, hasLength(1));
          } else {
            final owner = createOfficialFleetMembersModule(
              InMemoryOfficialFleetMembersAdapter.forReview(),
            );
            addTearDown(owner.dispose);
            await owner.open('officialFleet:7');
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder(
                  valueListenable: owner.projection,
                  builder: (_, p, _) => OfficialFleetMembersToolbar(
                    projection: p,
                    module: owner,
                    searchController: controller,
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const Key('official-fleet-members-search')),
              'no-match',
            );
            await t.testTextInput.receiveAction(TextInputAction.search);
            await t.pumpAndSettle();
            expect(owner.projection.value.query!.search, 'no-match');
            expect(owner.projection.value.members, isEmpty);
          }
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('$suite 200 percent room composer review', (t) async {
      final key = await composer(t, 'room', suite, frame: GlobalKey());
      // Use the harness's actual boundary, not a second product instance.
      final actual = key.currentState!.widget.frameKey!;
      key.currentState!.change(() => key.currentState!.scale = 2);
      await t.pumpAndSettle();
      await t.tap(nativeEditor());
      await t.pumpAndSettle();
      await t.runAsync(() async {
        final boundary =
            actual.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await boundary.toImage();
        try {
          final bytes = (await img.toByteData(format: ImageByteFormat.png))!;
          final dir = Directory('build/reviews/interaction-batch3y')
            ..createSync(recursive: true);
          File('${dir.path}/${suite.name}-composer-200.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
        } finally {
          img.dispose();
        }
      });
      expect(t.takeException(), isNull);
    });
  }
}
