// Slice34: the market sort dropdown and the trade confirmation's delivery
// method dropdown join the shared compact select (which keeps a native
// DropdownButton as its visual projection). Native geometry, text style and
// the confirmation's autofocus measured before the change are pinned for the
// standard suite; every suite keeps reader, keyboard and pointer choice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_item_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_market_page.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:flutter/services.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_routes_motion_test.dart' show seed, offer;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

final _sort = find.byKey(const Key('market-sort'));
final _delivery = find.byKey(const Key('market-confirm-delivery'));

void _activate(WidgetTester tester, String prefix) => activate(
  tester,
  exposedNodes(tester).firstWhere((n) {
    final d = n.getSemanticsData();
    return d.label.startsWith(prefix) && d.flagsCollection.isButton;
  }),
);

TextStyle _style(WidgetTester tester, Finder scope, String text) => tester
    .widget<RichText>(
      find.descendant(
        of: find.descendant(of: scope, matching: find.text(text)).first,
        matching: find.byType(RichText),
      ),
    )
    .text
    .style!;

Future<MarketplaceController> _confirm(
  WidgetTester tester,
  InteractionSuite suite, {
  bool single = false,
}) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceController(TradesPort());
  seed(c);
  if (single) {
    // Only one available: quantity is settled, so delivery takes focus.
    c.blocks['sell'] = MarketRead({
      'rows': [
        {...offer, 'availableQuantity': 1},
      ],
      'total': 1,
    }, DateTime.utc(2026, 10, 19));
  }
  await tester.pumpWidget(scopedApp(MarketplaceItemPage(c), suite));
  await tester.pumpAndSettle();
  await tester.tap(find.text('购买'));
  await tester.pumpAndSettle();
  return c;
}

Future<MarketplaceController> _market(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceController(TradesPort());
  await tester.pumpWidget(scopedApp(MarketplaceMarketPage(c), suite));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    var c = await _confirm(tester, InteractionSuite.standard);
    try {
      expect(
        tester.getRect(_delivery),
        const Rect.fromLTRB(786.5, 468.5, 839, 500.5),
      );
      expect(
        tester.getRect(
          find.descendant(of: _delivery, matching: find.text('面交')).first,
        ),
        const Rect.fromLTRB(786.5, 474.5, 815, 494.5),
      );
      expect(_style(tester, _delivery, '面交').fontSize, 14);
      expect(
        tester.getRect(
          find.descendant(of: _delivery, matching: find.byType(Icon)),
        ),
        const Rect.fromLTRB(815, 472.5, 839, 496.5),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      c = await _market(tester, InteractionSuite.standard);
      expect(
        tester.getRect(_sort),
        within(distance: .001, from: const Rect.fromLTRB(1090.6, 2, 1195, 28)),
      );
      final label = _style(tester, _sort, '挂单最多 ↓');
      expect(label.fontSize, 13);
      expect(label.color?.toARGB32(), 0xff93a4ae);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: delivery select chosen by reader and pointer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _confirm(tester, suite);
      try {
        _activate(tester, '交付方式');
        await tester.pumpAndSettle();
        await tester.tap(find.text('代运').last);
        await tester.pumpAndSettle();
        await tester.tap(_delivery);
        await tester.pumpAndSettle();
        await tester.tap(find.text('自提').last);
        await tester.pumpAndSettle();
        expect(
          exposedNodes(tester)
              .any((n) => n.getSemanticsData().label == '交付方式 · 自提'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: delivery select keeps its autofocus', (
      tester,
    ) async {
      final c = await _confirm(tester, suite, single: true);
      try {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.tap(find.text('其他').last);
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: _delivery, matching: find.text('其他')),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });

    testWidgets('${suite.name}: sort select by reader and pointer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _market(tester, suite);
      try {
        _activate(tester, '排序');
        await tester.pumpAndSettle();
        await tester.tap(find.text('出售最多 ↓').last);
        await tester.pumpAndSettle();
        expect(c.browser.options['sortKey'], 'sellOrderCount');
        await tester.tap(_sort);
        await tester.pumpAndSettle();
        await tester.tap(find.text('挂单最多 ↑').last);
        await tester.pumpAndSettle();
        expect(c.browser.options['sortKey'], 'totalOrderCount');
        expect(c.browser.options['sortOrder'], 'asc');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
