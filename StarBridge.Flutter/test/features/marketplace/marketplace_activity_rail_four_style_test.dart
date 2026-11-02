import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_activity_rail.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final reduce in [false, true]) {
      testWidgets('${suite.name} reduce=$reduce trading rail keeps selection', (
        t,
      ) async {
        var selected = 0;
        var calls = 0;
        await t.pumpWidget(
          scopedApp(
            StatefulBuilder(
              builder: (context, update) {
                return MarketActivityRail(
                  selected: selected,
                  items: const [
                    (id: 0, label: '交易', count: '3', hot: true),
                    (id: 1, label: '挂单', count: null, hot: false),
                    (id: 2, label: '清单', count: null, hot: false),
                  ],
                  onSelect: (id) => update(() {
                    selected = id;
                    calls++;
                  }),
                );
              },
            ),
            suite,
            reduce: reduce,
          ),
        );
        await t.pumpAndSettle();
        final target = find.byKey(const ValueKey(('market-activity-tab', 1)));
        if (suite != InteractionSuite.standard) {
          expect(
            find.descendant(of: target, matching: find.byType(SuitePressable)),
            findsOneWidget,
          );
        }
        await t.tap(target);
        await t.pumpAndSettle();
        expect(selected, 1);
        expect(calls, 1);
        final semantics = t.widget<Semantics>(
          find.ancestor(of: target, matching: find.byType(Semantics)).first,
        );
        expect(semantics.properties.selected, isTrue);
        expect(t.takeException(), isNull);
      });
    }
  }
}
