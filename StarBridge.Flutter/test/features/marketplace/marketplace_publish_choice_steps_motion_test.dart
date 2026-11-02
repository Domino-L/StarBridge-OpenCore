// Slice33: the publish wizard's choice steps — the type / form option cards
// (step 0) and the item pick tiles (step 1). Native geometry and text style
// measured before the change are pinned for the standard suite; every suite
// keeps one reader action per card/tile (spoken as selected), pointer
// activation, and the inert summary tile on the price step stays inert.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listing_publish_widgets.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Future<(MarketplaceListingsController, ListingDraft)> _wizard(
  WidgetTester tester,
  InteractionSuite suite,
  int step, {
  ListingDraft? draft,
}) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceListingsController(ListingsFixture());
  await c.refresh();
  final d = draft ?? ListingDraft();
  await tester.pumpWidget(
    scopedApp(ListingPublishDialog(c, d, initialStep: step), suite),
  );
  await tester.pumpAndSettle();
  return (c, d);
}

void _activate(WidgetTester tester, String label) => activate(
  tester,
  exposedNodes(tester).firstWhere((n) {
    final d = n.getSemanticsData();
    return d.label.startsWith(label) && d.flagsCollection.isButton;
  }),
);

Finder _of(Type type, String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(type)).first;

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    var (c, _) = await _wizard(tester, InteractionSuite.standard, 0);
    try {
      expect(
        tester.getRect(_of(ListingOptionCard, '出售')),
        within(distance: .01, from: const Rect.fromLTRB(380, 373, 545.33, 453)),
      );
      expect(
        tester.getRect(_of(ListingOptionCard, '以物易物')),
        within(distance: .01, from: const Rect.fromLTRB(726.67, 365, 900, 461)),
      );
      expect(
        tester.getRect(_of(ListingOptionCard, '清单')),
        const Rect.fromLTRB(644, 500, 900, 580),
      );
      final title = tester
          .widget<RichText>(
            find.descendant(
              of: find.descendant(
                of: _of(ListingOptionCard, '把物品卖给别人'),
                matching: find.text('出售'),
              ),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style!;
      expect(title.fontSize, 13);
      expect(title.color?.toARGB32(), 0xffe7eef2);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      (c, _) = await _wizard(tester, InteractionSuite.standard, 1);
      expect(
        tester.getRect(_of(ListingPickTile, '科力晶（单个矿块）')),
        const Rect.fromLTRB(440, 331, 741, 389),
      );
      expect(
        tester.getRect(find.text('科力晶（单个矿块）')),
        within(distance: .01, from: const Rect.fromLTRB(498, 339, 617.25, 357)),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: option cards choose side and form', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, d) = await _wizard(tester, suite, 0);
      try {
        _activate(tester, '求购');
        await tester.pumpAndSettle();
        expect(d.side, 'buy');
        await tester.tap(find.text('以物易物'));
        await tester.pumpAndSettle();
        expect(d.side, 'barter');
        expect(
          exposedNodes(tester)
              .firstWhere((n) {
                final s = n.getSemanticsData();
                return s.label.startsWith('以物易物') && s.flagsCollection.isButton;
              })
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .toString(),
          endsWith('isTrue'),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
      '${suite.name}: pick tiles choose the item; summary tile stays inert',
      (tester) async {
        final semantics = tester.ensureSemantics();
        var (c, d) = await _wizard(tester, suite, 1);
        try {
          _activate(tester, 'TS-35');
          await tester.pumpAndSettle();
          expect('${d.item['name']}', startsWith('TS-35'));
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();

          (c, d) = await _wizard(
            tester,
            suite,
            2,
            draft: ListingDraft(item: {'id': 1, 'name': 'Fixture'}),
          );
          final summary = find.byType(ListingPickTile);
          expect(summary, findsOneWidget);
          expect(
            find.descendant(
              of: summary,
              matching: find.byType(StarBridgeActionRow),
            ),
            findsNothing,
          );
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
