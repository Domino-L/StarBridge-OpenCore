// Slice22: the listings page's buttons — row edit, batch actions, clear
// selection, the batch result dialog (close and "got it"), the read-back
// confirmation and "publish from checklist". Native geometry measured before
// the change is pinned for the standard suite; every suite keeps one reader
// action per control, pointer activation and the pending gate.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_listings_page.dart';

import 'marketplace_slice4_test.dart' show ListingsFixture;
import 'marketplace_trade_inner_motion_test.dart' show namedButton, activate;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

Finder _edit(Object id) =>
    find.byKey(ValueKey<(String, Object?)>(('market-listing-edit', id)));
final _clear = find.byKey(const Key('market-listings-clear-selection'));
final _close = find.byKey(const Key('market-listing-batch-close'));
final _ok = find.byKey(const Key('market-listing-batch-ok'));
final _readBack = find.byKey(const Key('market-listings-confirm-readback'));
const _first = '科力晶（单个矿块）';
Finder _rowBox(Object id) =>
    find.byKey(ValueKey<(String, Object?)>(('market-listing-select', id)));

Future<(MarketplaceListingsController, ListingsFixture)> _page(
  WidgetTester tester,
  InteractionSuite suite, {
  bool manifests = false,
}) async {
  size(tester, const Size(1280, 900));
  final port = ListingsFixture();
  final c = MarketplaceListingsController(port);
  await tester.pumpWidget(
    scopedApp(MarketplaceListingsPage(c, initialManifests: manifests), suite),
  );
  await tester.pumpAndSettle();
  return (c, port);
}

Finder _button(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    )
    .last;

/// Batch results clear the selection; select the first row again.
Future<void> _select(WidgetTester tester) async {
  if (_clear.evaluate().isNotEmpty) return;
  await tester.tap(_rowBox(_first));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final (c, _) = await _page(tester, InteractionSuite.standard);
    try {
      expect(
        tester.getRect(_edit(_first)),
        const Rect.fromLTRB(1173, 152, 1221, 200),
      );
      expect(
        tester.getRect(
          find.descendant(of: _edit(_first), matching: find.byType(Icon)),
        ),
        const Rect.fromLTRB(1189, 168, 1205, 184),
      );
      await tester.tap(_rowBox(_first));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(_button('上架')),
        const Rect.fromLTRB(911, 125, 987, 149),
      );
      expect(
        tester.getRect(_button('下架')),
        const Rect.fromLTRB(995, 125, 1071, 149),
      );
      expect(
        tester.getRect(_button('复制为新挂单')),
        const Rect.fromLTRB(1079, 125, 1203, 149),
      );
      expect(tester.getRect(_clear), const Rect.fromLTRB(1203, 113, 1271, 161));
      await tester.tap(find.text('下架'));
      await tester.pumpAndSettle();
      expect(tester.getRect(_close), const Rect.fromLTRB(808, 341, 856, 389));
      expect(
        tester.getRect(
          find.descendant(of: _close, matching: find.byType(Icon)),
        ),
        const Rect.fromLTRB(823, 356, 841, 374),
      );
      expect(tester.getRect(_ok), const Rect.fromLTRB(762, 507, 850, 555));
      await tester.tap(_ok);
      await tester.pumpAndSettle();
      c.writeUncertain = true;
      c.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.getRect(_readBack), const Rect.fromLTRB(0, 106, 1280, 154));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      final (m, _) = await _page(
        tester,
        InteractionSuite.standard,
        manifests: true,
      );
      expect(
        tester.getRect(
          find.byKey(
            const ValueKey<(String, Object?)>((
              'market-manifest-publish',
              'M1',
            )),
          ),
        ),
        const Rect.fromLTRB(17, 261, 108, 293),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      m.dispose();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: batch result dialog: reader, keyboard and pointer',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (c, port) = await _page(tester, suite);
        try {
          await tester.tap(_rowBox(_first));
          await tester.pumpAndSettle();
          activate(tester, namedButton(tester, '下架'));
          await tester.pumpAndSettle();
          expect(port.calls, ['visibility:$_first']);
          expect(_ok, findsOneWidget);
          // "Got it" is autofocused: Enter closes the result.
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(_ok, findsNothing);
          await _select(tester);
          activate(tester, namedButton(tester, '上架'));
          await tester.pumpAndSettle();
          activate(tester, namedButton(tester, '关闭'));
          await tester.pumpAndSettle();
          expect(_ok, findsNothing);
          await _select(tester);
          await tester.tap(find.text('上架'));
          await tester.pumpAndSettle();
          await tester.tap(_ok);
          await tester.pumpAndSettle();
          expect(_ok, findsNothing);
          await _select(tester);
          activate(tester, namedButton(tester, '取消选择'));
          await tester.pumpAndSettle();
          expect(_clear, findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: row edit and read-back keep one reader action',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final (c, _) = await _page(tester, suite);
        try {
          c.writeUncertain = true;
          c.notifyListeners();
          await tester.pumpAndSettle();
          final readBack = namedButton(tester, '已核对，继续操作');
          expect(
            readBack.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          c.writeUncertain = false;
          c.notifyListeners();
          await tester.pumpAndSettle();
          await tester.tap(_edit(_first));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          Navigator.of(tester.element(find.byType(Dialog))).pop();
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          c.pending = true;
          c.notifyListeners();
          await tester.pump();
          await tester.tap(_edit(_first), warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing, reason: 'pending gate');
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets('${suite.name}: publish from checklist opens the wizard', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final (c, _) = await _page(tester, suite, manifests: true);
      try {
        activate(tester, namedButton(tester, '用清单发布'));
        await tester.pumpAndSettle();
        final dialog = tester.widget<ListingPublishDialog>(
          find.byType(ListingPublishDialog),
        );
        expect(dialog.initialStep, 2);
        expect(dialog.draft.manifestId, 'M1');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        semantics.dispose();
      }
    });
  }
}
