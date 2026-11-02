import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_chat_controller.dart';
import 'package:starbridge_flutter/features/communities/community_chat_copy.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_chat_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/features/communities/community_chat_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_local_message_tile.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/communities/community_chat_controller_test.dart'
    show FakeChat, page;
import '../../features/communities/community_workspace_test.dart'
    show WorkspaceTestPort, workspacePayload;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder chatKey(String suffix) => find.byKey(Key('community-chat-$suffix'));

Future<void> chatFrames(WidgetTester t, [int count = 8]) async {
  await t.pump();
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

Future<void> chatActivate(
  WidgetTester t,
  Finder target,
  String input,
  String label,
) async {
  await t.ensureVisible(target);
  await chatFrames(t, 2);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'reader') {
    final matches = exposedNodes(t).where((node) {
      final data = node.getSemanticsData();
      return data.label == label && data.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(matches, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      matches.single.id,
      ui.SemanticsAction.tap,
    );
  } else {
    final control = t.widget(target);
    final node = switch (control) {
      SuitePressable button => button.focusNode!,
      IconButton button => button.focusNode!,
      ButtonStyleButton button => button.focusNode!,
      _ => throw StateError('Unsupported target: $control'),
    };
    for (var i = 0; !node.hasPrimaryFocus && i < 40; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(node.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await t.pump();
  await t.pump();
}

class ChatProbe {
  ChatProbe(this.suite, this.port, this.model);
  InteractionSuite suite;
  FakeChat port;
  CommunityChatController model;
  bool reduce = false;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        CommunityChatPanel(
          port: port,
          controller: model,
          targetRef: 'a' * 32,
          name: 'Local fixture',
          onBack: () {},
        ),
        suite,
        reduce: reduce,
      );
    },
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fj $suite $input refresh/history/latest retain owner and admitted source',
        (t) async {
          size(t, const Size(1000, 820));
          final semantics = t.ensureSemantics();
          final port = FakeChat()..next = page([10, 12], latest: 20);
          final model = CommunityChatController(port, 'a' * 32);
          await model.refresh();
          model.updateDraft('kept draft');
          final probe = ChatProbe(suite, port, model);
          try {
            await t.pumpWidget(probe.app());
            await chatFrames(t);
            final editor = t.widget<TextField>(chatKey('input'));
            final controller = editor.controller, focus = editor.focusNode;
            String label(String name) =>
                communityChatText(t.element(chatKey('refresh')), name);
            final expected = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            var count = port.reads.length;
            final rejected = port.heldRead = Completer<CommunityChatPage>();
            await chatActivate(t, chatKey('refresh'), input, label('refresh'));
            expect(port.reads, hasLength(count + 1));
            expect(port.reads.last, (12, 0));
            var activity = t.widget<SocialReadActivity>(
              find.byType(SocialReadActivity),
            );
            expect(activity.source, expected);
            expect(activity.opening, isFalse);
            expect(model.messages.map((m) => m.sequence), [10, 12]);
            probe.update(() => probe.reduce = true);
            await chatFrames(t, 2);
            expect(
              t.widget<TextField>(chatKey('input')).controller,
              same(controller),
            );
            expect(
              t.widget<TextField>(chatKey('input')).focusNode,
              same(focus),
            );
            expect(port.reads, hasLength(count + 1));
            rejected.completeError(const CommunityFailure('unavailable'));
            port.heldRead = null;
            await chatFrames(t);
            expect(model.error, 'unavailable');
            expect(model.draft, 'kept draft');
            expect(model.messages, hasLength(2));
            probe.update(() => probe.reduce = false);
            final retry = port.heldRead = Completer<CommunityChatPage>();
            await chatFrames(t, 2);
            await chatActivate(t, chatKey('refresh'), input, label('refresh'));
            retry.complete(page([14], latest: 20));
            port.heldRead = null;
            await chatFrames(t);
            expect(model.messages.map((m) => m.sequence), [10, 12, 14]);
            expect(model.error, isNull);
            expect(model.draft, 'kept draft');
            final older = port.heldRead = Completer<CommunityChatPage>();
            count = port.reads.length;
            await chatActivate(t, chatKey('older'), input, label('older'));
            expect(port.reads, hasLength(count + 1));
            expect(port.reads.last, (0, 10));
            activity = t.widget<SocialReadActivity>(
              find.byType(SocialReadActivity),
            );
            expect(activity.source, expected);
            older.complete(page([5, 8], latest: 20, older: false));
            port.heldRead = null;
            await chatFrames(t, 14);
            expect(model.messages.map((m) => m.sequence), [5, 8, 10, 12, 14]);
            final latest = port.heldRead = Completer<CommunityChatPage>();
            count = port.reads.length;
            await chatActivate(t, chatKey('latest'), input, label('latest'));
            expect(port.reads, hasLength(count + 1));
            expect(port.reads.last, (14, 0));
            activity = t.widget<SocialReadActivity>(
              find.byType(SocialReadActivity),
            );
            expect(activity.source, expected);
            latest.complete(page([20], latest: 20, older: false));
            port.heldRead = null;
            await chatFrames(t);
            expect(model.messages.last.sequence, 20);
            expect(model.draft, 'kept draft');
            expect(port.sends, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            model.dispose();
            await port.changes.close();
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fj $suite silent reads stay silent and owner change retires old wait',
      (t) async {
        size(t, const Size(1000, 820));
        final oldPort = FakeChat()
          ..next = page([10, 12], latest: 12, older: false);
        final newPort = FakeChat()..next = page([30], latest: 30, older: false);
        final oldModel = CommunityChatController(oldPort, 'a' * 32);
        final newModel = CommunityChatController(newPort, 'a' * 32);
        await oldModel.refresh();
        final probe = ChatProbe(suite, oldPort, oldModel);
        try {
          await t.pumpWidget(probe.app());
          await chatFrames(t);
          final silent = oldPort.heldRead = Completer<CommunityChatPage>();
          final read = oldModel.refresh(silent: true);
          await chatFrames(t, 2);
          expect(find.byType(SocialReadActivity), findsNothing);
          silent.complete(page([], latest: 12, older: false));
          oldPort.heldRead = null;
          await read;
          final late = oldPort.heldRead = Completer<CommunityChatPage>();
          final pending = oldModel.refresh();
          await chatFrames(t, 2);
          expect(find.byType(SocialReadActivity), findsOneWidget);
          probe.update(() {
            probe.port = newPort;
            probe.model = newModel;
          });
          await chatFrames(t);
          expect(find.text('Message 30'), findsOneWidget);
          late.completeError(const CommunityFailure('unavailable'));
          await pending;
          await chatFrames(t);
          expect(find.byType(SocialReadActivity), findsNothing);
          expect(find.text('Message 30'), findsOneWidget);
          expect(newModel.error, isNull);
          // Regression probe of observer cleanup, not production access.
          // ignore: invalid_use_of_protected_member
          expect(oldModel.hasListeners, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          oldModel.dispose();
          newModel.dispose();
          await oldPort.changes.close();
          await newPort.changes.close();
        }
      },
    );

    for (final input in ['pointer', 'keyboard']) {
      testWidgets(
        '3fj $suite $input actual send wait preserves source and rejection state',
        (t) async {
          size(t, const Size(1000, 820));
          final port = FakeChat()
            ..next = page([], latest: 0, unread: 0, older: false);
          final model = CommunityChatController(
            port,
            'a' * 32,
            localEcho: true,
          );
          await model.refresh();
          final gate = port.heldSend = Completer<CommunityChatSendOutcome>();
          try {
            await t.pumpWidget(ChatProbe(suite, port, model).app());
            await chatFrames(t);
            await t.enterText(chatKey('input'), 'original intent');
            await t.pump();
            if (input == 'keyboard') {
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              final send = find.widgetWithText(FilledButton, '发送');
              final suiteSend = find.byWidgetPredicate(
                (w) => w is SuitePressable && w.kind == PressableKind.primary,
              );
              await t.tap(
                suite == InteractionSuite.standard ? send : suiteSend,
              );
            }
            await chatFrames(t, 2);
            expect(port.sends, hasLength(1));
            expect(port.sends.single.text, 'original intent');
            expect(model.sending, isTrue);
            final tile = t.widget<CommunityLocalMessageTile>(
              find.byType(CommunityLocalMessageTile),
            );
            expect(
              tile.source,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            gate.complete(
              const CommunityChatSendOutcome('rejected', error: 'rateLimited'),
            );
            await chatFrames(t);
            expect(model.localMessages.single.state, 'failed');
            expect(model.localMessages.single.intent, same(port.sends.single));
            expect(model.localMessages.single.error, 'rateLimited');
            expect(port.sends, hasLength(1));
          } finally {
            await t.pumpWidget(const SizedBox());
            model.dispose();
            await port.changes.close();
          }
        },
      );
    }

    testWidgets(
      '3fj $suite online members initial/read sources and owner replacement',
      (t) async {
        size(t, const Size(1000, 820));
        final port = WorkspaceTestPort(), replacement = WorkspaceTestPort();
        var current = port;
        var gate = Completer<CommunityWorkspace>();
        final calls = <InteractionSource>[];
        port.reader = (_, _, _) {
          calls.add(captureStarBridgeActivationSource()());
          return gate.future;
        };
        late StateSetter update;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, state) {
                update = state;
                return scopedApp(
                  Builder(
                    builder: (context) => starBridgeInitialReadViewport(
                      context,
                      source: InteractionSource.keyboard,
                      child: CommunityOnlineMembersPane(
                        port: current,
                        targetRef: 'a' * 32,
                        onAllMembers: () {},
                      ),
                    ),
                  ),
                  suite,
                );
              },
            ),
          );
          await chatFrames(t, 2);
          expect(find.byType(SocialReadActivity), findsOneWidget);
          expect(
            t
                .widget<SocialReadActivity>(find.byType(SocialReadActivity))
                .opening,
            isTrue,
          );
          gate.complete(CommunityWorkspace.parse(workspacePayload()));
          await chatFrames(t);
          gate = Completer<CommunityWorkspace>();
          await chatActivate(
            t,
            find.byKey(const Key('community-online-refresh')),
            'keyboard',
            '刷新',
          );
          expect(calls.last, InteractionSource.keyboard);
          expect(
            t
                .widget<SocialReadActivity>(find.byType(SocialReadActivity))
                .source,
            InteractionSource.keyboard,
          );
          update(() => current = replacement);
          await chatFrames(t);
          gate.completeError(const CommunityFailure('unavailable'));
          await chatFrames(t);
          expect(find.byType(SocialReadActivity), findsNothing);
          expect(find.text('示例成员'), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          await port.changes.close();
          await replacement.changes.close();
        }
      },
    );
  }
}
