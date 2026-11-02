import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  test(
    'reads the current official fleet through the Host projection',
    () async {
      final harness = _OfficialFleetHostHarness();

      final snapshot = await harness.adapter.read();

      expect(snapshot.availability, OfficialFleetAvailability.available);
      expect(snapshot.fleet?.sourceRef, 'officialFleet:7');
      expect(snapshot.fleet?.name, "Aster's Wing");
      expect(snapshot.fleet?.officialRankValue, 4);
      expect(snapshot.resourceVersion, 11);
      expect(harness.requestNames, [
        'account.getCurrent',
        'officialFleet.getCurrent',
      ]);
      await harness.close();
    },
  );

  test('keeps signed-out and no-membership states distinct', () async {
    final signedOut = _OfficialFleetHostHarness(signedIn: false);
    expect(
      (await signedOut.adapter.read()).availability,
      OfficialFleetAvailability.signedOut,
    );
    await signedOut.close();

    final notMember = _OfficialFleetHostHarness(member: false);
    expect(
      (await notMember.adapter.read()).availability,
      OfficialFleetAvailability.notMember,
    );
    await notMember.close();
  });

  test('rejects an out-of-range RSI rank instead of inferring it', () async {
    final harness = _OfficialFleetHostHarness(rankValue: 7);

    final snapshot = await harness.adapter.read();

    expect(snapshot.availability, OfficialFleetAvailability.unavailable);
    expect(snapshot.failureKey, 'officialFleet.error.invalidResponse');
    await harness.close();
  });

  test('publishes account changes as fleet invalidations', () async {
    final harness = _OfficialFleetHostHarness();
    final invalidated = harness.adapter.invalidations.first;

    await harness.sendAccountChanged();

    await invalidated.timeout(const Duration(seconds: 1));
    await harness.close();
  });

  test('optional SCM profile uses the existing typed fleet details', () async {
    final harness = _OfficialFleetHostHarness(
      profile: {
        'memberCount': 1286,
        'rsiDescription': 'Explore',
        'scmSupplementalDescription': 'Supplement',
        'languageLabels': ['English'],
        'tags': ['Exploration'],
      },
    );
    final snapshot = await harness.adapter.read();
    expect(snapshot.fleet?.profile?.rsiDescription, 'Explore');
    expect(snapshot.fleet?.profile?.scmSupplementalDescription, 'Supplement');
    expect(snapshot.fleet?.profile?.memberCount, 1286);
    expect(snapshot.fleet?.profile?.starBridgeRoleName, isNull);
    expect(snapshot.fleet?.officialRankValue, 4);
    await harness.close();
  });

  test('malformed profile media and negative counts fail closed', () async {
    for (final patch in [
      {'bannerUrl': 'http://invalid.example/image.png'},
      {'memberCount': -1},
    ]) {
      final harness = _OfficialFleetHostHarness(
        profile: {'languageLabels': <String>[], 'tags': <String>[], ...patch},
      );
      expect(
        (await harness.adapter.read()).availability,
        OfficialFleetAvailability.unavailable,
      );
      await harness.close();
    }
  });
  test('member bridge reads use the verified session and keep missing facts unknown', () async {
    final harness = _OfficialFleetHostHarness();
    final adapter = BridgeOfficialFleetMembersAdapter(harness._session);
    const query = OfficialFleetMemberDirectoryQuery(
      sourceRef: 'officialFleet:7',
      search: 'Pilot',
    );
    final snapshot = await adapter.read(query);
    expect(snapshot.coverage, OfficialFleetRosterCoverage.scmRegisteredMembers);
    expect(snapshot.totalPages, 2);
    expect(snapshot.members.single.gameId, isEmpty);
    expect(snapshot.members.single.starBridgeConnected, isNull);
    expect(
      snapshot.members.single.presence,
      OfficialFleetMemberPresence.unknown,
    );
    expect(snapshot.onlineCount, isNull);
    expect(harness.requests.last.accountContext?.subject, 'synthetic-subject');
    await adapter.close();
    await harness.close();
  });

  test('member projection rejects other sources, false presence and duplicate rows', () {
    const query = OfficialFleetMemberDirectoryQuery(
      sourceRef: 'officialFleet:7',
      search: 'Pilot',
    );
    final good = _memberPayload();
    final row = (good['members'] as List).single;
    for (final patch in <Map<String, Object?>>[
      {'sourceRef': 'officialFleet:8'},
      {'search': 'other'},
      {'totalPages': 1},
      {'coverage': 'completeOfficialRoster'},
      {'onlineCount': 2},
      {
        'members': [row, row],
      },
      {
        'members': [
          {...row as Map<String, Object?>, 'presence': 'online'},
        ],
      },
    ]) {
      expect(
        () => parseOfficialFleetMembers({...good, ...patch}, query),
        throwsA(isA<BridgeFormatException>()),
      );
    }
  });
}

final class _OfficialFleetHostHarness {
  _OfficialFleetHostHarness({
    this.signedIn = true,
    this.member = true,
    this.rankValue = 4,
    this.profile,
  }) {
    final pair = InMemoryBridgeConnection.createPair();
    _host = pair.host;
    _session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 4,
      requestTimeout: const Duration(seconds: 1),
    );
    adapter = BridgeOfficialFleetAdapter(_session);
    _subscription = _host.incoming.listen(_respond);
  }

  final bool signedIn;
  final bool member;
  final int rankValue;
  final Map<String, Object?>? profile;
  late final BridgeConnection _host;
  late final BridgeClientSession _session;
  late final StreamSubscription<BridgeEnvelope> _subscription;
  late final BridgeOfficialFleetAdapter adapter;
  final List<BridgeEnvelope> requests = [];

  List<String> get requestNames => requests.map((item) => item.name).toList();

  Future<void> _respond(BridgeEnvelope request) async {
    requests.add(request);
    const context = BridgeAccountContext(
      environment: 'development',
      authority: 'scm-development',
      subject: 'synthetic-subject',
    );
    if (request.name == 'account.getCurrent') {
      await _send(request, <String, Object?>{
        'schemaVersion': 1,
        'state': signedIn ? 'signedIn' : 'signedOut',
        'displayName': signedIn ? 'Aster Lin' : null,
        'avatarUrl': null,
      }, context: signedIn ? context : null);
      return;
    }
    if (request.name == 'officialFleet.getMembers') {
      await _send(request, _memberPayload(), context: context);
      return;
    }
    if (request.name != 'officialFleet.getCurrent') {
      throw StateError('Unexpected request ${request.name}');
    }
    expect(request.accountContext?.subject, 'synthetic-subject');
    await _send(request, <String, Object?>{
      'schemaVersion': 1,
      'state': member ? 'member' : 'notMember',
      'fleet': member
          ? <String, Object?>{
              'sourceRef': 'officialFleet:7',
              'sid': 'ASTER',
              'name': "Aster's Wing",
              'logoUrl': null,
              'officialRankName': 'Officer',
              'officialRankValue': rankValue,
              'profile': profile,
            }
          : null,
      'freshness': 'live',
      'resourceVersion': 11,
      'observedAtUtc': '2026-09-01T12:00:00Z',
    }, context: context);
  }

  Future<void> sendAccountChanged() => _host.send(
    const BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'account.changed',
      sessionGeneration: 5,
      sequence: 1,
      payload: <String, Object?>{'schemaVersion': 1},
    ),
  );

  Future<void> _send(
    BridgeEnvelope request,
    Map<String, Object?> payload, {
    BridgeAccountContext? context,
  }) => _host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: context,
      payload: payload,
      status: 'ok',
    ),
  );

  Future<void> close() async {
    await adapter.close();
    await _subscription.cancel();
    await _session.close();
    await _host.close();
  }
}

Map<String, Object?> _memberPayload() => {
  'schemaVersion': 1,
  'sourceRef': 'officialFleet:7',
  'search': 'Pilot',
  'filter': 'all',
  'pageNumber': 1,
  'pageSize': 50,
  'totalCount': 51,
  'totalPages': 2,
  'onlineCount': null,
  'inGameCount': null,
  'coverage': 'scmRegisteredMembers',
  'supportedFilters': ['all'],
  'members': [
    {
      'memberRef': 'a' * 64,
      'callsign': 'Pilot',
      'gameId': '',
      'officialRankName': 'Member',
      'officialRankValue': null,
      'presence': 'unknown',
      'starBridgeConnected': null,
    },
  ],
};
