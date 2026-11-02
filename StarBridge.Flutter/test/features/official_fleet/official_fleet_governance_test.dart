import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_governance_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_governance.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;

// These files must be the actual Server->Host->Codec export. Missing producer
// evidence fails explicitly; it is never replaced with handcrafted success JSON.
Map<String, Object?> governanceWire(String name) => jsonDecode(
  File('test/fixtures/official_fleet_governance/$name.bridge.json')
      .readAsStringSync(),
) as Map<String, Object?>;

void main() {
  test('actual context wire keeps use and root control decisions separate', () {
    final unknown = OrganizationGovernanceContext.parse(
      governanceWire('context-unconfigured'),
      'officialFleet:7',
    );
    final observed = OrganizationGovernanceContext.parse(
      governanceWire('context-observed'),
      'officialFleet:7',
    );
    expect(unknown.rootProviderState, 'unconfigured');
    expect(
      unknown.capabilities.map((value) => value.state),
      containsAll([
        OrganizationDecisionState.unavailable,
        OrganizationDecisionState.denied,
      ]),
    );
    expect(
      observed.capabilities.map((value) => value.state),
      contains(OrganizationDecisionState.allowed),
    );
    expect(unknown.policyRevision, 2);
  });
  test('typed context rejects foreign source, duplicate decisions and private fields', () {
    final row = governanceWire('context-unconfigured');
    expect(
      () => OrganizationGovernanceContext.parse(row, 'officialFleet:8'),
      throwsFormatException,
    );
    expect(
      () => OrganizationGovernanceContext.parse({
        ...row,
        'subject': 'synthetic-private',
      }, 'officialFleet:7'),
      throwsFormatException,
    );
    final caps = List<Object?>.from(row['capabilities'] as List);
    expect(
      () => OrganizationGovernanceContext.parse({
        ...row,
        'capabilities': [caps.first, caps.first, caps.last],
      }, 'officialFleet:7'),
      throwsFormatException,
    );
  });
  test(
    'real borrowed transport performs account admission and one context read',
    () async {
      final host = CommunityHarness(
        capabilities: [BridgeOfficialFleetGovernance.command],
        responses: {
          BridgeOfficialFleetGovernance.command: governanceWire(
            'context-unconfigured',
          ),
        },
      );
      final reader = BridgeOfficialFleetGovernance(host.adapter);
      addTearDown(host.close);
      addTearDown(reader.close);
      final result = await reader.read('officialFleet:7');
      expect(result.rootProviderState, 'unconfigured');
      expect(host.requests.map((value) => value.name), [
        'account.getCurrent',
        BridgeOfficialFleetGovernance.command,
      ]);
      await reader.close();
      expect(host.adapter.isClosed, isFalse);
    },
  );
  test(
    'old Host is unavailable without a speculative account or command request',
    () async {
      final host = CommunityHarness(capabilities: const []);
      final reader = BridgeOfficialFleetGovernance(host.adapter);
      addTearDown(host.close);
      addTearDown(reader.close);
      await expectLater(
        reader.read('officialFleet:7'),
        throwsA(
          isA<CommunityFailure>().having(
            (e) => e.code,
            'code',
            'upgradeRequired',
          ),
        ),
      );
      expect(host.requests, isEmpty);
    },
  );
  test(
    'generation retires a held original context without an automatic retry',
    () async {
      final host = CommunityHarness(
        capabilities: [BridgeOfficialFleetGovernance.command],
        holdNames: {BridgeOfficialFleetGovernance.command},
        responses: {
          BridgeOfficialFleetGovernance.command: governanceWire(
            'context-unconfigured',
          ),
        },
      );
      final reader = BridgeOfficialFleetGovernance(host.adapter);
      addTearDown(host.close);
      addTearDown(reader.close);
      final pending = reader.read('officialFleet:7');
      final rejected = expectLater(pending, throwsA(isA<CommunityFailure>()));
      await host.readArrived.future;
      host.session.advanceGeneration(host.session.activeGeneration + 1);
      await rejected;
      expect(
        host.requests.where(
          (row) => row.name == BridgeOfficialFleetGovernance.command,
        ),
        hasLength(1),
      );
    },
  );
}
