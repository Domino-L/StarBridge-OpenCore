// Slice35: the item page's "quality ≥" offer filter menu joins the shared
// menu anchor. Its chip keeps the measured native geometry; menu items keep
// the native 112 x 48 size and 12px inset (the menu now opens below the chip,
// as the other migrated marketplace menus do); every suite keeps one reader
// action for the chip and each entry, and pointer selection.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_routes_motion_test.dart' show seed;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

final _chip = find.byKey(const Key('market-quality-menu'));
Finder _entry(String value) =>
    find.byKey(ValueKey<(String, String)>(('market-quality', value)));

Future<MarketplaceController> _page(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceController(TradesPort());
  seed(c);
  await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
  await tester.pumpAndSettle();
  return c;
}

void _activate(WidgetTester tester, String prefix) => activate(
  tester,
  exposedNodes(tester).firstWhere((n) {
    final d = n.getSemanticsData();
    return d.label.startsWith(prefix) && d.flagsCollection.isButton;
  }),
);

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final c = await _page(tester, InteractionSuite.standard);
    try {
      expect(
        tester.getRect(_chip),
        within(
          distance: .001,
          from: const Rect.fromLTRB(481.75, 208, 572.75, 235),
        ),
      );
      await tester.tap(_chip);
      await tester.pumpAndSettle();
      for (final value in ['', '200', '800']) {
        final item = _entry(value);
        expect(tester.getSize(item), const Size(112, 48));
        final label = find.descendant(of: item, matching: find.byType(Text));
        expect(tester.getRect(label).left - tester.getRect(item).left, 12);
        expect(tester.getSize(label).height, 17);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: reader opens the menu and picks; pointer clears',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final c = await _page(tester, suite);
        try {
          _activate(tester, '品质 ≥');
          await tester.pumpAndSettle();
          _activate(tester, '≥ 600');
          await tester.pumpAndSettle();
          expect(c.offerFilters['minQuality'], '600');
          await tester.tap(_chip);
          await tester.pumpAndSettle();
          await tester.tap(_entry(''));
          await tester.pumpAndSettle();
          expect(c.offerFilters['minQuality'], isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );
  }
}
