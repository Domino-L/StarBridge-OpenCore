// Slice24: the listings row "more" menu (copy as new listing / hide or show)
// and the inline "reprice" link. Native geometry measured before the change
// is pinned for the standard suite (button, icon, 112 x 48 items with their
// 12px inset, the link's own size); every suite keeps one reader action per
// command, pointer activation and the pending gate.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

const _a = '科力晶（单个矿块）';
Finder _more(Object id) =>
    find.byKey(ValueKey<(String, Object?)>(('market-listing-more', id)));
Finder _entry(String op, Object id) =>
    find.byKey(ValueKey<(String, Object?)>(('market-listing-$op', id)));
final _reprice = find.byKey(const Key('market-listing-reprice'));

Future<(MarketplaceListingsController, ListingsFixture)> _page(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final port = ListingsFixture();
  final c = MarketplaceListingsController(port);
  await tester.pumpWidget(scopedApp(MarketplaceListingsPage(c), suite));
  await tester.pumpAndSettle();
  return (c, port);
}

/// The first exposed button named [label] (each row has its own "more").
void _activateFirst(WidgetTester tester, String label) {
  final node = exposedNodes(tester).firstWhere((n) {
    final d = n.getSemanticsData();
    return d.label == label && d.flagsCollection.isButton;
  });
  activate(tester, node);
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final (c, _) = await _page(tester, InteractionSuite.standard);
    try {
      expect(
        tester.getRect(_more(_a)),
        const Rect.fromLTRB(1221, 152, 1269, 200),
      );
      expect(
        tester.getRect(
          find.descendant(of: _more(_a), matching: find.byType(Icon)),
        ),
        const Rect.fromLTRB(1235, 166, 1255, 186),
      );
      expect(
        tester.getRect(_reprice.first),
        within(
          distance: .001,
          from: const Rect.fromLTRB(854.75, 180, 878.25, 196),
        ),
      );
      await tester.tap(_more(_a));
      await tester.pumpAndSettle();
      for (final op in ['copy', 'visibility']) {
        final item = _entry(op, _a);
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
    testWidgets('${suite.name}: reader opens the menu and hides the listing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, port) = await _page(tester, suite);
      try {
        _activateFirst(tester, '更多');
        await tester.pumpAndSettle();
        expect(_entry('visibility', _a), findsOneWidget);
        _activateFirst(tester, '下架');
        await tester.pumpAndSettle();
        expect(port.calls, ['visibility:$_a']);
        expect(_entry('visibility', _a), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: pointer copy opens the publish wizard', (
      tester,
    ) async {
      final (c, _) = await _page(tester, suite);
      try {
        await tester.tap(_more(_a));
        await tester.pumpAndSettle();
        await tester.tap(_entry('copy', _a));
        await tester.pumpAndSettle();
        final dialog = tester.widget<ListingPublishDialog>(
          find.byType(ListingPublishDialog),
        );
        expect(dialog.initialStep, 2);
        expect(dialog.draft.item['name'], _a);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });

    testWidgets(
      '${suite.name}: reprice link opens the editor; pending blocks',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (c, port) = await _page(tester, suite);
        try {
          await tester.tap(_reprice.first);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          Navigator.of(tester.element(find.byType(Dialog))).pop();
          await tester.pumpAndSettle();
          c.pending = true;
          c.notifyListeners();
          await tester.pump();
          await tester.tap(_reprice.first, warnIfMissed: false);
          await tester.tap(_more(_a), warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(_entry('copy', _a), findsNothing);
          expect(port.calls, isEmpty);
          c.pending = false;
          c.notifyListeners();
          await tester.pump();
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
