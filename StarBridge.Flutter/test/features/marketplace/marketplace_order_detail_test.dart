// Regression (user report, build 11, 2026-10-20):
// - slanted filter chips sat inside a rectangular box under the non-standard
//   suites (their secondary kind paints a raised fill and border at rest);
// - market orders should read like the hall's cards;
// - an order's detail sheet showed almost nothing useful.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

MarketRow _order(
  String number,
  num price, {
  int display = 1,
  String? remark,
  int quantity = 3,
}) => {
  'orderNumber': number,
  'itemId': 100,
  'itemName': display == 2 ? '枪口配件清单' : '科力晶（单个矿块）',
  'remainingQuantity': quantity,
  'locationName': '埃弗勒斯空间站',
  'creatorType': 1,
  'displayType': display,
  'unitPrice': price,
  'seller': 'A*****y',
  'presence': 'online',
  'point': 30,
  'remark': ?remark,
  'hasOngoingTransactions': number == 'O1',
  'items': [
    {'itemId': 100, 'itemName': '科力晶（单个矿块）', 'quantity': 1},
    if (display == 2)
      {
        'itemId': 201,
        'itemName': '实准 枪口补偿器 3',
        'quantity': 2,
        'unitPrice': 150000,
      },
  ],
};

class _Port extends TradesPort {
  final operations = <String>[];
  @override
  Future<MarketRead> read(
    String operation, {
    int id = 0,
    String keyword = '',
    int category = 0,
    int side = 1,
    int page = 1,
    String language = 'CN',
    Map<String, String> options = const {},
  }) {
    operations.add(operation);
    final at = DateTime.utc(2026, 10, 20);
    if (operation == 'marketOrders' || operation == 'latest') {
      return Future.value(
        MarketRead({
          'rows': [
            _order('O1', 1000000, remark: '晚上 8 点后在线'),
            _order('O2', 380000, display: 2),
          ],
          'total': 2,
          'pageEnd': true,
        }, at),
      );
    }
    if (operation == 'offers') {
      return Future.value(
        MarketRead({
          'rows': [
            _order('X1', 950000),
            _order('O1', 1000000),
            _order('X2', 1200000),
          ],
          'total': 3,
          'pageEnd': true,
        }, at),
      );
    }
    if (operation == 'trend') {
      return Future.value(
        MarketRead({'sellVWAP': '1062000', 'buyVWAP': '880000'}, at),
      );
    }
    if (operation == 'bestPrices') {
      return Future.value(
        MarketRead({
          'rows': [
            {'id': 100, 'side': 1, 'price': '950000'},
          ],
        }, at),
      );
    }
    return super.read(
      operation,
      id: id,
      keyword: keyword,
      category: category,
      side: side,
      page: page,
      language: language,
      options: options,
    );
  }
}

Finder _card(String n) =>
    find.byKey(ValueKey<(String, Object)>(('market-order-card', n)));

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: slanted chips draw no rectangular box', (
      tester,
    ) async {
      size(tester, const Size(800, 600));
      await tester.pumpWidget(
        scopedApp(
          Center(
            child: MarketToggle(
              label: const Text('只看有挂单'),
              selected: false,
              onSelected: (_) {},
            ),
          ),
          suite,
        ),
      );
      await tester.pumpAndSettle();
      if (suite == InteractionSuite.standard) {
        // Native path: a text button, no outline and no hover overlay.
        final button = tester.widget<TextButton>(find.byType(TextButton));
        // No visible outline (the theme may supply a zero-width "none").
        final side = button.style?.side?.resolve({});
        expect(side == null || side.style == BorderStyle.none, isTrue);
        expect(
          button.style?.overlayColor?.resolve({WidgetState.hovered}),
          Colors.transparent,
        );
      } else {
        final face = tester.widget<SuitePressable>(find.byType(SuitePressable));
        // The row kind has no raised fill or border at rest; the slant
        // draws its own hover instead of the suite's rectangle.
        expect(face.kind, PressableKind.row);
        expect(face.hoverFace, isFalse);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'orders open as hall cards; details tell what the order is worth',
    (tester) async {
      size(tester, const Size(1500, 900));
      final port = _Port();
      final c = MarketplaceController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        scopedApp(MarketplaceMarketPage(c), InteractionSuite.standard),
      );
      await tester.pumpAndSettle();
      await c.browser.choose(kind: 'orders');
      await tester.pumpAndSettle();

      expect(c.browser.layout, 'cards');
      expect(tester.widget(_card('O1')), isA<MarketCard>());

      await tester.tap(_card('O1'));
      await tester.pumpAndSettle();
      expect(find.text('订单详情'), findsOneWidget);
      // Price, quantity and what all of it costs.
      expect(find.text('¤ 1,000,000'), findsOneWidget);
      expect(find.text('×3'), findsWidgets);
      expect(find.text('¤ 300万'), findsOneWidget);
      // Against the market: the lowest ask and the recent average.
      expect(find.text('当前最低卖价'), findsOneWidget);
      expect(find.text('¤ 950,000'), findsOneWidget);
      expect(find.text('高 5.3%'), findsOneWidget);
      expect(find.text('近期均价'), findsOneWidget);
      expect(find.text('低 5.8%'), findsOneWidget);
      // Trader, note, ongoing trade.
      expect(find.text('交易方'), findsOneWidget);
      expect(find.text('晚上 8 点后在线'), findsOneWidget);
      expect(find.text('有进行中的交易'), findsOneWidget);
      // The item's other offers, never this order itself.
      expect(find.text('同物品其他报价'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<(String, Object)>(('market-order-other', 'X1')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<(String, Object)>(('market-order-other', 'O1')),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('market-order-close')));
      await tester.pumpAndSettle();

      // A bundle lists what is inside; no single-item comparison is read.
      port.operations.clear();
      await tester.tap(_card('O2'));
      await tester.pumpAndSettle();
      expect(find.text('清单内容'), findsOneWidget);
      expect(find.text('实准 枪口补偿器 3'), findsOneWidget);
      expect(find.text('行情对比'), findsNothing);
      expect(port.operations, isNot(contains('offers')));
      await tester.tap(find.byKey(const Key('market-order-close')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
