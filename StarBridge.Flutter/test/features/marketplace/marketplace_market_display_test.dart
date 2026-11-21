// Round-2 audit, market display (MK1, MK2, MK7, MK8, MK10): what list rows
// can and cannot say, given SCM lists carry only the first item and no
// wanted side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_copy.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hall_drawers.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_listing_copy_test.dart' show localized;
import 'marketplace_test.dart' show FixturePort;

void main() {
  test('MK1/MK2: only orders whose first item is the order show its picture and quality', () {
    final single = {'displayType': 1, 'creatorType': 1,
      'items': [{'thumbnailUrl': 'https://img.invalid/a.png'}]};
    expect(marketShowsItemVisual(single), isTrue);
    expect(marketThumbnail(single), 'https://img.invalid/a.png');
    // A checklist, a buy-side barter (titled after the wanted item) and a
    // multi-item barter use the crate and show no quality.
    for (final row in [
      {...single, 'displayType': 2},
      {...single, 'displayType': 3, 'creatorType': 0},
      {...single, 'displayType': 3, 'itemCount': 2},
    ]) {
      expect(marketShowsItemVisual(row), isFalse, reason: '$row');
      expect(marketThumbnail(row), marketChecklistArt, reason: '$row');
    }
    // A list row never says how many items a barter has: unknown is not one.
    expect(marketShowsItemVisual({...single, 'displayType': 3}), isFalse);
    // A one-item sell barter is titled after its offered item: keep its art,
    // once known from itemCount or from the full order's items.
    expect(marketShowsItemVisual({...single, 'displayType': 3, 'itemCount': 1}), isTrue);
    expect(marketShowsItemVisual({...single, 'displayType': 3, 'itemsComplete': true}), isTrue);
    expect(marketShowsItemVisual({...single, 'displayType': 3, 'itemsComplete': true,
      'items': [{'itemId': 1}, {'itemId': 2}]}), isFalse);
  });

  testWidgets('MK7: search rows say their counts include checklists; item reads split them', (tester) async {
    final c = MarketplaceController(FixturePort());
    addTearDown(c.dispose);
    Future<void> show(Map<String, Object?> row) async {
      await tester.pumpWidget(localized(Builder(builder: (context) =>
          Material(child: marketCatalogDrawer(context, context, c, row))),
          const Locale('zh', 'CN')));
      await tester.pumpAndSettle();
    }

    // The Host writes null for keys SCM left out: a search row.
    await show({'id': 7, 'sellOrderCount': 12, 'buyOrderCount': 3,
      'checklistSellCount': null, 'checklistBuyCount': null});
    expect(find.text('出售（含清单）'), findsOneWidget);
    expect(find.text('求购（含清单）'), findsOneWidget);
    expect(find.text('清单挂单'), findsNothing);

    await show({'id': 7, 'sellOrderCount': 9, 'buyOrderCount': 2,
      'checklistSellCount': 3, 'checklistBuyCount': 1});
    expect(find.text('出售'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('MK1/MK8/MK10 copy in three languages', (tester) async {
    for (final (locale, index) in [
      (const Locale('zh', 'CN'), 0), (const Locale('zh', 'TW'), 1), (const Locale('en'), 2),
    ]) {
      await tester.pumpWidget(localized(Builder(builder: (context) => Column(children: [
        Text(marketText(context, 'seeDetail')),
        Text(marketText(context, 'drawerChange')),
        Text(marketText(context, 'singleSell')),
      ])), locale));
      await tester.pumpAndSettle();
      expect(find.text(['看详情', '看詳情', 'see details'][index]), findsOneWidget);
      expect(find.text(['较上一交易日', '較上一交易日', 'vs previous trading day'][index]), findsOneWidget);
      expect(find.text(['单件出售', '單件出售', 'Single-item sell orders'][index]), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
