// Slice23: the listings page's selection checkboxes — one per row and the
// tristate "select all". Native geometry measured before the change is
// pinned for the standard suite; every suite keeps one reader action per
// checkbox (spoken as checked / mixed), pointer and keyboard toggling and the
// pending gate.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_trade_inner_motion_test.dart' show activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

const _a = '科力晶（单个矿块）';
const _b = 'TS-35 婆娑罗（3.5倍光学）';
Finder _row(Object id) =>
    find.byKey(ValueKey<(String, Object?)>(('market-listing-select', id)));
final _all = find.byKey(const Key('market-listings-select-all'));

Future<MarketplaceListingsController> _page(
  WidgetTester tester,
  InteractionSuite suite,
) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceListingsController(ListingsFixture());
  await tester.pumpWidget(scopedApp(MarketplaceListingsPage(c), suite));
  await tester.pumpAndSettle();
  return c;
}

CheckedState _checked(SemanticsNode n) =>
    n.getSemanticsData().flagsCollection.isChecked;

bool _mixed(SemanticsNode n) => _checked(n) == CheckedState.mixed;

/// The exposed checked node for a row (its own node, or the row node it
/// merges into when the row has no other action) or for "select all".
SemanticsNode _box(WidgetTester tester, String label) {
  final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode n) {
    final d = n.getSemanticsData();
    if (!n.isMergedIntoParent &&
        d.label.startsWith(label) &&
        d.flagsCollection.isChecked != CheckedState.none) {
      nodes.add(n);
    }
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(owner.rootSemanticsNode!);
  expect(nodes, hasLength(1), reason: 'One checked node for $label');
  return nodes.single;
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final c = await _page(tester, InteractionSuite.standard);
    try {
      expect(tester.getRect(_row(_a)), const Rect.fromLTRB(14, 152, 62, 200));
      await tester.tap(_row(_a), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.getRect(_all), const Rect.fromLTRB(9, 121, 41, 153));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: row checkboxes toggle by pointer, key and reader',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final c = await _page(tester, suite);
        try {
          expect(_checked(_box(tester, _a)), CheckedState.isFalse);
          await tester.tap(_row(_a), warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(_checked(_box(tester, _a)), CheckedState.isTrue);
          // Pointer focused the checkbox; Space toggles it back.
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(_checked(_box(tester, _a)), CheckedState.isFalse);
          activate(tester, _box(tester, _b));
          await tester.pumpAndSettle();
          expect(_checked(_box(tester, _b)), CheckedState.isTrue);
          expect(_all, findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: select all is mixed, selects all, then clears',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final c = await _page(tester, suite);
        try {
          activate(tester, _box(tester, _a));
          await tester.pumpAndSettle();
          final all = _box(tester, '全选');
          expect(_mixed(all), isTrue);
          activate(tester, all);
          await tester.pumpAndSettle();
          expect(_mixed(_box(tester, '全选')), isFalse);
          expect(_checked(_box(tester, '全选')), CheckedState.isTrue);
          expect(_checked(_box(tester, _b)), CheckedState.isTrue);
          await tester.tap(_all, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(_all, findsNothing, reason: 'Clearing hides the batch bar.');
          expect(_checked(_box(tester, _a)), CheckedState.isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets('${suite.name}: pending blocks selection changes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _page(tester, suite);
      try {
        c.pending = true;
        c.notifyListeners();
        await tester.pump();
        await tester.tap(_row(_a), warnIfMissed: false);
        await tester.pump();
        final node = _box(tester, _a);
        expect(_checked(node), CheckedState.isFalse);
        expect(
          node.getSemanticsData().flagsCollection.isEnabled,
          Tristate.isFalse,
        );
        c.pending = false;
        c.notifyListeners();
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
