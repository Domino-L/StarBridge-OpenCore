import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';

void main() {
  test(
    'invalid searches cannot replace or dispatch the current query',
    () async {
      final port = _RecordingMembersPort();
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      await module.open('officialFleet:7');
      final memberRef = module.projection.value.members.first.memberRef;
      module.selectMember(memberRef);
      module.rememberScrollOffset(280);
      for (final invalid in [
        'x' * 129,
        '🚀' * 65,
        'bad\u0000query',
        'bad\u0085query',
      ]) {
        await module.search(invalid);
        expect(port.queries, hasLength(1));
        expect(module.projection.value.query?.search, '');
        expect(module.selectedMemberRef.value, memberRef);
        expect(module.scrollOffset, 280);
      }
      await module.search('x' * 128);
      expect(port.queries.last.search, 'x' * 128);
      await module.search('');
      expect(module.projection.value.members, isNotEmpty);
    },
  );

  test(
    'preserves member context on return, clears it for a new viewer',
    () async {
      final module = createOfficialFleetMembersModule(
        InMemoryOfficialFleetMembersAdapter.forReview(),
      );
      addTearDown(module.dispose);
      await module.open('officialFleet:7');
      final ref = module.projection.value.members.first.memberRef;
      module.selectMember(ref);
      module.rememberScrollOffset(280);
      await module.open('officialFleet:7');
      expect(module.selectedMemberRef.value, ref);
      expect(module.scrollOffset, 280);
      module.selectMember('unavailable-member');
      expect(module.selectedMemberRef.value, ref);
      await module.refresh();
      expect(module.selectedMemberRef.value, ref);
      module.reset();
      expect(module.selectedMemberRef.value, isNull);
      expect(module.scrollOffset, 0);
      await module.open('officialFleet:7');
      expect(module.projection.value.query?.search, '');
      expect(module.selectedMemberRef.value, isNull);
    },
  );

  test(
    'query change clears selection and scroll; invalid page sizes are ignored',
    () async {
      final module = createOfficialFleetMembersModule(
        InMemoryOfficialFleetMembersAdapter.forReview(),
      );
      addTearDown(module.dispose);
      await module.open('officialFleet:7');
      module.selectMember(module.projection.value.members.first.memberRef);
      module.rememberScrollOffset(200);
      await module.setPageSize(0);
      expect(module.projection.value.query?.pageSize, 50);
      expect(module.selectedMemberRef.value, isNotNull);
      await module.search('no-match');
      expect(module.selectedMemberRef.value, isNull);
      expect(module.scrollOffset, 0);
      await module.goToPage(-100);
      expect(module.projection.value.query?.pageNumber, 1);
    },
  );

  test(
    'unknown counts and unsupported filters do not become fake data',
    () async {
      final port = _PendingMembersPort();
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      final opened = module.open('officialFleet:7');
      port.reads.single.complete(_unknown(port.queries.single));
      await opened;
      expect(
        module.projection.value.coverage,
        OfficialFleetRosterCoverage.unknown,
      );
      expect(module.projection.value.totalCount, isNull);
      expect(module.projection.value.totalPages, isNull);
      await module.goToPage(2);
      await module.setFilter(OfficialFleetMemberFilter.online);
      expect(port.reads, hasLength(1));
    },
  );

  test('late and cross-source results cannot repopulate directory', () async {
    final port = _PendingMembersPort();
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    final first = module.open('officialFleet:7');
    module.reset();
    final second = module.open('officialFleet:8');
    port.reads[1].complete(_unknown(port.queries[0]));
    await second;
    expect(
      module.projection.value.availability,
      OfficialFleetMemberDirectoryAvailability.unavailable,
    );
    port.reads[0].complete(_unknown(port.queries[0]));
    await first;
    expect(module.projection.value.query?.sourceRef, 'officialFleet:8');
    expect(module.projection.value.members, isEmpty);
  });

  group('a failed read after presence was shown', () {
    final query = const OfficialFleetMemberDirectoryQuery(
      sourceRef: 'officialFleet:7',
    );
    Future<OfficialFleetMemberDirectorySnapshot> shown() async {
      final sample = await InMemoryOfficialFleetMembersAdapter.forReview().read(
        query,
      );
      return OfficialFleetMemberDirectorySnapshot.available(
        query: sample.query,
        members: sample.members,
        totalCount: sample.members.length,
        onlineCount: null,
        inGameCount: null,
        totalPages: 1,
        runtimeCapabilities: const OfficialFleetMemberRuntimeCapabilities.all(),
      );
    }

    OfficialFleetMemberDirectorySnapshot failed(String key) =>
        OfficialFleetMemberDirectorySnapshot.unavailable(
          query: query,
          failureKey: key,
        );

    testWidgets('holds the place but no rows, then retries and recovers', (
      tester,
    ) async {
      final port = _PendingMembersPort();
      final module = createOfficialFleetMembersModule(port);
      final good = await shown();
      unawaited(module.open('officialFleet:7'));
      await tester.pump();
      port.reads.single.complete(good);
      await tester.pump();
      expect(module.projection.value.presenceHeld, isFalse);
      expect(module.projection.value.members, isNotEmpty);

      unawaited(module.refresh(silent: true));
      await tester.pump();
      port.reads.last.complete(
        failed('officialFleet.members.error.unavailable'),
      );
      await tester.pump();
      final held = module.projection.value;
      expect(held.presenceHeld, isTrue);
      expect(held.members, isEmpty, reason: 'No former name survives.');
      expect(held.visibleOnlineCount, isNull);
      expect(held.totalCount, isNull);

      final before = port.reads.length;
      await tester.pump(const Duration(seconds: 4));
      expect(port.reads, hasLength(before));
      await tester.pump(const Duration(seconds: 2));
      expect(port.reads, hasLength(before + 1), reason: 'Looks again soon.');
      port.reads.last.complete(good);
      await tester.pump();
      expect(module.projection.value.presenceHeld, isFalse);
      expect(module.projection.value.members, isNotEmpty);

      // Recovered: no further retries.
      final after = port.reads.length;
      await tester.pump(const Duration(minutes: 2));
      expect(port.reads, hasLength(after));
      module.dispose();
    });

    testWidgets('retries are bounded', (tester) async {
      final port = _PendingMembersPort();
      final module = createOfficialFleetMembersModule(port);
      unawaited(module.open('officialFleet:7'));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        if (port.reads.last.isCompleted) break;
        port.reads.last.complete(
          failed('officialFleet.members.error.transient'),
        );
        await tester.pump();
        await tester.pump(const Duration(minutes: 1));
      }
      expect(port.reads, hasLength(4), reason: 'The read and three retries.');
      module.dispose();
    });

    testWidgets('a refusal is not retried, and nothing outlives dispose', (
      tester,
    ) async {
      final port = _PendingMembersPort();
      final module = createOfficialFleetMembersModule(port);
      unawaited(module.open('officialFleet:7'));
      await tester.pump();
      port.reads.last.complete(failed('officialFleet.error.forbidden'));
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(port.reads, hasLength(1));
      unawaited(module.refresh(silent: true));
      await tester.pump();
      port.reads.last.complete(
        failed('officialFleet.members.error.unavailable'),
      );
      await tester.pump();
      module.dispose();
      await tester.pump(const Duration(minutes: 1));
      expect(port.reads, hasLength(2));
    });

    testWidgets('a retry never adds a read after a refusal', (tester) async {
      final port = _PendingMembersPort();
      final module = createOfficialFleetMembersModule(port);
      unawaited(module.open('officialFleet:7'));
      await tester.pump();
      port.reads.last.complete(
        failed('officialFleet.members.error.transient'),
      );
      await tester.pump();
      unawaited(module.refresh(silent: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      port.reads.last.complete(failed('officialFleet.error.forbidden'));
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      expect(port.reads, hasLength(2));
      module.dispose();
    });

    testWidgets('never shown means no place is held', (tester) async {
      final port = _PendingMembersPort();
      final module = createOfficialFleetMembersModule(port);
      unawaited(module.open('officialFleet:7'));
      await tester.pump();
      port.reads.last.complete(
        failed('officialFleet.members.error.unavailable'),
      );
      await tester.pump();
      expect(module.projection.value.presenceHeld, isFalse);
      module.dispose();
    });
  });

  test('duplicate stable member references are rejected', () async {
    final port = _PendingMembersPort();
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    final opened = module.open('officialFleet:7');
    final sample = await InMemoryOfficialFleetMembersAdapter.forReview().read(
      port.queries.single,
    );
    port.reads.single.complete(
      OfficialFleetMemberDirectorySnapshot.available(
        query: port.queries.single,
        members: [sample.members.first, sample.members.first],
        totalCount: 2,
        onlineCount: null,
        inGameCount: null,
        totalPages: 1,
      ),
    );
    await opened;
    expect(
      module.projection.value.availability,
      OfficialFleetMemberDirectoryAvailability.unavailable,
    );
  });

  test('member directory module owns server query and paging state', () async {
    final module = createOfficialFleetMembersModule(
      InMemoryOfficialFleetMembersAdapter.forReview(),
    );
    addTearDown(module.dispose);

    await module.open('officialFleet:7');
    expect(module.projection.value.members, hasLength(5));
    expect(module.projection.value.query?.pageSize, 50);

    await module.setFilter(OfficialFleetMemberFilter.inGame);
    expect(module.projection.value.members, hasLength(2));
    expect(
      module.projection.value.members.every(
        (member) => member.presence == OfficialFleetMemberPresence.inGame,
      ),
      isTrue,
    );

    await module.search('多米诺');
    expect(module.projection.value.members.single.callsign, '多米诺');
    expect(module.projection.value.query?.pageNumber, 1);

    await module.setPageSize(25);
    expect(module.projection.value.query?.pageSize, 25);
  });
}

OfficialFleetMemberDirectorySnapshot _unknown(
  OfficialFleetMemberDirectoryQuery query,
) => OfficialFleetMemberDirectorySnapshot.available(
  query: query,
  members: const [],
  totalCount: null,
  onlineCount: null,
  inGameCount: null,
  totalPages: null,
);

final class _PendingMembersPort implements OfficialFleetMembersPort {
  final queries = <OfficialFleetMemberDirectoryQuery>[];
  final reads = <Completer<OfficialFleetMemberDirectorySnapshot>>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) {
    queries.add(query);
    final completer = Completer<OfficialFleetMemberDirectorySnapshot>();
    reads.add(completer);
    return completer.future;
  }

  @override
  Future<void> close() async {}
}

final class _RecordingMembersPort implements OfficialFleetMembersPort {
  final queries = <OfficialFleetMemberDirectoryQuery>[];
  final delegate = InMemoryOfficialFleetMembersAdapter.forReview();
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    queries.add(query);
    return delegate.read(query);
  }

  @override
  Future<void> close() async {}
}
