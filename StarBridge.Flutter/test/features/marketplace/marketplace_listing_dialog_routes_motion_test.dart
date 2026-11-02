// Slice36: the listing dialogs (batch result, listing editor and its delete
// confirmation, publish wizard) join the suite route used by the trade
// dialogs. Every suite: the route is a StarBridgeDialogRoute, reader closes
// land within two frames, pointer closes keep their exit, and the dialogs'
// geometry stays as pinned by the slice 22/31/32 tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
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
Finder _k(String key) => find.byKey(Key(key));
final _edit = find.byKey(
  const ValueKey<(String, Object?)>(('market-listing-edit', _a)),
);
final _select = find.byKey(
  const ValueKey<(String, Object?)>(('market-listing-select', _a)),
);

Future<MarketplaceListingsController> _page(
  WidgetTester tester,
  InteractionSuite suite, {
  bool manifests = false,
}) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceListingsController(ListingsFixture());
  await tester.pumpWidget(
    scopedApp(MarketplaceListingsPage(c, initialManifests: manifests), suite),
  );
  await tester.pumpAndSettle();
  return c;
}

void _activate(WidgetTester tester, String label) => activate(
  tester,
  exposedNodes(tester).lastWhere((n) {
    final d = n.getSemanticsData();
    return d.label == label && d.flagsCollection.isButton;
  }),
);

/// The top route; asserts it is the suite dialog route.
ModalRoute<Object?> _route(WidgetTester tester, Finder inside) {
  final route = ModalRoute.of(tester.element(inside))!;
  expect(route, isA<StarBridgeDialogRoute<Object?>>());
  return route;
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('${suite.name}: listing editor and delete confirmation', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _page(tester, suite);
      try {
        await tester.tap(_edit);
        await tester.pumpAndSettle();
        final editor = _route(tester, _k('market-listing-save'));
        await tester.tap(_k('market-listing-delete'));
        await tester.pumpAndSettle();
        final confirm = _route(tester, _k('market-listing-delete-confirm'));
        _activate(tester, '取消');
        await tester.pump();
        await tester.pump();
        expect(confirm.animation!.value, 0, reason: 'Reader closes at once.');
        await tester.pumpAndSettle();
        expect(editor.isCurrent, isTrue);
        await tester.tap(_k('market-listing-edit-cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          editor.animation!.value,
          inExclusiveRange(0, 1),
          reason: 'Pointer close keeps its exit.',
        );
        await tester.pumpAndSettle();
        expect(_k('market-listing-save'), findsNothing);
        await tester.tap(_edit);
        await tester.pumpAndSettle();
        final again = _route(tester, _k('market-listing-save'));
        _activate(tester, '关闭');
        await tester.pump();
        await tester.pump();
        expect(again.animation!.value, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: batch result dialog', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = await _page(tester, suite);
      try {
        await tester.tap(_select, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.text('下架'));
        await tester.pumpAndSettle();
        final route = _route(tester, _k('market-listing-batch-ok'));
        _activate(tester, '知道了');
        await tester.pump();
        await tester.pump();
        expect(route.animation!.value, 0);
        await tester.pumpAndSettle();
        expect(_k('market-listing-batch-ok'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });

    testWidgets('${suite.name}: publish wizard from a checklist', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final c = await _page(tester, suite, manifests: true);
      try {
        await tester.tap(
          find.byKey(
            const ValueKey<(String, Object?)>((
              'market-manifest-publish',
              'M1',
            )),
          ),
        );
        await tester.pumpAndSettle();
        final route = _route(tester, find.byType(ListingPublishDialog));
        _activate(tester, '关闭');
        await tester.pump();
        await tester.pump();
        expect(route.animation!.value, 0);
        await tester.pumpAndSettle();
        expect(find.byType(ListingPublishDialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
