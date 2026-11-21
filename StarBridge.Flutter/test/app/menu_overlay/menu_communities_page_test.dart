import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_communities_page.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_page_relay.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/community_shortcuts.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_bridge_relay.dart';

const _primary = MethodChannel('test/org-primary');
const _surface = MethodChannel('test/org-surface');
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
        'communities.read',
        'communities.workspace',
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

  for (final (width, iconOnly) in const [(1460.0, false), (1180.0, true)]) {
    testWidgets('the client organization page and its left list mount through '
        'the relay at $width wide', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      menu.update(opening: opening, wanted: true, enabled: true);
      final owner = MenuCommunitiesOwner(menu);
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
              width: width,
              height: 800,
              child: MenuCommunitiesPage(owner: owner),
            ),
          ),
        ),
      );
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.byType(CommunitiesPage), findsOneWidget);
      expect(
        tester.widget<CommunityShortcuts>(find.byType(CommunityShortcuts)).iconOnly,
        iconOnly,
      );
      expect(host.seen.where((name) => name.startsWith('communities.')), isNotEmpty);
      expect(tester.takeException(), isNull);
      menu.update(opening: opening, wanted: false, enabled: true);
      await tester.pumpWidget(const SizedBox());
      await pumpFor(tester, const Duration(seconds: 1));
      owner.dispose();
      await menu.release();
      await pumpFor(tester, const Duration(seconds: 1));
    });
  }
}
