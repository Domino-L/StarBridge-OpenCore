import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_governance_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/common/organization_governance_settings.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_governance.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally_views.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;
import 'official_fleet_governance_test.dart' show governanceWire;

// Leader rule (user decision 2026-10-24, "都按建议"): every SCM rank-1 member
// is a leader, each enables management once; role is display only.
Map<String, Object?> _context({
  String? role,
  String? updated,
  bool activated = false,
  bool stale = false,
  bool canActivate = true,
  int revision = 2,
}) {
  final row = Map<String, Object?>.from(governanceWire('context-observed'));
  final root = Map<String, Object?>.from(row['rootAuthority'] as Map);
  root['controls'] = [
    {
      'action': 'activate',
      'state': activated || !canActivate ? 'denied' : 'allowed',
      'reason': 'explicitRootControl',
    },
    {'action': 'recover', 'state': 'allowed', 'reason': 'explicitRootControl'},
    {
      'action': 'delegate',
      'state': stale
          ? 'unavailable'
          : activated
          ? 'allowed'
          : 'denied',
      'reason': stale
          ? 'membershipEvidenceStale'
          : activated
          ? 'explicitRootDelegation'
          : 'rootActivationNotCurrent',
    },
  ];
  return {
    ...row,
    'policyRevision': revision,
    'rootAuthority': root,
    'role': ?role,
    'membershipUpdatedAt': ?updated,
  };
}

final class _Port implements OrganizationGovernancePort {
  _Port(this.rows);
  final List<Map<String, Object?>> rows;
  final calls = <(bool, String, int)>[];
  String nextState = 'accepted';
  CommunityFailure? nextFailure;
  int reads = 0;
  Completer<void>? hold;
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  bool get available => true;
  @override
  bool get canActivate => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<OrganizationGovernanceContext> read(String sourceRef) async =>
      OrganizationGovernanceContext.parse(
        rows[(reads++).clamp(0, rows.length - 1)],
        sourceRef,
      );
  @override
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  }) async {
    calls.add((active, operationId, expectedPolicyRevision));
    await hold?.future;
    if (nextFailure case final failure?) {
      nextFailure = null;
      throw failure;
    }
    return OrganizationActivationOutcome(nextState, policyRevision: 3);
  }

  @override
  Future<void> close() async {}
}

Widget _app(
  OrganizationGovernancePort port, {
  ValueChanged<OrganizationGovernanceContext>? onAuthorityRead,
}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  ),
  home: Scaffold(
    body: SizedBox(
      width: 1200,
      height: 800,
      child: OrganizationGovernanceSettings(
        port: port,
        sourceRef: 'officialFleet:7',
        name: 'DMNPZ',
        onBack: () async {},
        onAuthorityRead: onAuthorityRead,
      ),
    ),
  ),
);

void main() {
  test('context accepts the optional role and evidence time only', () {
    final value = OrganizationGovernanceContext.parse(
      _context(role: 'leader', updated: '2026-10-20T00:00:00Z', stale: true),
      'officialFleet:7',
    );
    expect(value.role, 'leader');
    expect(value.membershipUpdatedAt, DateTime.utc(2026, 10, 20));
    expect(value.evidenceStale, isTrue);
    expect(
      OrganizationGovernanceContext.parse(_context(), 'officialFleet:7').role,
      isNull,
    );
    for (final bad in [
      {..._context(), 'role': 'owner'},
      {..._context(), 'membershipUpdatedAt': 'yesterday'},
      {..._context(), 'rank': 1},
    ]) {
      expect(
        () => OrganizationGovernanceContext.parse(bad, 'officialFleet:7'),
        throwsFormatException,
      );
    }
  });

  test(
    'activation sends only source, operation and expected revision',
    () async {
      final host = CommunityHarness(
        capabilities: const [
          BridgeOfficialFleetGovernance.command,
          BridgeOfficialFleetGovernance.roleCapability,
        ],
        responses: {
          BridgeOfficialFleetGovernance.command: _context(role: 'leader'),
          BridgeOfficialFleetGovernance.activate: {
            'schemaVersion': 1,
            'sourceRef': 'officialFleet:7',
            'operationId': 'op1',
            'state': 'accepted',
            'policyRevision': 3,
            'auditSequence': 1,
          },
        },
      );
      final port = BridgeOfficialFleetGovernance(host.adapter);
      addTearDown(host.close);
      addTearDown(port.close);
      // Writes are offered only after a context that carried a role.
      expect(port.canActivate, isFalse);
      await port.read('officialFleet:7');
      expect(port.canActivate, isTrue);
      expect(
        host.requests
            .singleWhere((r) => r.name == BridgeOfficialFleetGovernance.command)
            .payload['include'],
        ['role'],
      );
      final outcome = await port.setActivation(
        'officialFleet:7',
        active: true,
        operationId: 'op1',
        expectedPolicyRevision: 2,
      );
      expect(outcome.succeeded, isTrue);
      expect(outcome.policyRevision, 3);
      final sent = host.requests.singleWhere(
        (r) => r.name == BridgeOfficialFleetGovernance.activate,
      );
      expect(sent.payload, {
        'schemaVersion': 1,
        'sourceRef': 'officialFleet:7',
        'operationId': 'op1',
        'expectedPolicyRevision': 2,
      });
    },
  );

  test('an old Host gets no include and offers no activation', () async {
    final host = CommunityHarness(
      capabilities: const [BridgeOfficialFleetGovernance.command],
      responses: {
        BridgeOfficialFleetGovernance.command: governanceWire(
          'context-observed',
        ),
      },
    );
    final port = BridgeOfficialFleetGovernance(host.adapter);
    addTearDown(host.close);
    addTearDown(port.close);
    await port.read('officialFleet:7');
    expect(port.canActivate, isFalse);
    expect(
      host.requests
          .singleWhere((r) => r.name == BridgeOfficialFleetGovernance.command)
          .payload
          .containsKey('include'),
      isFalse,
    );
  });

  testWidgets('a leader enables management, then sees revoke', (tester) async {
    final port = _Port([
      _context(role: 'leader'),
      _context(role: 'leader', activated: true, revision: 3),
    ]);
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    expect(find.text('你是舰队负责人（RSI 等级 1）'), findsOneWidget);
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    expect(port.calls.single.$1, isTrue);
    expect(port.calls.single.$3, 2);
    expect(find.byKey(const Key('governance-disable')), findsOneWidget);
    expect(find.byKey(const Key('governance-write-result')), findsNothing);
  });

  testWidgets('every read of the rights is reported, enabling included', (
    tester,
  ) async {
    final port = _Port([
      _context(role: 'leader'),
      _context(role: 'leader', activated: true, revision: 3),
    ]);
    final seen = <int>[];
    await tester.pumpWidget(
      _app(port, onAuthorityRead: (read) => seen.add(read.policyRevision)),
    );
    await tester.pumpAndSettle();
    expect(seen, [2]);
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    expect(seen, [2, 3]);
  });

  testWidgets('an unknown outcome keeps the same operation id on retry', (
    tester,
  ) async {
    final port = _Port([_context(role: 'leader')])
      ..nextState = 'outcomeUnknown';
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('governance-write-result')), findsOneWidget);
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    expect(port.calls, hasLength(2));
    expect(port.calls.first.$2, port.calls.last.$2);
    expect(port.calls.first.$3, port.calls.last.$3);
  });

  testWidgets('a retry that was never sent keeps the earlier unknown write', (
    tester,
  ) async {
    final port = _Port([_context(role: 'leader')])
      ..nextState = 'outcomeUnknown';
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    port.nextFailure = const CommunityFailure('unavailable');
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('governance-write-result')), findsOneWidget);
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    expect(port.calls, hasLength(3));
    expect(port.calls.map((call) => call.$2).toSet(), hasLength(1));
    expect(port.calls.map((call) => call.$3).toSet(), hasLength(1));
  });

  testWidgets('a first attempt that was never sent leaves nothing pending', (
    tester,
  ) async {
    final port = _Port([_context(role: 'leader')])
      ..nextFailure = const CommunityFailure('unavailable');
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pumpAndSettle();
    expect(port.calls, hasLength(2));
    expect(port.calls.first.$2, isNot(port.calls.last.$2));
  });

  testWidgets(
    'admins see their role but no activation; stale evidence says why',
    (tester) async {
      final port = _Port([
        _context(
          role: 'admin',
          stale: true,
          updated: '2026-10-20T00:00:00Z',
          canActivate: false,
        ),
      ]);
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('governance-role')), findsOneWidget);
      expect(find.byKey(const Key('governance-enable')), findsNothing);
      expect(find.byKey(const Key('governance-stale')), findsOneWidget);
    },
  );

  test('rallies name their starter when the relay sends one', () {
    Map<String, Object?> rally({Object? starter, bool include = true}) => {
      'rallyId': 'a' * 32,
      'text': '来打架',
      'minutes': 15,
      'startedAt': '2026-10-25T00:00:00Z',
      'expiresAt': '2026-10-25T00:15:00Z',
      'state': 'active',
      'coming': 1,
      'cannot': 0,
      'pending': 2,
      'response': null,
      if (include) 'starter': starter,
    };
    final named = OfficialFleetRally.parse(
      rally(starter: {'displayName': 'Leader A', 'isSelf': false}),
    );
    expect(named.starterName, 'Leader A');
    expect(named.startedBySelf, isFalse);
    expect(OfficialFleetRally.parse(rally(include: false)).starterName, isNull);
    expect(
      () => OfficialFleetRally.parse(rally(starter: {'subject': 'x'})),
      throwsFormatException,
    );
    expect(
      () => OfficialFleetRally.parse(
        rally(starter: {'isSelf': true, 'subject': 'x'}),
      ),
      throwsFormatException,
    );
    expect(
      OfficialFleetRally.parse(
        rally(starter: {'displayName': 'A' * 128, 'isSelf': true}),
      ).startedBySelf,
      isTrue,
    );
  });

  testWidgets('the rally title includes the starter', (tester) async {
    late String title;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Builder(
          builder: (context) {
            title = officialFleetRallyTitle(
              AppStrings.of(context),
              'DMNPZ',
              OfficialFleetRally.parse({
                'rallyId': 'b' * 32,
                'text': 'x',
                'minutes': 15,
                'startedAt': '2026-10-25T00:00:00Z',
                'expiresAt': '2026-10-25T00:15:00Z',
                'state': 'active',
                'coming': 0,
                'cannot': 0,
                'pending': 0,
                'response': null,
                'starter': {'displayName': 'Leader B', 'isSelf': false},
              }),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(title, 'DMNPZ · Leader B 召集');
  });

  testWidgets('an invalidation mid-write retires it instead of wedging', (
    tester,
  ) async {
    final port = _Port([_context(role: 'leader')])..hold = Completer<void>();
    addTearDown(port.changes.close);
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('governance-enable')));
    await tester.pump();
    port.changes.add(null);
    await tester.pump();
    port.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('governance-write-result')), findsNothing);
  });

  test('a sent write with an unreadable receipt stays unknown', () async {
    final host = CommunityHarness(
      capabilities: const [
        BridgeOfficialFleetGovernance.command,
        BridgeOfficialFleetGovernance.roleCapability,
      ],
      responses: {
        BridgeOfficialFleetGovernance.command: _context(role: 'leader'),
        BridgeOfficialFleetGovernance.activate: {
          'schemaVersion': 1,
          'sourceRef': 'officialFleet:7',
          'operationId': 'someone-else',
          'state': 'accepted',
          'policyRevision': 3,
        },
      },
    );
    final port = BridgeOfficialFleetGovernance(host.adapter);
    addTearDown(host.close);
    addTearDown(port.close);
    await port.read('officialFleet:7');
    final outcome = await port.setActivation(
      'officialFleet:7',
      active: true,
      operationId: 'op1',
      expectedPolicyRevision: 2,
    );
    expect(outcome.state, 'outcomeUnknown');
    expect(outcome.succeeded, isFalse);
  });

  for (final (code, expected) in [
    ('communities.unavailable', 'outcomeUnknown'),
    ('bridge.internal', 'outcomeUnknown'),
  ]) {
    test('a Host error after forwarding ($code) stays unknown', () async {
      final host = CommunityHarness(
        capabilities: const [
          BridgeOfficialFleetGovernance.command,
          BridgeOfficialFleetGovernance.roleCapability,
        ],
        responses: {
          BridgeOfficialFleetGovernance.command: _context(role: 'leader'),
        },
        errors: {BridgeOfficialFleetGovernance.activate: code},
      );
      final port = BridgeOfficialFleetGovernance(host.adapter);
      addTearDown(host.close);
      addTearDown(port.close);
      await port.read('officialFleet:7');
      final outcome = await port.setActivation(
        'officialFleet:7',
        active: true,
        operationId: 'op1',
        expectedPolicyRevision: 2,
      );
      expect(outcome.state, expected);
    });
  }

  test('a lock timeout before sending is retryable, not an unknown write', () async {
    final host = CommunityHarness(
      capabilities: const [
        BridgeOfficialFleetGovernance.command,
        BridgeOfficialFleetGovernance.roleCapability,
      ],
      responses: {
        BridgeOfficialFleetGovernance.command: _context(role: 'leader'),
      },
      errors: {
        BridgeOfficialFleetGovernance.activate:
            'communities.activationNotSent',
      },
    );
    final port = BridgeOfficialFleetGovernance(host.adapter);
    addTearDown(host.close);
    addTearDown(port.close);
    await port.read('officialFleet:7');
    await expectLater(
      port.setActivation(
        'officialFleet:7',
        active: true,
        operationId: 'op1',
        expectedPolicyRevision: 2,
      ),
      throwsA(
        isA<CommunityFailure>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
  });

  test('a Host refusal before forwarding is a definite failure', () async {
    final host = CommunityHarness(
      capabilities: const [
        BridgeOfficialFleetGovernance.command,
        BridgeOfficialFleetGovernance.roleCapability,
      ],
      responses: {
        BridgeOfficialFleetGovernance.command: _context(role: 'leader'),
      },
      errors: {
        BridgeOfficialFleetGovernance.activate: 'communities.upgradeRequired',
      },
    );
    final port = BridgeOfficialFleetGovernance(host.adapter);
    addTearDown(host.close);
    addTearDown(port.close);
    await port.read('officialFleet:7');
    await expectLater(
      port.setActivation(
        'officialFleet:7',
        active: true,
        operationId: 'op1',
        expectedPolicyRevision: 2,
      ),
      throwsA(
        isA<CommunityFailure>().having(
          (e) => e.code,
          'code',
          'upgradeRequired',
        ),
      ),
    );
  });
}
