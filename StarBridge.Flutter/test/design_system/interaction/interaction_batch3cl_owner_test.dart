import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../app/menu_overlay/menu_comms_compose_session_test.dart'
    show ComposePort, history;
import '../../app/menu_overlay/menu_comms_session_test.dart' show peer;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_test.dart' show fire;
import 'interaction_batch3cl_test.dart' show controller, draftField;

class Owner {
  final port = ComposePort();
  final view = ValueNotifier(const MenuCommsView('idle'));
  final calls = <(String, String, InteractionSource)>[];
  late final session = MenuCommsSession(
    port,
    (raw) => view.value = MenuCommsView.parse(jsonEncode(raw)),
  );
  Future<void> open(WidgetTester t, InteractionSuite suite) async {
    size(t, const Size(760, 900));
    session.show(true);
    port.directories.last.complete([peer('A'), peer('B')]);
    await t.pump();
    session.act('select', view.value.rows.first.key);
    port.histories.last.reply.complete(history());
    await t.pump();
    await t.pumpWidget(
      scopedApp(
        ValueListenableBuilder(
          valueListenable: view,
          builder: (_, value, _) => MenuCommsHistory(
            view: value,
            active: false,
            onAction: session.act,
            onCompose: (a, k, text, rev) {
              calls.add((a, k, currentStarBridgeActivationSource));
              session.compose(a, k, text, rev);
            },
          ),
        ),
        suite,
      ),
    );
    await t.pump();
  }

  Future<void> settleRead(
    WidgetTester t, {
    List<DirectMessage> messages = const [],
  }) async {
    if (!port.histories.last.reply.isCompleted) {
      port.histories.last.reply.complete(history(messages: messages));
    }
    await t.pump();
    await t.pump();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    session.dispose();
    for (final write in port.writes) {
      if (!write.reply.isCompleted) {
        write.reply.complete(const DirectSendResult('unknown'));
      }
    }
    await t.pump(const Duration(seconds: 16));
    view.dispose();
  }
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final outcome in [
        'sent',
        'request_sent',
        'duplicate',
        'rejected',
        'unknown',
        'mismatched',
      ]) {
        testWidgets(
          '$suite $source actual Session $outcome preserves exact outcome',
          (t) async {
            final semantics = t.ensureSemantics(), owner = Owner();
            try {
              await owner.open(t, suite);
              await t.enterText(draftField, ' 实际草稿 ');
              await t.pump();
              await fire(
                t,
                source,
                find.byKey(const ValueKey('menu-message-send')),
              );
              final write = owner.port.writes.single;
              expect((write.ref, write.text), ('secret-A', '实际草稿'));
              expect(
                owner.calls.last.$3,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(owner.view.value.delivery, 'sending');
              expect(find.byType(SuiteBusyFrame), findsOneWidget);
              expect(controller(t).text, ' 实际草稿 ');
              final message = DirectMessage(
                1,
                outcome == 'mismatched' ? 'wrong-id' : write.id,
                false,
                write.text,
                DateTime.utc(2026),
                null,
              );
              write.reply.complete(
                DirectSendResult(
                  outcome == 'mismatched' ? 'sent' : outcome,
                  message:
                      const {
                        'sent',
                        'request_sent',
                        'duplicate',
                        'mismatched',
                      }.contains(outcome)
                      ? message
                      : null,
                ),
              );
              await t.pump();
              await owner.settleRead(t);
              final expected = outcome == 'mismatched'
                  ? 'unknown'
                  : outcome == 'duplicate'
                  ? 'sent'
                  : outcome;
              expect(owner.view.value.delivery, expected);
              expect(
                controller(t).text,
                const {'sent', 'request_sent'}.contains(expected)
                    ? ''
                    : ' 实际草稿 ',
              );
              expect(owner.port.sends, 1);
              expect(find.byType(SuiteBusyFrame), findsNothing);
              if (expected == 'unknown') {
                expect(owner.view.value.locked, isTrue);
                await fire(
                  t,
                  source,
                  find.byKey(const ValueKey('menu-message-check')),
                );
                await owner.settleRead(
                  t,
                  messages: [
                    DirectMessage(
                      2,
                      write.id,
                      false,
                      write.text,
                      DateTime.utc(2026),
                      null,
                    ),
                  ],
                );
                expect(owner.view.value.delivery, 'sent');
                expect(controller(t).text, '');
                expect(owner.port.sends, 1);
              } else if (expected == 'rejected') {
                expect(owner.view.value.locked, isFalse);
                await fire(
                  t,
                  source,
                  find.byKey(const ValueKey('menu-message-send')),
                );
                expect(owner.port.sends, 2);
                owner.port.writes.last.reply.complete(
                  const DirectSendResult('rejected'),
                );
                await t.pump();
                await owner.settleRead(t);
                expect(controller(t).text, ' 实际草稿 ');
              }
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await owner.close(t);
            }
          },
        );
      }
    }
    for (final retire in ['hide', 'identity']) {
      testWidgets(
        '$suite $retire retires editor and ignores late result presentation',
        (t) async {
          final owner = Owner();
          try {
            await owner.open(t, suite);
            await t.enterText(draftField, 'old account draft');
            await t.pump();
            await fire(
              t,
              'pointer',
              find.byKey(const ValueKey('menu-message-send')),
            );
            final oldCompose = owner.calls.last.$2,
                write = owner.port.writes.single;
            if (retire == 'hide') {
              owner.session.show(false);
            } else {
              owner.port.events.add(null);
            }
            await t.pump();
            expect(draftField, findsNothing);
            write.reply.complete(
              DirectSendResult(
                'sent',
                message: DirectMessage(
                  1,
                  write.id,
                  false,
                  write.text,
                  DateTime.utc(2026),
                  null,
                ),
              ),
            );
            await t.pump();
            expect(find.text('已发送'), findsNothing);
            owner.session.compose('send', oldCompose, 'stale', 999);
            expect(owner.port.sends, 1);
          } finally {
            await owner.close(t);
          }
        },
      );
    }
  }
}
