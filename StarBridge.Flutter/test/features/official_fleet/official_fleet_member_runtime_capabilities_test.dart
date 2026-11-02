import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_port.dart';

const _query = OfficialFleetMemberDirectoryQuery(sourceRef: 'officialFleet:7');
const _member = OfficialFleetMember(
  memberRef: 'fixture:visible',
  callsign: 'Visible pilot',
  gameId: 'fixture-visible',
  officialRankName: 'Member',
  officialRankValue: 1,
  identityState: OfficialFleetMemberIdentityState.starBridge,
  presence: OfficialFleetMemberPresence.inGame,
  server: OfficialFleetMemberField.value('Fixture server'),
  ship: OfficialFleetMemberField.value('Fixture ship'),
  location: OfficialFleetMemberField.value('Fixture location'),
  starBridgeConnected: true,
);

void main() {
  test('fixture rows do not infer directory runtime support', () async {
    final result = await const InMemoryOfficialFleetMembersAdapter([_member])
        .read(_query);
    expect(result.onlineCount, isNull);
    expect(result.inGameCount, isNull);
    expect(result.supportedFilters, {OfficialFleetMemberFilter.all});
  });

  test(
    'module cannot enable runtime filters without directory capability',
    () async {
      final port = _UnadvertisedRuntimePort();
      final module = createOfficialFleetMembersModule(port);
      addTearDown(module.dispose);
      await module.open(_query.sourceRef);
      expect(module.projection.value.onlineCount, isNull);
      expect(module.projection.value.inGameCount, isNull);
      expect(module.projection.value.supportedFilters, {
        OfficialFleetMemberFilter.all,
      });
      await module.setFilter(OfficialFleetMemberFilter.inGame);
      expect(port.readCount, 1);
    },
  );

  test('current real Bridge explicitly advertises no runtime capability', () {
    final memberRef = 'a' * 64;
    final snapshot = parseOfficialFleetMembers({
      'schemaVersion': 1,
      'sourceRef': _query.sourceRef,
      'search': '',
      'filter': 'all',
      'pageNumber': 1,
      'pageSize': 50,
      'totalCount': 1,
      'totalPages': 1,
      'coverage': 'scmRegisteredMembers',
      'members': [
        {
          'memberRef': memberRef,
          'callsign': 'Visible pilot',
          'identityState': 'starBridge',
          'profileTargetRef': memberRef,
          'starBridgeConnected': true,
          'presence': 'unknown',
        },
      ],
    }, _query);
    final capabilities = snapshot.runtimeCapabilities;
    expect([
      capabilities.presence,
      capabilities.server,
      capabilities.ship,
      capabilities.location,
      capabilities.onlineCount,
      capabilities.inGameCount,
    ], everyElement(isFalse));
    expect(
      snapshot.members.single.publicPresence,
      OfficialFleetMemberPresence.unknown,
    );
    expect(snapshot.supportedFilters, {OfficialFleetMemberFilter.all});
    expect(snapshot.onlineCount, isNull);
    expect(snapshot.inGameCount, isNull);
  });

  test('runtime columns and counters are independent declarations retained on refresh', () {
    const capabilities = OfficialFleetMemberRuntimeCapabilities(
      server: true,
      onlineCount: true,
    );
    final snapshot = OfficialFleetMemberDirectorySnapshot.available(
      query: _query,
      members: const [_member],
      totalCount: 1,
      onlineCount: 0,
      inGameCount: 1,
      totalPages: 1,
      runtimeCapabilities: capabilities,
      supportedFilters: OfficialFleetMemberFilter.values.toSet(),
    );
    final projection = OfficialFleetMemberDirectoryProjection.fromSnapshot(
      snapshot,
    );
    expect(projection.runtimeCapabilities, same(capabilities));
    expect(projection.runtimeCapabilities.server, isTrue);
    expect(projection.runtimeCapabilities.presence, isFalse);
    expect(projection.runtimeCapabilities.ship, isFalse);
    expect(projection.runtimeCapabilities.location, isFalse);
    expect(projection.onlineCount, 0);
    expect(projection.inGameCount, isNull);
    expect(projection.supportedFilters, {OfficialFleetMemberFilter.all});
    final retained = OfficialFleetMemberDirectoryProjection.refreshing(
      projection,
    );
    expect(retained.runtimeCapabilities, same(capabilities));
    expect(retained.onlineCount, 0);
  });

  for (final identity in OfficialFleetMemberIdentityState.values) {
    for (final presence in OfficialFleetMemberPresence.values) {
      test(
        '$identity cannot turn linkage into $presence runtime authority',
        () {
          final member = _fixture(identity: identity, presence: presence);
          final expected =
              identity != OfficialFleetMemberIdentityState.starBridge ||
                  presence == OfficialFleetMemberPresence.notConnected
              ? OfficialFleetMemberPresence.unknown
              : presence == OfficialFleetMemberPresence.invisible
              ? OfficialFleetMemberPresence.offline
              : presence;
          expect(member.publicPresence, expected);
          expect(
            member.publicServer.state,
            expected == OfficialFleetMemberPresence.inGame
                ? OfficialFleetMemberFieldState.value
                : expected == OfficialFleetMemberPresence.unknown
                ? OfficialFleetMemberFieldState.unknown
                : OfficialFleetMemberFieldState.notInGame,
          );
        },
      );
    }
  }

  test('ordinary offline, invisible and paused in-game have identical public facts', () {
    final members = [
      _fixture(presence: OfficialFleetMemberPresence.offline),
      _fixture(presence: OfficialFleetMemberPresence.invisible),
      _fixture(presence: OfficialFleetMemberPresence.inGame, paused: true),
    ];
    for (final member in members) {
      expect(member.publicPresence, OfficialFleetMemberPresence.offline);
      expect([
        member.publicServer.state,
        member.publicShip.state,
        member.publicLocation.state,
      ], everyElement(OfficialFleetMemberFieldState.notInGame));
      expect([
        member.publicServer.value,
        member.publicShip.value,
        member.publicLocation.value,
      ], everyElement(isNull));
      expect(member.publicArrivalPending, isFalse);
    }
  });

  test(
    'explicit fixture support counts and filters only public online facts',
    () async {
      final adapter = InMemoryOfficialFleetMembersAdapter(
        [
          _member,
          _fixture(presence: OfficialFleetMemberPresence.online),
          _fixture(presence: OfficialFleetMemberPresence.away),
          _fixture(presence: OfficialFleetMemberPresence.invisible),
          _fixture(presence: OfficialFleetMemberPresence.inGame, paused: true),
          _fixture(identity: OfficialFleetMemberIdentityState.scm),
          _fixture(identity: OfficialFleetMemberIdentityState.restricted),
        ],
        runtimeCapabilities: const OfficialFleetMemberRuntimeCapabilities.all(),
      );
      final snapshot = await adapter.read(_query);
      expect(snapshot.onlineCount, 3);
      expect(snapshot.inGameCount, 1);
      expect(
        snapshot.supportedFilters,
        OfficialFleetMemberFilter.values.toSet(),
      );
      expect(
        (await adapter.read(
          _query.copyWith(filter: OfficialFleetMemberFilter.online),
        )).members,
        hasLength(3),
      );
      expect(
        (await adapter.read(
          _query.copyWith(filter: OfficialFleetMemberFilter.inGame),
        )).members,
        hasLength(1),
      );
      final module = createOfficialFleetMembersModule(adapter);
      addTearDown(module.dispose);
      await module.open(_query.sourceRef);
      await module.setFilter(OfficialFleetMemberFilter.inGame);
      expect(module.projection.value.members, hasLength(1));
    },
  );
}

OfficialFleetMember _fixture({
  OfficialFleetMemberIdentityState identity =
      OfficialFleetMemberIdentityState.starBridge,
  OfficialFleetMemberPresence presence = OfficialFleetMemberPresence.inGame,
  bool paused = false,
}) => OfficialFleetMember(
  memberRef: 'fixture:${identity.name}:${presence.name}:$paused',
  callsign: 'Fixture member',
  gameId: 'fixture',
  officialRankName: 'Member',
  officialRankValue: 1,
  identityState: identity,
  presence: presence,
  server: const OfficialFleetMemberField.value('Hidden server'),
  ship: const OfficialFleetMemberField.value('Hidden ship'),
  location: const OfficialFleetMemberField.value('Hidden location'),
  starBridgeConnected: identity == OfficialFleetMemberIdentityState.starBridge,
  sharingPaused: paused,
  arrivalPending: true,
);

final class _UnadvertisedRuntimePort implements OfficialFleetMembersPort {
  int readCount = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<OfficialFleetMemberDirectorySnapshot> read(
    OfficialFleetMemberDirectoryQuery query,
  ) async {
    readCount++;
    return OfficialFleetMemberDirectorySnapshot.available(
      query: query,
      members: const [_member],
      totalCount: 1,
      onlineCount: 1,
      inGameCount: 1,
      totalPages: 1,
      supportedFilters: OfficialFleetMemberFilter.values.toSet(),
    );
  }

  @override
  Future<void> close() async {}
}
