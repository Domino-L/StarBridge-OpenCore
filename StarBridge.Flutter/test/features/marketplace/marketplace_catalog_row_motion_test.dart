import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_catalog_view.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;
import 'marketplace_slice2_test.dart' show BrowsePort;

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets(
      'catalog ${suite.name} enabled row keeps native tile geometry and original open',
      (tester) async {
        size(tester, const Size(800, 600));
        final port = BrowsePort();
        final controller = MarketplaceController(port)
          ..keyword = 'ore'
          ..layout = 'rows';
        final read = MarketRead({
          'rows': [
            {'id': 7, 'itemName': '目录测试'},
          ],
          'total': 1,
        }, DateTime.utc(2026, 10, 19));
        controller.blocks['catalog'] = read;
        final semantics = tester.ensureSemantics();
        try {
          Widget surface({bool reduce = false}) => scopedApp(
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => marketCatalogView(
                context,
                controller,
                (_, build, _) => build(read),
              ),
            ),
            suite,
            reduce: reduce,
          );
          await tester.pumpWidget(surface());
          await tester.pumpAndSettle();
          final label = find.text('目录测试');
          expect(port.requests, isEmpty);
          expect(
            find.ancestor(of: label, matching: find.byType(SuitePressable)),
            findsOneWidget,
            reason: 'Catalog row must participate in the selected interaction suite.',
          );
          expect(
            tester.getRect(find.byType(ListTile)),
            const Rect.fromLTRB(0, 96, 800, 152),
          );
          expect(tester.getRect(label), const Rect.fromLTRB(76, 112, 776, 136));
          await tester.tap(label);
          expect(controller.itemId, 7);
          await tester.pumpAndSettle();
          expect(
            port.requests.where((operation) => operation == 'item'),
            hasLength(1),
          );
          final action = find.ancestor(
            of: label,
            matching: find.byType(SuitePressable),
          );
          expect(tester.getRect(action), const Rect.fromLTRB(0, 96, 800, 152));
          final namedNodes = <int>{
            for (final element in find.bySemanticsLabel('目录测试').evaluate())
              tester
                  .getSemantics(
                    find.byElementPredicate((e) => identical(e, element)),
                  )
                  .id,
          };
          debugPrint('ROW-NAMED-NODES|suite=${suite.name}|ids=$namedNodes');
          expect(namedNodes, hasLength(1));
          final focusable = find.descendant(
            of: action,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is FocusableActionDetector &&
                  w.focusNode?.canRequestFocus == true,
            ),
          );
          final focus = tester
              .widget<FocusableActionDetector>(focusable.first)
              .focusNode!;
          focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(
            port.requests.where((operation) => operation == 'item'),
            hasLength(2),
          );
          await tester.pumpAndSettle();
          final node = tester.getSemantics(action);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(node.id, SemanticsAction.tap);
          expect(
            port.requests.where((operation) => operation == 'item'),
            hasLength(3),
          );
          await tester.pumpAndSettle();
          await tester.pumpWidget(surface(reduce: true));
          await tester.pump();
          expect(
            resolveStarBridgeInteraction(tester.element(label)).reduceMotion,
            isTrue,
          );
          await tester.tap(label);
          expect(
            port.requests.where((operation) => operation == 'item'),
            hasLength(4),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byType(ListTile)),
            const Rect.fromLTRB(0, 96, 800, 152),
          );
          expect(tester.getRect(label), const Rect.fromLTRB(76, 112, 776, 136));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      },
    );
    for (final kind in ['blueprint', 'missing-id']) {
      testWidgets('catalog ${suite.name} $kind row remains noninteractive', (
        tester,
      ) async {
        size(tester, const Size(800, 600));
        final semantics = tester.ensureSemantics();
        final port = BrowsePort();
        final controller = MarketplaceController(port)
          ..keyword = kind == 'blueprint' ? '' : 'ore'
          ..layout = 'rows'
          ..relation = kind == 'blueprint' ? 'blueprints' : ''
          ..relatedId = kind == 'blueprint' ? 42 : 0;
        final read = MarketRead({
          'rows': [
            {
              if (kind == 'blueprint') 'id': 7,
              'itemName': '不可打开行',
              'blueprintNameCn': '不可打开行',
            },
          ],
          'total': 1,
        }, DateTime.utc(2026, 10, 19));
        controller.blocks['catalog'] = read;
        try {
          await tester.pumpWidget(
            scopedApp(
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) => marketCatalogView(
                  context,
                  controller,
                  (_, build, _) => build(read),
                ),
              ),
              suite,
            ),
          );
          await tester.pumpAndSettle();
          final label = find.text('不可打开行');
          expect(label, findsOneWidget);
          expect(
            find.ancestor(of: label, matching: find.byType(SuitePressable)),
            findsNothing,
          );
          expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
          expect(
            tester
                .getSemantics(label)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          await tester.tap(label);
          await tester.pumpAndSettle();
          expect(controller.itemId, isNull);
          expect(port.requests, isEmpty);
          expect(tester.getSize(find.byType(ListTile)).height, 56);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          semantics.dispose();
        }
      });
    }
  }
}
