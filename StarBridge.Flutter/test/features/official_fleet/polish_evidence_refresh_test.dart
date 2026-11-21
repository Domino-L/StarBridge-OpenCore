import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_governance_port.dart';
import 'package:starbridge_flutter/features/common/organization_governance_settings.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_governance.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_profile_section.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;
import 'official_fleet_governance_test.dart' show governanceWire;

Widget app(Widget child, [Locale locale = const Locale('zh', 'CN')]) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Scaffold(body: child),
    );

class Port
    implements OrganizationGovernancePort, OrganizationEvidenceRefreshPort {
  final changes = StreamController<void>.broadcast(sync: true);
  bool stale = true, supported = true;
  String? readError;
  int reads = 0, writes = 0;
  Completer<OrganizationEvidenceRefreshResult>? hold;
  OrganizationEvidenceRefreshResult result =
      const OrganizationEvidenceRefreshResult('requested');
  @override
  bool get available => true;
  @override
  bool get canActivate => false;
  @override
  bool get canRefreshEvidence => supported;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<OrganizationGovernanceContext> read(String source) async {
    reads++;
    if (readError case final error?) throw CommunityFailure(error);
    final wire = Map<String, Object?>.from(governanceWire('context-observed'));
    wire['capabilities'] = [
      for (final raw in wire['capabilities'] as List)
        {
          ...raw as Map<String, Object?>,
          if (stale) 'reason': 'membershipEvidenceStale',
        },
    ];
    return OrganizationGovernanceContext.parse(wire, source);
  }

  @override
  Future<OrganizationEvidenceRefreshResult> refreshEvidence() async {
    writes++;
    return hold == null ? result : hold!.future;
  }

  @override
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  }) => throw UnimplementedError();
  @override
  Future<void> close() async => changes.close();
}

Widget settings(Port port) => app(
  OrganizationGovernanceSettings(
    port: port,
    sourceRef: 'officialFleet:7',
    name: 'Fixture',
    onBack: () async {},
  ),
);

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets('missing rank uses explicit localized copy $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          const SingleChildScrollView(
            child: OfficialFleetProfileSection(
              fleet: OfficialFleetSummary(
                sourceRef: 'officialFleet:7',
                sid: 'TEST',
                name: 'Fixture',
                officialRankName: 'Master',
                officialRankValue: null,
              ),
              observedAtUtc: null,
            ),
          ),
          locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          AppStrings.resolve(locale).text('officialFleet.rank.unavailable'),
        ),
        findsNWidgets(2),
      );
      expect(find.textContaining('Master · —'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('only stale evidence and new Host offer refresh', (tester) async {
    final port = Port();
    addTearDown(port.close);
    for (final (stale, supported, error, shown)
        in <(bool, bool, String?, bool)>[
          (false, true, null, false),
          (true, false, null, false),
          (false, true, 'unavailable', false),
          (false, true, 'membershipEvidenceStale', true),
          (true, true, null, true),
        ]) {
      await tester.pumpWidget(const SizedBox());
      port.stale = stale;
      port.supported = supported;
      port.readError = error;
      await tester.pumpWidget(settings(port));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('governance-refresh-evidence')),
        shown ? findsOneWidget : findsNothing,
      );
      expect(port.writes, 0);
    }
  });
  testWidgets(
    'one click, disabled while pending, success rereads once and retains honest feedback',
    (tester) async {
      final port = Port()..hold = Completer();
      addTearDown(port.close);
      await tester.pumpWidget(settings(port));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('governance-refresh-evidence'));
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      expect(port.writes, 1);
      port.stale = false;
      port.hold!.complete(const OrganizationEvidenceRefreshResult('requested'));
      await tester.pumpAndSettle();
      expect(port.reads, 2);
      expect(find.textContaining('约 1 分钟后回来重试'), findsOneWidget);
      expect(button, findsNothing);
    },
  );
  for (final state in [
    'rateLimited',
    'globalBusy',
    'verificationRequired',
    'cached',
    'unavailable',
    'signInRequired',
  ]) {
    testWidgets('$state uses fixed feedback without automatic retry', (
      tester,
    ) async {
      final port = Port()
        ..result = OrganizationEvidenceRefreshResult(
          state,
          state == 'rateLimited' ? 17 : null,
        );
      addTearDown(port.close);
      await tester.pumpWidget(settings(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('governance-refresh-evidence')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 31));
      expect(port.writes, 1);
      expect(port.reads, 1);
      expect(
        find.byKey(const Key('governance-refresh-result')),
        findsOneWidget,
      );
      if (state == 'rateLimited') {
        expect(find.text('还要等 17 分钟才能刷新。'), findsOneWidget);
      }
    });
  }
  testWidgets('identity invalidation discards pending refresh completion', (
    tester,
  ) async {
    final port = Port()..hold = Completer();
    addTearDown(port.close);
    await tester.pumpWidget(settings(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('governance-refresh-evidence')));
    await tester.pump();
    port.changes.add(null);
    await tester.pump();
    port.hold!.complete(const OrganizationEvidenceRefreshResult('requested'));
    await tester.pumpAndSettle();
    expect(port.reads, 1);
    expect(find.byKey(const Key('governance-refresh-result')), findsNothing);
  });
  test(
    'bridge negotiates capability and sends once with no raw message field',
    () async {
      final host = CommunityHarness(
        capabilities: [
          BridgeOfficialFleetGovernance.command,
          BridgeOfficialFleetGovernance.refresh,
        ],
        responses: {
          BridgeOfficialFleetGovernance.refresh: {
            'schemaVersion': 1,
            'state': 'rateLimited',
            'remainingMinutes': 12,
          },
        },
      );
      final port = BridgeOfficialFleetGovernance(host.adapter);
      addTearDown(host.close);
      addTearDown(port.close);
      expect(port.canRefreshEvidence, isTrue);
      expect((await port.refreshEvidence()).remainingMinutes, 12);
      expect(
        host.requests.where(
          (r) => r.name == BridgeOfficialFleetGovernance.refresh,
        ),
        hasLength(1),
      );
    },
  );
  test('old Host sends no speculative refresh', () async {
    final host = CommunityHarness(
      capabilities: [BridgeOfficialFleetGovernance.command],
    );
    final port = BridgeOfficialFleetGovernance(host.adapter);
    addTearDown(host.close);
    addTearDown(port.close);
    expect(port.canRefreshEvidence, isFalse);
    await expectLater(port.refreshEvidence(), throwsA(isA<CommunityFailure>()));
    expect(host.requests, isEmpty);
  });
}
