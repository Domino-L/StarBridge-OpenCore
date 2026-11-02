// Slice30: the market filter's category tree rows. Native geometry and the
// rows' own text style measured before the change are pinned for the
// standard suite; every suite keeps one reader action per row (now spoken as
// selected for the current category) and pointer activation.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_filters.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Finder _row(int id) =>
    find.byKey(ValueKey<(String, int)>(('market-category', id)));

Future<MarketplaceController> _tree(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceController(TradesPort());
  c.browser.categories = [
    for (var i = 1; i <= 4; i++) {'id': i, 'parentId': 0, 'name': '分类 $i'},
  ];
  await c.browser.choose(kind: 'items');
  await tester.pumpWidget(
    scopedApp(
      SizedBox(
        width: 300,
        height: 860,
        child: MarketplaceMarketFilters(c, reset: (w) => w),
      ),
      suite,
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final c = await _tree(tester, InteractionSuite.standard);
    try {
      expect(tester.getRect(_row(0)), const Rect.fromLTRB(503, 33, 777, 67));
      expect(tester.getRect(_row(1)), const Rect.fromLTRB(503, 67, 777, 101));
      expect(
        tester.getRect(find.text('分类 1')),
        const Rect.fromLTRB(541, 75, 755, 93),
      );
      final style = tester
          .widget<RichText>(
            find.descendant(
              of: find.text('分类 1'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!;
      expect(style.fontSize, 13);
      expect(style.color?.toARGB32(), 0xff93a4ae);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: rows choose a category by reader and pointer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _tree(tester, suite);
      try {
        activate(tester, namedButton(tester, '分类 2'));
        await tester.pumpAndSettle();
        expect(c.browser.category, 2);
        await tester.tap(_row(0));
        await tester.pumpAndSettle();
        expect(c.browser.category, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
