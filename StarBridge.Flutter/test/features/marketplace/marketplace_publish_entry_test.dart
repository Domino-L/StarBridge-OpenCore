import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/bridge_marketplace_listings_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_publish_entry.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'marketplace_bridge_trade_test.dart' show Online;
import 'marketplace_slice4_test.dart' show preview;

void main() {
  testWidgets('publish opens the wizard at once, before the Host answers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(['marketplace.read', 'marketplace.listings']);
    // The Host never answers: the click must still give visible feedback.
    final subscription = pair.host.incoming.listen((_) {});
    final mode = Online();
    final market = MarketplaceController(BridgeMarketplacePort(session, mode));
    await tester.pumpWidget(
      preview(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openMarketPublish(context, market),
            child: const Text('publish'),
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('publish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ListingPublishDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    market.dispose();
    mode.dispose();
    // The unanswered request must not hold the test open.
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close().timeout(const Duration(seconds: 1), onTimeout: () {});
      await pair.host.close().timeout(const Duration(seconds: 1), onTimeout: () {});
    });
  });

  testWidgets('我也要收 opens the wizard on step 3 with item and side filled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    session.acceptHostCapabilities(['marketplace.read', 'marketplace.listings']);
    final subscription = pair.host.incoming.listen((_) {});
    final mode = Online();
    final market = MarketplaceController(BridgeMarketplacePort(session, mode));
    await tester.pumpWidget(
      preview(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openMarketPublish(
              context,
              market,
              item: listingPickable({
                'id': 43475,
                'itemName': '科力晶（单个矿块）',
                'qualityInfo': '{"q":1}',
                'best': 995574,
                'highestBuy': 900000,
              }),
              side: 'buy',
            ),
            child: const Text('also-buy'),
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('also-buy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final dialog = tester.widget<ListingPublishDialog>(find.byType(ListingPublishDialog));
    expect(dialog.initialStep, 2);
    expect(dialog.draft.side, 'buy');
    expect(dialog.draft.item['name'], '科力晶（单个矿块）');
    expect(dialog.draft.item['hasQuality'], isTrue);
    expect(dialog.draft.item['highestBuy'], 900000);
    await tester.pumpWidget(const SizedBox.shrink());
    market.dispose();
    mode.dispose();
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close().timeout(const Duration(seconds: 1), onTimeout: () {});
      await pair.host.close().timeout(const Duration(seconds: 1), onTimeout: () {});
    });
  });
}
