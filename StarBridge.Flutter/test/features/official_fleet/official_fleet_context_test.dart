import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_overview_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_overview_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_port.dart';

void main() {
  test(
    'account invalidation never publishes an old identity response',
    () async {
      final identity = _IdentityPort();
      final module = _module(identity);
      addTearDown(module.dispose);
      final seen = <OfficialFleetAvailability>[];
      module.projection.addListener(
        () => seen.add(module.projection.value.availability),
      );
      final reading = module.initialize();
      identity.changed.add(null);
      final latest = module.refresh();
      identity.reads[0].complete(await _memberSnapshot());
      await _flush();
      expect(identity.reads, hasLength(2));
      expect(seen, isNot(contains(OfficialFleetAvailability.available)));
      identity.reads[1].complete(const OfficialFleetSnapshot.signedOut());
      await Future.wait([reading, latest]);
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.signedOut,
      );
    },
  );

  test('switching viewer clears all child data and rejects late results', () async {
    final identity = _IdentityPort();
    final members = _MembersPort();
    final overview = _OverviewPort();
    final ships = _ShipsPort();
    final module = createOfficialFleetModule(
      identity,
      overview,
      members,
      ships,
    );
    addTearDown(module.dispose);
    final initial = module.initialize();
    identity.reads.single.complete(await _memberSnapshot());
    await initial;
    members.complete(0);
    overview.complete(0);
    ships.complete(0);
    await _flush();
    expect(module.members.projection.value.members, isNotEmpty);
    expect(module.overview.projection.value.metrics, isNotNull);
    expect(
      module.ships.projection.value.availability,
      OfficialFleetShipsAvailability.available,
    );

    final pending = Future.wait([
      module.members.refresh(),
      module.overview.refresh(),
      module.ships.refresh(),
    ]);
    identity.changed.add(null);
    expect(module.members.projection.value.members, isEmpty);
    expect(module.members.projection.value.query, isNull);
    expect(module.overview.projection.value.metrics, isNull);
    expect(module.ships.projection.value.query, isNull);
    members.complete(1);
    overview.complete(1);
    ships.complete(1);
    await pending;
    expect(
      module.members.projection.value.availability,
      OfficialFleetMemberDirectoryAvailability.idle,
    );
    expect(
      module.overview.projection.value.availability,
      OfficialFleetOverviewAvailability.idle,
    );
    expect(
      module.ships.projection.value.availability,
      OfficialFleetShipsAvailability.idle,
    );

    // A new viewer in the same fleet still receives fresh queries and defaults.
    identity.reads.last.complete(await _memberSnapshot());
    await _flush();
    expect(members.queries, hasLength(3));
    expect(members.queries.last.search, isEmpty);
    members.complete(2);
    overview.complete(2);
    ships.complete(2);
    await _flush();
  });

  test(
    'manual refresh rereads child data and retains directory query',
    () async {
      final identity = _IdentityPort();
      final module = _module(identity);
      addTearDown(module.dispose);
      final initial = module.initialize();
      identity.reads.single.complete(await _memberSnapshot());
      await initial;
      await _flush();
      await module.members.search('Alpha');
      await module.members.setPageSize(25);
      final refreshing = module.refresh();
      expect(
        module.members.projection.value.availability,
        OfficialFleetMemberDirectoryAvailability.idle,
      );
      identity.reads.last.complete(await _memberSnapshot());
      await refreshing;
      await _flush();
      expect(module.members.projection.value.query?.search, 'Alpha');
      expect(module.members.projection.value.query?.pageSize, 25);
      expect(
        module.members.projection.value.availability,
        OfficialFleetMemberDirectoryAvailability.available,
      );
    },
  );

  test(
    'read exceptions recover on retry instead of leaving loading stuck',
    () async {
      final identity = _IdentityPort();
      final module = _module(identity);
      addTearDown(module.dispose);
      final initial = module.initialize();
      identity.reads.single.completeError(StateError('read failed'));
      await initial;
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.unavailable,
      );
      final retry = module.refresh();
      identity.reads.last.complete(await _memberSnapshot());
      await retry;
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.available,
      );
    },
  );

  test('dispose during identity read prevents late child requests', () async {
    final identity = _IdentityPort();
    final members = _MembersPort();
    final module = createOfficialFleetModule(
      identity,
      _OverviewPort(),
      members,
      _ShipsPort(),
    );
    final initial = module.initialize();
    module.dispose();
    identity.reads.single.complete(await _memberSnapshot());
    await initial;
    expect(members.queries, isEmpty);
  });
}

OfficialFleetModule _module(_IdentityPort identity) =>
    createOfficialFleetModule(
      identity,
      InMemoryOfficialFleetOverviewAdapter.forReview(),
      InMemoryOfficialFleetMembersAdapter.forReview(),
      InMemoryOfficialFleetShipsAdapter.forReview(),
    );

Future<OfficialFleetSnapshot> _memberSnapshot() =>
    InMemoryOfficialFleetAdapter.forReview(signedIn: true).read();
Future<void> _flush() => Future<void>.delayed(Duration.zero);

final class _IdentityPort implements OfficialFleetPort {
  final changed = StreamController<void>.broadcast(sync: true);
  final reads = <Completer<OfficialFleetSnapshot>>[];
  @override
  Stream<void> get invalidations => changed.stream;
  @override
  Future<OfficialFleetSnapshot> read() {
    final pending = Completer<OfficialFleetSnapshot>();
    reads.add(pending);
    return pending.future;
  }

  @override
  Future<void> close() => changed.close();
}

final class _MembersPort implements OfficialFleetMembersPort {
  final queries = <OfficialFleetMemberDirectoryQuery>[];
  final reads = <Completer<OfficialFleetMemberDirectorySnapshot>>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) {
    queries.add(query);
    final pending = Completer<OfficialFleetMemberDirectorySnapshot>();
    reads.add(pending);
    return pending.future;
  }

  void complete(int index) => reads[index].complete(
    InMemoryOfficialFleetMembersAdapter.forReview().read(queries[index]),
  );
  @override
  Future<void> close() async {}
}

final class _OverviewPort implements OfficialFleetOverviewPort {
  final refs = <String>[];
  final reads = <Completer<OfficialFleetOverviewSnapshot>>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetOverviewSnapshot> read(String sourceRef) {
    refs.add(sourceRef);
    final pending = Completer<OfficialFleetOverviewSnapshot>();
    reads.add(pending);
    return pending.future;
  }

  void complete(int index) => reads[index].complete(
    InMemoryOfficialFleetOverviewAdapter.forReview().read(refs[index]),
  );
  @override
  Future<void> close() async {}
}

final class _ShipsPort implements OfficialFleetShipsPort {
  final queries = <OfficialFleetShipsQuery>[];
  final reads = <Completer<OfficialFleetShipsSnapshot>>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetShipsSnapshot> read(OfficialFleetShipsQuery query) {
    queries.add(query);
    final pending = Completer<OfficialFleetShipsSnapshot>();
    reads.add(pending);
    return pending.future;
  }

  void complete(int index) => reads[index].complete(
    InMemoryOfficialFleetShipsAdapter.forReview().read(queries[index]),
  );
  @override
  Future<void> close() async {}
}
