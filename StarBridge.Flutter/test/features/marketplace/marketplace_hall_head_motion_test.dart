// Slice38: the hall head — tabs (which keep their own hover text colour and
// slanted preview), the banner "my trades →" button inside its hover card,
// refresh — and the hover drawer's hide confirmation, which now uses the
// suite dialog route. Geometry and text style were compared before and after
// (logs/slice38-*-probe.log).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_publish_entry.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'marketplace_bridge_trade_test.dart' show Online;
import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Finder _tab(String label) =>
    find.byKey(ValueKey<(String, String)>(('market-tab', label)));

Future<MarketplaceController> _hall(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceController(TradesPort());
  await tester.pumpWidget(scopedApp(MarketplacePage(c), suite));
  await tester.pumpAndSettle();
  return c;
}

Color? _color(WidgetTester tester, String text) => tester
    .widget<RichText>(
      find.descendant(of: _tab(text), matching: find.byType(RichText)).first,
    )
    .text
    .style
    ?.color;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: tabs keep their own hover and switch', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _hall(tester, suite);
      try {
        final idle = _color(tester, '市场');
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: tester.getCenter(_tab('市场')));
        await tester.pump();
        expect(_color(tester, '市场'), isNot(idle), reason: 'Hover brightens.');
        await mouse.moveTo(const Offset(5, 880));
        await tester.pump();
        expect(_color(tester, '市场'), idle);
        await mouse.removePointer();
        activate(tester, namedButton(tester, '合约'));
        await tester.pumpAndSettle();
        expect(c.mainTab, 2);
        await tester.tap(_tab('大厅'));
        await tester.pumpAndSettle();
        expect(c.mainTab, 0);
        activate(tester, namedButton(tester, '我的交易 →'));
        await tester.pumpAndSettle();
        expect(c.mainTab, 3);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: hide confirmation uses the suite route', (
      tester,
    ) async {
      size(tester, const Size(1280, 900));
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      session.acceptHostCapabilities([
        'marketplace.read',
        'marketplace.listings',
      ]);
      final writes = <String>[];
      final sub = pair.host.incoming.listen((envelope) {
        writes.add(envelope.toString());
      });
      final mode = Online();
      final market = MarketplaceController(
        BridgeMarketplacePort(session, mode),
      );
      try {
        await tester.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => openMarketListingAction(context, market, {
                  'id': 'L1',
                  'visible': true,
                  'name': 'Fixture',
                }, 'visibility'),
                child: const Text('hide'),
              ),
            ),
            suite,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('hide'));
        await tester.pumpAndSettle();
        final confirm = find.byKey(const ValueKey('drawer-hide-confirm'));
        expect(confirm, findsOneWidget);
        expect(
          ModalRoute.of(tester.element(confirm)),
          isA<StarBridgeDialogRoute<Object?>>(),
        );
        final before = writes.length;
        await tester.tap(find.byKey(const ValueKey('drawer-hide-cancel')));
        await tester.pumpAndSettle();
        expect(confirm, findsNothing);
        expect(writes.length, before, reason: 'Cancel never writes.');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        market.dispose();
        mode.dispose();
        await tester.pump(const Duration(minutes: 2));
        await tester.runAsync(() async {
          await sub.cancel();
          await session.close().timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
          await pair.host.close().timeout(
            const Duration(seconds: 1),
            onTimeout: () {},
          );
        });
      }
    });
  }
}
