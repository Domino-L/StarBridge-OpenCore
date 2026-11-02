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
      'catalog ${suite.name} layout requests preserve existing selection owner',
      (tester) async {
        size(tester, const Size(800, 600));
        final port = BrowsePort();
        final controller = MarketplaceController(port);
        final semantics = tester.ensureSemantics();
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
          final rows = find.text('密集行');
          expect(port.requests, isEmpty);
          expect(controller.layout, 'cards');
          expect(
            find.ancestor(
              of: rows,
              matching: find.byType(
                suite == InteractionSuite.standard
                    ? ChoiceChip
                    : SuiteChoiceChip,
              ),
            ),
            findsOneWidget,
            reason: 'Catalog layout must participate in the selected interaction suite.',
          );
          await tester.tap(rows);
          expect(controller.layout, 'rows');
          await tester.pumpAndSettle();
          expect((port.prefs['view'] as Map)['layout'], 'rows');
          final cards = find.text('图片卡片');
          final cardFace = find.ancestor(
            of: cards,
            matching: find.byType(
              suite == InteractionSuite.standard ? ChoiceChip : SuiteChoiceChip,
            ),
          );
          final focus = suite == InteractionSuite.standard
              ? tester.widget<ChoiceChip>(cardFace).focusNode!
              : tester.widget<SuiteChoiceChip>(cardFace).focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(controller.layout, 'cards');
          await tester.pumpAndSettle();
          expect((port.prefs['view'] as Map)['layout'], 'cards');
          final node = tester.getSemantics(rows);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          expect(controller.layout, 'rows');
          await tester.pumpAndSettle();
          await tester.tap(cards);
          expect(controller.layout, 'cards');
          await tester.tap(rows);
          expect(controller.layout, 'rows');
          await tester.pumpAndSettle();
          await tester.pumpWidget(surface(reduce: true));
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(rows)).reduceMotion,
            isTrue,
          );
          await tester.tap(cards);
          expect(controller.layout, 'cards');
          await tester.pumpAndSettle();
          expect(port.requests, isEmpty);
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
