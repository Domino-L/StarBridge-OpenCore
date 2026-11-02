import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_module.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3aq_test.dart'
    show
        Port,
        moduleFor,
        page,
        sendFrom,
        conversation,
        a,
        b,
        origin,
        disposePage;
import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3am_test.dart' show action;
import '../../features/friends/social_layout_test.dart' show loadFonts;

// Real held-send regressions using the original actual send and action chain.
// No feedback, payload or owner behavior is changed to make settling possible.
Future<void> _frames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite sent held receipt does not block settle false real conversation click helper',
      (t) async {
        final p = Port();
        final m = await moduleFor(p, open: true);
        final held = Completer<DirectSendResult>();
        p.heldSend = held;
        Timer? watchdog;
        var releasedForUnwind = false;
        void acknowledge() {
          if (held.isCompleted) {
            return;
          }
          final sent = p.writes.single;
          p.confirmed = DirectMessage(
            14,
            sent.$3,
            false,
            sent.$2,
            DateTime.utc(2026),
            null,
          );
          held.complete(DirectSendResult('sent', message: p.confirmed));
        }

        try {
          await mount(t, page(m), suite);
          await t.enterText(find.byType(TextFormField), '  Original message  ');
          await t.pump();
          await sendFrom(t, 'pointer');
          expect(p.writes, hasLength(1));
          expect(p.writes.single.$1, a.ref);
          expect(p.writes.single.$2, 'Original message');
          expect(p.writes.single.$3, matches(RegExp(r'^[0-9a-f]{32}$')));
          expect(p.writes.single.$4, origin('pointer'));
          // A2 (2026-10-21): listed at once, composer free, nothing blocks.
          expect(m.outgoing.single.text, 'Original message');
          expect(m.draft, isEmpty);
          expect(held.isCompleted, isFalse);

          // A fake-clock watchdog only releases the transport to unwind an old
          // helper's still-running pumpAndSettle without leaving a concurrent
          // guarded pump Future behind. Firing is itself a hard test failure;
          // it can never stand in for a successful held-send assertion.
          watchdog = Timer(const Duration(seconds: 2), () {
            releasedForUnwind = true;
            acknowledge();
          });
          await action(t, conversation(b), 'pointer', settle: false);
          watchdog.cancel();
          expect(
            releasedForUnwind,
            isFalse,
            reason:
                'settle:false must return while the real send receipt is held; '
                'the watchdog released it only to unwind a stuck pre-action settle.',
          );
          expect(held.isCompleted, isFalse);
          expect(find.byType(AlertDialog), findsNothing);
          expect(m.selected?.ref, b.ref, reason: 'a held send no longer pins');
          expect(p.writes, hasLength(1));
          final sent = p.writes.single;

          // Preserve the original explicit receipt and outcome checks in full.
          // A bounded helper must not need an early ack to reach these lines.
          acknowledge();
          await _frames(t);
          expect(p.writes, hasLength(1));
          expect(m.draft, '');
          // Delivered: nothing of it is left sending or failed (the fixture's
          // history may already have returned it and dropped the local copy).
          expect(
            m.outbox
                .forConversation(a)
                .where((o) => o.state != DirectOutgoingState.confirmed),
            isEmpty,
          );
          expect(sent.$2, 'Original message');
          expect(m.selected?.ref, b.ref);
          expect(t.takeException(), isNull);
        } finally {
          watchdog?.cancel();
          if (!held.isCompleted && p.writes.isNotEmpty) {
            acknowledge();
            await _frames(t);
          }
          await disposePage(t, m);
          await t.runAsync(() async {
            await Future<void>.delayed(Duration.zero);
          });
        }
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  }
}
