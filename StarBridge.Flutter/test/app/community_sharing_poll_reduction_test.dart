import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

import '../features/settings/community_sharing_test.dart'
    show SharingFixture, target;
import 'community_sharing_flow_test.dart' show Harness;

class CountingSharingFixture extends SharingFixture {
  int targetReads = 0;
  int publicationReads = 0;
  Completer<CommunitySharingTargets>? targetGate;
  Completer<PrivacyPublicationView>? publicationGate;
  Duration? targetDelay;

  @override
  Future<CommunitySharingTargets> readCommunityTargets() {
    targetReads++;
    final gate = targetGate;
    targetGate = null;
    final delay = targetDelay;
    if (gate == null && delay != null) {
      return Future.delayed(delay, super.readCommunityTargets);
    }
    return gate?.future ?? super.readCommunityTargets();
  }

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
    bool firstOfficialDefault = false,
  }) {
    publicationReads++;
    final gate = publicationGate;
    publicationGate = null;
    return gate?.future ??
        super.publication(
          action,
          revision: revision,
          firstOfficialDefault: firstOfficialDefault,
        );
  }
}

void main() {
  for (final requestCount in [1, 4]) {
    testWidgets(
      'startup target read retains a membership event and $requestCount waiting requests',
      (tester) async {
        final port = CountingSharingFixture();
        final h = await Harness.create(tester, fixture: port);
        final oldTargets = CommunitySharingTargets(communities: [target('A')]);
        final newTargets = CommunitySharingTargets(
          communities: [target('A'), target('B')],
        );
        final gate = port.targetGate = Completer<CommunitySharingTargets>();
        final reread = Completer<CommunitySharingTargets>();
        var disposed = false;
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete(oldTargets);
          if (!reread.isCompleted) reread.complete(newTargets);
          if (!disposed) await h.dispose(tester);
        });
        final startup = h.controller.refresh();
        await tester.pump();
        expect(port.targetReads, 1);
        expect(port.publicationReads, 1);
        port.targetGate = reread;
        h.memberships.value++;
        await tester.pump(const Duration(milliseconds: 100));
        var completed = 0;
        final waiting = List.generate(
          requestCount,
          (_) =>
              h.controller.refreshCommunityTargets().then((_) => completed++),
        );
        await tester.pump();
        expect(port.targetReads, 1);
        expect(completed, 0);
        expect(
          port.publicationReads,
          1,
          reason: 'The membership poll must wait for fresh targets.',
        );
        gate.complete(oldTargets);
        await tester.pump();
        expect(port.targetReads, 2);
        expect(
          completed,
          0,
          reason: 'The supplementary read is still blocked.',
        );
        expect(port.publicationReads, 1);
        reread.complete(newTargets);
        await tester.pump();
        await startup;
        await Future.wait(waiting);
        expect(completed, requestCount);
        expect(h.controller.communityTargets!.communities.map((t) => t.code), [
          'A',
          'B',
        ]);
        expect(port.targetReads, 2, reason: 'Requests share one reread.');
        expect(port.publicationReads, 2);
        h.ready = false; // Keep the automatic choice dialog out of this test.
        await tester.pump(const Duration(seconds: 1));
        expect(port.targetReads, 2);
        expect(port.writes, 0);
        // The flow's 5-minute discovery timer must be gone before the binding checks timers.
        await h.dispose(tester);
        disposed = true;
      },
    );
  }

  for (final dispose in [false, true]) {
    testWidgets(
      'target read retires pending requests on ${dispose ? 'dispose' : 'account invalidation'}',
      (tester) async {
        final port = CountingSharingFixture();
        final h = await Harness.create(tester, fixture: port);
        final gate = port.targetGate = Completer<CommunitySharingTargets>();
        var disposed = false;
        addTearDown(() async {
          if (!gate.isCompleted) {
            gate.complete(CommunitySharingTargets(communities: []));
          }
          if (!disposed) await h.dispose(tester);
        });
        final startup = h.controller.refresh();
        await tester.pump();
        h.memberships.value++;
        await tester.pump(const Duration(milliseconds: 100));
        var completed = false;
        final waiting = h.controller.refreshCommunityTargets().then(
          (_) => completed = true,
        );
        await tester.pump();
        expect(completed, isFalse);
        final oldEpoch = h.controller.scopeEpoch;
        if (dispose) {
          await h.dispose(tester);
          disposed = true;
        } else {
          port.events.add(null);
          await tester.pump();
          expect(h.controller.scopeEpoch, isNot(oldEpoch));
          port.targets = CommunitySharingTargets(communities: [target('C')]);
          await h.controller.refresh();
          expect(port.targetReads, 2, reason: 'Only the new account is read.');
        }
        await tester.pump();
        expect(completed, isTrue, reason: 'Retired waiters are released.');
        gate.complete(CommunitySharingTargets(communities: [target('A')]));
        await tester.pump();
        await startup;
        await waiting;
        expect(port.targetReads, dispose ? 1 : 2);
        expect(
          h.controller.communityTargets?.communities.map((t) => t.code),
          dispose ? isNull : ['C'],
          reason: 'The retired snapshot cannot replace the new account.',
        );
        h.ready = false;
        await tester.pump(const Duration(seconds: 1));
        expect(port.targetReads, dispose ? 1 : 2);
        expect(port.writes, 0);
        if (!disposed) {
          await h.dispose(tester);
          disposed = true;
        }
      },
    );
  }

  for (final eventCount in [0, 1, 4]) {
    testWidgets(
      'publication in flight coalesces $eventCount membership events into one reread',
      (tester) async {
        final port = CountingSharingFixture();
        final h = await Harness.create(tester, fixture: port);
        port.targets = CommunitySharingTargets(
          primaryFleetCode: 'A',
          communities: [target('A')],
        );
        await h.controller.refresh();
        await h.settle(tester);
        final gate = port.publicationGate = Completer<PrivacyPublicationView>();
        await tester.pump(const Duration(minutes: 5));
        await tester.pump();
        expect(port.targetReads, 2);
        expect(port.publicationReads, 2);
        // The poll already read the old roster; only publication is blocked.
        port.targets = CommunitySharingTargets(communities: []);
        for (var i = 0; i < eventCount; i++) {
          h.memberships.value++;
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(port.targetReads, 2);
        gate.complete(const PrivacyPublicationView('applied'));
        await tester.pump();
        final expectedReads = eventCount == 0 ? 2 : 3;
        expect(port.targetReads, expectedReads);
        expect(port.publicationReads, expectedReads);
        expect(
          h.controller.communityTargets!.communities,
          eventCount == 0 ? hasLength(1) : isEmpty,
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          port.targetReads,
          expectedReads,
          reason: 'No queued extra rounds.',
        );
        expect(port.writes, 0);
        await h.dispose(tester);
      },
    );
  }

  testWidgets(
    'an in-flight event is remembered before its debounce would expire',
    (tester) async {
      final port = CountingSharingFixture();
      final h = await Harness.create(tester, fixture: port);
      port.targets = CommunitySharingTargets(communities: []);
      await h.controller.refresh();
      final gate = port.publicationGate = Completer<PrivacyPublicationView>();
      await tester.pump(const Duration(minutes: 5));
      await tester.pump();
      expect(port.publicationReads, 2);
      for (var i = 0; i < 4; i++) {
        h.memberships.value++;
      }
      gate.complete(const PrivacyPublicationView('applied'));
      await tester.pump();
      expect(
        port.targetReads,
        3,
        reason: 'Reread immediately when the round ends.',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        port.targetReads,
        3,
        reason: 'No leftover debounce adds another read.',
      );
      await h.dispose(tester);
    },
  );

  for (final newEvent in [false, true]) {
    testWidgets(
      'account invalidation clears old pending work; new event=$newEvent',
      (tester) async {
        final port = CountingSharingFixture();
        final h = await Harness.create(tester, fixture: port);
        port.targets = CommunitySharingTargets(communities: []);
        await h.controller.refresh();
        final gate = port.publicationGate = Completer<PrivacyPublicationView>();
        await tester.pump(const Duration(minutes: 5));
        await tester.pump();
        h.memberships.value++;
        await tester.pump(const Duration(milliseconds: 100));
        final oldEpoch = h.controller.scopeEpoch;
        port.events.add(null);
        await tester.pump();
        expect(h.controller.scopeEpoch, isNot(oldEpoch));
        await h.controller.refresh();
        expect(port.targetReads, 3, reason: 'Reconnect reads the new scope.');
        if (newEvent) {
          h.memberships.value++;
          await tester.pump(const Duration(milliseconds: 100));
        }
        gate.complete(const PrivacyPublicationView('applied'));
        await tester.pump();
        expect(port.targetReads, newEvent ? 4 : 3);
        await tester.pump(const Duration(seconds: 1));
        expect(port.targetReads, newEvent ? 4 : 3);
        expect(port.writes, 0);
        await h.dispose(tester);
      },
    );
  }

  testWidgets(
    'account invalidation cancels an old debounced membership event',
    (tester) async {
      final port = CountingSharingFixture();
      final h = await Harness.create(tester, fixture: port);
      port.targets = CommunitySharingTargets(communities: []);
      await h.controller.refresh();
      h.memberships.value++;
      port.events.add(null);
      await tester.pump();
      await h.controller.refresh();
      expect(port.targetReads, 2);
      await tester.pump(const Duration(milliseconds: 100));
      expect(port.targetReads, 2);
      await h.dispose(tester);
    },
  );

  testWidgets(
    'discovery reads once per five minutes and membership still wakes it',
    (tester) async {
      final port = CountingSharingFixture();
      final h = await Harness.create(tester, fixture: port);
      port.targets = CommunitySharingTargets(
        primaryFleetCode: 'A',
        communities: [target('A')],
      );
      await h.controller.refresh();
      await h.settle(tester);
      expect(port.targetReads, 1, reason: 'Startup still reads immediately.');
      for (var i = 0; i < 19; i++) {
        await tester.pump(const Duration(seconds: 15));
      }
      expect(port.targetReads, 1);
      await tester.pump(const Duration(seconds: 15));
      await tester.pump();
      expect(port.targetReads, 2);
      h.memberships.value++;
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(
        port.targetReads,
        3,
        reason: 'Membership events bypass the interval.',
      );
      expect(port.writes, 0, reason: 'Discovery never grants sharing.');
      await h.dispose(tester);
    },
  );

  testWidgets('reconnect and failed discovery do not reuse old memberships', (
    tester,
  ) async {
    final port = CountingSharingFixture();
    final h = await Harness.create(tester, fixture: port);
    port.targets = CommunitySharingTargets(
      primaryFleetCode: 'A',
      communities: [target('A')],
    );
    final release = h.controller.monitorPublication();
    await h.settle(tester);
    expect(port.targetReads, 1);
    port.events.add(null);
    await h.settle(tester);
    expect(
      port.targetReads,
      2,
      reason: 'Connection/account invalidation rereads immediately.',
    );
    port.failTargets = true;
    h.memberships.value++;
    await tester.pump(const Duration(milliseconds: 100));
    await h.settle(tester);
    expect(port.targetReads, 3);
    expect(h.controller.communityTargetsFailed, isTrue);
    expect(h.controller.unconfirmedCommunities, isEmpty);
    port.failTargets = false;
    h.memberships.value++;
    await tester.pump(const Duration(milliseconds: 100));
    await h.settle(tester);
    expect(port.targetReads, 4);
    expect(h.controller.communityTargetsFailed, isFalse);
    expect(port.writes, 0);
    release();
    await h.dispose(tester);
  });

  testWidgets(
    'editor refreshes during slow target reads cannot starve a waiter',
    (tester) async {
      final port = CountingSharingFixture()
        ..targetDelay = const Duration(seconds: 20);
      final h = await Harness.create(tester, fixture: port);
      h.ready = false; // Keep the automatic choice dialog out of this test.
      unawaited(h.controller.refresh());
      await tester.pump();
      expect(port.targetReads, 1);
      h.controller
          .open(); // Asks for targets every 15 seconds, shorter than a read.
      await tester.pump(const Duration(seconds: 1));
      var done = false;
      unawaited(
        h.controller.refreshCommunityTargets().then((_) => done = true),
      );
      for (var second = 1; second < 45 && !done; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(done, isTrue, reason: 'Released after its own follow-up round.');
      expect(port.targetReads, 3, reason: 'The editor queued a third round.');
      h.controller.closeEditor();
      await tester.pump(const Duration(seconds: 60));
      expect(port.targetReads, 3, reason: 'No round without a request.');
      await h.dispose(tester);
    },
  );
}
