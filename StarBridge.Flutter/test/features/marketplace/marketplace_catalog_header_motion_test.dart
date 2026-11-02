import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_catalog_view.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_slice2_test.dart' show BrowsePort;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'catalog ${suite.name} header keeps native geometry and original commands',
      (tester) async {
        size(tester, const Size(800, 600));
        final port = BrowsePort();
        final controller = MarketplaceController(port)
          ..keyword = 'ore'
          ..categoryId = 3;
        try {
          await tester.pumpWidget(
            scopedApp(
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) => marketCatalogView(
                  context,
                  controller,
                  (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              suite,
            ),
          );
          await tester.pumpAndSettle();
          // 10-29: the button names the page it returns to.
          final back = find.text('← 返回 大厅');
          final clear = find.text('全部清除');
          expect(port.requests, isEmpty);
          expect(
            find.ancestor(
              of: back,
              matching: find.byType(
                suite == InteractionSuite.standard
                    ? TextButton
                    : SuitePressable,
              ),
            ),
            findsOneWidget,
            reason: 'Catalog header must participate in the selected interaction suite.',
          );
          expect(
            tester.getRect(find.byKey(const Key('market-catalog-back'))),
            const Rect.fromLTRB(0, 0, 104, 48),
          );
          expect(tester.getRect(back), const Rect.fromLTRB(10, 18, 94, 30));
          // This button keeps its own native geometry. The preceding filter
          // group's approved chip faces may legitimately change its flow x.
          final clearRect = tester.getRect(
            find.byKey(const Key('market-catalog-clear')),
          );
          expect(clearRect.size.width, moreOrLessEquals(68, epsilon: .001));
          expect(clearRect.size.height, 48);
          expect(
            (tester.getCenter(clear) - clearRect.center).distance,
            lessThan(.001),
          );
          final filtersRect = tester.getRect(
            find.byKey(const Key('market-catalog-filters')),
          );
          expect(
            clearRect.left - filtersRect.right,
            moreOrLessEquals(8, epsilon: .001),
          );
          expect(
            clearRect.center.dy - filtersRect.center.dy,
            moreOrLessEquals(0, epsilon: .001),
          );
          expect(
            tester.getRect(find.byKey(const Key('market-catalog-refresh'))),
            const Rect.fromLTRB(752, 0, 800, 48),
          );
          await tester.tap(back);
          expect(controller.keyword, isEmpty);
          expect(controller.categoryId, isNull);
          expect(controller.relation, isEmpty);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('market-catalog-filters')), findsNothing);
          expect(
            tester.getTopLeft(find.byKey(const Key('market-catalog-clear'))),
            const Offset(0, 48),
          );
          controller.keyword = 'again';
          controller.categoryId = 6;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) => marketCatalogView(
                  context,
                  controller,
                  (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              suite,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(clear);
          expect(controller.keyword, isEmpty);
          expect(controller.categoryId, isNull);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      },
    );
    testWidgets(
      'catalog ${suite.name} refresh forwards pointer keyboard reader without changing query',
      (tester) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        final port = BrowsePort();
        final controller = MarketplaceController(port)
          ..keyword = 'ore'
          ..categoryId = 3;
        try {
          Widget surface({bool reduce = false}) => scopedApp(
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => marketCatalogView(
                context,
                controller,
                (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            suite,
            reduce: reduce,
          );
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          final refresh = find.byKey(const Key('market-catalog-refresh'));
          expect(port.requests, isEmpty);
          await tester.tap(refresh);
          expect(port.requests, ['search']);
          await tester.pumpAndSettle();
          final native = find.descendant(
            of: refresh,
            matching: find.byType(IconButton),
          );
          tester.widget<IconButton>(native).focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(port.requests, ['search', 'search']);
          await tester.pumpAndSettle();
          final node = tester.getSemantics(find.bySemanticsLabel('刷新'));
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          expect(port.requests, ['search', 'search', 'search']);
          await tester.pumpAndSettle();
          await tester.pumpWidget(surface(reduce: true));
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(refresh)).reduceMotion,
            isTrue,
          );
          await tester.tap(refresh);
          expect(port.requests, ['search', 'search', 'search', 'search']);
          await tester.pumpAndSettle();
          expect(controller.keyword, 'ore');
          expect(controller.categoryId, 3);
          expect(controller.relation, isEmpty);
          expect(tester.getRect(refresh), const Rect.fromLTRB(752, 0, 800, 48));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      },
    );
  }
}
