// Slice28: the item page's sub-components — offer status chips, the quality
// menu chip, offer sort headers, "clear filters" and the related rows/chips.
// Native geometry (and inherited text style) measured before the change is
// pinned for the standard suite; every suite keeps one reader action per
// control, pointer activation, and the menu chip still opens its menu.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_components.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_routes_motion_test.dart' show seed;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Finder _of(Type type, String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(type)).first;
final _clear = find.byKey(const Key('market-offer-clear-filters'));

Future<MarketplaceController> _page(
  WidgetTester tester,
  InteractionSuite suite, {
  double width = 1280,
}) async {
  size(tester, Size(width, 900));
  final c = MarketplaceController(TradesPort());
  seed(c);
  c.offerSortField = 'time';
  // The app rebuilds the item page from the controller (the hall's ListenableBuilder).
  await tester.pumpWidget(
    scopedApp(
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => MarketplaceItemPage(c),
      ),
      suite,
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

/// The exposed button whose label starts with [label].
void _activate(WidgetTester tester, String label) {
  activate(
    tester,
    exposedNodes(tester).firstWhere((n) {
      final d = n.getSemanticsData();
      return d.label.startsWith(label) && d.flagsCollection.isButton;
    }),
  );
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    var c = await _page(tester, InteractionSuite.standard);
    try {
      for (final (label, rect) in [
        ('全部', const Rect.fromLTRB(300, 214.5, 350.5, 241.5)),
        ('在线', const Rect.fromLTRB(356.5, 214.5, 407, 241.5)),
        ('游戏中', const Rect.fromLTRB(413, 214.5, 475.75, 241.5)),
        ('品质 ≥', const Rect.fromLTRB(481.75, 214.5, 572.75, 241.5)),
        ('全部地点', const Rect.fromLTRB(578.75, 214.5, 669.75, 241.5)),
      ]) {
        expect(
          tester.getRect(_of(ItemFilterChip, label)),
          within(distance: .001, from: rect),
        );
      }
      // Sort headers keep the inherited, scaled-down header text.
      expect(
        tester.getRect(_of(ItemSortHeader, '数量')),
        within(
          distance: .001,
          from: const Rect.fromLTRB(969.8, 260, 1007, 284),
        ),
      );
      expect(
        tester.getRect(find.text('数量')),
        within(
          distance: .001,
          from: const Rect.fromLTRB(969.8, 264, 992.6, 280),
        ),
      );
      expect(
        tester.getRect(_of(ItemRelatedRow, '兼容配件')),
        const Rect.fromLTRB(0, 463, 280, 502),
      );
      expect(
        tester.getRect(find.text('兼容配件')),
        const Rect.fromLTRB(26, 473, 262, 491),
      );
      expect(
        tester.getRect(_clear),
        within(
          distance: .001,
          from: const Rect.fromLTRB(675.75, 208, 744.15, 248),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      c = await _page(tester, InteractionSuite.standard, width: 800);
      expect(
        tester.getRect(_of(ItemRelatedChip, '兼容配件')),
        within(
          distance: .001,
          from: const Rect.fromLTRB(249.2, 148, 351.2, 176),
        ),
      );
      expect(
        tester.getRect(find.text('兼容配件')),
        within(
          distance: .001,
          from: const Rect.fromLTRB(278.2, 153, 329.2, 171),
        ),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: chips, sort and clear by reader and pointer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _page(tester, suite);
      try {
        _activate(tester, '在线');
        await tester.pumpAndSettle();
        expect(c.offerFilters['creatorStatus'], '1');
        await tester.tap(find.text('游戏中'));
        await tester.pumpAndSettle();
        expect(c.offerFilters['creatorStatus'], '2');
        // Activating the active status again clears it back to 全部.
        await tester.tap(find.text('游戏中'));
        await tester.pumpAndSettle();
        expect(c.offerFilters.containsKey('creatorStatus'), isFalse);
        await tester.tap(find.text('游戏中'));
        await tester.pumpAndSettle();
        expect(c.offerFilters['creatorStatus'], '2');
        _activate(tester, '单价');
        await tester.pumpAndSettle();
        expect(c.offerSortField, 'price');
        await tester.tap(find.text('数量'));
        await tester.pumpAndSettle();
        expect(c.offerSortField, 'quantity');
        _activate(tester, '全部清除');
        await tester.pumpAndSettle();
        expect(c.offerFilters, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: the quality menu chip still opens its menu', (
      tester,
    ) async {
      final c = await _page(tester, suite);
      try {
        await tester.tap(find.text('品质 ≥'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('≥ 400'));
        await tester.pumpAndSettle();
        expect(c.offerFilters['minQuality'], '400');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });

    testWidgets('${suite.name}: related rows keep one reader action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _page(tester, suite);
      try {
        final node = exposedNodes(tester)
            .firstWhere((n) => n.getSemanticsData().label.startsWith('兼容配件'));
        expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
