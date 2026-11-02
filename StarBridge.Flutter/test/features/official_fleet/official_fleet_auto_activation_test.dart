import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_governance_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_auto_activation.dart';

const _source = 'officialFleet:7';

// The same sample the relay's tests read, so the two sides cannot drift.
Map<String, Object?> _sample() =>
    jsonDecode(
          File(
            'test/fixtures/official_fleet_governance/context-never-activated.bridge.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

Map<String, Object?> _withActivateReason(String reason, {String? state}) {
  final row = _sample();
  final root = Map<String, Object?>.from(row['rootAuthority'] as Map);
  root['controls'] = [
    for (final control in root['controls'] as List)
      (control as Map)['action'] == 'activate'
          ? {...control, 'reason': reason, 'state': ?state ?? control['state']}
          : control,
  ];
  return {...row, 'rootAuthority': root};
}

final class _Port implements OrganizationGovernancePort {
  _Port(this.row);
  Map<String, Object?> row;
  @override
  bool available = true;
  @override
  bool canActivate = true;
  int reads = 0;
  bool failRead = false;
  String nextState = 'accepted';
  Object? failWrite;
  final writes = <(bool, String, int)>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<OrganizationGovernanceContext> read(String sourceRef) async {
    reads++;
    if (failRead) throw const CommunityFailure('unavailable');
    return OrganizationGovernanceContext.parse(row, sourceRef);
  }

  @override
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  }) async {
    writes.add((active, operationId, expectedPolicyRevision));
    if (failWrite != null) throw failWrite!;
    return OrganizationActivationOutcome(nextState, policyRevision: 1);
  }

  @override
  Future<void> close() async {}
}

final class _HeldPort extends _Port {
  _HeldPort(super.row, {this.holdSecondRead = false});
  final bool holdSecondRead;
  Completer<void> _gate = Completer<void>();
  void release() {
    final gate = _gate;
    _gate = Completer<void>();
    gate.complete();
  }

  @override
  Future<OrganizationGovernanceContext> read(String sourceRef) async {
    if (reads == 0 || holdSecondRead) await _gate.future;
    return super.read(sourceRef);
  }
}

void main() {
  late _Port port;
  late List<int> activated;
  late OfficialFleetAutoActivation auto;
  late int revision;
  String? fleet;
  setUp(() {
    port = _Port(_sample());
    activated = [];
    revision = 1;
    fleet = _source;
    auto = OfficialFleetAutoActivation(
      port: () => port,
      context: () => (revision, fleet),
      onActivated: (authority) => activated.add(authority.policyRevision),
      operationId: () => 'op',
    );
  });

  test('never activated enables once and reports the new rights', () async {
    await auto.enter();
    expect(port.writes, [(true, 'op', 0)]);
    expect(activated, hasLength(1));
    await auto.enter();
    expect(port.writes, hasLength(1));
    expect(port.reads, 2);
  });

  for (final reason in ['explicitRootControl', 'somethingNew']) {
    test('$reason, which covers someone who revoked, writes nothing', () async {
      port.row = _withActivateReason(reason);
      await auto.enter();
      expect(port.writes, isEmpty);
      expect(activated, isEmpty);
    });
  }

  test('the same reason on a denied control writes nothing', () async {
    port.row = _withActivateReason(
      OfficialFleetAutoActivation.neverActivated,
      state: 'denied',
    );
    await auto.enter();
    expect(port.writes, isEmpty);
  });

  test('an old Host that cannot activate writes nothing', () async {
    port.canActivate = false;
    await auto.enter();
    expect(port.writes, isEmpty);
  });

  test('a failed write is never repeated', () async {
    port.failWrite = const CommunityFailure('notAllowed');
    await auto.enter();
    await auto.enter();
    expect(port.writes, hasLength(1));
    expect(activated, isEmpty);
  });

  test('a refused outcome is never repeated or reported', () async {
    port.nextState = 'conflict';
    await auto.enter();
    await auto.enter();
    expect(port.writes, hasLength(1));
    expect(activated, isEmpty);
  });

  test('failed reads stop after three visits', () async {
    port.failRead = true;
    for (var visit = 0; visit < 5; visit++) {
      await auto.enter();
    }
    expect(port.reads, 3);
    expect(port.writes, isEmpty);
  });

  test('a read that recovers still enables', () async {
    port.failRead = true;
    await auto.enter();
    port.failRead = false;
    await auto.enter();
    expect(port.writes, hasLength(1));
  });

  test('before the Host is ready nothing is spent', () async {
    port.available = false;
    await auto.enter();
    expect(port.reads, 0);
    port.available = true;
    await auto.enter();
    expect(port.writes, hasLength(1));
  });

  test('another fleet gets its own single try', () async {
    await auto.enter();
    port.row = {..._sample(), 'sourceRef': 'officialFleet:8'};
    fleet = 'officialFleet:8';
    await auto.enter();
    expect(port.writes, hasLength(2));
  });

  test('a failed write is not repeated after going away and back', () async {
    port.failWrite = const CommunityFailure('notAllowed');
    await auto.enter();
    port.row = {..._sample(), 'sourceRef': 'officialFleet:8'};
    fleet = 'officialFleet:8';
    await auto.enter();
    port.row = _sample();
    fleet = _source;
    await auto.enter();
    expect(port.writes, hasLength(2));
  });

  test('another account on the same fleet gets its own check', () async {
    port.row = _withActivateReason('explicitRootControl');
    await auto.enter();
    expect(port.writes, isEmpty);
    port.row = _sample();
    revision = 2;
    await auto.enter();
    expect(port.writes, hasLength(1));
  });

  test('a read finishing after the account changed writes nothing', () async {
    final held = _HeldPort(_sample());
    final worker = OfficialFleetAutoActivation(
      port: () => held,
      context: () => (revision, fleet),
      onActivated: (_) {},
    );
    final running = worker.enter();
    revision = 2;
    held.release();
    await running;
    expect(held.writes, isEmpty);
  });

  test('closing during the last read reports nothing', () async {
    final held = _HeldPort(_sample(), holdSecondRead: true);
    final reported = <int>[];
    final worker = OfficialFleetAutoActivation(
      port: () => held,
      context: () => (revision, fleet),
      onActivated: (a) => reported.add(a.policyRevision),
    );
    final running = worker.enter();
    held.release();
    await pumpEventQueue();
    worker.close();
    held.release();
    await running;
    expect(held.writes, hasLength(1));
    expect(reported, isEmpty);
  });

  test('no fleet and a closed worker do nothing', () async {
    fleet = null;
    await auto.enter();
    fleet = _source;
    auto.close();
    await auto.enter();
    expect(port.reads, 0);
  });
}
