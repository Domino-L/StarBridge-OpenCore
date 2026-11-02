import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_member_row.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_views.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_members_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../settings/local_privacy_page_test.dart' show app, viewport;

const query = OfficialFleetMemberDirectoryQuery(sourceRef: 'officialFleet:7');
Map<String, Object?> cell(String state, [String? value]) => {
  'state': state,
  'value': ?value,
};
Map<String, Object?> runtimePage({String presence = 'inGame'}) {
  final playing = presence == 'inGame';
  return {
    'schemaVersion': 2,
    'sourceRef': query.sourceRef,
    'search': '',
    'pageNumber': 1,
    'pageSize': 50,
    'filter': 'all',
    'totalCount': 1,
    'totalPages': 1,
    'coverage': 'scmRegisteredMembers',
    'supportedFilters': ['all'],
    'runtimeCapabilities': {
      'presence': true,
      'server': true,
      'ship': true,
      'location': true,
      'onlineCount': false,
      'inGameCount': false,
    },
    'members': [
      {
        'memberRef': 'a' * 64,
        'callsign': 'Synthetic Pilot',
        'gameId': '',
        'identityState': 'starBridge',
        'starBridgeConnected': true,
        'profileTargetRef': 'a' * 64,
        'officialRankName': 'Member',
        'presence': presence,
        'server': playing
            ? cell('value', 'synthetic-shard')
            : cell('notInGame'),
        'ship': playing ? cell('value', 'Arrow') : cell('notInGame'),
        'location': playing ? cell('value', 'Area18') : cell('notInGame'),
        'arrivalPending': false,
        if (playing) 'serverRegion': 'US',
        if (playing) 'hasServerSession': true,
      },
    ],
  };
}

Map<String, Object?> member(Map<String, Object?> page) =>
    (page['members'] as List).single as Map<String, Object?>;

void main() {
  test('actual Bridge handshake enables runtime only on success and failure clears linked rows', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    )..acceptHostCapabilities(['officialFleet.runtimeMembers']);
    final names = <String>[];
    var fail = false;
    const account = BridgeAccountContext(
      environment: 'development',
      authority: 'scm-development',
      subject: 'synthetic-owner',
    );
    final host = pair.host.incoming.listen((request) async {
      names.add(request.name);
      if (request.name == 'bridge.cancel') return;
      expect(
        request.name,
        isIn(['account.getCurrent', 'officialFleet.getRuntimeMembers']),
      );
      if (request.name == 'officialFleet.getRuntimeMembers') {
        expect(request.payload, {
          'schemaVersion': 2,
          'sourceRef': query.sourceRef,
          'search': '',
          'filter': 'all',
          'pageNumber': 1,
          'pageSize': 50,
        });
        expect(request.accountContext?.toJson(), account.toJson());
      }
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: account,
          status: fail && request.name != 'account.getCurrent' ? 'error' : 'ok',
          error: fail && request.name != 'account.getCurrent'
              ? const BridgeErrorBody(
                  code: 'official_fleet.identity_unavailable',
                  message: 'synthetic unavailable',
                  retryable: false,
                )
              : null,
          payload: request.name == 'account.getCurrent'
              ? const {'schemaVersion': 1, 'state': 'signedIn'}
              : runtimePage(),
        ),
      );
    });
    final module = createOfficialFleetMembersModule(
      BridgeOfficialFleetMembersAdapter(session),
    );
    addTearDown(() async {
      module.dispose();
      await host.cancel();
      await session.close();
      await pair.host.close();
    });
    await module.open(query.sourceRef);
    expect(module.projection.value.runtimeCapabilities.presence, isTrue);
    expect(
      module.projection.value.members.single.identityState,
      OfficialFleetMemberIdentityState.starBridge,
    );
    fail = true;
    await module.refresh();
    expect(
      module.projection.value.availability,
      OfficialFleetMemberDirectoryAvailability.unavailable,
    );
    expect(module.projection.value.members, isEmpty);
    expect(module.projection.value.runtimeCapabilities.presence, isFalse);
    expect(
      names.where((name) => name == 'officialFleet.getRuntimeMembers'),
      hasLength(2),
    );
    expect(names, isNot(contains('officialFleet.getMembers')));
  });
  test('schema2 permits four runtime columns but retains registered all-only unknown counts', () {
    final value = parseOfficialFleetMembers(
      runtimePage(),
      query,
      runtime: true,
    );
    expect(value.coverage, OfficialFleetRosterCoverage.scmRegisteredMembers);
    expect(value.supportedFilters, {OfficialFleetMemberFilter.all});
    expect(value.onlineCount, isNull);
    expect(value.inGameCount, isNull);
    expect(value.runtimeCapabilities.presence, isTrue);
    expect(value.runtimeCapabilities.onlineCount, isFalse);
    expect(value.runtimeCapabilities.inGameCount, isFalse);
  });
  test(
    'capability inflation, current-page filtering and wrong source fail closed',
    () {
      for (final change in <void Function(Map<String, Object?>)>[
        (p) => (p['runtimeCapabilities'] as Map)['onlineCount'] = true,
        (p) => p['supportedFilters'] = ['all', 'online'],
        (p) => p['onlineCount'] = 1,
        (p) => p['sourceRef'] = 'officialFleet:8',
        (p) => p['schemaVersion'] = 1,
      ]) {
        final page = runtimePage();
        change(page);
        expect(
          () => parseOfficialFleetMembers(page, query, runtime: true),
          throwsA(isA<BridgeFormatException>()),
        );
      }
    },
  );
  test('restricted/unlinked identities cannot carry live runtime or profile target', () {
    for (final state in ['scm', 'restricted']) {
      final page = runtimePage();
      member(page)
        ..['identityState'] = state
        ..remove('starBridgeConnected')
        ..remove('profileTargetRef');
      expect(
        () => parseOfficialFleetMembers(page, query, runtime: true),
        throwsA(isA<BridgeFormatException>()),
      );
    }
  });
  test('hidden metadata and non-game stale telemetry are rejected', () {
    for (final change in <void Function(Map<String, Object?>)>[
      (m) => m['server'] = cell(
        'notShared',
      ), // region/session remain: privacy leak
      (m) {
        m['location'] = cell('notShared');
        m['arrivalPending'] = true;
      },
      (m) => m['presence'] = 'offline', // game cells remain
      (m) => m['presence'] = 'future-state',
      (m) => m['locationHiddenReason'] = 'future-reason',
      (m) => m['location'] = {'state': 'unknown', 'confidence': 'High'},
    ]) {
      final page = runtimePage();
      change(member(page));
      expect(
        () => parseOfficialFleetMembers(page, query, runtime: true),
        throwsA(isA<BridgeFormatException>()),
      );
    }
  });
  testWidgets('actual production row retains 0.7.1 hidden and process copy', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    Future<void> show(Map<String, Object?> page) async {
      final value = parseOfficialFleetMembers(
        page,
        query,
        runtime: true,
      ).members.single;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => OrganizationMemberRow(
              entry: officialFleetMemberEntry(
                context,
                value,
                allowProfile: false,
              ),
              columns: const OrganizationMemberColumns.all(),
              roleLabel: 'RSI',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final hidden = runtimePage();
    member(hidden)
      ..['server'] = cell('notShared')
      ..remove('serverRegion')
      ..remove('hasServerSession')
      ..['ship'] = cell('notShared')
      ..['location'] = cell('notShared');
    await show(hidden);
    expect(find.text('暂无可见信息'), findsNWidgets(3));
    for (final old in ['未公开', '识别中', '位置不确定']) {
      expect(find.text(old), findsNothing);
    }
    final waiting = runtimePage();
    member(waiting)
      ..['serverRegion'] = 'Unknown'
      ..remove('hasServerSession')
      ..['server'] = cell('unknown')
      ..['ship'] = cell('unknown')
      ..['location'] = cell('unknown');
    await show(waiting);
    expect(find.text('等待服务器同步'), findsNWidgets(3));
    member(waiting)['hasServerSession'] = false;
    await show(waiting);
    expect(find.text('未进入服务器'), findsNWidgets(3));
    final pending = runtimePage();
    member(pending)
      ..['arrivalPending'] = true
      ..['arrivalTargetCode'] = 'Area18';
    await show(pending);
    expect(find.textContaining('地点待确认'), findsOneWidget);
    final low = runtimePage();
    member(low)
      ..['location'] = cell('unknown')
      ..['locationHiddenReason'] = 'lowConfidence';
    await show(low);
    expect(find.text('低可信度位置'), findsOneWidget);
    await show(runtimePage(presence: 'online'));
    expect(find.text('未进入游戏'), findsNWidgets(3));
    await show(runtimePage(presence: 'offline'));
    expect(find.text('未进入游戏'), findsNWidgets(3));
  });
}
