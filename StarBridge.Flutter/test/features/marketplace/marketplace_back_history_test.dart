// User 10-29 (images/44): 返回 goes back to the page you came from — item →
// 兼容配件 catalog → 返回 lands on that item, with its tab — and names it;
// the 撤销 bar times out, never stacks, and leaves with the page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

import 'marketplace_test.dart' show FixturePort, app;

Future<MarketplaceController> _hall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final c = MarketplaceController(FixturePort());
  await tester.pumpWidget(
    app(c, AppearanceMode.dark, const Locale('zh', 'CN')),
  );
  await tester.pumpAndSettle();
  return c;
}

String _name(MarketplaceController c, int id) =>
    marketName(c.blocks['recent:$id']!.data, 'zh-CN');

final _itemBack = find.byKey(const Key('marketplace-back'));
final _catalogBack = find.byKey(const Key('market-catalog-back'));

void main() {
  testWidgets('item → related catalog → back returns to that item and tab', (
    tester,
  ) async {
    final c = await _hall(tester);
    try {
      await c.openItem(3);
      await tester.pumpAndSettle();
      c.selectItemTab(2);
      await tester.pumpAndSettle();
      await c.related('attachments', 3);
      await tester.pumpAndSettle();
      expect(c.itemId, isNull);
      expect(c.relation, 'attachments');
      // The button names the item it returns to, not a fixed 大厅.
      expect(
        find.descendant(
          of: _catalogBack,
          matching: find.textContaining(_name(c, 3)),
        ),
        findsOneWidget,
      );
      await tester.tap(_catalogBack);
      await tester.pumpAndSettle();
      expect(
        c.itemId,
        3,
        reason: 'back from the related catalog lands on the item',
      );
      expect(c.itemTab, 2, reason: 'the item tab is kept');
      // With no history left, the item goes back to the tab it came from.
      expect(
        find.descendant(of: _itemBack, matching: find.textContaining('大厅')),
        findsOneWidget,
      );
      await tester.tap(_itemBack);
      await tester.pumpAndSettle();
      expect(c.itemId, isNull);
      expect(c.relation, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('search catalog → item → back → catalog → back → hall', (
    tester,
  ) async {
    final c = await _hall(tester);
    try {
      await c.browse(query: 'quant');
      await tester.pumpAndSettle();
      // Refining inside the catalog replaces the step instead of stacking it.
      await c.browse(query: 'quantainium');
      await tester.pumpAndSettle();
      await c.openItem(2);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: _itemBack, matching: find.textContaining('物品目录')),
        findsOneWidget,
      );
      await tester.tap(_itemBack);
      await tester.pumpAndSettle();
      expect(c.itemId, isNull);
      expect(c.keyword, 'quantainium');
      expect(
        find.descendant(of: _catalogBack, matching: find.textContaining('大厅')),
        findsOneWidget,
      );
      await tester.tap(_catalogBack);
      await tester.pumpAndSettle();
      expect(
        c.keyword,
        isEmpty,
        reason: 'one back from the catalog is the hall',
      );
      expect(c.backTarget, isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('top tabs start over; history never grows past twenty', (
    tester,
  ) async {
    final c = await _hall(tester);
    try {
      await c.openItem(1);
      await c.related('attachments', 1);
      c.tab(3);
      await tester.pumpAndSettle();
      expect(c.backTarget, isNull);
      for (var i = 1; i <= 30; i++) {
        await c.openItem(i);
      }
      await tester.pumpAndSettle();
      var steps = 0;
      while (c.backTarget != null) {
        c.back();
        steps++;
      }
      expect(steps, 20);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets('the 撤销 bar times out, never stacks and leaves with the page', (
    tester,
  ) async {
    final c = await _hall(tester);
    try {
      await c.toggleFavorite(1);
      await c.toggleFavorite(2);
      await c.openItem(1);
      await tester.pumpAndSettle();
      final follow = find.byKey(const Key('market-item-follow'));
      await tester.tap(follow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('撤销'), findsOneWidget);
      // Five seconds later it is gone without being touched.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('撤销'), findsNothing);
      // A second message replaces the first instead of queueing behind it.
      await tester.tap(follow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(follow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);
      // Leaving the page puts it away.
      c.tab(3);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });
}
