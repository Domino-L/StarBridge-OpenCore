import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/direct_messages/example_direct_messages.dart';
import 'package:starbridge_flutter/features/friends/friend_action_controls.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/friends_test.dart' show PendingPort;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cz_actions_test.dart' show exposed, fire;
import 'interaction_batch3i_test.dart' show scopedApp;

const ref = '00000000000000000000000000000001';
const relationships = {
  'send': 'none',
  'accept': 'incoming',
  'reject': 'incoming',
  'cancel': 'outgoing',
  'remove': 'friend',
  'block': 'friend',
  'unblock': 'blocked',
};
FriendsSection sectionFor(String relation) => switch (relation) {
  'incoming' => FriendsSection.incoming,
  'outgoing' => FriendsSection.outgoing,
  'blocked' => FriendsSection.blocked,
  _ => FriendsSection.friends,
};
FriendRow subject(String action) => FriendRow(
  'Pilot',
  'Fixture',
  relationships[action]!,
  DateTime.utc(2026),
  targetRef: ref,
  chatTargetRef: ref,
  conversationKey: 'peer',
  actions: [action],
);
FriendsSnapshot snapshot(FriendRow row, {String? query}) => FriendsSnapshot(
  query: query,
  groups: {
    for (final s in FriendsSection.values)
      s: [if (query == null && s == sectionFor(row.relationship)) row],
  },
  results: [if (query != null) row],
);

class MotionCommandPort extends PendingPort implements FriendsCommandPort {
  final calls = <(String, String, InteractionSource)>[];
  final replies = <Completer<FriendCommandResult>>[];
  @override
  bool get commandsAvailable => true;
  @override
  Future<FriendCommandResult> execute(String action, String targetRef) {
    calls.add((action, targetRef, currentStarBridgeActivationSource));
    final pending = Completer<FriendCommandResult>();
    replies.add(pending);
    return pending.future;
  }
}

class Fixture {
  Fixture(this.action) : row = subject(action);
  final String action;
  final FriendRow row;
  final port = MotionCommandPort();
  late final owner = FriendsModule(port, now: () => DateTime.utc(2026));
  final alive = ValueNotifier(true);
  Future<void> mount(
    WidgetTester t,
    InteractionSuite suite, {
    bool page = false,
    bool separate = false,
    ValueChanged<String>? route,
  }) async {
    size(t, const Size(1400, 1000));
    if (action == 'send') owner.editQuery('Pilot');
    final read = owner.refresh();
    port.requests.last.complete(
      FriendsReadResult(
        FriendsReadState.ready,
        snapshot: snapshot(row, query: action == 'send' ? 'Pilot' : null),
      ),
    );
    await read;
    owner.select(sectionFor(row.relationship));
    // send is a directory search result, not a membership group.
    if (action == 'send') {
      owner.editQuery('Pilot');
      final search = owner.refresh();
      port.requests.last.complete(
        FriendsReadResult(
          FriendsReadState.ready,
          snapshot: snapshot(row, query: 'Pilot'),
        ),
      );
      await search;
    }
    final body = page
        ? Actions(
            actions: {
              OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                onInvoke: (intent) {
                  route?.call(intent.route);
                  return null;
                },
              ),
            },
            child: FriendsPage(
              createPort: () => throw StateError('borrowed'),
              module: owner,
              createChatPort: ExampleDirectMessages.new,
              separateMessages: separate,
            ),
          )
        : ListenableBuilder(
            listenable: owner,
            builder: (_, _) => Center(
              child: FriendActionControls(module: owner, row: row),
            ),
          );
    await t.pumpWidget(
      scopedApp(
        ValueListenableBuilder<bool>(
          valueListenable: alive,
          builder: (_, value, _) => value ? body : const SizedBox(),
        ),
        suite,
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    owner.dispose();
    alive.dispose();
  }

  String get key => 'friend-$action-$ref';
}

Future<void> hitRow(WidgetTester t, String input, String id) async {
  final target = find.byKey(Key(id));
  if (input != 'keyboard') return fire(t, input, id);
  final ink = find.descendant(of: target, matching: find.byType(InkWell));
  if (ink.evaluate().isNotEmpty &&
      t.widget<InkWell>(ink.first).focusNode != null) {
    t.widget<InkWell>(ink.first).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    return;
  }
  final focus = t
      .widget<FocusableActionDetector>(
        find
            .descendant(
              of: target,
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      )
      .focusNode!;
  focus.requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'local friend confirmation content follows live suite and reduce',
    (t) async {
      final h = Fixture('remove');
      final settings = ValueNotifier((InteractionSuite.rail, false));
      try {
        await h.mount(t, InteractionSuite.standard);
        await t.pumpWidget(
          scopedApp(
            ValueListenableBuilder<(InteractionSuite, bool)>(
              valueListenable: settings,
              builder: (_, value, _) => StarBridgeInteractionConfiguration(
                suite: value.$1,
                reduceMotion: value.$2,
                child: FriendActionControls(module: h.owner, row: h.row),
              ),
            ),
            InteractionSuite.standard,
          ),
        );
        await t.pumpAndSettle();
        await fire(t, 'pointer', h.key);
        await t.pumpAndSettle();
        InteractionData actual() => InteractionScope.of(
          t.element(find.byKey(const Key('friend-confirm-apply'))),
        );
        expect(actual().suite, InteractionSuite.rail);
        settings.value = (InteractionSuite.scan, true);
        await t.pump();
        await t.pump();
        expect(actual().suite, InteractionSuite.scan);
        expect(actual().reduceMotion, isTrue);
        settings.value = (InteractionSuite.glow, false);
        await t.pump();
        await t.pump();
        expect(actual().suite, InteractionSuite.glow);
        expect(actual().reduceMotion, isFalse);
        await fire(t, 'keyboard', 'friend-confirm-keep');
        await t.pumpAndSettle();
        expect(h.port.calls, isEmpty);
      } finally {
        await h.close(t);
        settings.dispose();
      }
    },
  );
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite actual avatar $input removal keeps awaited final source',
        (t) async {
          final sem = t.ensureSemantics();
          final h = Fixture('remove');
          try {
            await h.mount(t, suite, page: true);
            await hitRow(t, input, 'user-avatar-menu-anchor');
            await t.pumpAndSettle();
            final entry = find.byKey(
              const ValueKey<Object>(('avatar-custom', '删除好友', 0)),
            );
            expect(entry, findsOneWidget);
            if (input == 'pointer') {
              await t.tap(entry);
            } else if (input == 'keyboard') {
              final widget = t.widget(entry);
              final focus = widget is SuitePressable
                  ? widget.focusNode!
                  : (widget as MenuItemButton).focusNode!;
              focus.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              var node = t.getSemantics(entry);
              while (!node.getSemanticsData().hasAction(
                ui.SemanticsAction.tap,
              )) {
                node = node.parent!;
              }
              t.binding.performSemanticsAction(
                ui.SemanticsActionEvent(
                  type: ui.SemanticsAction.tap,
                  viewId: t.view.viewId,
                  nodeId: node.id,
                ),
              );
            }
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(h.port.calls, isEmpty);
            // Pointer-opening menus still permit a later keyboard/reader confirmation.
            await fire(t, 'reader', 'friend-confirm-apply');
            await t.pump();
            await t.pump(const Duration(milliseconds: 500));
            expect(h.port.calls, [('remove', ref, InteractionSource.keyboard)]);
            h.port.replies.single.complete(
              FriendCommandResult('accepted', directory: snapshot(h.row)),
            );
            await t.pumpAndSettle();
            expect(h.owner.feedback, 'success.remove');
          } finally {
            sem.dispose();
            await h.close(t);
          }
        },
      );
    }
    testWidgets(
      '$suite main busy navigation and refreshing message guards remain distinct',
      (t) async {
        final sem = t.ensureSemantics();
        final h = Fixture('remove');
        try {
          await h.mount(t, suite, page: true, separate: true);
          final refresh = h.owner.refresh(silent: true);
          await t.pump();
          await t.pump();
          expect(h.owner.reading, isTrue);
          expect(
            t
                .widget<StarBridgeActionButton>(
                  find.ancestor(
                    of: find.byKey(const Key('friend-message-0')),
                    matching: find.byType(StarBridgeActionButton),
                  ),
                )
                .onActivate,
            isNull,
          );
          expect(
            t
                .getSemantics(find.byKey(const Key('friend-message-0')))
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
          expect(
            exposed(
              t,
              'friends-nav-incoming',
            ).getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          h.port.requests.last.complete(
            FriendsReadResult(
              FriendsReadState.ready,
              snapshot: snapshot(h.row),
            ),
          );
          await refresh;
          await t.pumpAndSettle();
          await fire(t, 'pointer', h.key);
          await t.pumpAndSettle();
          await fire(t, 'pointer', 'friend-confirm-apply');
          await t.pump();
          await t.pump(const Duration(milliseconds: 500));
          final nav = find.byKey(const Key('friends-nav-incoming'));
          expect(
            t
                .widget<StarBridgeActionRow>(
                  find.ancestor(
                    of: nav,
                    matching: find.byType(StarBridgeActionRow),
                  ),
                )
                .onActivate,
            isNull,
          );
          expect(
            t
                .getSemantics(find.byKey(const Key('friend-message-0')))
                .getSemanticsData()
                .hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
          h.port.events.add(null);
          h.port.requests.last.complete(
            const FriendsReadResult(FriendsReadState.signedOut),
          );
          h.port.replies.single.complete(
            FriendCommandResult('accepted', directory: snapshot(h.row)),
          );
          await t.pumpAndSettle();
          expect(h.owner.state, FriendsReadState.signedOut);
          expect(h.owner.snapshot, isNull);
          expect(h.owner.feedback, isNull);
        } finally {
          sem.dispose();
          await h.close(t);
        }
      },
    );
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final action in relationships.keys) {
        testWidgets(
          '$suite $input $action waits for authority and retains source',
          (t) async {
            final semantics = t.ensureSemantics();
            final h = Fixture(action);
            try {
              await h.mount(t, suite);
              await fire(t, input, h.key);
              if (action == 'remove' || action == 'block') {
                await t.pumpAndSettle();
                expect(h.port.calls, isEmpty);
                expect(h.owner.busy, isFalse);
                await fire(t, input, 'friend-confirm-apply');
              }
              await t.pumpAndSettle();
              expect(h.port.calls, [
                (
                  action,
                  ref,
                  input == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              ]);
              expect(h.owner.rows.single, same(h.row));
              expect(h.owner.busy, isTrue);
              expect(h.owner.feedback, isNull);
              expect(
                exposed(
                  t,
                  h.key,
                ).getSemanticsData().hasAction(ui.SemanticsAction.tap),
                isFalse,
              );
              await h.owner.execute(h.row, action);
              expect(h.port.calls, hasLength(1));
              h.port.replies.single.complete(
                FriendCommandResult('accepted', directory: snapshot(h.row)),
              );
              await t.pumpAndSettle();
              expect(h.owner.feedback, 'success.$action');
              expect(h.owner.busy, isFalse);
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await h.close(t);
            }
          },
        );
      }
      testWidgets(
        '$suite $input main navigation remains usable during read and clears query',
        (t) async {
          final sem = t.ensureSemantics();
          final h = Fixture('remove');
          try {
            await h.mount(t, suite, page: true);
            final read = h.owner.refresh(silent: true);
            await t.pump();
            expect(h.owner.reading, isTrue);
            await hitRow(t, input, 'friends-nav-incoming');
            expect(h.owner.section, FriendsSection.incoming);
            h.port.requests.last.complete(
              FriendsReadResult(
                FriendsReadState.ready,
                snapshot: snapshot(h.row),
              ),
            );
            await read;
            await t.pumpAndSettle();
            await t.enterText(find.byType(TextField).first, 'Pilot');
            await t.pump();
            await hitRow(t, input, 'friends-nav-friends');
            expect(h.owner.query, isEmpty);
            expect(
              t
                  .widget<TextField>(find.byType(TextField).first)
                  .controller!
                  .text,
              isEmpty,
            );
            h.port.requests.last.complete(
              FriendsReadResult(
                FriendsReadState.ready,
                snapshot: snapshot(h.row),
              ),
            );
            await t.pumpAndSettle();
            expect(
              exposed(
                t,
                'friends-nav-friends',
              ).getSemanticsData().flagsCollection.isSelected,
              ui.Tristate.isTrue,
            );
            expect(t.takeException(), isNull);
          } finally {
            sem.dispose();
            await h.close(t);
          }
        },
      );
      testWidgets(
        '$suite $input message routes exact peer; recent does not replace it',
        (t) async {
          final sem = t.ensureSemantics();
          final h = Fixture('remove');
          final routes = <String>[];
          try {
            await h.mount(
              t,
              suite,
              page: true,
              separate: true,
              route: routes.add,
            );
            await fire(t, input, 'friend-message-0');
            expect(routes, ['/messages']);
            final request = h.owner.requestedConversation;
            expect(request!.ref, ref);
            expect(request.conversationKey, 'peer');
            await t.pumpAndSettle();
            await hitRow(t, input, 'friends-recent');
            expect(routes, ['/messages', '/messages']);
            expect(h.owner.requestedConversation, same(request));
            expect(h.port.calls, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            sem.dispose();
            await h.close(t);
          }
        },
      );
    }
    for (final opener in ['pointer', 'keyboard', 'reader']) {
      for (final closer in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $opener open $closer confirm supplies final source',
          (t) async {
            final sem = t.ensureSemantics();
            final h = Fixture('remove');
            try {
              await h.mount(t, suite);
              await fire(t, opener, h.key);
              await t.pumpAndSettle();
              await fire(t, closer, 'friend-confirm-apply');
              await t.pumpAndSettle();
              expect(
                h.port.calls.single.$3,
                closer == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              h.port.replies.single.complete(
                const FriendCommandResult('rejected', error: 'forbidden'),
              );
              await t.pumpAndSettle();
              expect(h.owner.feedback, 'forbidden');
              expect(h.owner.snapshot, isNull);
            } finally {
              sem.dispose();
              await h.close(t);
            }
          },
        );
      }
    }
    for (final cancel in [
      'pointer',
      'keyboard',
      'reader',
      'escape',
      'barrier',
    ]) {
      testWidgets(
        '$suite $cancel cancel preserves relation and sends nothing',
        (t) async {
          final sem = t.ensureSemantics();
          final h = Fixture('block');
          try {
            await h.mount(t, suite);
            await fire(t, 'pointer', h.key);
            await t.pumpAndSettle();
            if (cancel == 'escape') {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
            } else if (cancel == 'barrier') {
              await t.tapAt(const Offset(5, 5));
            } else {
              await fire(t, cancel, 'friend-confirm-keep');
            }
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(h.port.calls, isEmpty);
            expect(h.owner.rows.single, same(h.row));
            expect(h.owner.feedback, isNull);
          } finally {
            sem.dispose();
            await h.close(t);
          }
        },
      );
    }
    testWidgets(
      '$suite invalidation removes owned dialog but not unrelated top route',
      (t) async {
        final h = Fixture('remove');
        try {
          await h.mount(t, suite);
          await fire(t, 'pointer', h.key);
          await t.pumpAndSettle();
          final nav = Navigator.of(
            t.element(find.byType(AlertDialog)),
            rootNavigator: true,
          );
          unawaited(
            nav.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('unrelated-top')),
              ),
            ),
          );
          await t.pumpAndSettle();
          h.port.events.add(null);
          h.port.requests.last.complete(
            const FriendsReadResult(FriendsReadState.signedOut),
          );
          await t.pumpAndSettle();
          expect(find.text('unrelated-top'), findsOneWidget);
          nav.pop();
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(h.port.calls, isEmpty);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets('$suite refreshed references cannot confirm old row', (
      t,
    ) async {
      final sem = t.ensureSemantics();
      final h = Fixture('remove');
      try {
        await h.mount(t, suite);
        await fire(t, 'pointer', h.key);
        await t.pumpAndSettle();
        final refresh = h.owner.refresh(silent: true);
        h.port.requests.last.complete(
          FriendsReadResult(
            FriendsReadState.ready,
            snapshot: snapshot(subject('remove')),
          ),
        );
        await refresh;
        await t.pumpAndSettle();
        expect(
          exposed(
            t,
            'friend-confirm-apply',
          ).getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
        await fire(t, 'keyboard', 'friend-confirm-keep');
        await t.pumpAndSettle();
        expect(h.port.calls, isEmpty);
      } finally {
        sem.dispose();
        await h.close(t);
      }
    });
    testWidgets('$suite parent unmount retires approved command', (t) async {
      final h = Fixture('remove');
      try {
        await h.mount(t, suite);
        await fire(t, 'pointer', h.key);
        await t.pumpAndSettle();
        h.alive.value = false;
        await t.pump();
        await fire(t, 'keyboard', 'friend-confirm-apply');
        await t.pumpAndSettle();
        expect(h.port.calls, isEmpty);
      } finally {
        await h.close(t);
      }
    });
    for (final status in ['unknown', 'accepted']) {
      testWidgets('$suite $status without directory is not success', (t) async {
        final h = Fixture('accept');
        try {
          await h.mount(t, suite);
          await fire(t, 'pointer', h.key);
          await t.pumpAndSettle();
          h.port.replies.single.complete(FriendCommandResult(status));
          await t.pumpAndSettle();
          expect(h.owner.feedbackSuccess, isFalse);
          expect(h.owner.feedback, 'outcomeUnknown');
          expect(h.owner.snapshot, isNull);
        } finally {
          await h.close(t);
        }
      });
    }
  }
}
