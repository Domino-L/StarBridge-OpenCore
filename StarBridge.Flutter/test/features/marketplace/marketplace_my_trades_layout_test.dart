// 我的交易 layout A and the quality tags (user 2026-10-23): an empty trade
// list says what to do next, and every quality tag uses its tier's colour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_diagonal.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trades_page.dart';

import 'marketplace_slice4_test.dart' show preview;
import 'marketplace_trades_test.dart' show TradesPort;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  testWidgets('only finished trades: the active list explains itself', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final port = TradesPort()
      ..row = {
        'transactionNumber': 'T9',
        'itemsName': '科力晶',
        'actorRole': 'seller',
        'creatorType': 1,
        'deliveryStatus': 3,
        'transactionStatus': 3,
        'amount': 1200000,
        'number': 1,
      };
    final c = MarketplaceController(port);
    addTearDown(c.dispose);
    await c.trades.refresh();
    await tester.pumpWidget(
      scopedApp(MarketplaceTradesPage(c), InteractionSuite.standard),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('market-trades-empty')), findsOneWidget);
    expect(find.text('还没有进行中的交易'), findsOneWidget);
    expect(find.text('已显示全部'), findsNothing);
    expect(find.text('我的交易'), findsNothing, reason: 'no repeated heading');
    await tester.tap(find.byKey(const Key('market-trades-empty-market')));
    await tester.pumpAndSettle();
    expect(c.mainTab, 1, reason: 'opens the market');
    expect(tester.takeException(), isNull);
  });

  testWidgets('极品 in a table shows only its number, with the foil', (
    tester,
  ) async {
    MarketRow row(int q) => {
      'qualityData': {'type': 'material', 'quality': q},
    };
    await tester.pumpWidget(
      preview(
        Column(
          children: [
            MarketQualityBadge(row(961)),
            MarketQualityBadge(row(967), prefixed: true),
          ],
        ),
        AppearanceMode.dark,
      ),
    );
    await tester.pump();
    expect(find.byType(MarketFoilTag), findsNWidgets(2));
    expect(find.text('961'), findsOneWidget);
    expect(find.text('品质 967'), findsOneWidget);
    expect(find.textContaining('极品'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
