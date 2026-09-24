import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';

void main() {
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
