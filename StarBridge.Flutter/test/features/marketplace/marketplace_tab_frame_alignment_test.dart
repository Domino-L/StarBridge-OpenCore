// User report on build 20 ("选择框歪了"): the item page's selected tab frame
// sat left of its text, because the slanted divider was inside the target the
// suite frames. Every hall tab row keeps its frame centred on its text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_surfaces.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_unified.dart';

import '../friends/social_layout_test.dart' show size;
import 'marketplace_test.dart' show app;
import 'marketplace_trades_test.dart' show TradesPort;

void _centred(WidgetTester tester, Finder frame, Finder text, String what) {
  final a = tester.getRect(frame).center.dx, b = tester.getRect(text).center.dx;
  expect(
    (a - b).abs(),
    lessThanOrEqualTo(1),
    reason: '$what: frame $a, text $b',
  );
}

void main() {
  for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
    testWidgets('tab frames centre on their text $locale', (tester) async {
      size(tester, const Size(1440, 1000));
      final c = MarketplaceController(TradesPort());
      await tester.pumpWidget(app(c, AppearanceMode.dark, locale));
      await tester.pumpAndSettle();

      // Hall tabs (大厅 / 市场 / 关注 / 合约 / 我的交易 / 仓储), with badges.
      final hall = find.byWidgetPredicate(
        (w) =>
            w is StarBridgeActionRow &&
            w.controlKey is ValueKey &&
            '${w.controlKey}'.contains('market-tab'),
      );
      expect(hall, findsAtLeastNWidgets(6));
      for (var i = 0; i < hall.evaluate().length; i++) {
        final tab = hall.at(i);
        _centred(
          tester,
          tab,
          find.descendant(of: tab, matching: find.byType(Row)).first,
          'hall tab $i',
        );
      }

      // Item page tabs (出售 n / 求购 n / 走势 / 获取途径): the suite frames
      // the anchored target, so the anchor must centre on the label.
      await c.openItem(1);
      for (final selected in [0, 1, 2, 3]) {
        c.selectItemTab(selected);
        await tester.pumpAndSettle();
        final anchors = find.descendant(
          of: find.byType(MarketTabs),
          matching: find.byWidgetPredicate(
            (w) => w is KeyedSubtree && w.key is GlobalKey,
          ),
        );
        expect(anchors, findsNWidgets(4));
        for (var i = 0; i < 4; i++) {
          _centred(
            tester,
            anchors.at(i),
            find
                .descendant(of: anchors.at(i), matching: find.byType(Text))
                .first,
            'item tab $i (selected $selected)',
          );
        }
      }

      // Second-level tabs with counts (我的交易: 进行中 n …).
      c.tab(3);
      await tester.pumpAndSettle();
      final buttons = find.descendant(
        of: find.byType(MarketSubTabs).first,
        matching: find.byType(TextButton),
      );
      expect(buttons, findsAtLeastNWidgets(2));
      for (var i = 0; i < buttons.evaluate().length; i++) {
        _centred(
          tester,
          buttons.at(i),
          find
              .descendant(of: buttons.at(i), matching: find.byType(RichText))
              .first,
          'sub tab $i',
        );
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(const Duration(seconds: 31));
    });
  }
}
