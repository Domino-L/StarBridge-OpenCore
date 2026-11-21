import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_fleet_page.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_page_relay.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_bridge_relay.dart';

const _primary = MethodChannel('test/fleet-primary');
const _surface = MethodChannel('test/fleet-surface');
const _owner = BridgeAccountContext(
  environment: 'test',
  authority: 'test',
  subject: 'owner',
);

/// The primary engine's Host, answering the main fleet reads.
final class _Host {
  _Host() {
    final pair = InMemoryBridgeConnection.createPair();
    connection = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 3)
      ..acceptHostCapabilities(const {
        'account.getCurrent',
        'officialFleet.getCurrent',
        'officialFleet.getMembers',
        'officialFleet.governanceRole',
      });
    pair.host.incoming.listen(_answer);
  }
  late final dynamic connection;
  late final BridgeClientSession session;
  final seen = <String>[];

  Future<void> _answer(BridgeEnvelope request) async {
    seen.add(request.name);
    final payload = switch (request.name) {
      'account.getCurrent' => {
        'schemaVersion': 1,
        'state': 'signedIn',
        'displayName': 'Aster Lin',
      },
      'officialFleet.getCurrent' => {
        'schemaVersion': 1,
        'state': 'member',
        'fleet': {
          'sourceRef': 'officialFleet:7',
          'sid': 'ASTER',
          'name': "Aster's Wing",
          'logoUrl': null,
          'officialRankName': 'Officer',
          'officialRankValue': 4,
          'profile': null,
        },
        'freshness': 'live',
        'resourceVersion': 11,
        'observedAtUtc': '2026-09-01T12:00:00Z',
      },
      _ => null,
    };
    await connection.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: _owner,
        payload: payload ?? const {},
        status: payload == null ? 'error' : 'ok',
        error: payload == null
            ? const BridgeErrorBody(
                code: 'test.unanswered',
                message: 'test.unanswered',
                retryable: false,
              )
            : null,
      ),
    );
  }
}

final class _Online extends ChangeNotifier implements ConnectionModeControl {
  @override
  bool get allowsOnlineTraffic => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  final messenger = TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger;
  late _Host host;
  late MenuBridgeRelay primary;
  late MenuPageRelay menu;
  const opening = 9;

  setUp(() {
    host = _Host();
    menu = MenuPageRelay(_surface);
    primary = MenuBridgeRelay(
      host.session,
      mode: () => _Online(),
      channel: _primary,
      ownProfile: () => const AccountProfile(
        displayName: 'Aster Lin',
        email: 'aster@example.invalid',
      ),
    );
    messenger.setMockMethodCallHandler(_primary, (call) async {
      if (call.method == 'bridgeEvent') menu.accept(call.arguments);
      return null;
    });
    messenger.setMockMethodCallHandler(
      _surface,
      (call) =>
          primary.handle(call.arguments, opening: opening, isCurrent: () => true),
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_primary, null);
    messenger.setMockMethodCallHandler(_surface, null);
  });

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    for (
      var left = total;
      left > Duration.zero;
      left -= const Duration(milliseconds: 100)
    ) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the client main fleet page reads through the relay, and its '
      'dialogs stay in the panel', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    menu.update(opening: opening, wanted: true, enabled: true);
    final owner = MenuFleetOwner(menu);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStringsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildMenuOverlayTheme(const Locale('zh', 'CN')),
        home: Center(
          child: SizedBox(
            width: 1180,
            height: 760,
            child: MenuFleetPage(owner: owner),
          ),
        ),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(OfficialFleetPage), findsOneWidget);
    expect(host.seen, contains('officialFleet.getCurrent'));
    expect(find.textContaining("Aster's Wing"), findsWidgets);
    expect(menu.ownProfile?.displayName, 'Aster Lin');
    expect(menu.ownProfile?.email, isNull);
    expect(host.seen, isNot(contains('officialFleet.governanceRole')));

    final page = tester.element(find.byType(OfficialFleetPage));
    unawaited(
      showStarBridgeDialog<void>(
        page,
        builder: (_) => const Text('fleet-dialog'),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    final dialog = find.text('fleet-dialog');
    expect(dialog, findsOneWidget);
    expect(
      Navigator.of(tester.element(dialog)),
      isNot(same(Navigator.of(tester.element(dialog), rootNavigator: true))),
    );

    // Escape closes the panel's dialog, as in the client.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(dialog, findsNothing);
    expect(find.byType(OfficialFleetPage), findsOneWidget);

    // Done in the client only: answered in the menu, a notice in the panel.
    final session = (await tester.runAsync(menu.connect))!;
    Object? failure;
    unawaited(
      session
          .request(
            'account.refreshRsiData',
            payload: const {'schemaVersion': 1},
            accountContext: _owner,
          )
          .then<void>((_) {}, onError: (Object error) => failure = error),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(failure, isNotNull);
    expect(host.seen, isNot(contains('account.refreshRsiData')));
    final notice = find.byKey(const Key('menu-client-only'));
    expect(notice, findsOneWidget);
    expect(find.text('请在客户端里操作'), findsOneWidget);
    expect(
      Navigator.of(tester.element(notice)),
      isNot(same(Navigator.of(tester.element(notice), rootNavigator: true))),
    );
    await tester.tap(find.text('知道了'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(notice, findsNothing);

    // Hidden: the own profile goes, the page shows loading on return.
    menu.update(opening: opening, wanted: false, enabled: true);
    expect(menu.ownProfile, isNull);
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(seconds: 1));
    owner.dispose();
    await menu.release();
    await pumpFor(tester, const Duration(seconds: 1));
  });
}
