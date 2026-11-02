// Slice29: the hall page controls outside the hover cards — section actions,
// the sell / buy / barter switch, watch rows with their unwatch button and
// "back to top". Native geometry (and inherited text style) measured before
// the change is pinned for the standard suite; every suite keeps one reader
// action per control and pointer activation. Hover-card tiles and the tab
// strip belong to the hover E acceptance and are not touched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Finder _section(String action) =>
    find.byKey(ValueKey<(String, String)>(('market-section-action', action)));
Finder _side(int side) =>
    find.byKey(ValueKey<(String, int)>(('market-hall-side', side)));
final _watch = find.byKey(
  const ValueKey<(String, int)>(('market-watch-row', 1)),
);
final _unwatch = find.byKey(
  const ValueKey<(String, int)>(('market-watch-favorite', 1)),
);
final _top = find.byKey(const Key('market-hall-top'));

Future<MarketplaceController> _hall(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 2600));
  final c = MarketplaceController(TradesPort());
  await c.toggleFavorite(1);
  await tester.pumpWidget(scopedApp(MarketplacePage(c), suite));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final c = await _hall(tester, InteractionSuite.standard);
    try {
      for (final (action, rect) in [
        ('enterMarket', const Rect.fromLTRB(1160.4, 499, 1256, 539)),
        ('moreLink', const Rect.fromLTRB(1185.6, 700, 1256, 740)),
        ('allOrders', const Rect.fromLTRB(1160.4, 1011, 1256, 1051)),
      ]) {
        expect(
          tester.getRect(_section(action)),
          within(distance: .001, from: rect),
        );
      }
      for (final (side, rect) in [
        (1, const Rect.fromLTRB(990.4, 1018.5, 1034.9, 1043.5)),
        (0, const Rect.fromLTRB(1038.9, 1018.5, 1083.4, 1043.5)),
        (2, const Rect.fromLTRB(1087.4, 1018.5, 1156.4, 1043.5)),
      ]) {
        expect(tester.getRect(_side(side)), within(distance: .001, from: rect));
      }
      // The lowest-ask label shares the price line since 10-28 (backlog 30),
      // so the watch row is one label line shorter.
      expect(tester.getRect(_watch), const Rect.fromLTRB(27, 405, 282, 473));
      expect(
        tester.getRect(_unwatch),
        const Rect.fromLTRB(282, 419, 322, 459),
      );
      expect(
        tester.getRect(
          find.descendant(of: _unwatch, matching: find.byType(Icon)),
        ),
        const Rect.fromLTRB(294, 431, 310, 447),
      );
      expect(tester.getRect(_top), const Rect.fromLTRB(1188, 1694, 1256, 1742));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: side switch and unwatch by reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _hall(tester, suite);
      try {
        activate(tester, namedButton(tester, '求购'));
        await tester.pumpAndSettle();
        expect(c.side, 0);
        await tester.tap(_side(2));
        await tester.pumpAndSettle();
        expect(c.side, 2);
        // Activating the selected filter again clears it: all types, none selected.
        await tester.tap(_side(2));
        await tester.pumpAndSettle();
        expect(c.side, MarketplaceController.allSides);
        for (final side in [1, 0, 2]) {
          expect(
            tester.getSemantics(_side(side)),
            isNot(matchesSemantics(isSelected: true)),
            reason: 'no filter reads as selected once cleared',
          );
        }
        activate(tester, namedButton(tester, '出售'));
        await tester.pumpAndSettle();
        expect(c.side, 1);
        activate(tester, namedButton(tester, '出售'));
        await tester.pumpAndSettle();
        expect(
          c.side,
          MarketplaceController.allSides,
          reason: 'reader activation clears too',
        );
        activate(tester, namedButton(tester, '我的关注'));
        await tester.pumpAndSettle();
        expect(c.favorites, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
      '${suite.name}: watch row opens the item; top and section act',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final c = await _hall(tester, suite);
        try {
          activate(tester, namedButton(tester, '回到顶部'));
          await tester.pumpAndSettle();
          await tester.tap(_section('enterMarket'));
          await tester.pumpAndSettle();
          expect(c.mainTab, isNot(0));
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();

          final d = await _hall(tester, suite);
          await tester.tap(_watch);
          await tester.pumpAndSettle();
          expect(d.itemId, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          d.dispose();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        }
      },
    );
  }
}
