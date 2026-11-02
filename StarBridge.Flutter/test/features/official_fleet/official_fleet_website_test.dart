import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_port.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show loadFonts, size;

void main() {
  setUpAll(loadFonts);
  test('actual adapter sends only SID to advertised public command', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 5,
    );
    final adapter = BridgeOfficialFleetAdapter(session);
    final received = <BridgeEnvelope>[];
    final sub = pair.host.incoming.listen((request) {
      received.add(request);
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 5,
          status: 'ok',
          payload: const {'schemaVersion': 1, 'opened': true},
        ),
      );
    });
    addTearDown(() async {
      await adapter.close();
      await sub.cancel();
      await session.close();
      await pair.host.close();
    });
    expect(await adapter.openWebsite('ASTER'), isFalse);
    expect(received, isEmpty);
    session.acceptHostCapabilities(['helpSupport.openRsiOrganization']);
    expect(await adapter.openWebsite('ASTER'), isTrue);
    expect(received.single.name, 'helpSupport.openRsiOrganization');
    expect(received.single.accountContext, isNull);
    expect(received.single.payload, {'schemaVersion': 1, 'sid': 'ASTER'});
    for (final sid in [
      '',
      '../ASTER',
      'ASTER?x=1',
      'aster',
      'ABCDEFGHIJK',
      'Ａ',
    ]) {
      expect(await adapter.openWebsite(sid), isFalse);
    }
    expect(received, hasLength(1));
  });
  test('account invalidation retires a late browser acknowledgement', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 5,
    );
    session.acceptHostCapabilities(['helpSupport.openRsiOrganization']);
    final adapter = BridgeOfficialFleetAdapter(session);
    final request = Completer<BridgeEnvelope>();
    final sub = pair.host.incoming.listen((r) {
      if (r.name == 'helpSupport.openRsiOrganization' && !request.isCompleted) {
        request.complete(r);
      }
    });
    addTearDown(() async {
      await adapter.close();
      await sub.cancel();
      await session.close();
      await pair.host.close();
    });
    final opening = adapter.openWebsite('ASTER');
    final r = await request.future;
    await pair.host.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 5,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: r.name,
        correlationId: r.correlationId,
        sessionGeneration: 5,
        status: 'ok',
        payload: const {'schemaVersion': 1, 'opened': true},
      ),
    );
    expect(await opening, isFalse);
  });
  test(
    'module opens only current fleet and discards acknowledgement after leave',
    () async {
      final port = _WebsitePort();
      final module = _module(port);
      addTearDown(module.dispose);
      expect(module.websiteAvailable, isFalse);
      await module.initialize();
      final opening = module.openWebsite();
      expect(port.opened, ['ASTER']);
      port.snapshot = const OfficialFleetSnapshot.notMember(
        freshness: OfficialFleetFreshness.live,
        observedAtUtc: null,
      );
      port.changed.add(null);
      await Future<void>.delayed(Duration.zero);
      port.result.complete(true);
      expect(await opening, isFalse);
      expect(module.websiteAvailable, isFalse);
      expect(await module.openWebsite(), isFalse);
      expect(port.opened, hasLength(1));
    },
  );
  testWidgets(
    'details opens current website on click only, suppresses double click and shows failure',
    (tester) async {
      size(tester, const Size(1280, 900));
      final port = _WebsitePort();
      final module = _module(port);
      addTearDown(module.dispose);
      await module.initialize();
      await tester.pumpWidget(_app(module));
      await tester.pumpAndSettle();
      expect(port.opened, isEmpty);
      await tester.tap(find.byKey(const Key('official-fleet-open-details')));
      await tester.pumpAndSettle();
      final link = find.byKey(const Key('official-fleet-open-website'));
      expect(link, findsOneWidget);
      await tester.tap(link);
      await tester.pump();
      await tester.tap(link);
      await tester.pump();
      expect(port.opened, ['ASTER']);
      port.result.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('暂时无法打开 RSI 官网，请稍后重试。'), findsOneWidget);
      expect(
        find.byKey(const Key('official-fleet-details-dialog')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'old host keeps existing details without unsupported website action',
    (tester) async {
      size(tester, const Size(1280, 900));
      final module = _module(
        InMemoryOfficialFleetAdapter.forReview(signedIn: true),
      );
      addTearDown(module.dispose);
      await module.initialize();
      await tester.pumpWidget(_app(module));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('official-fleet-open-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('official-fleet-details-dialog')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('official-fleet-open-website')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

OfficialFleetModule _module(OfficialFleetPort port) =>
    createOfficialFleetModule(
      port,
      UnavailableOfficialFleetOverviewAdapter(),
      InMemoryOfficialFleetMembersAdapter.forReview(),
      UnavailableOfficialFleetShipsAdapter(),
    );
Widget _app(OfficialFleetModule module) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  ),
  home: Scaffold(body: OfficialFleetPage(module: module)),
);

class _WebsitePort implements OfficialFleetPort, OfficialFleetWebsitePort {
  final changed = StreamController<void>.broadcast(sync: true);
  final opened = <String>[];
  final result = Completer<bool>();
  OfficialFleetSnapshot? snapshot;
  @override
  Stream<void> get invalidations => changed.stream;
  @override
  bool get supportsWebsite => true;
  @override
  Future<bool> openWebsite(String sid) {
    opened.add(sid);
    return result.future;
  }

  @override
  Future<OfficialFleetSnapshot> read() async =>
      snapshot ??
      await InMemoryOfficialFleetAdapter.forReview(signedIn: true).read();
  @override
  Future<void> close() => changed.close();
}
