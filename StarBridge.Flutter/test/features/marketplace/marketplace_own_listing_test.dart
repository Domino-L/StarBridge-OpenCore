import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trade_confirm.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_controller.dart';

import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_trade_precheck_test.dart' show PrecheckPort;

void main() {
  tearDown(marketMyOrders.clear);

  testWidgets('own listings say 我 with a tag instead of the masked name', (
    tester,
  ) async {
    marketMyOrders.add('O-MINE');
    await tester.pumpWidget(
      preview(
        const Column(
          children: [
            MarketTrader({'orderNumber': 'O-MINE', 'seller': 'd*******N'}),
            MarketTrader({'orderNumber': 'O-OTHER', 'seller': 'a***u'}),
          ],
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('d*******N'), findsNothing);
    expect(find.text('我'), findsOneWidget);
    expect(find.text('我的挂单'), findsOneWidget);
    expect(find.text('a***u'), findsOneWidget);
  });

  testWidgets('a trade with your own listing never opens', (tester) async {
    marketMyOrders.add('O-MINE');
    final port = PrecheckPort('marketplace.trade_rejected');
    final market = MarketplaceController(port);
    await tester.pumpWidget(
      preview(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmMarketTrade(context, market, {
              'orderNumber': 'O-MINE',
              'itemName': 'Fixture',
              'creatorType': 1,
              'availableQuantity': 1,
              'locationId': 1,
              'unitPrice': 1,
            }),
            child: const Text('open'),
          ),
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('这是你自己发布的挂单，不能和自己交易'), findsOneWidget);
    expect(port.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    market.dispose();
  });

  test('SCM self-trade rejection is a definite, specific answer', () {
    expect(tradeAccountPrechecks, contains('marketplace.own_listing'));
    expect(
      tradeError(const MarketplaceTradeError('marketplace.own_listing')),
      '这是你自己发布的挂单，不能和自己交易。',
    );
  });

  test('own listings become hall cards; 管理挂单 opens the listings sub-tab', () {
    final card = marketOwnListingCard({
      'id': 'O-SELL', 'name': '科力晶', 'itemId': 5, 'side': 'buy',
      'visible': true, 'price': 1, 'quantity': 2, 'locationName': '新巴贝奇',
    });
    expect(card['orderNumber'], 'O-SELL');
    expect(card['creatorType'], 0);
    expect(card.containsKey('id'), isFalse);
    expect(card.containsKey('seller'), isTrue);
    final market = MarketplaceController(PrecheckPort('marketplace.trade_rejected'));
    market.openMyListings();
    expect(market.mainTab, 3);
    expect(market.activityTab, 1);
    market.dispose();
  });

  test('quality and quantity sort locally, one column at a time', () {
    final market = MarketplaceController(PrecheckPort('marketplace.trade_rejected'));
    final rows = <MarketRow>[
      {'orderNumber': 'A', 'availableQuantity': 3, 'qualityData': '{"type":"material","quality":500}'},
      {'orderNumber': 'B', 'availableQuantity': 9, 'qualityData': '{"type":"material","quality":900}'},
      {'orderNumber': 'C', 'availableQuantity': 1},
    ];
    expect(market.sortedOffers(rows).map((r) => r['orderNumber']), ['A', 'B', 'C']);
    market.offerSortField = 'quality';
    market.offerSortDesc = true;
    expect(market.sortedOffers(rows).map((r) => r['orderNumber']), ['B', 'A', 'C']);
    market.offerSortField = 'quantity';
    market.offerSortDesc = false;
    expect(market.sortedOffers(rows).map((r) => r['orderNumber']), ['C', 'A', 'B']);
    market.dispose();
  });
}
