// Slice17: the trade action dialog's own fields — the "handed over /
// received" checkbox, the five rating stars and the four report-type chips.
// Native geometry measured before the adaptation is pinned for the standard
// suite; every suite keeps autofocus on the first field, one reader action
// per control, keyboard activation and the pending gate.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';

import 'marketplace_trades_test.dart' show TradesPort;
import 'marketplace_trade_inner_motion_test.dart'
    show app, open, namedButton, activate;
import '../friends/social_layout_test.dart' show size;

const _received = Key('market-trade-action-received');
Finder _star(int i) =>
    find.byKey(ValueKey<(String, int)>(('market-trade-rating', i)));
Finder _report(int i) =>
    find.byKey(ValueKey<(String, int)>(('market-trade-report', i)));

Future<MarketplaceController> _dialog(
  WidgetTester tester,
  InteractionSuite suite,
  String op,
  TradesPort port,
  FocusNode trigger,
) async {
  size(tester, const Size(1280, 900));
  final c = MarketplaceController(port);
  await c.trades.refresh();
  await tester.pumpWidget(app(c, suite, trigger, operation: op));
  await tester.pumpAndSettle();
  await open(tester);
  return c;
}

void main() {
  testWidgets('standard suite keeps the measured native geometry', (
    tester,
  ) async {
    final trigger = FocusNode();
    final port = TradesPort();
    var c = await _dialog(
      tester,
      InteractionSuite.standard,
      'ship',
      port,
      trigger,
    );
    try {
      final box = find.byKey(_received);
      final row = find.ancestor(of: box, matching: find.byType(ListTile));
      expect(tester.getRect(row), const Rect.fromLTRB(430, 463, 850, 519));
      expect(tester.getRect(box), const Rect.fromLTRB(432, 473, 468, 509));
      final title = find.descendant(of: row, matching: find.byType(Text)).first;
      expect(tester.getRect(title).left, 486);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      c = await _dialog(
        tester,
        InteractionSuite.standard,
        'review',
        port,
        trigger,
      );
      for (var i = 1; i <= 5; i++) {
        expect(
          tester.getRect(_star(i)),
          Rect.fromLTWH(430 + 30.0 * (i - 1), 428, 30, 30),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      c = await _dialog(
        tester,
        InteractionSuite.standard,
        'report',
        port,
        trigger,
      );
      Rect chip(int i) => tester.getRect(_report(i));
      expect(
        chip(1),
        within(
          distance: .001,
          from: const Rect.fromLTRB(430, 378.5, 512.4, 426.5),
        ),
      );
      expect(chip(2).width, closeTo(82.4, .001));
      expect(chip(3).width, closeTo(82.4, .001));
      expect(
        chip(4),
        within(
          distance: .001,
          from: const Rect.fromLTRB(430, 434.5, 597.1, 482.5),
        ),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      trigger.dispose();
    }
  });

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '${suite.name}: received checkbox autofocuses, toggles by key and reader, respects pending',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final trigger = FocusNode();
        final port = TradesPort();
        final c = await _dialog(tester, suite, 'ship', port, trigger);
        try {
          final label = '我已在游戏里交给买家';
          bool checked() => namedOrChecked(tester, label)
              .getSemanticsData()
              .flagsCollection
              .isChecked
              .toString()
              .endsWith('isTrue');
          expect(checked(), isFalse);
          // Autofocus: Space toggles straight away.
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(checked(), isTrue);
          activate(tester, namedOrChecked(tester, label));
          await tester.pumpAndSettle();
          expect(checked(), isFalse);
          await tester.tap(find.byKey(_received));
          await tester.pumpAndSettle();
          expect(checked(), isTrue);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: rating stars autofocus the first, select by key, pointer and reader',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final trigger = FocusNode();
        final port = TradesPort();
        final c = await _dialog(tester, suite, 'review', port, trigger);
        try {
          // The icon target reports its confirmed state as selected (native)
          // or toggled (suite); either is the same spoken state.
          bool lit(int i) {
            final flags = namedButton(tester, '$i').getSemanticsData().flagsCollection;
            return flags.isSelected.toString().endsWith('isTrue') ||
                flags.isToggled.toString().endsWith('isTrue');
          }
          // Default five, first star focused.
          expect(lit(5), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(lit(1), isTrue);
          expect(lit(2), isFalse);
          await tester.tap(_star(3));
          await tester.pumpAndSettle();
          expect(lit(3), isTrue);
          expect(lit(4), isFalse);
          activate(tester, namedButton(tester, '4'));
          await tester.pumpAndSettle();
          expect(lit(4), isTrue);
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '${suite.name}: report chips autofocus the first, single-select, toggle off, reader',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final trigger = FocusNode();
        final port = TradesPort();
        final c = await _dialog(tester, suite, 'report', port, trigger);
        try {
          bool on(String label) => namedButton(tester, label)
              .getSemanticsData()
              .flagsCollection
              .isSelected
              .toString()
              .endsWith('isTrue');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(on('欺诈行为'), isTrue, reason: 'first chip autofocused');
          await tester.tap(find.text('虚假交易'));
          await tester.pumpAndSettle();
          expect(on('虚假交易'), isTrue);
          expect(on('欺诈行为'), isFalse);
          activate(tester, namedButton(tester, '虚假交易'));
          await tester.pumpAndSettle();
          expect(on('虚假交易'), isFalse, reason: 'selecting again clears it');
          expect(port.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          trigger.dispose();
          semantics.dispose();
        }
      },
    );
  }
}

/// The exposed node for a checkbox row (checked semantics, not a button).
SemanticsNode namedOrChecked(WidgetTester tester, String label) {
  final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode n) {
    if (n.isMergedIntoParent) return;
    if (n.getSemanticsData().label == label) nodes.add(n);
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(owner.rootSemanticsNode!);
  expect(nodes, hasLength(1), reason: 'One exposed node named $label');
  return nodes.single;
}
