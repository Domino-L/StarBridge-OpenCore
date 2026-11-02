// Slice37: hall hover-card contents (trending / listing / item cards,
// category tiles, my-listing cards) and drawer actions join the shared row
// target without disturbing hover plan E: MarketHoverCard keeps its own lift
// and outline (the rows add no second suite hover face), keyboard focus on a
// card still opens its drawer, and a drawer's slanted action closes the
// drawer before it acts. Native geometry and text style were compared before
// and after (logs/slice37-*-probe.log).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hover.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_page.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3b_test.dart'
    show exposedNodes;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Future<MarketplaceController> _hall(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 2600));
  final c = MarketplaceController(TradesPort());
  await tester.pumpWidget(scopedApp(MarketplacePage(c), suite));
  await tester.pumpAndSettle();
  return c;
}

Finder _trendCard(String name) => find
    .ancestor(
      of: find.text(name).first,
      matching: find.byType(StarBridgeActionRow),
    )
    .first;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: hover rows add no second hover face', (
      tester,
    ) async {
      final c = await _hall(tester, suite);
      try {
        final rows = tester
            .widgetList<StarBridgeActionRow>(
              find.descendant(
                of: find.byType(MarketHoverCard),
                matching: find.byType(StarBridgeActionRow),
              ),
            )
            .toList();
        expect(rows, isNotEmpty);
        for (final row in rows) {
          expect(row.hoverFace, isFalse);
          expect(row.inheritContentStyle, isTrue);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });

    testWidgets('${suite.name}: keyboard focus on a card opens its drawer', (
      tester,
    ) async {
      final c = await _hall(tester, suite);
      try {
        expect(find.byType(MarketSlantButton), findsNothing);
        final target = _trendCard('测试物品 1');
        for (var i = 0; i < 80; i++) {
          final focus = FocusManager.instance.primaryFocus?.context;
          if (focus != null &&
              find
                  .descendant(
                    of: target,
                    matching: find.byElementPredicate((e) => e == focus),
                  )
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.byType(MarketSlantButton), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
    });

    testWidgets(
      '${suite.name}: a slanted drawer action closes the drawer first',
      (tester) async {
        final c = await _hall(tester, suite);
        try {
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(
            location: tester.getCenter(find.text('测试物品 1').first),
          );
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          final follow = find.widgetWithText(MarketSlantButton, '关注');
          expect(follow, findsOneWidget);
          await mouse.moveTo(tester.getCenter(follow));
          await tester.pump();
          await mouse.down(tester.getCenter(follow));
          await mouse.up();
          await tester.pump();
          expect(c.favorites, isNotEmpty);
          await mouse.moveTo(const Offset(5, 5));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(find.byType(MarketSlantButton), findsNothing);
          await mouse.removePointer();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      },
    );

    testWidgets('${suite.name}: cards and tiles open by reader and pointer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _hall(tester, suite);
      try {
        await tester.tap(find.text('分类 3'));
        await tester.pumpAndSettle();
        expect(c.mainTab, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();

        final d = await _hall(tester, suite);
        activate(
          tester,
          exposedNodes(tester).firstWhere((n) {
            final s = n.getSemanticsData();
            return s.label.startsWith('测试物品 2') && s.flagsCollection.isButton;
          }),
        );
        await tester.pumpAndSettle();
        expect(d.itemId, 2);
        await tester.pumpWidget(const SizedBox.shrink());
        d.dispose();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }
}
