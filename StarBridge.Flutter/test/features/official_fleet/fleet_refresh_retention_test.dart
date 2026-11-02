import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_overview_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_overview_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_ships_module.dart';

void main() {
  test('legacy SCM-only member failure preserves the original read time and selection until a hard or query failure', () async {
    var now = DateTime.utc(2026, 10, 15, 1);
    // Older Host projections carry no StarBridge identity authority. Their
    // transient retention policy must not borrow an identity-aware fixture.
    final port = _HeldMembers(
      source: const InMemoryOfficialFleetMembersAdapter([
        OfficialFleetMember(
          memberRef: 'legacy-scm:1',
          callsign: 'Legacy SCM member',
          gameId: '',
          officialRankName: 'Member',
          officialRankValue: 1,
          presence: OfficialFleetMemberPresence.unknown,
          server: OfficialFleetMemberField(
            OfficialFleetMemberFieldState.unknown,
          ),
          ship: OfficialFleetMemberField(OfficialFleetMemberFieldState.unknown),
          location: OfficialFleetMemberField(
            OfficialFleetMemberFieldState.unknown,
          ),
          starBridgeConnected: null,
        ),
      ]),
    );
    final module = createOfficialFleetMembersModule(port, now: () => now);
    addTearDown(module.dispose);
    await module.open('officialFleet:7');
    expect(
      module.projection.value.members.every(
        (member) => member.identityState == null,
      ),
      isTrue,
    );
    final selected = module.projection.value.members.first.memberRef;
    module.selectMember(selected);
    module.rememberScrollOffset(240);
    final readTime = module.projection.value.lastReadAtUtc;
    now = now.add(const Duration(minutes: 5));
    port.failTransient = true;
    await module.refresh();
    expect(module.projection.value.refreshFailed, isTrue);
    expect(module.projection.value.members, isNotEmpty);
    expect(module.projection.value.lastReadAtUtc, readTime);
    expect(module.selectedMemberRef.value, selected);
    expect(module.scrollOffset, 240);
    await module.refresh();
    expect(module.projection.value.lastReadAtUtc, readTime);
    port.failTransient = null;
    await module.refresh();
    expect(module.projection.value.refreshFailed, isFalse);
    expect(module.projection.value.lastReadAtUtc, now);
    port.failTransient = true;
    await module.search('new query');
    expect(module.projection.value.members, isEmpty);
    expect(module.selectedMemberRef.value, isNull);
    expect(module.projection.value.lastReadAtUtc, isNull);
    await module.search('');
    port.failTransient = null;
    await module.refresh();
    port.failTransient = false;
    await module.refresh();
    expect(module.projection.value.members, isEmpty);
    expect(module.projection.value.refreshFailed, isFalse);
  });
  test('identity-aware member failure clears linked data instead of retaining authorization', () async {
    final port = _HeldMembers();
    final module = createOfficialFleetMembersModule(port);
    addTearDown(module.dispose);
    await module.open('officialFleet:7');
    final linked = module.projection.value.members.first;
    expect(linked.identityState, OfficialFleetMemberIdentityState.starBridge);
    module.selectMember(linked.memberRef);
    expect(module.projection.value.lastReadAtUtc, isNotNull);
    port.failTransient = true;
    await module.refresh();
    expect(
      module.projection.value.availability,
      OfficialFleetMemberDirectoryAvailability.unavailable,
    );
    expect(module.projection.value.members, isEmpty);
    expect(module.projection.value.lastReadAtUtc, isNull);
    expect(module.projection.value.refreshFailed, isFalse);
    expect(module.selectedMemberRef.value, isNull);
  });
  test('ship failure retains one query without extending read time or retaining a different query', () async {
    var now = DateTime.utc(2026, 10, 15, 1);
    final port = _HeldShips();
    final module = createOfficialFleetShipsModule(port, now: () => now);
    addTearDown(module.dispose);
    await module.open('officialFleet:7');
    final readTime = module.projection.value.lastReadAtUtc;
    now = now.add(const Duration(minutes: 5));
    port.failTransient = true;
    await module.refresh();
    expect(module.projection.value.refreshFailed, isTrue);
    expect(module.projection.value.ships, isNotEmpty);
    expect(module.projection.value.lastReadAtUtc, readTime);
    port.failTransient = null;
    await module.refresh();
    expect(module.projection.value.lastReadAtUtc, now);
    port.failTransient = true;
    await module.search('Vulture');
    expect(module.projection.value.ships, isEmpty);
    expect(module.projection.value.lastReadAtUtc, isNull);
  });
  test(
    'overview known failure retains data and a later unknown failure clears it',
    () async {
      final overview = _HeldOverview();
      final module = createOfficialFleetModule(
        _HeldIdentity(),
        overview,
        _HeldMembers(),
        _HeldShips(),
      );
      addTearDown(module.dispose);
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      final loaded = module.overview.projection.value;
      overview.failTransient = true;
      await module.overview.refresh();
      expect(module.overview.projection.value.metrics, same(loaded.metrics));
      expect(
        module.overview.projection.value.observedAtUtc,
        loaded.observedAtUtc,
      );
      expect(module.overview.projection.value.refreshFailed, isTrue);
      overview.failTransient = false;
      await module.overview.refresh();
      expect(module.overview.projection.value.metrics, isNull);
      expect(module.overview.projection.value.refreshFailed, isFalse);
    },
  );
  for (final part in ['identity', 'overview', 'members', 'ships']) {
    test(
      'manual fleet refresh retains $part while its source read is pending',
      () async {
        final port = _HeldIdentity();
        final module = createOfficialFleetModule(
          port,
          InMemoryOfficialFleetOverviewAdapter.forReview(),
          InMemoryOfficialFleetMembersAdapter.forReview(),
          InMemoryOfficialFleetShipsAdapter.forReview(),
        );
        addTearDown(module.dispose);
        await module.initialize();
        await Future<void>.delayed(Duration.zero);
        expect(module.overview.projection.value.metrics, isNotNull);
        expect(module.members.projection.value.members, isNotEmpty);
        expect(
          module.ships.projection.value.availability,
          OfficialFleetShipsAvailability.available,
        );
        port.hold = Completer<OfficialFleetSnapshot>();
        final pending = module.refresh();
        final repeated = module.refresh();
        expect(identical(pending, repeated), isTrue);
        expect(module.projection.value.isRefreshing, isTrue);
        switch (part) {
          case 'identity':
            expect(
              module.projection.value.availability,
              OfficialFleetAvailability.available,
            );
          case 'overview':
            expect(module.overview.projection.value.metrics, isNotNull);
          case 'members':
            expect(module.members.projection.value.members, isNotEmpty);
          case 'ships':
            expect(
              module.ships.projection.value.availability,
              OfficialFleetShipsAvailability.available,
            );
        }
        port.hold!.complete(await port.source.read());
        await pending;
        expect(module.projection.value.isRefreshing, isFalse);
      },
    );
  }
  for (final part in ['overview', 'members', 'ships']) {
    test(
      'direct $part refresh keeps confirmed content and coalesces reads',
      () async {
        final identity = _HeldIdentity();
        final overview = _HeldOverview();
        final members = _HeldMembers();
        final ships = _HeldShips();
        final module = createOfficialFleetModule(
          identity,
          overview,
          members,
          ships,
        );
        addTearDown(module.dispose);
        await module.initialize();
        await Future<void>.delayed(Duration.zero);
        final selected =
            module.members.projection.value.members.first.memberRef;
        module.members.selectMember(selected);
        module.members.rememberScrollOffset(240);
        overview.hold = members.hold = ships.hold = true;
        final first = switch (part) {
          'overview' => module.overview.refresh(),
          'members' => module.members.refresh(),
          _ => module.ships.refresh(),
        };
        final second = switch (part) {
          'overview' => module.overview.refresh(),
          'members' => module.members.refresh(),
          _ => module.ships.refresh(),
        };
        try {
          switch (part) {
            case 'overview':
              expect(module.overview.projection.value.isRefreshing, isTrue);
              expect(module.overview.projection.value.metrics, isNotNull);
              expect(overview.pending, hasLength(1));
            case 'members':
              expect(module.members.projection.value.isRefreshing, isTrue);
              expect(module.members.projection.value.members, isNotEmpty);
              expect(module.members.selectedMemberRef.value, selected);
              expect(module.members.scrollOffset, 240);
              expect(members.pending, hasLength(1));
            case 'ships':
              expect(module.ships.projection.value.isRefreshing, isTrue);
              expect(module.ships.projection.value.ships, isNotEmpty);
              expect(ships.pending, hasLength(1));
          }
        } finally {
          await overview.complete();
          await members.complete();
          await ships.complete();
          await Future.wait([first, second]);
        }
      },
    );
  }

  test(
    'membership loss clears all children and rejects their late refreshes',
    () async {
      final identity = _HeldIdentity();
      final overview = _HeldOverview();
      final members = _HeldMembers();
      final ships = _HeldShips();
      final module = createOfficialFleetModule(
        identity,
        overview,
        members,
        ships,
      );
      addTearDown(module.dispose);
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      overview.hold = members.hold = ships.hold = true;
      final childReads = Future.wait([
        module.overview.refresh(),
        module.members.refresh(),
        module.ships.refresh(),
      ]);
      identity.hold = Completer<OfficialFleetSnapshot>();
      final identityRead = module.refresh();
      identity.hold!.complete(
        OfficialFleetSnapshot.notMember(
          freshness: OfficialFleetFreshness.live,
          observedAtUtc: DateTime.utc(2026, 10, 15),
        ),
      );
      await identityRead;
      expect(
        module.projection.value.availability,
        OfficialFleetAvailability.notMember,
      );
      expect(module.overview.projection.value.metrics, isNull);
      expect(module.members.projection.value.members, isEmpty);
      expect(module.ships.projection.value.ships, isEmpty);
      await overview.complete();
      await members.complete();
      await ships.complete();
      await childReads;
      expect(module.overview.projection.value.metrics, isNull);
      expect(module.members.projection.value.members, isEmpty);
      expect(module.ships.projection.value.ships, isEmpty);
    },
  );

  test(
    'another fleet clears query selection and child data before new reads',
    () async {
      final identity = _HeldIdentity();
      final overview = _HeldOverview();
      final members = _HeldMembers();
      final ships = _HeldShips();
      final module = createOfficialFleetModule(
        identity,
        overview,
        members,
        ships,
      );
      addTearDown(module.dispose);
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      await module.members.search('Alpha');
      module.members.rememberScrollOffset(240);
      overview.hold = members.hold = ships.hold = true;
      identity.hold = Completer<OfficialFleetSnapshot>();
      final pending = module.refresh();
      identity.hold!.complete(
        OfficialFleetSnapshot.available(
          fleet: const OfficialFleetSummary(
            sourceRef: 'officialFleet:8',
            sid: 'SYNTHETIC_OTHER',
            name: 'Other fleet',
            officialRankName: null,
            officialRankValue: null,
          ),
          freshness: OfficialFleetFreshness.live,
          observedAtUtc: DateTime.utc(2026, 10, 15),
        ),
      );
      await pending;
      expect(module.contextRevision, 1);
      expect(module.overview.projection.value.metrics, isNull);
      expect(module.members.projection.value.members, isEmpty);
      expect(
        module.members.projection.value.query?.sourceRef,
        'officialFleet:8',
      );
      expect(module.members.projection.value.query?.search, isEmpty);
      expect(module.members.scrollOffset, 0);
      expect(module.ships.projection.value.ships, isEmpty);
      await overview.complete();
      await members.complete();
      await ships.complete();
    },
  );

  test(
    'new ship query clears old rows and ignores the older pending query',
    () async {
      final port = _HeldShips();
      final module = createOfficialFleetModule(
        _HeldIdentity(),
        _HeldOverview(),
        _HeldMembers(),
        port,
      );
      addTearDown(module.dispose);
      await module.initialize();
      await Future<void>.delayed(Duration.zero);
      port.hold = true;
      final oldRead = module.ships.refresh();
      final newRead = module.ships.search('Vulture');
      expect(module.ships.projection.value.ships, isEmpty);
      expect(module.ships.projection.value.query?.search, 'Vulture');
      final (query, newest) = port.pending.last;
      newest.complete(await port.source.read(query));
      await newRead;
      final newestData = module.ships.projection.value;
      final (oldQuery, oldest) = port.pending.first;
      oldest.complete(await port.source.read(oldQuery));
      await oldRead;
      expect(identical(module.ships.projection.value, newestData), isTrue);
    },
  );
}

final class _HeldIdentity implements OfficialFleetPort {
  final source = InMemoryOfficialFleetAdapter.forReview(signedIn: true);
  Completer<OfficialFleetSnapshot>? hold;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetSnapshot> read() => hold?.future ?? source.read();
  @override
  Future<void> close() => source.close();
}

final class _HeldOverview implements OfficialFleetOverviewPort {
  bool? failTransient;
  bool hold = false;
  final source = InMemoryOfficialFleetOverviewAdapter.forReview();
  final pending = <(String, Completer<OfficialFleetOverviewSnapshot>)>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetOverviewSnapshot> read(String ref) {
    if (failTransient != null) {
      return Future.value(
        OfficialFleetOverviewSnapshot.unavailable(
          failureKey: 'officialFleet.error.transient',
          transientFailure: failTransient!,
        ),
      );
    }
    if (!hold) return source.read(ref);
    final completer = Completer<OfficialFleetOverviewSnapshot>();
    pending.add((ref, completer));
    return completer.future;
  }

  Future<void> complete() async {
    for (final (ref, completer) in pending) {
      completer.complete(await source.read(ref));
    }
  }

  @override
  Future<void> close() => source.close();
}

final class _HeldMembers implements OfficialFleetMembersPort {
  _HeldMembers({InMemoryOfficialFleetMembersAdapter? source})
    : source = source ?? InMemoryOfficialFleetMembersAdapter.forReview();
  bool? failTransient;
  bool hold = false;
  final InMemoryOfficialFleetMembersAdapter source;
  final pending =
      <
        (
          OfficialFleetMemberDirectoryQuery,
          Completer<OfficialFleetMemberDirectorySnapshot>,
        )
      >[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) {
    if (failTransient != null) {
      return Future.value(
        OfficialFleetMemberDirectorySnapshot.unavailable(
          query: query,
          failureKey: 'officialFleet.members.error.transient',
          transientFailure: failTransient!,
        ),
      );
    }
    if (!hold) return source.read(query);
    final completer = Completer<OfficialFleetMemberDirectorySnapshot>();
    pending.add((query, completer));
    return completer.future;
  }

  Future<void> complete() async {
    for (final (query, completer) in pending) {
      completer.complete(await source.read(query));
    }
  }

  @override
  Future<void> close() => source.close();
}

final class _HeldShips implements OfficialFleetShipsPort {
  bool? failTransient;
  bool hold = false;
  final source = InMemoryOfficialFleetShipsAdapter.forReview();
  final pending =
      <(OfficialFleetShipsQuery, Completer<OfficialFleetShipsSnapshot>)>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OfficialFleetShipsSnapshot> read(OfficialFleetShipsQuery query) {
    if (failTransient != null) {
      return Future.value(
        OfficialFleetShipsSnapshot.unavailable(
          query: query,
          failureKey: 'officialFleet.error.transient',
          transientFailure: failTransient!,
        ),
      );
    }
    if (!hold) return source.read(query);
    final completer = Completer<OfficialFleetShipsSnapshot>();
    pending.add((query, completer));
    return completer.future;
  }

  Future<void> complete() async {
    for (final (query, completer) in pending) {
      completer.complete(await source.read(query));
    }
  }

  @override
  Future<void> close() => source.close();
}
