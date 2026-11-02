import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_operation_motion.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/features/friends/friends_waiting_indicator.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/friends_test.dart' show PendingPort, ready;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3dc_actions_test.dart' show Fixture, snapshot;
import 'interaction_batch3db_actions_test.dart' show SearchFixture;
import 'interaction_batch3i_test.dart' show scopedApp;

FriendsWaitingIndicator indicator(WidgetTester t, String id) =>
    t.widget<FriendsWaitingIndicator>(
      find.ancestor(
        of: find.byKey(Key(id)),
        matching: find.byType(FriendsWaitingIndicator),
      ),
    );
InteractionSource sourceFor(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;
Future<void> pendingFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

class ActivityPort extends PendingPort implements FriendsActivityPort {
  final updates = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get changes => updates.stream;
  @override
  Future<void> close() async {
    await updates.close();
    await super.close();
  }
}

void main() {
  setUpAll(loadFonts);
  test('presentation binding shares pending source, retires at idle, and never owns requests', () async {
    final port = PendingPort();
    final owner = FriendsModule(port);
    final first = FriendsOperationMotion.retain(owner);
    final second = FriendsOperationMotion.retain(owner);
    expect(second, same(first));
    final read = runStarBridgeSynchronousActivation(
      InteractionSource.keyboard,
      owner.refresh,
    );
    expect(first.readSource, InteractionSource.keyboard);
    // No-op background read must neither replace source nor dispatch again.
    await owner.refresh(silent: true);
    expect(port.requests, hasLength(1));
    first.release();
    second.release();
    final reopened = FriendsOperationMotion.retain(owner);
    expect(reopened, same(first));
    expect(reopened.readSource, InteractionSource.keyboard);
    reopened.release();
    port.requests.single.complete(ready('Done'));
    await read;
    final fresh = FriendsOperationMotion.retain(owner);
    expect(fresh, isNot(same(first)));
    expect(fresh.readSource, InteractionSource.programmatic);
    fresh.release();
    owner.dispose();
  });
  test(
    'first attachment cannot invent origin for existing pending owner',
    () async {
      final port = PendingPort();
      final owner = FriendsModule(port);
      final read = runStarBridgeSynchronousActivation(
        InteractionSource.keyboard,
        owner.refresh,
      );
      final motion = FriendsOperationMotion.retain(owner);
      expect(motion.readSource, InteractionSource.programmatic);
      port.requests.single.complete(ready('Done'));
      await read;
      motion.release();
      owner.dispose();
    },
  );
  test(
    'owned pending disposal retires binding without waiting for a notification',
    () async {
      final port = PendingPort();
      final owner = FriendsModule(port);
      final old = FriendsOperationMotion.retain(owner);
      final read = owner.refresh();
      old.release(ownerDisposing: true);
      final replacement = FriendsOperationMotion.retain(owner);
      expect(replacement, isNot(same(old)));
      replacement.release(ownerDisposing: true);
      owner.dispose();
      port.requests.single.complete(ready('Late'));
      await read;
      expect(port.closed, isTrue);
    },
  );
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      for (final action in ['search', 'refresh', 'clear-query', 'retry']) {
        testWidgets(
          '$suite $input $action wait source survives void callback lease',
          (t) async {
            final h = SearchFixture();
            final sem = t.ensureSemantics();
            try {
              await h.mount(t, suite);
              if (action != 'refresh') {
                await t.enterText(h.input, 'Pilot');
                await t.pump();
              }
              if (action == 'retry') {
                final failed = h.owner.refresh();
                h.port.requests.last.complete(
                  const FriendsReadResult(FriendsReadState.unavailable),
                );
                await failed;
                await t.pumpAndSettle();
              }
              final before = h.port.requests.length;
              await fire(t, input, 'friends-$action');
              await pendingFrames(t);
              final id = action == 'refresh'
                  ? 'friends-syncing'
                  : 'friends-initial-wait';
              expect(indicator(t, id).source, sourceFor(input));
              expect(
                find.byType(SuiteProgressBar),
                input == 'pointer' ? findsOneWidget : findsNothing,
              );
              expect(h.port.requests, hasLength(before + 1));
              expect(h.owner.feedbackSuccess, isFalse);
              h.port.requests.last.complete(
                ready(
                  'Confirmed',
                  query: action == 'search' || action == 'retry'
                      ? 'Pilot'
                      : null,
                ),
              );
              await t.pumpAndSettle();
              expect(find.byKey(Key(id)), findsNothing);
              expect(h.owner.rows.single.callsign, 'Confirmed');
            } finally {
              sem.dispose();
              await h.close(t);
            }
          },
        );
      }
      testWidgets(
        '$suite $input navigation opening carries initial read provenance',
        (t) async {
          size(t, const Size(1400, 1000));
          final port = PendingPort();
          final owner = FriendsModule(port);
          try {
            final inherited = sourceFor(input);
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) => starBridgeInitialReadViewport(
                    context,
                    source: inherited,
                    child: FriendsPage(
                      createPort: () => throw StateError('borrowed'),
                      module: owner,
                    ),
                  ),
                ),
                suite,
              ),
            );
            await pendingFrames(t);
            expect(indicator(t, 'friends-initial-wait').source, inherited);
            expect(
              find.byType(SuiteProgressBar),
              input == 'pointer' ? findsOneWidget : findsNothing,
            );
            port.requests.single.complete(ready('Confirmed'));
            await t.pumpAndSettle();
          } finally {
            await t.pumpWidget(const SizedBox());
            owner.dispose();
          }
        },
      );
      for (final outcome in ['accepted', 'rejected', 'unknown']) {
        testWidgets(
          '$suite $input confirm $outcome waits without claiming success',
          (t) async {
            final h = Fixture('remove');
            final sem = t.ensureSemantics();
            try {
              await h.mount(t, suite, page: true);
              await fire(t, 'pointer', h.key);
              await t.pumpAndSettle();
              expect(
                find.byKey(const Key('friends-command-wait')),
                findsNothing,
              );
              await fire(t, input, 'friend-confirm-apply');
              await pendingFrames(t);
              expect(
                indicator(t, 'friends-command-wait').source,
                sourceFor(input),
              );
              expect(
                find.byType(SuiteProgressBar),
                input == 'pointer' ? findsOneWidget : findsNothing,
              );
              expect(h.owner.rows.single, same(h.row));
              expect(h.owner.feedback, isNull);
              expect(h.port.calls, hasLength(1));
              h.port.replies.single.complete(
                FriendCommandResult(
                  outcome,
                  directory: outcome == 'accepted' ? snapshot(h.row) : null,
                ),
              );
              await t.pumpAndSettle();
              expect(
                find.byKey(const Key('friends-command-wait')),
                findsNothing,
              );
              expect(h.owner.feedbackSuccess, outcome == 'accepted');
            } finally {
              sem.dispose();
              await h.close(t);
            }
          },
        );
      }
    }
    testWidgets(
      '$suite active read completion drains pending activity as programmatic',
      (t) async {
        size(t, const Size(1400, 1000));
        final port = ActivityPort();
        final owner = FriendsModule(port, now: () => DateTime.utc(2026));
        final first = owner.enter();
        port.requests.single.complete(ready('Old'));
        await first;
        try {
          await t.pumpWidget(
            scopedApp(
              FriendsPage(
                createPort: () => throw StateError('borrowed'),
                module: owner,
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final active = runStarBridgeActivation<void>(
            InteractionSource.pointer,
            () => owner.refresh(),
          );
          await pendingFrames(t);
          expect(
            indicator(t, 'friends-syncing').source,
            InteractionSource.pointer,
          );
          port.updates.add(null);
          expect(port.requests, hasLength(2));
          port.requests[1].complete(ready('Middle'));
          await active;
          await pendingFrames(t);
          expect(port.requests, hasLength(3));
          expect(
            indicator(t, 'friends-syncing').source,
            InteractionSource.programmatic,
          );
          expect(owner.rows.single.callsign, 'Middle');
          port.requests.last.complete(ready('Latest'));
          await t.pumpAndSettle();
          expect(owner.rows.single.callsign, 'Latest');
        } finally {
          await t.pumpWidget(const SizedBox());
          owner.dispose();
        }
      },
    );
    testWidgets(
      '$suite leaving pending keyboard refresh and reopening preserves its source',
      (t) async {
        final h = SearchFixture();
        try {
          await h.mount(t, suite);
          await fire(t, 'keyboard', 'friends-refresh');
          await pendingFrames(t);
          await t.pumpWidget(scopedApp(const SizedBox(), suite));
          await t.pump();
          await t.pumpWidget(h.page(suite));
          await pendingFrames(t);
          expect(h.port.requests, hasLength(2));
          expect(
            indicator(t, 'friends-syncing').source,
            InteractionSource.keyboard,
          );
          expect(find.byType(SuiteProgressBar), findsNothing);
          h.port.requests.last.complete(ready('Late confirmed'));
          await t.pumpAndSettle();
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite account invalidation clears old waiting origin and late receipt',
      (t) async {
        final h = SearchFixture();
        try {
          await h.mount(t, suite);
          await fire(t, 'keyboard', 'friends-refresh');
          await pendingFrames(t);
          final old = h.port.requests.last;
          h.port.events.add(null);
          await pendingFrames(t);
          expect(
            indicator(t, 'friends-initial-wait').source,
            InteractionSource.programmatic,
          );
          old.complete(ready('Old account'));
          await t.pump();
          expect(h.owner.snapshot, isNull);
          h.port.requests.last.complete(
            const FriendsReadResult(FriendsReadState.signedOut),
          );
          await t.pumpAndSettle();
          expect(find.byType(FriendsWaitingIndicator), findsNothing);
        } finally {
          await h.close(t);
        }
      },
    );
    testWidgets(
      '$suite transient failure retains data/time and retry enters a new wait',
      (t) async {
        final h = SearchFixture();
        try {
          await h.mount(t, suite);
          await fire(t, 'keyboard', 'friends-refresh');
          await pendingFrames(t);
          h.port.requests.last.completeError(
            TimeoutException('offline fixture'),
          );
          await t.pumpAndSettle();
          expect(find.byKey(const Key('friends-sync-failed')), findsOneWidget);
          expect(h.owner.rows.single.callsign, '初始好友');
          expect(find.byType(FriendsWaitingIndicator), findsNothing);
          await fire(t, 'pointer', 'friends-refresh');
          await pendingFrames(t);
          expect(
            indicator(t, 'friends-syncing').source,
            InteractionSource.pointer,
          );
          h.port.requests.last.complete(ready('Recovered'));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('friends-sync-failed')), findsNothing);
        } finally {
          await h.close(t);
        }
      },
    );
  }
}
