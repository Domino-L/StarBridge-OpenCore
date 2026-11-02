import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/common/chat_room_invitation.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_page.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3am_test.dart' show action;

final a = Conversation('a' * 32, 'Peer A', '', DateTime.utc(2026), 2, 'friend');
final b = Conversation('b' * 32, 'Peer B', '', DateTime.utc(2026), 0, 'friend');
final request = Conversation(
  'c' * 32,
  'Request',
  '',
  DateTime.utc(2026),
  0,
  'request_incoming',
);

class Port implements DirectMessagesPort, DirectMessageSender {
  final events = StreamController<void>.broadcast(sync: true);
  final reads = <(String, int, int, InteractionSource)>[];
  final writes = <(String, String, String, InteractionSource)>[];
  int directories = 0;
  bool failDirectory = false, failHistory = false, allowed = true;
  Completer<DirectPage>? heldRead;
  Completer<DirectSendResult>? heldSend;
  DirectMessage? confirmed;
  String result = 'unknown';
  @override
  bool get supportsSending => true;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<List<Conversation>> directory() async {
    directories++;
    if (failDirectory) throw const DirectReadFailure('unavailable');
    return [a, b, request];
  }

  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    reads.add((ref, before, after, currentStarBridgeActivationSource));
    if (failHistory) throw const DirectReadFailure('unavailable');
    if (heldRead != null) return heldRead!.future;
    if (confirmed != null && before == 0) {
      final snapshot = [
        if (after == 0)
          for (final i in [11, 12])
            DirectMessage(
              i,
              '$ref-$i',
              true,
              'Original $i',
              DateTime.utc(2026),
              null,
            ),
        confirmed!,
      ];
      return DirectPage(
        ref,
        snapshot,
        snapshot.first.sequence,
        confirmed!.sequence,
        false,
        'friend',
        canSend: allowed,
      );
    }
    final sequences = before > 0
        ? [1, 2]
        : after > 0
        ? [13]
        : [11, 12];
    return DirectPage(
      ref,
      [
        for (final i in sequences)
          DirectMessage(
            i,
            '$ref-$i',
            true,
            'Original $i',
            DateTime.utc(2026),
            null,
          ),
      ],
      sequences.first,
      sequences.last,
      before == 0,
      'friend',
      canSend: allowed,
    );
  }

  @override
  Future<DirectSendResult> send(String ref, String text, String id) async {
    writes.add((ref, text, id, currentStarBridgeActivationSource));
    if (heldSend != null) return heldSend!.future;
    if (result == 'sent') {
      confirmed = DirectMessage(14, id, false, text, DateTime.utc(2026), null);
      return DirectSendResult('sent', message: confirmed);
    }
    return DirectSendResult(result);
  }

  @override
  void cancel() {}
  @override
  Future<void> close() async {
    if (!events.isClosed) await events.close();
  }
}

InteractionSource origin(String source) => source == 'pointer'
    ? InteractionSource.pointer
    : InteractionSource.keyboard;
Key conversation(Conversation row) => ValueKey(('chat-conversation', row.ref));
Widget page(
  DirectMessagesModule module, {
  VoidCallback? onBack,
  Future<void> Function(BuildContext, DirectMessagesModule)? sendInvite,
}) => DirectMessagesPage(
  createPort: () => module.port,
  sharedModule: module,
  onBack: onBack ?? () {},
  sendCommunityInvite: sendInvite,
);
Future<DirectMessagesModule> moduleFor(Port port, {bool open = false}) async {
  final module = DirectMessagesModule(port);
  await module.refresh();
  if (open) await module.open(module.rows.first);
  return module;
}

Future<void> disposePage(WidgetTester t, DirectMessagesModule module) async {
  await t.pumpWidget(const SizedBox());
  module.dispose();
}

StarBridgeDialogRoute route(WidgetTester t) =>
    ModalRoute.of(t.element(find.byType(AlertDialog)))!
        as StarBridgeDialogRoute;

Future<void> sendFrom(WidgetTester t, String source) async {
  final target = find.text('发送');
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    Focus.of(t.element(target)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final outcome in ['sent', 'unknown', 'rejected']) {
        testWidgets(
          'actual send remains single and accurate through $outcome $suite $source',
          (t) async {
            final semantics = t.ensureSemantics(),
                p = Port(),
                m = await moduleFor(p, open: true);
            p.heldSend = Completer<DirectSendResult>();
            try {
              await mount(t, page(m), suite);
              await t.enterText(
                find.byType(TextFormField),
                '  Original message  ',
              );
              await t.pump();
              await sendFrom(t, source);
              expect(p.writes, hasLength(1));
              expect(p.writes.single.$1, a.ref);
              expect(p.writes.single.$2, 'Original message');
              expect(p.writes.single.$3, matches(RegExp(r'^[0-9a-f]{32}$')));
              expect(p.writes.single.$4, origin(source));
              // A2 (2026-10-21): the message is listed at once and the
              // composer is free for the next one while this one sends.
              expect(m.draft, isEmpty);
              expect(m.outgoing.single.text, 'Original message');
              expect(
                t.widget<TextFormField>(find.byType(TextFormField)).enabled,
                isNot(false),
              );
              final sent = p.writes.single;
              if (outcome == 'sent') {
                p.confirmed = DirectMessage(
                  14,
                  sent.$3,
                  false,
                  sent.$2,
                  DateTime.utc(2026),
                  null,
                );
              }
              p.heldSend!.complete(
                DirectSendResult(outcome, message: p.confirmed),
              );
              await t.pumpAndSettle();
              expect(p.writes, hasLength(1));
              expect(m.draft, isEmpty);
              if (outcome == 'sent') {
                expect(
                  m.messages.any((x) => x.id == sent.$3 && x.text == sent.$2),
                  true,
                );
                expect(m.outgoing, isEmpty, reason: 'history replaced it');
              } else {
                // Uncertain: still queued for a same-id retry, text kept.
                expect(m.outgoing.single.text, 'Original message');
              }
              expect(t.takeException(), isNull);
            } finally {
              await disposePage(t, m);
              semantics.dispose();
            }
          },
        );
      }
      testWidgets(
        'directory selection, draft keep/discard and accurate source $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              p = Port(),
              m = await moduleFor(p);
          try {
            await mount(t, page(m), suite);
            await action(t, conversation(a), source);
            expect(m.selected?.ref, a.ref);
            expect(p.reads, contains((a.ref, 0, 0, origin(source))));
            await t.enterText(
              find.byType(TextFormField),
              'Private original draft',
            );
            await action(t, conversation(b), source);
            expect(route(t).instant, source != 'pointer');
            await action(t, const ValueKey('chat-leave-keep'), source);
            expect(m.selected?.ref, a.ref);
            expect(m.draft, 'Private original draft');
            await action(t, conversation(b), source);
            await action(t, const ValueKey('chat-leave-discard'), source);
            expect(m.selected?.ref, b.ref);
            expect(m.draft, isEmpty);
            expect(p.reads, contains((b.ref, 0, 0, origin(source))));
            expect(p.writes, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await disposePage(t, m);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'history newer older latest preserve original cursor and feedback $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              p = Port(),
              m = await moduleFor(p, open: true);
          try {
            await mount(t, page(m), suite);
            await action(t, const ValueKey('chat-refresh-history'), source);
            expect(p.reads.last, (a.ref, 0, 12, origin(source)));
            expect(m.messages.map((x) => x.sequence), [11, 12, 13]);
            await action(t, const ValueKey('chat-older'), source);
            expect(p.reads.last, (a.ref, 11, 0, origin(source)));
            expect(m.messages.map((x) => x.sequence), [1, 2, 11, 12, 13]);
            await action(t, const ValueKey('chat-latest'), source);
            expect(p.reads, contains((a.ref, 0, 0, origin(source))));
            expect(p.writes, isEmpty);
          } finally {
            await disposePage(t, m);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'filter draft guard, native search and back callback $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              p = Port(),
              m = await moduleFor(p, open: true);
          var back = 0;
          try {
            await mount(t, page(m, onBack: () => back++), suite);
            await t.enterText(find.byType(TextFormField), 'Keep me');
            await action(
              t,
              const ValueKey('direct-messages-filter-true'),
              source,
            );
            expect(route(t).instant, source != 'pointer');
            await action(t, const ValueKey('chat-leave-keep'), source);
            expect(m.requests, false);
            await action(
              t,
              const ValueKey('direct-messages-filter-true'),
              source,
            );
            await action(t, const ValueKey('chat-leave-discard'), source);
            expect(m.requests, true);
            expect(m.selected, isNull);
            await t.enterText(
              find.byKey(const ValueKey('chat-search')),
              '  REQUEST  ',
            );
            await t.pump();
            expect(find.text('Request'), findsOneWidget);
            expect(find.text('Peer A'), findsNothing);
            await action(t, const ValueKey('chat-back-friends'), source);
            expect(back, 1);
            expect(p.writes, isEmpty);
          } finally {
            await disposePage(t, m);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'invitation callback keeps source and original module $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(),
              p = Port(),
              m = await moduleFor(p, open: true);
          DirectMessagesModule? called;
          InteractionSource? from;
          try {
            await mount(
              t,
              page(
                m,
                sendInvite: (context, module) async {
                  called = module;
                  from = currentStarBridgeActivationSource;
                  await showStarBridgeDialog<void>(
                    context,
                    builder: (context) => AlertDialog(
                      title: const Text('Original invitation'),
                      actions: [
                        StarBridgeActionButton(
                          controlKey: const ValueKey('preview-close'),
                          onActivate: (source) =>
                              dismissStarBridgeDialog(context, source: source),
                          child: const Text('Close preview'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              suite,
            );
            await action(
              t,
              const ValueKey('chat-send-organization-invitation'),
              source,
            );
            expect(identical(called, m), true);
            expect(from, origin(source));
            expect(route(t).instant, source != 'pointer');
            await action(t, const ValueKey('preview-close'), source);
            expect(p.writes, isEmpty);
          } finally {
            await disposePage(t, m);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'room invitation uses exact existing destination, even expired $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          String? destination;
          InteractionSource? from;
          try {
            await mount(
              t,
              Actions(
                actions: {
                  OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                    onInvoke: (intent) {
                      destination = intent.route;
                      from = currentStarBridgeActivationSource;
                      return null;
                    },
                  ),
                },
                child: ChatRoomInvitationCard(
                  value: ChatRoomInvitation(
                    'Original room',
                    'Original summary',
                    'fixture-invitation',
                    DateTime.utc(2000),
                  ),
                ),
              ),
              suite,
              width: 400,
            );
            await action(
              t,
              const ValueKey('chat-room-invitation-open'),
              source,
            );
            expect(
              destination,
              '/rooms/invitations?invitation=fixture-invitation',
            );
            expect(from, origin(source));
            expect(find.text('邀请已过期。'), findsOneWidget);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
    for (final departure in ['caller', 'account', 'selection']) {
      testWidgets(
        'pending leave route retires only its caller on $departure $suite',
        (t) async {
          final p = Port(), m = await moduleFor(p, open: true);
          try {
            final live = await mount(t, page(m), suite);
            m.editDraft('Sensitive old draft');
            await t.pump();
            await action(t, conversation(b), 'pointer');
            final old = route(t);
            if (departure == 'caller') {
              live.change(() => live.visible = false);
            } else if (departure == 'account') {
              p.events.add(null);
            } else {
              await m.open(m.rows.lastWhere((x) => x.ref == b.ref));
            }
            await t.pump();
            await t.pump();
            await t.pumpAndSettle();
            expect(old.isActive, false);
            expect(find.byType(AlertDialog), findsNothing);
            expect(p.writes, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await disposePage(t, m);
          }
        },
      );
    }
    testWidgets(
      'unrelated top route survives invalidated draft confirmation $suite',
      (t) async {
        final p = Port(), m = await moduleFor(p, open: true);
        try {
          await mount(t, page(m), suite);
          m.editDraft('Private');
          await t.pump();
          await action(t, conversation(b), 'pointer');
          final own = route(t), context = t.element(find.byType(AlertDialog));
          StarBridgeDialogRoute<void>? unrelated;
          unawaited(
            showStarBridgeDialog<void>(
              context,
              onRouteCreated: (value) => unrelated = value,
              builder: (_) => const AlertDialog(title: Text('Unrelated route')),
            ),
          );
          await t.pumpAndSettle();
          p.events.add(null);
          await t.pump();
          await t.pump();
          await t.pumpAndSettle();
          expect(own.isActive, false);
          expect(unrelated!.isActive, true);
          expect(find.text('Unrelated route'), findsOneWidget);
          expect(p.writes, isEmpty);
          unrelated!.navigator!.removeRoute(unrelated!);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        } finally {
          await disposePage(t, m);
        }
      },
    );
    testWidgets(
      'late sending acknowledgement after account invalidation cannot restore old UI $suite',
      (t) async {
        final p = Port(), m = await moduleFor(p, open: true);
        p.heldSend = Completer<DirectSendResult>();
        try {
          await mount(t, page(m), suite);
          await t.enterText(find.byType(TextFormField), 'Sensitive outgoing');
          await t.pump();
          await sendFrom(t, 'pointer');
          final sent = p.writes.single;
          p.events.add(null);
          await t.pump();
          await t.pump();
          p.heldSend!.complete(
            DirectSendResult(
              'sent',
              message: DirectMessage(
                14,
                sent.$3,
                false,
                sent.$2,
                DateTime.utc(2026),
                null,
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(m.selected, isNull);
          expect(m.draft, isEmpty);
          expect(m.messages, isEmpty);
          expect(m.sendStatus, isNull);
          expect(p.writes, hasLength(1));
          expect(find.text('Sensitive outgoing'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await disposePage(t, m);
        }
      },
    );
    testWidgets(
      'room invitation without destination handler is not actionable $suite',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          await mount(
            t,
            ChatRoomInvitationCard(
              value: ChatRoomInvitation(
                'Original room',
                'Summary',
                'fixture-invitation',
                DateTime.utc(2099),
              ),
            ),
            suite,
            width: 400,
          );
          final node = t.getSemantics(
            find.byKey(const ValueKey('chat-room-invitation-open')),
          );
          expect(node.getSemanticsData().hasAction(SemanticsAction.tap), false);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
    testWidgets(
      'an uncertain message stays queued for its own conversation $suite',
      (t) async {
        final p = Port(), m = await moduleFor(p, open: true);
        try {
          await mount(t, page(m), suite);
          m.editDraft('Uncertain text');
          await m.send();
          await t.pumpAndSettle();
          expect(p.writes, hasLength(1));
          expect(m.outgoing.single.text, 'Uncertain text');
          expect(m.draft, isEmpty);
          // A2: nothing to keep or discard; the queued message is not a draft.
          await action(t, conversation(b), 'pointer');
          expect(find.byType(AlertDialog), findsNothing);
          expect(m.selected?.ref, b.ref);
          expect(m.outgoing, isEmpty, reason: 'only its own conversation');
          expect(m.outbox.forConversation(a).single.text, 'Uncertain text');
          expect(p.writes, hasLength(1));
        } finally {
          await disposePage(t, m);
        }
      },
    );
    testWidgets(
      'history failure keeps visible contents and explicit retry $suite',
      (t) async {
        final p = Port(), m = await moduleFor(p, open: true);
        try {
          await mount(t, page(m), suite);
          p.failHistory = true;
          await action(t, const ValueKey('chat-refresh-history'), 'pointer');
          expect(m.error, 'unavailable');
          expect(m.messages.map((x) => x.text), ['Original 11', 'Original 12']);
          p.failHistory = false;
          await action(t, const ValueKey('chat-refresh-history'), 'keyboard');
          expect(m.error, isNull);
          expect(m.messages.last.sequence, 13);
          expect(p.writes, isEmpty);
        } finally {
          await disposePage(t, m);
        }
      },
    );
    testWidgets(
      'narrow layout, live reduce and theme during draft confirmation $suite',
      (t) async {
        final p = Port(), m = await moduleFor(p, open: true);
        try {
          final live = await mount(t, page(m), suite, width: 390);
          m.editDraft('Draft');
          await t.pump();
          await action(
            t,
            const ValueKey('chat-back-list'),
            'pointer',
            settle: false,
          );
          final dialog = route(t);
          live.change(() {
            live.reduce = true;
            live.light = true;
          });
          await t.pump();
          await t.pump();
          expect(dialog.animation!.value, 1);
          await action(t, const ValueKey('chat-leave-keep'), 'keyboard');
          expect(m.selected?.ref, a.ref);
          expect(m.draft, 'Draft');
          await action(t, const ValueKey('chat-back-list'), 'keyboard');
          expect(route(t).instant, true);
          await action(t, const ValueKey('chat-leave-discard'), 'keyboard');
          expect(m.selected, isNull);
          expect(t.takeException(), isNull);
        } finally {
          await disposePage(t, m);
        }
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('render actual private history and draft confirmation $suite', (
      t,
    ) async {
      final p = Port(),
          m = await moduleFor(p, open: true),
          capture = GlobalKey();
      try {
        await mount(t, page(m), suite, capture: capture);
        final directory = Directory('build/reviews/interaction-batch3aq');
        await t.runAsync(() => directory.create(recursive: true));
        for (final state in ['history', 'leave']) {
          if (state == 'leave') {
            m.editDraft('Original draft');
            await t.pump();
            await action(t, conversation(b), 'pointer');
          }
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ImageByteFormat.png);
            image.dispose();
            await File('${directory.path}/${suite.name}-$state.png')
                .writeAsBytes(data!.buffer.asUint8List());
          });
          expect(t.takeException(), isNull);
        }
      } finally {
        await disposePage(t, m);
      }
    });
  }
}
