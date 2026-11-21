import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_panel_specs.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_marketplace_page.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_theme.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_page_relay.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_feedback.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

const _channel = MethodChannel('test/hall-surface');
const _owner = BridgeAccountContext(
  environment: 'test',
  authority: 'test',
  subject: 'owner',
);

Widget _app(MenuMarketplaceOwner owner, {Size size = const Size(1180, 760)}) =>
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildMenuOverlayTheme(const Locale('zh', 'CN')),
      home: Center(
        child: SizedBox.fromSize(
          size: size,
          child: MenuMarketplacePage(owner: owner),
        ),
      ),
    );

void main() {
  final messenger = TestWidgetsFlutterBinding.ensureInitialized()
      .defaultBinaryMessenger;
  final requests = <String>[];
  Completer<void>? holdHello;
  var capabilities = ['marketplace.read', 'marketplace.preferences'];
  var relayId = 1;

  setUp(() {
    requests.clear();
    holdHello = null;
    relayId = 1;
    capabilities = ['marketplace.read', 'marketplace.preferences'];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'bridgeRelay');
      final args = call.arguments as Map;
      if (args['action'] == 'hello') {
        await holdHello?.future;
        return jsonEncode({
          'kind': 'state',
          'relay': relayId,
          'generation': 1,
          'capabilities': capabilities,
          'online': true,
        });
      }
      final request = BridgeEnvelope.fromJson(
        (jsonDecode(args['payload'] as String) as Map).cast<String, Object?>(),
      );
      requests.add(request.name);
      return jsonEncode(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 1,
          accountContext: request.name == 'account.getCurrent' ? _owner : null,
          payload: request.name == 'account.getCurrent'
              ? const {'schemaVersion': 1, 'state': 'signedIn'}
              : {
                  'schemaVersion': 1,
                  'data': {'rows': <Object?>[]},
                  'readAt': '2026-10-30T00:00:00Z',
                },
          status: 'ok',
        ).toJson(),
      );
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    for (var left = total; left > Duration.zero; left -= const Duration(milliseconds: 100)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the real hall page mounts and reads through the relay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final relay = MenuPageRelay(_channel)
      ..update(opening: 4, wanted: true, enabled: true);
    final owner = MenuMarketplaceOwner(relay);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(MarketplacePage), findsOneWidget);
    expect(requests, contains('marketplace.read'));
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(MarketplacePage))),
      const Size(1180, 760),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(seconds: 1));
    owner.dispose();
    await pumpFor(tester, const Duration(seconds: 1));
  });

  testWidgets('a hall hidden long enough lets go, and comes back on return', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final relay = MenuPageRelay(_channel)
      ..update(opening: 4, wanted: true, enabled: true);
    final owner = MenuMarketplaceOwner(relay);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    relay.update(opening: 4, wanted: false, enabled: true);
    await tester.pump(const Duration(minutes: 9));
    expect(find.byType(MarketplacePage), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(MarketplacePage), findsNothing);
    relay.update(opening: 5, wanted: true, enabled: true);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(MarketplacePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(seconds: 1));
    owner.dispose();
    await pumpFor(tester, const Duration(seconds: 1));
  });

  testWidgets('the hall outlives a panel rebuild, and an account change clears its dialogs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final relay = MenuPageRelay(_channel)
      ..update(opening: 4, wanted: true, enabled: true);
    final owner = MenuMarketplaceOwner(relay);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    final first = tester.widget<MarketplacePage>(find.byType(MarketplacePage));
    // The workspace builds new panels every opening.
    relay.update(opening: 4, wanted: false, enabled: true);
    await tester.pumpWidget(const SizedBox());
    relay.update(opening: 5, wanted: true, enabled: true);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    final second = tester.widget<MarketplacePage>(find.byType(MarketplacePage));
    expect(identical(first.controller, second.controller), isTrue);

    final page = tester.element(find.byType(MarketplacePage));
    unawaited(
      tradeMotionDialog<void>(page, (_) => const Text('panel-dialog')),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    final dialog = find.text('panel-dialog');
    expect(dialog, findsOneWidget);
    // Inside the panel's navigator, not the app's.
    expect(
      Navigator.of(tester.element(dialog)),
      isNot(
        same(
          Navigator.of(tester.element(dialog), rootNavigator: true),
        ),
      ),
    );

    relay.accept({
      'opening': 5,
      'payload': jsonEncode({
        'kind': 'state',
        'generation': 2,
        'capabilities': ['marketplace.read', 'marketplace.preferences'],
        'online': true,
      }),
    });
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('panel-dialog'), findsNothing);
    expect(find.byType(MarketplacePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await pumpFor(tester, const Duration(seconds: 1));
  });

  testWidgets('trade chat opens inside the panel and catches up on reopening', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    capabilities = [...capabilities, 'marketplace.chat'];
    final relay = MenuPageRelay(_channel)
      ..update(opening: 4, wanted: true, enabled: true);
    final owner = MenuMarketplaceOwner(relay);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    final chat = tester
        .widget<MarketplacePage>(find.byType(MarketplacePage))
        .controller
        .tradeChat;
    expect(chat, isNotNull);
    expect(chat!.supported, isTrue);

    requests.clear();
    chat.requestShow();
    await pumpFor(tester, const Duration(seconds: 1));
    final view = find.byKey(const Key('menu-trade-chat'));
    expect(view, findsOneWidget);
    expect(requests, contains('marketplace.chat'));
    expect(
      Navigator.of(tester.element(view)),
      isNot(same(Navigator.of(tester.element(view), rootNavigator: true))),
    );
    // A second request while it is open goes to the open view.
    chat.requestShow();
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(view, findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-trade-chat-close')));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(view, findsNothing);

    // Hidden: no pushes reach the menu. Reopening reads what was missed.
    relay.update(opening: 4, wanted: false, enabled: true);
    await tester.pumpWidget(const SizedBox());
    requests.clear();
    relay.update(opening: 5, wanted: true, enabled: true);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(requests, contains('marketplace.chat'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await pumpFor(tester, const Duration(seconds: 1));
  });

  testWidgets('retained content stays covered until the opening is verified', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final relay = MenuPageRelay(_channel)
      ..update(opening: 4, wanted: true, enabled: true);
    final owner = MenuMarketplaceOwner(relay);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    final first = tester.widget<MarketplacePage>(find.byType(MarketplacePage));
    relay.update(opening: 4, wanted: false, enabled: true);
    await tester.pumpWidget(const SizedBox());

    holdHello = Completer();
    relay.update(opening: 5, wanted: true, enabled: true);
    await tester.pumpWidget(_app(owner));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(MarketplacePage), findsNothing);

    // The greeting shows another primary composition: nothing old is reused.
    relayId = 2;
    holdHello!.complete();
    await pumpFor(tester, const Duration(seconds: 1));
    final second = tester.widget<MarketplacePage>(find.byType(MarketplacePage));
    expect(identical(first.controller, second.controller), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await pumpFor(tester, const Duration(seconds: 6));
  });

  test('the hall panel starts from the approved size and stays on screen', () {
    final spec = menuBridgePanelSpecs(
      hasHangar: false,
      hasLocalTools: false,
      profileIds: const [],
      hasMarketplace: true,
    ).singleWhere((panel) => panel.id == 'marketplace');
    expect(spec.minimumSize, const Size(900, 600));
    expect(spec.viewportBounds!(const Size(1920, 1080)).size, const Size(1180, 760));
    final small = spec.viewportBounds!(const Size(1280, 720));
    expect(small.size, const Size(1180, 600));
    expect((const Offset(0, 0) & const Size(1280, 720)).contains(small.center), isTrue);
    expect(
      menuBridgePanelSpecs(
        hasHangar: false,
        hasLocalTools: false,
        profileIds: const [],
      ).any((panel) => panel.id == 'marketplace'),
      isFalse,
    );
  });
}
