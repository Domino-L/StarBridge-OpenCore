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
    for (final width in [800.0, 430.0, 320.0]) {
      testWidgets(
        'catalog ${suite.name} filter geometry fits content width $width',
        (tester) async {
          size(tester, Size(width, 600));
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
            final back = tester.getRect(
              find.byKey(const Key('market-catalog-back')),
            );
            final refresh = tester.getRect(
              find.byKey(const Key('market-catalog-refresh')),
            );
            // 10-29: the button names the page it returns to ("← 返回 大厅").
            expect(back, const Rect.fromLTRB(0, 0, 104, 48));
            expect(refresh, Rect.fromLTRB(width - 48, 0, width, 48));
            final filters = tester.getRect(
              find.byKey(const Key('market-catalog-filters')),
            );
            final clear = tester.getRect(
              find.byKey(const Key('market-catalog-clear')),
            );
            final cards = tester.getRect(
              find.byKey(const ValueKey('market-catalog-layout-cards')),
            );
            final rows = tester.getRect(
              find.byKey(const ValueKey('market-catalog-layout-rows')),
            );
            debugPrint(
              'FILTER-GEOMETRY|suite=${suite.name}|width=$width|back=$back|refresh=$refresh|filters=$filters|clear=$clear|cards=$cards|rows=$rows',
            );
            expect(clear.width, moreOrLessEquals(68, epsilon: .001));
            expect(clear.height, 48);
            expect(
              (tester.getCenter(find.text('全部清除')) - clear.center).distance,
              lessThan(.001),
            );
            final controls = [filters, clear, cards, rows];
            for (var i = 0; i < controls.length; i++) {
              final rect = controls[i];
              expect(rect.left, greaterThanOrEqualTo(-.001));
              expect(rect.right, lessThanOrEqualTo(width + .001));
              expect(rect.top, greaterThanOrEqualTo(48));
              expect(rect.bottom, lessThanOrEqualTo(600));
              for (var j = i + 1; j < controls.length; j++) {
                expect(rect.overlaps(controls[j]), isFalse);
              }
            }
            for (var i = 0; i < controls.length - 1; i++) {
              final left = controls[i], right = controls[i + 1];
              if (left.top < right.bottom && right.top < left.bottom) {
                expect(
                  right.left - left.right,
                  moreOrLessEquals(8, epsilon: .001),
                );
                expect(
                  right.center.dy - left.center.dy,
                  moreOrLessEquals(0, epsilon: .001),
                );
              } else {
                expect(right.top, greaterThanOrEqualTo(left.bottom));
              }
            }
            controller.hall();
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('market-catalog-filters')),
              findsNothing,
            );
            expect(
              tester.getTopLeft(find.byKey(const Key('market-catalog-clear'))),
              const Offset(0, 48),
            );
            expect(port.requests, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          }
        },
      );
    }
    for (final kind in ['keyword', 'category', 'relation']) {
      testWidgets(
        'catalog ${suite.name} $kind removal preserves existing filter meaning',
        (tester) async {
          size(tester, const Size(800, 600));
          final semantics = tester.ensureSemantics();
          final port = BrowsePort();
          final controller = MarketplaceController(port)
            ..keyword = kind == 'relation' ? '' : 'ore'
            ..categoryId = kind == 'relation' ? null : 3
            ..relation = kind == 'relation' ? 'blueprints' : ''
            ..relatedId = kind == 'relation' ? 42 : 0;
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
            final label = kind == 'keyword'
                ? 'ore'
                : kind == 'category'
                ? '分类' // no category list loaded: a word, never the id (10-29)
                : '用到它的蓝图'; // item name not read yet: never the id
            final chip = find.byKey(ValueKey(kind));
            expect(chip, findsOneWidget);
            expect(
              find.byType(
                suite == InteractionSuite.standard ? InputChip : SuiteChipGroup,
              ),
              suite == InteractionSuite.standard
                  ? findsWidgets
                  : findsOneWidget,
              reason: 'Catalog filter must participate in the selected interaction suite.',
            );
            expect(port.requests, isEmpty);
            if (kind == 'keyword') {
              await tester.tap(find.text('ore'));
              expect(controller.keyword, 'ore');
              expect(port.requests, isEmpty);
              final remove = suite == InteractionSuite.standard
                  ? find.byTooltip(
                      '${MaterialLocalizations.of(tester.element(chip)).deleteButtonTooltip} ore',
                    )
                  : find.byKey(
                      const ValueKey<Object>(('chip-remove', 'keyword')),
                    );
              await tester.tap(remove);
              expect(controller.keyword, isEmpty);
              expect(controller.categoryId, 3);
              expect(port.requests, ['search']);
              await tester.pump();
              await tester.pumpWidget(surface(reduce: true));
              await tester.pump();
              expect(
                resolveStarBridgeInteraction(
                  tester.element(
                    find.byKey(const Key('market-catalog-filters')),
                  ),
                ).reduceMotion,
                isTrue,
              );
            } else if (kind == 'category') {
              final remove = suite == InteractionSuite.standard
                  ? find.byTooltip(
                      '${MaterialLocalizations.of(tester.element(chip)).deleteButtonTooltip} $label',
                    )
                  : find.byKey(
                      const ValueKey<Object>(('chip-remove', 'category')),
                    );
              final node = tester.getSemantics(remove);
              expect(
                node.getSemanticsData().hasAction(SemanticsAction.tap),
                isTrue,
              );
              tester.binding.renderViews.single.owner!.semanticsOwner!
                  .performAction(node.id, SemanticsAction.tap);
              expect(controller.keyword, 'ore');
              expect(controller.categoryId, isNull);
              expect(port.requests, ['search']);
            } else {
              final FocusNode focus;
              if (suite == InteractionSuite.standard) {
                final focusWidget = find.ancestor(
                  of: chip,
                  matching: find.byWidgetPredicate(
                    (w) => w is Focus && w.focusNode != null,
                  ),
                );
                focus = tester.widget<Focus>(focusWidget.first).focusNode!;
              } else {
                focus = tester
                    .widget<SuitePressable>(
                      find.byKey(
                        const ValueKey<Object>(('chip-remove', 'relation')),
                      ),
                    )
                    .focusNode!;
              }
              focus.requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.delete);
              expect(controller.relation, isEmpty);
              expect(controller.relatedId, 0);
              expect(controller.keyword, isEmpty);
              expect(controller.categoryId, isNull);
              expect(port.requests, isEmpty);
            }
            await tester.pumpAndSettle();
            expect(find.byKey(ValueKey(kind)), findsNothing);
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
}
